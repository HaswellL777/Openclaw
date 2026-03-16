#!/usr/bin/env bash
set -euo pipefail

# revert-gateway-restart-slice.sh
# Purpose: Single-command revert for gateway_restart live activation
# Usage:   sudo bash scripts/revert-gateway-restart-slice.sh <artifacts-dir>
#
# Reads result.env from the activation artifacts directory to determine:
#   - Which plugin backup file to restore
#   - Which wrapper backup file to restore
#   - Which live paths to restore to
#
# Steps:
#   1. Read and validate result.env from artifacts dir
#   2. Verify plugin and wrapper backup files exist
#   3. Restore plugin backup to live plugin path (openclaw:openclaw 644)
#   4. Restore wrapper backup to live wrapper path (root:root 755)
#   5. Restart gateway
#   6. Verify gateway + broker health
#   7. Write revert result to artifacts dir
#
# Safety:
#   - Only restores the exact backup files recorded in result.env
#   - Does not delete snapshots (audit trail preserved)
#   - Does not modify /etc/openclaw/openclaw.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Input validation
# ============================================================

if [[ $# -lt 1 ]]; then
    echo "Usage: sudo bash $0 <artifacts-dir>" >&2
    echo "" >&2
    echo "The artifacts-dir is the directory created by activate-gateway-restart-slice.sh," >&2
    echo "typically: artifacts/phase2/gateway-restart-live-activation-YYYYMMDD-HHMM" >&2
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
    echo "Cannot determine backup file paths without result.env." >&2
    exit 1
fi

# ============================================================
# Read result.env
# ============================================================

echo ""
echo ">>> [REVERT] Reading activation result from: $RESULT_ENV"

# Source result.env to get variables (safe: we wrote this file ourselves)
# shellcheck source=/dev/null
source "$RESULT_ENV"

# Validate required variables for plugin
if [[ -z "${BACKUP_FILE:-}" ]]; then
    echo "FAIL: BACKUP_FILE not set in result.env" >&2
    exit 1
fi

if [[ -z "${LIVE_PLUGIN_FILE:-}" ]]; then
    echo "FAIL: LIVE_PLUGIN_FILE not set in result.env" >&2
    exit 1
fi

# Validate required variables for wrapper
if [[ -z "${WRAPPER_BACKUP_FILE:-}" ]]; then
    echo "FAIL: WRAPPER_BACKUP_FILE not set in result.env" >&2
    exit 1
fi

if [[ -z "${LIVE_WRAPPER_FILE:-}" ]]; then
    echo "FAIL: LIVE_WRAPPER_FILE not set in result.env" >&2
    exit 1
fi

echo "    Plugin backup:     $BACKUP_FILE"
echo "    Plugin live:       $LIVE_PLUGIN_FILE"
echo "    Wrapper backup:    $WRAPPER_BACKUP_FILE"
echo "    Wrapper live:      $LIVE_WRAPPER_FILE"

# ============================================================
# Verify backup files
# ============================================================

echo ""
echo ">>> [VERIFY] Checking backup files exist"

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "FAIL: Plugin backup file not found: $BACKUP_FILE" >&2
    echo "Manual intervention required." >&2
    exit 1
fi
echo "    OK: Plugin backup file exists"

PLUGIN_BACKUP_SHA=$(sha256sum "$BACKUP_FILE" | awk '{print $1}')
echo "    Plugin backup SHA256: $PLUGIN_BACKUP_SHA"

if [[ ! -f "$WRAPPER_BACKUP_FILE" ]]; then
    echo "FAIL: Wrapper backup file not found: $WRAPPER_BACKUP_FILE" >&2
    echo "Manual intervention required." >&2
    exit 1
fi
echo "    OK: Wrapper backup file exists"

WRAPPER_BACKUP_SHA=$(sha256sum "$WRAPPER_BACKUP_FILE" | awk '{print $1}')
echo "    Wrapper backup SHA256: $WRAPPER_BACKUP_SHA"

# ============================================================
# Restore plugin backup
# ============================================================

echo ""
echo ">>> [RESTORE-PLUGIN] Copying plugin backup to live plugin path"

cp "$BACKUP_FILE" "$LIVE_PLUGIN_FILE"
chown openclaw:openclaw "$LIVE_PLUGIN_FILE"
chmod 644 "$LIVE_PLUGIN_FILE"

PLUGIN_RESTORED_SHA=$(sha256sum "$LIVE_PLUGIN_FILE" | awk '{print $1}')
if [[ "$PLUGIN_BACKUP_SHA" != "$PLUGIN_RESTORED_SHA" ]]; then
    echo "FAIL: Restored plugin checksum mismatch" >&2
    exit 1
fi

echo "    OK: Plugin restored and verified (SHA256: $PLUGIN_RESTORED_SHA)"

# ============================================================
# Restore wrapper backup
# ============================================================

echo ""
echo ">>> [RESTORE-WRAPPER] Copying wrapper backup to live wrapper path"

cp "$WRAPPER_BACKUP_FILE" "$LIVE_WRAPPER_FILE"
chown root:root "$LIVE_WRAPPER_FILE"
chmod 755 "$LIVE_WRAPPER_FILE"

WRAPPER_RESTORED_SHA=$(sha256sum "$LIVE_WRAPPER_FILE" | awk '{print $1}')
if [[ "$WRAPPER_BACKUP_SHA" != "$WRAPPER_RESTORED_SHA" ]]; then
    echo "FAIL: Restored wrapper checksum mismatch" >&2
    exit 1
fi

echo "    OK: Wrapper restored and verified (SHA256: $WRAPPER_RESTORED_SHA)"

# ============================================================
# Restart gateway
# ============================================================

echo ""
echo ">>> [RESTART] Restarting gateway service"

GATEWAY_SERVICE="openclaw-gateway.service"
BROKER_SERVICE="openclaw-broker.service"

systemctl restart "$GATEWAY_SERVICE"
echo "    OK: systemctl restart issued"

echo "    Waiting 3s for services to stabilize..."
sleep 3

# ============================================================
# Health check (with retry)
# ============================================================

echo ""
echo ">>> [HEALTH] Checking service health (up to 13s)"

HEALTH_RETRY_INTERVAL=2
HEALTH_MAX_RETRIES=5
HEALTH_ATTEMPT=0

while true; do
    GW_STATUS=$(systemctl is-active "$GATEWAY_SERVICE" 2>/dev/null || true)
    BR_STATUS=$(systemctl is-active "$BROKER_SERVICE" 2>/dev/null || true)

    if [[ "$GW_STATUS" == "active" && "$BR_STATUS" == "active" ]]; then
        break
    fi

    HEALTH_ATTEMPT=$((HEALTH_ATTEMPT + 1))
    if [[ $HEALTH_ATTEMPT -gt $HEALTH_MAX_RETRIES ]]; then
        break
    fi

    echo "    Attempt $HEALTH_ATTEMPT/$HEALTH_MAX_RETRIES: gateway=$GW_STATUS broker=$BR_STATUS — retrying in ${HEALTH_RETRY_INTERVAL}s..."
    sleep "$HEALTH_RETRY_INTERVAL"
done

echo "    Gateway: $GW_STATUS"
echo "    Broker:  $BR_STATUS"

if [[ "$GW_STATUS" != "active" ]]; then
    echo "FAIL: Gateway is not active after revert restart (waited $((3 + HEALTH_ATTEMPT * HEALTH_RETRY_INTERVAL))s)" >&2
fi

if [[ "$BR_STATUS" != "active" ]]; then
    echo "FAIL: Broker is not active after revert restart (waited $((3 + HEALTH_ATTEMPT * HEALTH_RETRY_INTERVAL))s)" >&2
fi

if [[ $HEALTH_ATTEMPT -gt 0 && "$GW_STATUS" == "active" && "$BR_STATUS" == "active" ]]; then
    echo "    OK: Health check passed after $HEALTH_ATTEMPT retries"
fi

# ============================================================
# Write revert result
# ============================================================

REVERT_TS="$(date +%Y%m%d-%H%M)"

cat > "${ARTIFACTS_DIR}/revert-result.env" <<RBEOF
# gateway_restart slice revert result
# Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
REVERT_TIMESTAMP="${REVERT_TS}"
PLUGIN_BACKUP_FILE="${BACKUP_FILE}"
PLUGIN_BACKUP_SHA256="${PLUGIN_BACKUP_SHA}"
PLUGIN_RESTORED_SHA256="${PLUGIN_RESTORED_SHA}"
LIVE_PLUGIN_FILE="${LIVE_PLUGIN_FILE}"
WRAPPER_BACKUP_FILE="${WRAPPER_BACKUP_FILE}"
WRAPPER_BACKUP_SHA256="${WRAPPER_BACKUP_SHA}"
WRAPPER_RESTORED_SHA256="${WRAPPER_RESTORED_SHA}"
LIVE_WRAPPER_FILE="${LIVE_WRAPPER_FILE}"
GATEWAY_STATUS="${GW_STATUS}"
BROKER_STATUS="${BR_STATUS}"
RBEOF

# Capture post-revert journals
journalctl -u "$GATEWAY_SERVICE" -n 30 --no-pager > "${ARTIFACTS_DIR}/revert-journal-gateway.txt" 2>&1 || true
journalctl -u "$BROKER_SERVICE" -n 30 --no-pager > "${ARTIFACTS_DIR}/revert-journal-broker.txt" 2>&1 || true

echo ""
echo "========================================================"
if [[ "$GW_STATUS" == "active" && "$BR_STATUS" == "active" ]]; then
    echo "  REVERT COMPLETE — previous plugin + wrapper restored"
else
    echo "  REVERT PARTIAL — services may need manual attention"
fi
echo "========================================================"
echo ""
echo "  Gateway: $GW_STATUS"
echo "  Broker:  $BR_STATUS"
echo "  Plugin restored from:  $BACKUP_FILE"
echo "  Wrapper restored from: $WRAPPER_BACKUP_FILE"
echo "  Revert artifacts: $ARTIFACTS_DIR"
echo "========================================================"
