#!/usr/bin/env bash
set -euo pipefail

# restore-openclaw.sh
# Purpose: Restore/rollback OpenClaw from a previous backup snapshot.
#
# Usage:
#   sudo bash scripts/restore-openclaw.sh                     # list available snapshots
#   sudo bash scripts/restore-openclaw.sh <label>             # dry-run showing what would be restored
#   sudo bash scripts/restore-openclaw.sh <label> --apply     # execute restore
#
# Example:
#   sudo bash scripts/restore-openclaw.sh pre-upgrade --apply
#
# What it does:
#   1. Stops openclaw-gateway and openclaw-gui services
#   2. Restores root filesystem from snapshot (btrfs rollback)
#   3. Restores /var/lib/openclaw from data snapshot
#   4. Restores /etc/openclaw from config archive (if available)
#   5. Re-applies hotfixes (using hotfix scripts from dev repo)
#   6. Restarts gateway and GUI services
#   7. Runs basic health check
#
# IMPORTANT:
#   - Root snapshot restore requires a REBOOT to take effect (btrfs limitation
#     with subvolid=5 top-level mount). This script prepares the rollback but
#     the operator must reboot manually.
#   - /var/lib/openclaw restore is immediate (subvolume replace).
#   - Config restore is immediate (tar extract).
#   - Hotfix re-application is immediate.
#
# DOES NOT mount or modify Vault.
#
# Paths reference (from host-sop.md):
#   Snapshots: /.snapshots/
#   Data:      /var/lib/openclaw  (separate btrfs subvolume)
#   Config:    /etc/openclaw
#   Hotfixes:  /opt/openclaw/node_modules/openclaw/dist/

# --- Constants ---
SNAPSHOT_DIR="/.snapshots"
DATA_DIR="/var/lib/openclaw"
BACKUP_DIR="${DATA_DIR}/backup"
CONFIG_DIR="/etc/openclaw"
DIST_DIR="/opt/openclaw/node_modules/openclaw/dist"

# Dev repo hotfix scripts (relative to this script's location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Argument parsing ---
LABEL="${1:-}"
APPLY=false

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

# --- List mode (no arguments) ---
if [[ -z "$LABEL" ]]; then
    echo "=============================================="
    echo "  OpenClaw Restore — Available Snapshots"
    echo "=============================================="
    echo ""

    echo "--- Root Snapshots ---"
    if ls -1d "${SNAPSHOT_DIR}"/root-pre-* 2>/dev/null | head -20; then
        true
    else
        echo "  (none found)"
    fi
    echo ""

    echo "--- Data Snapshots (/var/lib/openclaw) ---"
    if ls -1d "${SNAPSHOT_DIR}"/openclaw-data-pre-* 2>/dev/null | head -20; then
        true
    else
        echo "  (none found)"
    fi
    echo ""

    echo "--- Config Archives ---"
    if ls -1 "${BACKUP_DIR}"/etc-openclaw-*.tar.gz 2>/dev/null | head -20; then
        true
    else
        echo "  (none found in ${BACKUP_DIR}/)"
    fi
    echo ""

    echo "--- Backup Manifests ---"
    if ls -1 "${BACKUP_DIR}"/backup-manifest-*.txt 2>/dev/null | head -20; then
        true
    else
        echo "  (none found in ${BACKUP_DIR}/)"
    fi
    echo ""

    echo "Usage:"
    echo "  sudo bash $0 <label>           # dry-run"
    echo "  sudo bash $0 <label> --apply   # execute restore"
    echo ""
    echo "The <label> should match the label used during backup."
    echo "Example: if backup was 'pre-upgrade', use 'pre-upgrade' here."
    exit 0
fi

# --- Locate matching snapshots and archives ---
echo "=============================================="
echo "  OpenClaw Restore"
echo "=============================================="
echo ""
echo "Label:   ${LABEL}"
echo "Mode:    $(if $APPLY; then echo 'APPLY'; else echo 'DRY-RUN'; fi)"
echo ""

# Find root snapshot (most recent matching the label)
ROOT_SNAP=""
ROOT_SNAP_CANDIDATES=()
while IFS= read -r snap; do
    ROOT_SNAP_CANDIDATES+=("$snap")
done < <(ls -1d "${SNAPSHOT_DIR}"/root-pre-"${LABEL}"-* 2>/dev/null | sort -r)

if [[ ${#ROOT_SNAP_CANDIDATES[@]} -gt 0 ]]; then
    ROOT_SNAP="${ROOT_SNAP_CANDIDATES[0]}"
fi

# Find data snapshot
DATA_SNAP=""
DATA_SNAP_CANDIDATES=()
while IFS= read -r snap; do
    DATA_SNAP_CANDIDATES+=("$snap")
done < <(ls -1d "${SNAPSHOT_DIR}"/openclaw-data-pre-"${LABEL}"-* 2>/dev/null | sort -r)

if [[ ${#DATA_SNAP_CANDIDATES[@]} -gt 0 ]]; then
    DATA_SNAP="${DATA_SNAP_CANDIDATES[0]}"
fi

# Find config archive
CONFIG_ARCHIVE=""
CONFIG_ARCHIVE_CANDIDATES=()
while IFS= read -r archive; do
    CONFIG_ARCHIVE_CANDIDATES+=("$archive")
done < <(ls -1 "${BACKUP_DIR}"/etc-openclaw-"${LABEL}"-*.tar.gz 2>/dev/null | sort -r)

if [[ ${#CONFIG_ARCHIVE_CANDIDATES[@]} -gt 0 ]]; then
    CONFIG_ARCHIVE="${CONFIG_ARCHIVE_CANDIDATES[0]}"
fi

# Find manifest
MANIFEST=""
MANIFEST_CANDIDATES=()
while IFS= read -r m; do
    MANIFEST_CANDIDATES+=("$m")
done < <(ls -1 "${BACKUP_DIR}"/backup-manifest-"${LABEL}"-*.txt 2>/dev/null | sort -r)

if [[ ${#MANIFEST_CANDIDATES[@]} -gt 0 ]]; then
    MANIFEST="${MANIFEST_CANDIDATES[0]}"
fi

# --- Display what was found ---
echo "--- Restore Targets ---"

if [[ -n "$ROOT_SNAP" ]]; then
    echo "  Root snapshot:    ${ROOT_SNAP}"
    if [[ ${#ROOT_SNAP_CANDIDATES[@]} -gt 1 ]]; then
        echo "    (${#ROOT_SNAP_CANDIDATES[@]} candidates found, using most recent)"
    fi
else
    echo "  Root snapshot:    NOT FOUND (no root-pre-${LABEL}-* in ${SNAPSHOT_DIR}/)"
fi

if [[ -n "$DATA_SNAP" ]]; then
    echo "  Data snapshot:    ${DATA_SNAP}"
    if [[ ${#DATA_SNAP_CANDIDATES[@]} -gt 1 ]]; then
        echo "    (${#DATA_SNAP_CANDIDATES[@]} candidates found, using most recent)"
    fi
else
    echo "  Data snapshot:    NOT FOUND (no openclaw-data-pre-${LABEL}-* in ${SNAPSHOT_DIR}/)"
fi

if [[ -n "$CONFIG_ARCHIVE" ]]; then
    echo "  Config archive:   ${CONFIG_ARCHIVE}"
else
    echo "  Config archive:   NOT FOUND (no etc-openclaw-${LABEL}-* in ${BACKUP_DIR}/)"
fi

if [[ -n "$MANIFEST" ]]; then
    echo "  Manifest:         ${MANIFEST}"
else
    echo "  Manifest:         NOT FOUND"
fi
echo ""

# --- Check that at least one restore target exists ---
if [[ -z "$ROOT_SNAP" && -z "$DATA_SNAP" && -z "$CONFIG_ARCHIVE" ]]; then
    echo "ERROR: No snapshots or archives found for label '${LABEL}'." >&2
    echo "Run without arguments to list available snapshots." >&2
    exit 1
fi

# --- Show manifest if available ---
if [[ -n "$MANIFEST" ]]; then
    echo "--- Backup Manifest ---"
    cat "$MANIFEST"
    echo ""
fi

# --- Check hotfix scripts availability ---
echo "--- Hotfix Scripts ---"
HOTFIX_SCRIPTS_OK=true

if [[ -f "${SCRIPT_DIR}/hotfix-streamto-noop.sh" ]]; then
    echo "  streamTo noop:      ${SCRIPT_DIR}/hotfix-streamto-noop.sh"
else
    echo "  streamTo noop:      NOT FOUND"
    HOTFIX_SCRIPTS_OK=false
fi

if [[ -f "${SCRIPT_DIR}/hotfix-json-file-chmod.sh" ]]; then
    echo "  json-file chmod:    ${SCRIPT_DIR}/hotfix-json-file-chmod.sh"
else
    echo "  json-file chmod:    NOT FOUND"
    HOTFIX_SCRIPTS_OK=false
fi

if [[ -f "${SCRIPT_DIR}/hotfix-cleanup-keep.sh" ]]; then
    echo "  cleanup keep:       ${SCRIPT_DIR}/hotfix-cleanup-keep.sh"
else
    echo "  cleanup keep:       NOT FOUND"
    HOTFIX_SCRIPTS_OK=false
fi

if ! $HOTFIX_SCRIPTS_OK; then
    echo ""
    echo "  WARNING: Some hotfix scripts are missing. Hotfixes will need manual re-application."
fi
echo ""

# --- Restore plan ---
echo "--- Restore Plan ---"
STEP=0

if [[ -n "$DATA_SNAP" ]]; then
    STEP=$((STEP + 1))
    echo "  ${STEP}. Stop openclaw-gateway.service and openclaw-gui.service"
    STEP=$((STEP + 1))
    echo "  ${STEP}. Restore /var/lib/openclaw from data snapshot"
    echo "     (rename current subvolume, snapshot restore copy, fix ownership)"
fi

if [[ -n "$CONFIG_ARCHIVE" ]]; then
    STEP=$((STEP + 1))
    echo "  ${STEP}. Restore /etc/openclaw from config archive"
fi

if $HOTFIX_SCRIPTS_OK; then
    STEP=$((STEP + 1))
    echo "  ${STEP}. Re-apply hotfixes (streamTo noop, json-file chmod, cleanup keep)"
fi

STEP=$((STEP + 1))
echo "  ${STEP}. Restart services (gateway, gui)"

STEP=$((STEP + 1))
echo "  ${STEP}. Run health check"

if [[ -n "$ROOT_SNAP" ]]; then
    STEP=$((STEP + 1))
    echo "  ${STEP}. ROOT SNAPSHOT: Requires manual reboot to take effect"
    echo "     (btrfs root rollback with subvolid=5 requires system reboot)"
fi
echo ""

# --- Dry run exit ---
if ! $APPLY; then
    echo "=============================================="
    echo "  DRY RUN — no changes made"
    echo "  Re-run with --apply to execute restore"
    echo "=============================================="
    exit 0
fi

# --- Confirmation ---
echo "=============================================="
echo "  WARNING: This will modify the live system!"
echo "=============================================="
echo ""
read -p "Type 'RESTORE' to confirm: " CONFIRM
if [[ "$CONFIRM" != "RESTORE" ]]; then
    echo "Aborted."
    exit 1
fi
echo ""

# --- Execute restore ---
echo "=============================================="
echo "  Executing restore..."
echo "=============================================="
echo ""

STEP=0

# Step: Stop services
STEP=$((STEP + 1))
echo "[${STEP}] Stopping OpenClaw services..."

if systemctl is-active --quiet openclaw-gui.service 2>/dev/null; then
    systemctl stop openclaw-gui.service
    echo "      Stopped openclaw-gui.service"
else
    echo "      openclaw-gui.service was not running"
fi

if systemctl is-active --quiet openclaw-gateway.service 2>/dev/null; then
    systemctl stop openclaw-gateway.service
    echo "      Stopped openclaw-gateway.service"
    # Wait for clean shutdown
    sleep 2
else
    echo "      openclaw-gateway.service was not running"
fi
echo ""

# Step: Restore /var/lib/openclaw data
if [[ -n "$DATA_SNAP" ]]; then
    STEP=$((STEP + 1))
    echo "[${STEP}] Restoring /var/lib/openclaw from data snapshot..."

    # The data snapshot is a read-only snapshot. We need to create a
    # writable snapshot from it to replace the current subvolume.
    #
    # Strategy:
    #   1. Rename current /var/lib/openclaw to /var/lib/openclaw.rollback-<ts>
    #   2. Create writable snapshot from the backup snapshot
    #   3. Fix ownership
    #
    # Note: This requires that /var/lib/openclaw is not in use (services stopped above).

    ROLLBACK_TS=$(date +%Y%m%d-%H%M%S)
    ROLLBACK_NAME="/var/lib/openclaw.rollback-${ROLLBACK_TS}"

    echo "      Renaming current subvolume to: ${ROLLBACK_NAME}"
    mv "$DATA_DIR" "$ROLLBACK_NAME"

    echo "      Creating writable snapshot from: ${DATA_SNAP}"
    btrfs subvolume snapshot "$DATA_SNAP" "$DATA_DIR"

    echo "      Fixing ownership (openclaw:openclaw, mode 700)..."
    chown openclaw:openclaw "$DATA_DIR"
    chmod 700 "$DATA_DIR"

    echo "      Data restore complete."
    echo "      Previous data preserved at: ${ROLLBACK_NAME}"
    echo "      (Delete when satisfied: sudo btrfs subvolume delete ${ROLLBACK_NAME})"
    echo ""
fi

# Step: Restore /etc/openclaw
if [[ -n "$CONFIG_ARCHIVE" ]]; then
    STEP=$((STEP + 1))
    echo "[${STEP}] Restoring /etc/openclaw from config archive..."

    # Back up current config first
    CONFIG_BACKUP="/etc/openclaw.rollback-$(date +%Y%m%d-%H%M%S)"
    cp -a "$CONFIG_DIR" "$CONFIG_BACKUP"
    echo "      Current config backed up to: ${CONFIG_BACKUP}"

    # Extract archive over existing config
    tar -xzf "$CONFIG_ARCHIVE" -C /etc
    echo "      Config restored from: ${CONFIG_ARCHIVE}"

    # Verify permissions
    chown root:openclaw "$CONFIG_DIR"
    chmod 750 "$CONFIG_DIR"
    if [[ -f "${CONFIG_DIR}/openclaw.json" ]]; then
        chown root:openclaw "${CONFIG_DIR}/openclaw.json"
        chmod 640 "${CONFIG_DIR}/openclaw.json"
    fi
    if [[ -f "${CONFIG_DIR}/openclaw.env" ]]; then
        chown root:openclaw "${CONFIG_DIR}/openclaw.env"
        chmod 640 "${CONFIG_DIR}/openclaw.env"
    fi
    echo "      Permissions verified."
    echo ""
fi

# Step: Re-apply hotfixes
if $HOTFIX_SCRIPTS_OK; then
    STEP=$((STEP + 1))
    echo "[${STEP}] Re-applying hotfixes..."

    echo "      Applying streamTo noop hotfix..."
    bash "${SCRIPT_DIR}/hotfix-streamto-noop.sh" --apply 2>&1 | sed 's/^/      /'
    echo ""

    echo "      Applying json-file chmod hotfix..."
    bash "${SCRIPT_DIR}/hotfix-json-file-chmod.sh" --apply 2>&1 | sed 's/^/      /'
    echo ""

    echo "      Applying cleanup keep hotfix..."
    bash "${SCRIPT_DIR}/hotfix-cleanup-keep.sh" --apply 2>&1 | sed 's/^/      /'
    echo ""
fi

# Step: Restart services
STEP=$((STEP + 1))
echo "[${STEP}] Restarting OpenClaw services..."

# Fix directory permissions that gateway ExecStartPre expects
# (gateway creates .openclaw/ with 700 but group read is needed for GUI)
systemctl start openclaw-gateway.service
echo "      Started openclaw-gateway.service"

# Wait for gateway to initialize
echo "      Waiting for gateway to initialize (5s)..."
sleep 5

# Fix permissions for GUI access (runs.json group-read)
if [[ -d "${DATA_DIR}/.openclaw" ]]; then
    chmod 0750 "${DATA_DIR}/.openclaw" 2>/dev/null || true
    if [[ -d "${DATA_DIR}/.openclaw/subagents" ]]; then
        chmod 0750 "${DATA_DIR}/.openclaw/subagents" 2>/dev/null || true
    fi
fi

if systemctl is-enabled --quiet openclaw-gui.service 2>/dev/null; then
    systemctl start openclaw-gui.service
    echo "      Started openclaw-gui.service"
fi
echo ""

# Step: Health check
STEP=$((STEP + 1))
echo "[${STEP}] Running basic health check..."
echo ""

HEALTH_PASS=0
HEALTH_FAIL=0

# Check gateway
if systemctl is-active --quiet openclaw-gateway.service 2>/dev/null; then
    echo "      [PASS] openclaw-gateway.service is active"
    HEALTH_PASS=$((HEALTH_PASS + 1))
else
    echo "      [FAIL] openclaw-gateway.service is not active"
    HEALTH_FAIL=$((HEALTH_FAIL + 1))
fi

# Check gateway log for errors (last 10 lines)
echo "      --- Recent gateway log ---"
journalctl -u openclaw-gateway.service -n 5 --no-pager 2>/dev/null | sed 's/^/      /' || true
echo "      ---"

# Check GUI
if systemctl is-enabled --quiet openclaw-gui.service 2>/dev/null; then
    if systemctl is-active --quiet openclaw-gui.service 2>/dev/null; then
        echo "      [PASS] openclaw-gui.service is active"
        HEALTH_PASS=$((HEALTH_PASS + 1))
    else
        echo "      [FAIL] openclaw-gui.service is not active"
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
    fi
fi

# Check hotfixes
if [[ -f "$DIST_DIR/pi-embedded-CbCYZxIb.js" ]]; then
    if grep -q '\[hotfix\] streamTo guard disabled' "$DIST_DIR/pi-embedded-CbCYZxIb.js" 2>/dev/null; then
        echo "      [PASS] streamTo hotfix applied"
        HEALTH_PASS=$((HEALTH_PASS + 1))
    else
        echo "      [FAIL] streamTo hotfix not applied"
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
    fi
fi

if [[ -f "$DIST_DIR/json-file-Dl3Z1jL1.js" ]]; then
    if grep -q 'chmodSync(pathname, 416)' "$DIST_DIR/json-file-Dl3Z1jL1.js" 2>/dev/null; then
        echo "      [PASS] json-file chmod hotfix applied (0640)"
        HEALTH_PASS=$((HEALTH_PASS + 1))
    else
        echo "      [FAIL] json-file chmod hotfix not applied"
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
    fi
fi
echo ""

# Root snapshot notice
if [[ -n "$ROOT_SNAP" ]]; then
    STEP=$((STEP + 1))
    echo "[${STEP}] ROOT SNAPSHOT ROLLBACK"
    echo ""
    echo "      The root filesystem snapshot is available at:"
    echo "        ${ROOT_SNAP}"
    echo ""
    echo "      Because this system uses btrfs subvolid=5 (top-level) as root,"
    echo "      a full root rollback requires operator-assisted steps:"
    echo ""
    echo "      Option A — Boot from snapshot (recommended):"
    echo "        1. Edit GRUB: add rootflags=subvol=<snapshot-subvol-name>"
    echo "        2. Reboot"
    echo ""
    echo "      Option B — Replace root in-place (requires rescue/live boot):"
    echo "        1. Boot from live USB"
    echo "        2. Mount root filesystem"
    echo "        3. Rename current root, snapshot restore copy"
    echo "        4. Reboot"
    echo ""
    echo "      Note: /etc/openclaw and /opt/openclaw are part of the root snapshot."
    echo "      If you restored config from archive above, the root rollback may"
    echo "      overwrite those changes. Plan accordingly."
fi

echo ""
echo "=============================================="
echo "  Restore Summary"
echo "=============================================="
echo "  Health checks: ${HEALTH_PASS} passed, ${HEALTH_FAIL} failed"
if [[ -n "${ROLLBACK_NAME:-}" ]]; then
    echo "  Previous data:  ${ROLLBACK_NAME}"
fi
if [[ -n "${CONFIG_BACKUP:-}" ]]; then
    echo "  Previous config: ${CONFIG_BACKUP}"
fi
echo ""
echo "Next steps:"
echo "  1. Run full validation:  sudo bash scripts/validate-openclaw.sh"
echo "  2. Check gateway health: sudo journalctl -u openclaw-gateway.service -f"
if [[ -n "$ROOT_SNAP" ]]; then
    echo "  3. Root rollback requires reboot (see instructions above)"
fi
echo "  4. When satisfied, clean up rollback data:"
if [[ -n "${ROLLBACK_NAME:-}" ]]; then
    echo "     sudo btrfs subvolume delete ${ROLLBACK_NAME}"
fi
if [[ -n "${CONFIG_BACKUP:-}" ]]; then
    echo "     sudo rm -rf ${CONFIG_BACKUP}"
fi
