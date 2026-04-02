#!/usr/bin/env bash
set -euo pipefail

# backup-openclaw.sh
# Purpose: Full OpenClaw backup — root snapshot, /var/lib/openclaw snapshot,
#          config archive, and hotfix verification.
#
# Usage:
#   sudo bash scripts/backup-openclaw.sh <label>           # dry-run
#   sudo bash scripts/backup-openclaw.sh <label> --apply   # execute
#
# Example:
#   sudo bash scripts/backup-openclaw.sh pre-upgrade --apply
#
# What it does:
#   1. Creates root btrfs snapshot:        /.snapshots/root-pre-{label}-YYYYMMDD-HHMM
#   2. Creates /var/lib/openclaw snapshot:  /.snapshots/openclaw-data-pre-{label}-YYYYMMDD-HHMM
#   3. Archives /etc/openclaw/ to:         /var/lib/openclaw/backup/etc-openclaw-{label}-YYYYMMDD-HHMM.tar.gz
#   4. Verifies and records hotfix state
#   5. Writes a backup manifest
#
# DOES NOT mount or modify Vault — that is an operator responsibility.
# Vault sync: sudo /usr/local/sbin/vault-backup-root-btrfs
#
# Paths reference (from host-sop.md):
#   Code:   /opt/openclaw       (root:root, 755)
#   Config: /etc/openclaw       (root:openclaw, 750)
#   Data:   /var/lib/openclaw   (separate btrfs subvolume, openclaw:openclaw, 700)
#   Logs:   /var/log/openclaw   (openclaw:openclaw)

# --- Constants ---
SNAPSHOT_DIR="/.snapshots"
DATA_DIR="/var/lib/openclaw"
BACKUP_DIR="${DATA_DIR}/backup"
CONFIG_DIR="/etc/openclaw"
DIST_DIR="/opt/openclaw/node_modules/openclaw/dist"

# Hotfix target files
HOTFIX_PI_EMBEDDED="${DIST_DIR}/pi-embedded-CbCYZxIb.js"
HOTFIX_JSON_FILE="${DIST_DIR}/json-file-Dl3Z1jL1.js"

# --- Argument parsing ---
LABEL="${1:-}"
APPLY=false

if [[ -z "$LABEL" ]]; then
    echo "Usage: sudo bash $0 <label> [--apply]"
    echo ""
    echo "Examples:"
    echo "  sudo bash $0 pre-upgrade          # dry-run"
    echo "  sudo bash $0 pre-upgrade --apply   # execute backup"
    exit 1
fi

if [[ "${2:-}" == "--apply" ]]; then
    APPLY=true
fi

# --- Preflight checks ---
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo)." >&2
    exit 1
fi

if ! command -v btrfs &>/dev/null; then
    echo "ERROR: btrfs command not found." >&2
    exit 1
fi

if [[ ! -d "$SNAPSHOT_DIR" ]]; then
    echo "ERROR: Snapshot directory $SNAPSHOT_DIR does not exist." >&2
    exit 1
fi

if [[ ! -d "$DATA_DIR" ]]; then
    echo "ERROR: Data directory $DATA_DIR does not exist." >&2
    exit 1
fi

if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "ERROR: Config directory $CONFIG_DIR does not exist." >&2
    exit 1
fi

# --- Timestamp ---
TS=$(date +%Y%m%d-%H%M)
ROOT_SNAP_NAME="root-pre-${LABEL}-${TS}"
DATA_SNAP_NAME="openclaw-data-pre-${LABEL}-${TS}"
CONFIG_ARCHIVE="etc-openclaw-${LABEL}-${TS}.tar.gz"
MANIFEST_FILE="backup-manifest-${LABEL}-${TS}.txt"

echo "=============================================="
echo "  OpenClaw Full Backup"
echo "=============================================="
echo ""
echo "Label:          ${LABEL}"
echo "Timestamp:      ${TS}"
echo "Mode:           $(if $APPLY; then echo 'APPLY'; else echo 'DRY-RUN'; fi)"
echo ""
echo "Planned actions:"
echo "  1. Root snapshot:    ${SNAPSHOT_DIR}/${ROOT_SNAP_NAME}"
echo "  2. Data snapshot:    ${SNAPSHOT_DIR}/${DATA_SNAP_NAME}"
echo "  3. Config archive:   ${BACKUP_DIR}/${CONFIG_ARCHIVE}"
echo "  4. Hotfix state:     verify and record"
echo "  5. Manifest:         ${BACKUP_DIR}/${MANIFEST_FILE}"
echo ""

# --- Check for existing snapshots with same name ---
if [[ -d "${SNAPSHOT_DIR}/${ROOT_SNAP_NAME}" ]]; then
    echo "ERROR: Root snapshot already exists: ${SNAPSHOT_DIR}/${ROOT_SNAP_NAME}" >&2
    exit 1
fi

if [[ -d "${SNAPSHOT_DIR}/${DATA_SNAP_NAME}" ]]; then
    echo "ERROR: Data snapshot already exists: ${SNAPSHOT_DIR}/${DATA_SNAP_NAME}" >&2
    exit 1
fi

# --- Hotfix verification ---
echo "--- Hotfix State ---"

HOTFIX_STREAMTO="NOT_FOUND"
HOTFIX_CHMOD="NOT_FOUND"
HOTFIX_CLEANUP="NOT_FOUND"

if [[ -f "$HOTFIX_PI_EMBEDDED" ]]; then
    if grep -q '\[hotfix\] streamTo guard disabled' "$HOTFIX_PI_EMBEDDED" 2>/dev/null; then
        HOTFIX_STREAMTO="APPLIED"
        echo "  streamTo noop:      APPLIED"
    else
        HOTFIX_STREAMTO="NOT_APPLIED"
        echo "  streamTo noop:      NOT APPLIED (original code present)"
    fi
else
    echo "  streamTo noop:      FILE NOT FOUND ($HOTFIX_PI_EMBEDDED)"
fi

if [[ -f "$HOTFIX_JSON_FILE" ]]; then
    if grep -q 'chmodSync(pathname, 416)' "$HOTFIX_JSON_FILE" 2>/dev/null; then
        HOTFIX_CHMOD="APPLIED"
        echo "  json-file chmod:    APPLIED (0640)"
    else
        HOTFIX_CHMOD="NOT_APPLIED"
        echo "  json-file chmod:    NOT APPLIED (original 0600)"
    fi
else
    echo "  json-file chmod:    FILE NOT FOUND ($HOTFIX_JSON_FILE)"
fi

if [[ -f "$HOTFIX_PI_EMBEDDED" ]]; then
    if grep -q '\[hotfix\] force keep' "$HOTFIX_PI_EMBEDDED" 2>/dev/null; then
        HOTFIX_CLEANUP="APPLIED"
        echo "  cleanup keep:       APPLIED"
    else
        HOTFIX_CLEANUP="NOT_APPLIED"
        echo "  cleanup keep:       NOT APPLIED"
    fi
else
    echo "  cleanup keep:       FILE NOT FOUND ($HOTFIX_PI_EMBEDDED)"
fi
echo ""

# --- Record file hashes for hotfix targets ---
echo "--- Hotfix File Hashes ---"
PI_HASH="N/A"
JSON_HASH="N/A"

if [[ -f "$HOTFIX_PI_EMBEDDED" ]]; then
    PI_HASH=$(sha256sum "$HOTFIX_PI_EMBEDDED" | awk '{print $1}')
    echo "  pi-embedded:        ${PI_HASH}"
fi
if [[ -f "$HOTFIX_JSON_FILE" ]]; then
    JSON_HASH=$(sha256sum "$HOTFIX_JSON_FILE" | awk '{print $1}')
    echo "  json-file:          ${JSON_HASH}"
fi
echo ""

# --- Gateway status ---
echo "--- Gateway Status ---"
GW_STATUS="unknown"
if systemctl is-active --quiet openclaw-gateway.service 2>/dev/null; then
    GW_STATUS="active"
    echo "  openclaw-gateway:   active (running)"
else
    GW_STATUS="inactive"
    echo "  openclaw-gateway:   inactive or not found"
fi
echo ""

# --- Execute or dry-run ---
if ! $APPLY; then
    echo "=============================================="
    echo "  DRY RUN — no changes made"
    echo "  Re-run with --apply to execute backup"
    echo "=============================================="
    exit 0
fi

echo "=============================================="
echo "  Executing backup..."
echo "=============================================="
echo ""

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Step 1: Root btrfs snapshot
echo "[1/5] Creating root btrfs snapshot..."
btrfs subvolume snapshot -r / "${SNAPSHOT_DIR}/${ROOT_SNAP_NAME}"
echo "      Created: ${SNAPSHOT_DIR}/${ROOT_SNAP_NAME}"
echo ""

# Step 2: /var/lib/openclaw subvolume snapshot
echo "[2/5] Creating /var/lib/openclaw data snapshot..."
btrfs subvolume snapshot -r "$DATA_DIR" "${SNAPSHOT_DIR}/${DATA_SNAP_NAME}"
echo "      Created: ${SNAPSHOT_DIR}/${DATA_SNAP_NAME}"
echo ""

# Step 3: Archive /etc/openclaw
echo "[3/5] Archiving /etc/openclaw..."
tar -czf "${BACKUP_DIR}/${CONFIG_ARCHIVE}" -C /etc openclaw
chmod 640 "${BACKUP_DIR}/${CONFIG_ARCHIVE}"
chown root:openclaw "${BACKUP_DIR}/${CONFIG_ARCHIVE}"
echo "      Created: ${BACKUP_DIR}/${CONFIG_ARCHIVE}"
echo "      Size:    $(du -h "${BACKUP_DIR}/${CONFIG_ARCHIVE}" | awk '{print $1}')"
echo ""

# Step 4: Hotfix state already verified above (logged in manifest)
echo "[4/5] Hotfix state recorded (see manifest)."
echo ""

# Step 5: Write manifest
echo "[5/5] Writing backup manifest..."
cat > "${BACKUP_DIR}/${MANIFEST_FILE}" <<MANIFEST
# OpenClaw Backup Manifest
# Generated: $(date --iso-8601=seconds)
# Label: ${LABEL}

## Snapshots
root_snapshot: ${SNAPSHOT_DIR}/${ROOT_SNAP_NAME}
data_snapshot: ${SNAPSHOT_DIR}/${DATA_SNAP_NAME}

## Config Archive
config_archive: ${BACKUP_DIR}/${CONFIG_ARCHIVE}

## Gateway Status at Backup Time
gateway_status: ${GW_STATUS}

## Hotfix State
hotfix_streamto_noop: ${HOTFIX_STREAMTO}
hotfix_json_file_chmod: ${HOTFIX_CHMOD}
hotfix_cleanup_keep: ${HOTFIX_CLEANUP}

## Hotfix File Hashes (SHA256)
pi_embedded_hash: ${PI_HASH}
json_file_hash: ${JSON_HASH}

## Hotfix Target Files
pi_embedded_path: ${HOTFIX_PI_EMBEDDED}
json_file_path: ${HOTFIX_JSON_FILE}

## Host Info
hostname: $(hostname)
openclaw_version: $(cat /opt/openclaw/package.json 2>/dev/null | grep '"version"' | head -1 | sed 's/.*: *"//;s/".*//' || echo "unknown")
kernel: $(uname -r)
date: $(date --iso-8601=seconds)
MANIFEST

chmod 640 "${BACKUP_DIR}/${MANIFEST_FILE}"
chown root:openclaw "${BACKUP_DIR}/${MANIFEST_FILE}"
echo "      Created: ${BACKUP_DIR}/${MANIFEST_FILE}"
echo ""

# --- Summary ---
echo "=============================================="
echo "  Backup Complete"
echo "=============================================="
echo ""
echo "  Root snapshot:    ${SNAPSHOT_DIR}/${ROOT_SNAP_NAME}"
echo "  Data snapshot:    ${SNAPSHOT_DIR}/${DATA_SNAP_NAME}"
echo "  Config archive:   ${BACKUP_DIR}/${CONFIG_ARCHIVE}"
echo "  Manifest:         ${BACKUP_DIR}/${MANIFEST_FILE}"
echo ""
echo "Next steps (operator responsibility):"
echo "  1. Verify snapshots:  sudo btrfs subvolume list /.snapshots | tail -5"
echo "  2. Vault sync:        sudo /usr/local/sbin/vault-backup-root-btrfs"
echo "  3. Validate:          bash scripts/validate-openclaw.sh"
