#!/usr/bin/env bash
set -euo pipefail

# activate-rollback-prepare-slice.sh
# Purpose: Single-command operator script for rollback_prepare live activation
# Usage:   sudo bash scripts/activate-rollback-prepare-slice.sh
#
# This script performs the complete rollback_prepare slice activation:
#   1. Pre-flight checks (root, files, content verification, btrfs, systemd)
#   2. Pre-change root btrfs snapshot
#   3. Backup current live plugin AND live wrapper
#   4. Copy new plugin + wrapper with correct ownership/permissions
#   5. Restart gateway
#   6. Health check (gateway + broker + journal error scan)
#   7. Write structured results to artifacts/
#
# NOTE: Post-change snapshot is NOT created by this script.
#       Post-change snapshot should be created separately after E2E verification passes.
#
# On failure: stops immediately, prints revert command.
# Revert:    sudo bash scripts/revert-rollback-prepare-slice.sh <artifacts-dir>
#
# Safety:
#   - set -euo pipefail: any failure stops execution
#   - All paths are hardcoded constants, no user-supplied path expansion
#   - No /etc/openclaw/openclaw.json modification
#   - Plugin + wrapper file backups are taken BEFORE any modification
#   - Pre-change root snapshot is taken BEFORE any modification

# ============================================================
# 1. Unified variable block
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Plugin source and target
REPO_PLUGIN_SRC="${REPO_ROOT}/plugins/host-ops-tool/index.js"
LIVE_PLUGIN_DIR="/var/lib/openclaw/.openclaw/extensions/host-ops-tool"
LIVE_PLUGIN_FILE="${LIVE_PLUGIN_DIR}/index.js"

# Wrapper source and target
REPO_WRAPPER_SRC="${REPO_ROOT}/broker/wrappers/ocw-rollback-prepare.sh"
LIVE_WRAPPER_DIR="/opt/openclaw/broker/wrappers"
LIVE_WRAPPER_FILE="${LIVE_WRAPPER_DIR}/ocw-rollback-prepare.sh"

# Backup
BACKUP_DIR="/var/lib/openclaw/host-ops-tool-backups"

# Timestamps and naming
TIMESTAMP="$(date +%Y%m%d-%H%M)"
PLUGIN_BACKUP_FILE="${BACKUP_DIR}/index.js.backup-before-rollback-prepare-slice-${TIMESTAMP}"
WRAPPER_BACKUP_FILE="${BACKUP_DIR}/ocw-rollback-prepare.sh.backup-before-rollback-prepare-slice-${TIMESTAMP}"

# Snapshots
SNAPSHOT_DIR="/.snapshots"
PRE_SNAPSHOT_NAME="root-pre-rollback-prepare-slice-${TIMESTAMP}"
PRE_SNAPSHOT_PATH="${SNAPSHOT_DIR}/${PRE_SNAPSHOT_NAME}"

# Artifacts output
ARTIFACTS_DIR="${REPO_ROOT}/artifacts/phase2/rollback-prepare-live-activation-${TIMESTAMP}"

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

abort_with_revert() {
    echo "" >&2
    echo "========================================" >&2
    echo "  ACTIVATION FAILED — see error above" >&2
    echo "========================================" >&2
    echo "" >&2
    echo "Revert command:" >&2
    echo "  sudo bash ${SCRIPT_DIR}/revert-rollback-prepare-slice.sh ${ARTIFACTS_DIR}" >&2
    echo "" >&2
    # Write partial result before exiting
    write_result_file "FAILED"
    exit 1
}

write_result_file() {
    local final_status="$1"
    mkdir -p "$ARTIFACTS_DIR"
    cat > "${ARTIFACTS_DIR}/result.env" <<RESULTEOF
# rollback_prepare slice activation result
# Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
TIMESTAMP="${TIMESTAMP}"
REPO_PLUGIN_SRC="${REPO_PLUGIN_SRC}"
LIVE_PLUGIN_FILE="${LIVE_PLUGIN_FILE}"
BACKUP_FILE="${PLUGIN_BACKUP_FILE}"
REPO_WRAPPER_SRC="${REPO_WRAPPER_SRC}"
LIVE_WRAPPER_FILE="${LIVE_WRAPPER_FILE}"
WRAPPER_BACKUP_FILE="${WRAPPER_BACKUP_FILE}"
PRE_SNAPSHOT_NAME="${PRE_SNAPSHOT_NAME}"
PRE_SNAPSHOT_PATH="${PRE_SNAPSHOT_PATH}"
PLUGIN_BACKUP_SHA256="${PLUGIN_BACKUP_SHA:-unknown}"
PLUGIN_DEPLOYED_SHA256="${PLUGIN_DEPLOYED_SHA:-unknown}"
WRAPPER_BACKUP_SHA256="${WRAPPER_BACKUP_SHA:-unknown}"
WRAPPER_DEPLOYED_SHA256="${WRAPPER_DEPLOYED_SHA:-unknown}"
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

# 2.3 Source wrapper file exists
if [[ ! -f "$REPO_WRAPPER_SRC" ]]; then
    log_fail "Source wrapper not found: $REPO_WRAPPER_SRC"
    exit 1
fi
log_ok "Source wrapper exists: $REPO_WRAPPER_SRC"

# 2.4 PREFLIGHT-CONTENT: Verify repo plugin contains "rollback_prepare" in ENABLED_ACTIONS
if ! grep -q '"rollback_prepare"' "$REPO_PLUGIN_SRC"; then
    log_fail "Source plugin does not contain rollback_prepare in ENABLED_ACTIONS"
    exit 1
fi
log_ok "Source plugin contains rollback_prepare in ENABLED_ACTIONS"

# 2.5 PREFLIGHT-CONTENT: Verify repo wrapper contains "prepare_only" (new contract)
if ! grep -q 'prepare_only' "$REPO_WRAPPER_SRC"; then
    log_fail "Source wrapper does not contain prepare_only (still has old rollback_steps contract?)"
    exit 1
fi
log_ok "Source wrapper contains prepare_only (new contract verified)"

# 2.6 Verify repo wrapper does NOT contain rollback_steps (old contract removed)
if grep -q 'rollback_steps' "$REPO_WRAPPER_SRC"; then
    log_fail "Source wrapper still contains rollback_steps (old contract not removed)"
    exit 1
fi
log_ok "Source wrapper does not contain rollback_steps (old contract removed)"

# 2.7 Live plugin directory exists
if [[ ! -d "$LIVE_PLUGIN_DIR" ]]; then
    log_fail "Live plugin directory not found: $LIVE_PLUGIN_DIR"
    exit 1
fi
log_ok "Live plugin directory exists: $LIVE_PLUGIN_DIR"

# 2.8 Current live plugin file exists (we need something to back up)
if [[ ! -f "$LIVE_PLUGIN_FILE" ]]; then
    log_fail "Current live plugin not found: $LIVE_PLUGIN_FILE"
    exit 1
fi
log_ok "Current live plugin exists: $LIVE_PLUGIN_FILE"

# 2.9 Live wrapper directory exists
if [[ ! -d "$LIVE_WRAPPER_DIR" ]]; then
    log_fail "Live wrapper directory not found: $LIVE_WRAPPER_DIR"
    exit 1
fi
log_ok "Live wrapper directory exists: $LIVE_WRAPPER_DIR"

# 2.10 Current live wrapper file exists (we need something to back up)
if [[ ! -f "$LIVE_WRAPPER_FILE" ]]; then
    log_fail "Current live wrapper not found: $LIVE_WRAPPER_FILE"
    exit 1
fi
log_ok "Current live wrapper exists: $LIVE_WRAPPER_FILE"

# 2.11 Backup directory exists or can be created
if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "    Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi
if [[ ! -w "$BACKUP_DIR" ]]; then
    log_fail "Backup directory not writable: $BACKUP_DIR"
    exit 1
fi
log_ok "Backup directory writable: $BACKUP_DIR"

# 2.12 btrfs command available
if ! command -v btrfs >/dev/null 2>&1; then
    log_fail "btrfs command not found"
    exit 1
fi
log_ok "btrfs command available"

# 2.13 Snapshot directory exists
if [[ ! -d "$SNAPSHOT_DIR" ]]; then
    log_fail "Snapshot directory not found: $SNAPSHOT_DIR"
    exit 1
fi
log_ok "Snapshot directory exists: $SNAPSHOT_DIR"

# 2.14 Pre-snapshot name not already taken
if [[ -d "$PRE_SNAPSHOT_PATH" ]]; then
    log_fail "Pre-snapshot already exists: $PRE_SNAPSHOT_PATH (timestamp collision)"
    exit 1
fi
log_ok "Pre-snapshot name available: $PRE_SNAPSHOT_NAME"

# 2.15 Systemd services exist
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

# 2.16 Gateway is currently active (don't activate on a broken baseline)
GATEWAY_PRE=$(systemctl is-active "$GATEWAY_SERVICE" 2>/dev/null || true)
if [[ "$GATEWAY_PRE" != "active" ]]; then
    log_fail "Gateway is not active before activation (status: $GATEWAY_PRE)"
    exit 1
fi
log_ok "Gateway is currently active"

# 2.17 Broker is currently active
BROKER_PRE=$(systemctl is-active "$BROKER_SERVICE" 2>/dev/null || true)
if [[ "$BROKER_PRE" != "active" ]]; then
    log_fail "Broker is not active before activation (status: $BROKER_PRE)"
    exit 1
fi
log_ok "Broker is currently active"

# 2.18 Artifacts directory can be created
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

# From this point on, failures should suggest revert
trap 'abort_with_revert' ERR

# ============================================================
# 4. Backup current live plugin AND wrapper
# ============================================================

log_step "BACKUP" "Backing up current live plugin and wrapper"

# 4.1 Backup plugin
cp "$LIVE_PLUGIN_FILE" "$PLUGIN_BACKUP_FILE"

if [[ ! -f "$PLUGIN_BACKUP_FILE" ]]; then
    log_fail "Plugin backup file not found after copy: $PLUGIN_BACKUP_FILE"
    abort_with_revert
fi

LIVE_PLUGIN_SHA=$(sha256sum "$LIVE_PLUGIN_FILE" | awk '{print $1}')
PLUGIN_BACKUP_SHA=$(sha256sum "$PLUGIN_BACKUP_FILE" | awk '{print $1}')
if [[ "$LIVE_PLUGIN_SHA" != "$PLUGIN_BACKUP_SHA" ]]; then
    log_fail "Plugin backup checksum mismatch (live: $LIVE_PLUGIN_SHA, backup: $PLUGIN_BACKUP_SHA)"
    abort_with_revert
fi

log_ok "Plugin backup created: $PLUGIN_BACKUP_FILE"
log_ok "Plugin backup checksum verified: $PLUGIN_BACKUP_SHA"

# 4.2 Backup wrapper
cp "$LIVE_WRAPPER_FILE" "$WRAPPER_BACKUP_FILE"

if [[ ! -f "$WRAPPER_BACKUP_FILE" ]]; then
    log_fail "Wrapper backup file not found after copy: $WRAPPER_BACKUP_FILE"
    abort_with_revert
fi

LIVE_WRAPPER_SHA=$(sha256sum "$LIVE_WRAPPER_FILE" | awk '{print $1}')
WRAPPER_BACKUP_SHA=$(sha256sum "$WRAPPER_BACKUP_FILE" | awk '{print $1}')
if [[ "$LIVE_WRAPPER_SHA" != "$WRAPPER_BACKUP_SHA" ]]; then
    log_fail "Wrapper backup checksum mismatch (live: $LIVE_WRAPPER_SHA, backup: $WRAPPER_BACKUP_SHA)"
    abort_with_revert
fi

log_ok "Wrapper backup created: $WRAPPER_BACKUP_FILE"
log_ok "Wrapper backup checksum verified: $WRAPPER_BACKUP_SHA"

# ============================================================
# 5. Deploy new plugin and wrapper to live
# ============================================================

log_step "DEPLOY" "Copying new plugin and wrapper to live locations"

# 5.1 Deploy plugin
cp "$REPO_PLUGIN_SRC" "$LIVE_PLUGIN_FILE"
chown openclaw:openclaw "$LIVE_PLUGIN_FILE"
chmod 644 "$LIVE_PLUGIN_FILE"

PLUGIN_SRC_SHA=$(sha256sum "$REPO_PLUGIN_SRC" | awk '{print $1}')
PLUGIN_DEPLOYED_SHA=$(sha256sum "$LIVE_PLUGIN_FILE" | awk '{print $1}')
if [[ "$PLUGIN_SRC_SHA" != "$PLUGIN_DEPLOYED_SHA" ]]; then
    log_fail "Deployed plugin checksum mismatch (source: $PLUGIN_SRC_SHA, deployed: $PLUGIN_DEPLOYED_SHA)"
    abort_with_revert
fi

log_ok "Plugin deployed: $LIVE_PLUGIN_FILE (openclaw:openclaw 644)"
log_ok "Plugin deployed checksum verified: $PLUGIN_DEPLOYED_SHA"

# 5.2 Deploy wrapper
cp "$REPO_WRAPPER_SRC" "$LIVE_WRAPPER_FILE"
chown root:root "$LIVE_WRAPPER_FILE"
chmod 755 "$LIVE_WRAPPER_FILE"

WRAPPER_SRC_SHA=$(sha256sum "$REPO_WRAPPER_SRC" | awk '{print $1}')
WRAPPER_DEPLOYED_SHA=$(sha256sum "$LIVE_WRAPPER_FILE" | awk '{print $1}')
if [[ "$WRAPPER_SRC_SHA" != "$WRAPPER_DEPLOYED_SHA" ]]; then
    log_fail "Deployed wrapper checksum mismatch (source: $WRAPPER_SRC_SHA, deployed: $WRAPPER_DEPLOYED_SHA)"
    abort_with_revert
fi

log_ok "Wrapper deployed: $LIVE_WRAPPER_FILE (root:root 755)"
log_ok "Wrapper deployed checksum verified: $WRAPPER_DEPLOYED_SHA"

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
    abort_with_revert
fi
log_ok "Gateway status: $GATEWAY_STATUS"

if [[ "$BROKER_STATUS" != "active" ]]; then
    log_fail "Broker is not active after restart (status: $BROKER_STATUS)"
    journalctl -u "$GATEWAY_SERVICE" -n 40 --no-pager > "${ARTIFACTS_DIR}/journal-gateway.txt" 2>&1 || true
    journalctl -u "$BROKER_SERVICE" -n 40 --no-pager > "${ARTIFACTS_DIR}/journal-broker.txt" 2>&1 || true
    abort_with_revert
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

# Disable ERR trap for post-success steps
trap - ERR

# ============================================================
# 8. Write results
# ============================================================

log_step "RESULTS" "Writing structured results"

write_result_file "SUCCESS"

# Write human-readable summary
cat > "${ARTIFACTS_DIR}/summary.txt" <<SUMMARYEOF
================================================================
  rollback_prepare Slice Activation — Result Summary
================================================================

Timestamp:    ${TIMESTAMP}
Date (UTC):   $(date -u +'%Y-%m-%d %H:%M:%S UTC')
Operator:     ${SUDO_USER:-root}

--- Plugin Deployment ---
Source:           ${REPO_PLUGIN_SRC}
Target:           ${LIVE_PLUGIN_FILE}
Source SHA256:     ${PLUGIN_SRC_SHA}
Deployed SHA256:  ${PLUGIN_DEPLOYED_SHA}
Backup:           ${PLUGIN_BACKUP_FILE}
Backup SHA256:    ${PLUGIN_BACKUP_SHA}

--- Wrapper Deployment ---
Source:           ${REPO_WRAPPER_SRC}
Target:           ${LIVE_WRAPPER_FILE}
Source SHA256:     ${WRAPPER_SRC_SHA}
Deployed SHA256:  ${WRAPPER_DEPLOYED_SHA}
Backup:           ${WRAPPER_BACKUP_FILE}
Backup SHA256:    ${WRAPPER_BACKUP_SHA}

--- Snapshots ---
Pre-change:   ${PRE_SNAPSHOT_PATH}
Post-change:  (not created — create after E2E verification passes)

--- Service Health ---
Gateway:      ${GATEWAY_STATUS}
Broker:       ${BROKER_STATUS}

--- Result ---
Status:       SUCCESS

--- Artifacts ---
Directory:    ${ARTIFACTS_DIR}
Files:
  - summary.txt       (this file)
  - result.env         (machine-readable, used by revert script)
  - journal-gateway.txt
  - journal-broker.txt

--- Next Steps ---
1. Review journal-gateway.txt for any plugin/tool registration warnings
2. In a FRESH Claude Code session, run agent-facing E2E tests:
   - Positive: rollback_prepare with valid target_snapshot+reason
   - Negative: missing target_snapshot, nonexistent snapshot, non-enabled action
   - Regression: gateway_health + snapshot_pre + snapshot_post still work
3. Do NOT mark as live verified until E2E tests pass
4. After E2E passes, create post-change snapshot (via agent snapshot_post or manually)
5. If issues found, revert with:
   sudo bash ${SCRIPT_DIR}/revert-rollback-prepare-slice.sh ${ARTIFACTS_DIR}
================================================================
SUMMARYEOF

log_ok "Summary written: ${ARTIFACTS_DIR}/summary.txt"
log_ok "Result env written: ${ARTIFACTS_DIR}/result.env"

# ============================================================
# 9. Final output
# ============================================================

echo ""
echo "========================================================"
echo "  ACTIVATION COMPLETE — rollback_prepare slice deployed"
echo "========================================================"
echo ""
echo "  Gateway: ${GATEWAY_STATUS}"
echo "  Broker:  ${BROKER_STATUS}"
echo ""
echo "  Plugin backup:  ${PLUGIN_BACKUP_FILE}"
echo "  Wrapper backup: ${WRAPPER_BACKUP_FILE}"
echo "  Pre-snap:       ${PRE_SNAPSHOT_PATH}"
echo ""
echo "  Artifacts: ${ARTIFACTS_DIR}"
echo ""
echo "  If revert needed:"
echo "    sudo bash ${SCRIPT_DIR}/revert-rollback-prepare-slice.sh ${ARTIFACTS_DIR}"
echo ""
echo "  IMPORTANT: This is NOT yet live verified."
echo "  Agent-facing E2E tests must pass before writing live verified."
echo "  Post-change snapshot should be created AFTER E2E verification passes."
echo "========================================================"
