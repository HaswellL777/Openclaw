#!/usr/bin/env bash
set -euo pipefail

# activate-snapshot-post-slice.sh
# Purpose: Single-command operator script for snapshot_post live activation
# Usage:   sudo bash scripts/activate-snapshot-post-slice.sh
#
# This script performs the complete snapshot_post slice activation:
#   1. Pre-flight checks (root, files, btrfs, systemd)
#   2. Pre-change root btrfs snapshot
#   3. Backup current live plugin
#   4. Copy new plugin with correct ownership/permissions
#   5. Restart gateway
#   6. Health check (gateway + broker)
#   7. Post-change root btrfs snapshot
#   8. Write structured results to artifacts/
#
# On failure: stops immediately, prints rollback command.
# Rollback:   sudo bash scripts/rollback-snapshot-post-slice.sh <artifacts-dir>
#
# Safety:
#   - set -euo pipefail: any failure stops execution
#   - All paths are hardcoded constants, no user-supplied path expansion
#   - No /etc/openclaw/openclaw.json modification
#   - Plugin file backup is taken BEFORE any modification
#   - Pre-change root snapshot is taken BEFORE any modification

# ============================================================
# 1. Unified variable block
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source and target paths
REPO_PLUGIN_SRC="${REPO_ROOT}/plugins/host-ops-tool/index.js"
LIVE_PLUGIN_DIR="/var/lib/openclaw/.openclaw/extensions/host-ops-tool"
LIVE_PLUGIN_FILE="${LIVE_PLUGIN_DIR}/index.js"

# Backup
BACKUP_DIR="/var/lib/openclaw/host-ops-tool-backups"

# Timestamps and naming
TIMESTAMP="$(date +%Y%m%d-%H%M)"
BACKUP_FILE="${BACKUP_DIR}/index.js.backup-before-snapshot-post-slice-${TIMESTAMP}"

# Snapshots
SNAPSHOT_DIR="/.snapshots"
PRE_SNAPSHOT_NAME="root-pre-snapshot-post-slice-${TIMESTAMP}"
POST_SNAPSHOT_NAME="root-post-snapshot-post-slice-${TIMESTAMP}"
PRE_SNAPSHOT_PATH="${SNAPSHOT_DIR}/${PRE_SNAPSHOT_NAME}"
POST_SNAPSHOT_PATH="${SNAPSHOT_DIR}/${POST_SNAPSHOT_NAME}"

# Artifacts output
ARTIFACTS_DIR="${REPO_ROOT}/artifacts/phase2/snapshot-post-live-activation-${TIMESTAMP}"

# Systemd services
GATEWAY_SERVICE="openclaw-gateway.service"
BROKER_SERVICE="openclaw-broker.service"

# Health check delay (seconds to wait after restart before checking)
HEALTH_DELAY=4

# ============================================================
# Helpers
# ============================================================

log_step() { echo ""; echo ">>> [$1] $2"; }
log_ok()   { echo "    OK: $1"; }
log_fail() { echo "    FAIL: $1" >&2; }

abort_with_rollback() {
    echo "" >&2
    echo "========================================" >&2
    echo "  ACTIVATION FAILED — see error above" >&2
    echo "========================================" >&2
    echo "" >&2
    echo "Rollback command:" >&2
    echo "  sudo bash ${SCRIPT_DIR}/rollback-snapshot-post-slice.sh ${ARTIFACTS_DIR}" >&2
    echo "" >&2
    # Write partial result before exiting
    write_result_file "FAILED"
    exit 1
}

write_result_file() {
    local final_status="$1"
    mkdir -p "$ARTIFACTS_DIR"
    cat > "${ARTIFACTS_DIR}/result.env" <<RESULTEOF
# snapshot_post slice activation result
# Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
TIMESTAMP="${TIMESTAMP}"
REPO_PLUGIN_SRC="${REPO_PLUGIN_SRC}"
LIVE_PLUGIN_FILE="${LIVE_PLUGIN_FILE}"
BACKUP_FILE="${BACKUP_FILE}"
PRE_SNAPSHOT_NAME="${PRE_SNAPSHOT_NAME}"
PRE_SNAPSHOT_PATH="${PRE_SNAPSHOT_PATH}"
POST_SNAPSHOT_NAME="${POST_SNAPSHOT_NAME}"
POST_SNAPSHOT_PATH="${POST_SNAPSHOT_PATH}"
GATEWAY_STATUS="${GATEWAY_STATUS:-unknown}"
BROKER_STATUS="${BROKER_STATUS:-unknown}"
ARTIFACTS_DIR="${ARTIFACTS_DIR}"
EXIT_STATUS="${final_status}"
RESULTEOF
}

# ============================================================
# 2. Pre-flight checks
# ============================================================

log_step "PREFLIGHT" "Running pre-flight checks"

# 2.1 Must be root (via sudo)
if [[ $EUID -ne 0 ]]; then
    log_fail "This script must be run with sudo"
    echo "Usage: sudo bash $0" >&2
    exit 1
fi
log_ok "Running as root (EUID=0)"

# 2.2 Source plugin file exists
if [[ ! -f "$REPO_PLUGIN_SRC" ]]; then
    log_fail "Source plugin not found: $REPO_PLUGIN_SRC"
    exit 1
fi
log_ok "Source plugin exists: $REPO_PLUGIN_SRC"

# 2.3 Verify source contains snapshot_post in ENABLED_ACTIONS
if ! grep -q '"snapshot_post"' "$REPO_PLUGIN_SRC"; then
    log_fail "Source plugin does not contain snapshot_post in ENABLED_ACTIONS"
    exit 1
fi
log_ok "Source plugin contains snapshot_post in ENABLED_ACTIONS"

# 2.4 Live plugin directory exists
if [[ ! -d "$LIVE_PLUGIN_DIR" ]]; then
    log_fail "Live plugin directory not found: $LIVE_PLUGIN_DIR"
    exit 1
fi
log_ok "Live plugin directory exists: $LIVE_PLUGIN_DIR"

# 2.5 Current live plugin file exists (we need something to back up)
if [[ ! -f "$LIVE_PLUGIN_FILE" ]]; then
    log_fail "Current live plugin not found: $LIVE_PLUGIN_FILE"
    exit 1
fi
log_ok "Current live plugin exists: $LIVE_PLUGIN_FILE"

# 2.6 Backup directory exists or can be created
if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "    Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi
if [[ ! -w "$BACKUP_DIR" ]]; then
    log_fail "Backup directory not writable: $BACKUP_DIR"
    exit 1
fi
log_ok "Backup directory writable: $BACKUP_DIR"

# 2.7 btrfs command available
if ! command -v btrfs >/dev/null 2>&1; then
    log_fail "btrfs command not found"
    exit 1
fi
log_ok "btrfs command available"

# 2.8 Snapshot directory exists
if [[ ! -d "$SNAPSHOT_DIR" ]]; then
    log_fail "Snapshot directory not found: $SNAPSHOT_DIR"
    exit 1
fi
log_ok "Snapshot directory exists: $SNAPSHOT_DIR"

# 2.9 Pre-snapshot name not already taken
if [[ -d "$PRE_SNAPSHOT_PATH" ]]; then
    log_fail "Pre-snapshot already exists: $PRE_SNAPSHOT_PATH (timestamp collision)"
    exit 1
fi
log_ok "Pre-snapshot name available: $PRE_SNAPSHOT_NAME"

# 2.10 Systemd services exist
if ! systemctl list-unit-files "$GATEWAY_SERVICE" >/dev/null 2>&1; then
    log_fail "Systemd unit not found: $GATEWAY_SERVICE"
    exit 1
fi
log_ok "Systemd unit exists: $GATEWAY_SERVICE"

if ! systemctl list-unit-files "$BROKER_SERVICE" >/dev/null 2>&1; then
    log_fail "Systemd unit not found: $BROKER_SERVICE"
    exit 1
fi
log_ok "Systemd unit exists: $BROKER_SERVICE"

# 2.11 Gateway is currently active (don't activate on a broken baseline)
GATEWAY_PRE=$(systemctl is-active "$GATEWAY_SERVICE" 2>/dev/null || true)
if [[ "$GATEWAY_PRE" != "active" ]]; then
    log_fail "Gateway is not active before activation (status: $GATEWAY_PRE)"
    exit 1
fi
log_ok "Gateway is currently active"

# 2.12 Broker is currently active
BROKER_PRE=$(systemctl is-active "$BROKER_SERVICE" 2>/dev/null || true)
if [[ "$BROKER_PRE" != "active" ]]; then
    log_fail "Broker is not active before activation (status: $BROKER_PRE)"
    exit 1
fi
log_ok "Broker is currently active"

# 2.13 Artifacts directory can be created
mkdir -p "$ARTIFACTS_DIR"
if [[ ! -w "$ARTIFACTS_DIR" ]]; then
    log_fail "Cannot write to artifacts directory: $ARTIFACTS_DIR"
    exit 1
fi
log_ok "Artifacts directory ready: $ARTIFACTS_DIR"

echo ""
echo "    All pre-flight checks passed."

# ============================================================
# 3. Pre-change root snapshot
# ============================================================

log_step "PRE-SNAPSHOT" "Creating pre-change root snapshot"

if ! btrfs subvolume snapshot -r / "$PRE_SNAPSHOT_PATH" >/dev/null; then
    log_fail "Failed to create pre-change snapshot: $PRE_SNAPSHOT_PATH"
    exit 1
fi

if [[ ! -d "$PRE_SNAPSHOT_PATH" ]]; then
    log_fail "Pre-change snapshot not found after creation: $PRE_SNAPSHOT_PATH"
    exit 1
fi

log_ok "Pre-change snapshot created: $PRE_SNAPSHOT_PATH"

# From this point on, failures should suggest rollback
trap 'abort_with_rollback' ERR

# ============================================================
# 4. Backup current live plugin
# ============================================================

log_step "BACKUP" "Backing up current live plugin"

cp "$LIVE_PLUGIN_FILE" "$BACKUP_FILE"

if [[ ! -f "$BACKUP_FILE" ]]; then
    log_fail "Backup file not found after copy: $BACKUP_FILE"
    abort_with_rollback
fi

# Verify backup matches current live file
LIVE_SHA=$(sha256sum "$LIVE_PLUGIN_FILE" | awk '{print $1}')
BACKUP_SHA=$(sha256sum "$BACKUP_FILE" | awk '{print $1}')
if [[ "$LIVE_SHA" != "$BACKUP_SHA" ]]; then
    log_fail "Backup checksum mismatch (live: $LIVE_SHA, backup: $BACKUP_SHA)"
    abort_with_rollback
fi

log_ok "Backup created: $BACKUP_FILE"
log_ok "Backup checksum verified: $BACKUP_SHA"

# ============================================================
# 5. Copy new plugin to live
# ============================================================

log_step "DEPLOY" "Copying new plugin to live location"

cp "$REPO_PLUGIN_SRC" "$LIVE_PLUGIN_FILE"
log_ok "File copied"

chown openclaw:openclaw "$LIVE_PLUGIN_FILE"
log_ok "Ownership set to openclaw:openclaw"

chmod 644 "$LIVE_PLUGIN_FILE"
log_ok "Permissions set to 644"

# Verify deployed file matches source
SRC_SHA=$(sha256sum "$REPO_PLUGIN_SRC" | awk '{print $1}')
DEPLOYED_SHA=$(sha256sum "$LIVE_PLUGIN_FILE" | awk '{print $1}')
if [[ "$SRC_SHA" != "$DEPLOYED_SHA" ]]; then
    log_fail "Deployed file checksum mismatch (source: $SRC_SHA, deployed: $DEPLOYED_SHA)"
    abort_with_rollback
fi

log_ok "Deployed file checksum verified: $DEPLOYED_SHA"

# ============================================================
# 6. Restart gateway
# ============================================================

log_step "RESTART" "Restarting gateway service"

systemctl restart "$GATEWAY_SERVICE"
log_ok "systemctl restart $GATEWAY_SERVICE issued"

echo "    Waiting ${HEALTH_DELAY}s for services to stabilize..."
sleep "$HEALTH_DELAY"

# ============================================================
# 7. Health check
# ============================================================

log_step "HEALTH" "Checking service health"

GATEWAY_STATUS=$(systemctl is-active "$GATEWAY_SERVICE" 2>/dev/null || true)
BROKER_STATUS=$(systemctl is-active "$BROKER_SERVICE" 2>/dev/null || true)

if [[ "$GATEWAY_STATUS" != "active" ]]; then
    log_fail "Gateway is not active after restart (status: $GATEWAY_STATUS)"
    # Capture journals before abort
    journalctl -u "$GATEWAY_SERVICE" -n 40 --no-pager > "${ARTIFACTS_DIR}/journal-gateway.txt" 2>&1 || true
    journalctl -u "$BROKER_SERVICE" -n 40 --no-pager > "${ARTIFACTS_DIR}/journal-broker.txt" 2>&1 || true
    abort_with_rollback
fi
log_ok "Gateway status: $GATEWAY_STATUS"

if [[ "$BROKER_STATUS" != "active" ]]; then
    log_fail "Broker is not active after restart (status: $BROKER_STATUS)"
    journalctl -u "$GATEWAY_SERVICE" -n 40 --no-pager > "${ARTIFACTS_DIR}/journal-gateway.txt" 2>&1 || true
    journalctl -u "$BROKER_SERVICE" -n 40 --no-pager > "${ARTIFACTS_DIR}/journal-broker.txt" 2>&1 || true
    abort_with_rollback
fi
log_ok "Broker status: $BROKER_STATUS"

# Capture journal logs for review
journalctl -u "$GATEWAY_SERVICE" -n 40 --no-pager > "${ARTIFACTS_DIR}/journal-gateway.txt" 2>&1 || true
journalctl -u "$BROKER_SERVICE" -n 40 --no-pager > "${ARTIFACTS_DIR}/journal-broker.txt" 2>&1 || true
log_ok "Journal logs captured to artifacts"

# Quick scan for obvious errors in gateway journal (non-blocking — just a warning)
if grep -qiE 'error|fail|exception|crash' "${ARTIFACTS_DIR}/journal-gateway.txt" 2>/dev/null; then
    echo "    WARNING: Gateway journal contains potential error keywords."
    echo "    Review ${ARTIFACTS_DIR}/journal-gateway.txt manually."
fi

# Disable ERR trap for post-success steps (snapshot + summary)
trap - ERR

# ============================================================
# 8. Post-change root snapshot
# ============================================================

log_step "POST-SNAPSHOT" "Creating post-change root snapshot"

if btrfs subvolume snapshot -r / "$POST_SNAPSHOT_PATH" >/dev/null 2>&1; then
    if [[ -d "$POST_SNAPSHOT_PATH" ]]; then
        log_ok "Post-change snapshot created: $POST_SNAPSHOT_PATH"
    else
        echo "    WARNING: Post-change snapshot command succeeded but path not found"
        POST_SNAPSHOT_PATH="(creation reported success but path not verified)"
    fi
else
    echo "    WARNING: Post-change snapshot creation failed (non-fatal)"
    POST_SNAPSHOT_PATH="(failed — non-fatal)"
fi

# ============================================================
# 9. Write results
# ============================================================

log_step "RESULTS" "Writing structured results"

write_result_file "SUCCESS"

# Write human-readable summary
cat > "${ARTIFACTS_DIR}/summary.txt" <<SUMMARYEOF
================================================================
  snapshot_post Slice Activation — Result Summary
================================================================

Timestamp:    ${TIMESTAMP}
Date (UTC):   $(date -u +'%Y-%m-%d %H:%M:%S UTC')
Operator:     ${SUDO_USER:-root}

--- Plugin Deployment ---
Source:       ${REPO_PLUGIN_SRC}
Target:       ${LIVE_PLUGIN_FILE}
Source SHA256: ${SRC_SHA}
Deploy SHA256: ${DEPLOYED_SHA}
Backup:       ${BACKUP_FILE}
Backup SHA256: ${BACKUP_SHA}

--- Snapshots ---
Pre-change:   ${PRE_SNAPSHOT_PATH}
Post-change:  ${POST_SNAPSHOT_PATH}

--- Service Health ---
Gateway:      ${GATEWAY_STATUS}
Broker:       ${BROKER_STATUS}

--- Result ---
Status:       SUCCESS

--- Artifacts ---
Directory:    ${ARTIFACTS_DIR}
Files:
  - summary.txt       (this file)
  - result.env         (machine-readable, used by rollback script)
  - journal-gateway.txt
  - journal-broker.txt

--- Next Steps ---
1. Review journal-gateway.txt for any plugin/tool registration warnings
2. In a FRESH Claude Code session, run agent-facing E2E tests:
   - Positive: snapshot_post with valid label+reason
   - Negative: invalid label, missing reason, non-object inputs
   - Regression: gateway_health + snapshot_pre still work
3. Do NOT mark as live verified until E2E tests pass
4. If issues found, rollback with:
   sudo bash ${SCRIPT_DIR}/rollback-snapshot-post-slice.sh ${ARTIFACTS_DIR}
================================================================
SUMMARYEOF

log_ok "Summary written: ${ARTIFACTS_DIR}/summary.txt"
log_ok "Result env written: ${ARTIFACTS_DIR}/result.env"

# ============================================================
# 10. Final output
# ============================================================

echo ""
echo "========================================================"
echo "  ACTIVATION COMPLETE — snapshot_post slice deployed"
echo "========================================================"
echo ""
echo "  Gateway: ${GATEWAY_STATUS}"
echo "  Broker:  ${BROKER_STATUS}"
echo "  Backup:  ${BACKUP_FILE}"
echo "  Pre-snap:  ${PRE_SNAPSHOT_PATH}"
echo "  Post-snap: ${POST_SNAPSHOT_PATH}"
echo ""
echo "  Artifacts: ${ARTIFACTS_DIR}"
echo ""
echo "  If rollback needed:"
echo "    sudo bash ${SCRIPT_DIR}/rollback-snapshot-post-slice.sh ${ARTIFACTS_DIR}"
echo ""
echo "  IMPORTANT: This is NOT yet live verified."
echo "  Agent-facing E2E tests must pass before writing live verified."
echo "========================================================"
