#!/usr/bin/env bash
# ocw-gateway-restart.sh — Wrapper for gateway_restart action
# Status: Phase 2 implementation slice 1 — candidate wrapper, repo-only
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, restarts openclaw-gateway.service
#
# Design rules (per design-v3.md SS5.6.4):
# 1. Does exactly one thing: restart openclaw-gateway.service
# 2. Validates inputs before acting
# 3. Returns structured JSON result on stdout
# 4. Never executes free-form shell or user-supplied commands
# 5. Logs all actions to stderr
# 6. Failure exits non-zero with structured error JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# --- Common validation ---
broker_validate_request_file "$@"
broker_parse_common "$REQUEST_FILE"
broker_validate_action "gateway_restart"
broker_validate_required_fields

# --- Action-specific validation ---
REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE" 2>/dev/null || true)
if [ -z "$REASON" ]; then
  broker_error "error" "Missing required input: reason" "E_MISSING_INPUT"
fi

# --- Execution ---
if [ "${BROKER_DRY_RUN:-true}" = "true" ]; then
  echo "[STUB] Would run: systemctl restart openclaw-gateway.service" >&2
  echo "[STUB] Reason: $REASON" >&2
  echo "[STUB] Would verify: systemctl is-active openclaw-gateway.service" >&2

  broker_emit_result \
    "{\"reason\":$(jq -n --arg r "$REASON" '$r'),\"service_active_after\":null,\"mode\":\"dry-run\"}" \
    "[STUB] Gateway restart — dry-run, no live execution" \
    "If gateway fails to start, check journalctl -u openclaw-gateway.service"
else
  # [LIVE] Production execution — requires root
  broker_require_live_capable

  echo "[LIVE] Restarting openclaw-gateway.service. Reason: $REASON" >&2
  if ! systemctl restart openclaw-gateway.service 2>&1; then
    broker_error "error" "systemctl restart failed" "E_WRAPPER_FAILED"
  fi

  # Post-restart health check
  sleep 2
  local_service_active="unknown"
  if systemctl is-active --quiet openclaw-gateway.service 2>/dev/null; then
    local_service_active="active"
  else
    local_service_active="inactive"
    broker_error "error" "Gateway not active after restart" "E_WRAPPER_FAILED"
  fi

  broker_emit_result \
    "{\"reason\":$(jq -n --arg r "$REASON" '$r'),\"service_active_after\":\"${local_service_active}\",\"mode\":\"live\"}" \
    "Gateway restarted successfully" \
    "If gateway fails to start, check journalctl -u openclaw-gateway.service"
fi
