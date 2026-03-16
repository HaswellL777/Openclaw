#!/usr/bin/env bash
set -euo pipefail

# rollback-snapshot-pre-slice.sh
# Purpose: Single-command rollback for snapshot_pre live activation
# Usage:   sudo bash scripts/rollback-snapshot-pre-slice.sh <artifacts-dir>
#
# Reads result.env from the activation artifacts directory to determine:
#   - Which backup file to restore
#   - Which live plugin path to restore to
#
# Steps:
#   1. Read and validate result.env from artifacts dir
#   2. Verify backup file exists
#   3. Restore backup to live plugin path
#   4. Restart gateway
#   5. Verify gateway + broker health
#   6. Write rollback result to artifacts dir
#
# Safety:
#   - Only restores the exact backup file recorded in result.env
#   - Does not delete snapshots (audit trail preserved)
#   - Does not modify /etc/openclaw/openclaw.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Input validation
# ============================================================

if [[ $# -lt 1 ]]; then
    echo "Usage: sudo bash $0 <artifacts-dir>" >&2
    echo "" >&2
    echo "The artifacts-dir is the directory created by activate-snapshot-pre-slice.sh," >&2
    echo "typically: artifacts/phase2/snapshot-pre-live-activation-YYYYMMDD-HHMM" >&2
    exit 1
fi

ARTIFACTS_DIR="$1"
RESULT_ENV="${ARTIFACTS_DIR}/result.env"

# Must be root
if [[ $EUID -ne 0 ]]; then
    echo "FAIL: This script must be run with sudo" >&2
    echo "Usage: sudo bash $0 $ARTIFACTS_DIR" >&2
    exit 1
fi

# Result file must exist
if [[ ! -f "$RESULT_ENV" ]]; then
    echo "FAIL: result.env not found: $RESULT_ENV" >&2
    echo "Cannot determine backup file path without result.env." >&2
    exit 1
fi

# ============================================================
# Read result.env
# ============================================================

echo ""
echo ">>> [ROLLBACK] Reading activation result from: $RESULT_ENV"

# Source result.env to get variables (safe: we wrote this file ourselves)
# shellcheck source=/dev/null
source "$RESULT_ENV"

# Validate required variables
if [[ -z "${BACKUP_FILE:-}" ]]; then
    echo "FAIL: BACKUP_FILE not set in result.env" >&2
    exit 1
fi

if [[ -z "${LIVE_PLUGIN_FILE:-}" ]]; then
    echo "FAIL: LIVE_PLUGIN_FILE not set in result.env" >&2
    exit 1
fi

echo "    Backup file:     $BACKUP_FILE"
echo "    Live plugin:     $LIVE_PLUGIN_FILE"

# ============================================================
# Verify backup file
# ============================================================

echo ""
echo ">>> [VERIFY] Checking backup file exists"

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "FAIL: Backup file not found: $BACKUP_FILE" >&2
    echo "Manual intervention required." >&2
    exit 1
fi

echo "    OK: Backup file exists"

BACKUP_SHA=$(sha256sum "$BACKUP_FILE" | awk '{print $1}')
echo "    Backup SHA256: $BACKUP_SHA"

# ============================================================
# Restore backup
# ============================================================

echo ""
echo ">>> [RESTORE] Copying backup to live plugin path"

cp "$BACKUP_FILE" "$LIVE_PLUGIN_FILE"
chown openclaw:openclaw "$LIVE_PLUGIN_FILE"
chmod 644 "$LIVE_PLUGIN_FILE"

RESTORED_SHA=$(sha256sum "$LIVE_PLUGIN_FILE" | awk '{print $1}')
if [[ "$BACKUP_SHA" != "$RESTORED_SHA" ]]; then
    echo "FAIL: Restored file checksum mismatch" >&2
    exit 1
fi

echo "    OK: Plugin restored and verified (SHA256: $RESTORED_SHA)"

# ============================================================
# Restart gateway
# ============================================================

echo ""
echo ">>> [RESTART] Restarting gateway service"

GATEWAY_SERVICE="openclaw-gateway.service"
BROKER_SERVICE="openclaw-broker.service"

systemctl restart "$GATEWAY_SERVICE"
echo "    OK: systemctl restart issued"

echo "    Waiting 4s for services to stabilize..."
sleep 4

# ============================================================
# Health check
# ============================================================

echo ""
echo ">>> [HEALTH] Checking service health"

GW_STATUS=$(systemctl is-active "$GATEWAY_SERVICE" 2>/dev/null || true)
BR_STATUS=$(systemctl is-active "$BROKER_SERVICE" 2>/dev/null || true)

echo "    Gateway: $GW_STATUS"
echo "    Broker:  $BR_STATUS"

if [[ "$GW_STATUS" != "active" ]]; then
    echo "FAIL: Gateway is not active after rollback restart" >&2
fi

if [[ "$BR_STATUS" != "active" ]]; then
    echo "FAIL: Broker is not active after rollback restart" >&2
fi

# ============================================================
# Write rollback result
# ============================================================

ROLLBACK_TS="$(date +%Y%m%d-%H%M)"

cat > "${ARTIFACTS_DIR}/rollback-result.env" <<RBEOF
# snapshot_pre slice rollback result
# Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
ROLLBACK_TIMESTAMP="${ROLLBACK_TS}"
BACKUP_FILE="${BACKUP_FILE}"
BACKUP_SHA256="${BACKUP_SHA}"
RESTORED_SHA256="${RESTORED_SHA}"
LIVE_PLUGIN_FILE="${LIVE_PLUGIN_FILE}"
GATEWAY_STATUS="${GW_STATUS}"
BROKER_STATUS="${BR_STATUS}"
RBEOF

# Capture post-rollback journals
journalctl -u "$GATEWAY_SERVICE" -n 30 --no-pager > "${ARTIFACTS_DIR}/rollback-journal-gateway.txt" 2>&1 || true
journalctl -u "$BROKER_SERVICE" -n 30 --no-pager > "${ARTIFACTS_DIR}/rollback-journal-broker.txt" 2>&1 || true

echo ""
echo "========================================================"
if [[ "$GW_STATUS" == "active" && "$BR_STATUS" == "active" ]]; then
    echo "  ROLLBACK COMPLETE — previous plugin restored"
else
    echo "  ROLLBACK PARTIAL — services may need manual attention"
fi
echo "========================================================"
echo ""
echo "  Gateway: $GW_STATUS"
echo "  Broker:  $BR_STATUS"
echo "  Restored from: $BACKUP_FILE"
echo "  Rollback artifacts: $ARTIFACTS_DIR"
echo "========================================================"
