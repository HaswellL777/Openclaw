#!/usr/bin/env bash
# ocw-gateway-restart.sh — Wrapper for gateway_restart action
# Status: Phase 2 — contract stabilized with --no-block two-stage semantic
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, dispatches restart via --no-block, returns before restart completes
#
# Contract note (2026-03-16):
#   openclaw-broker.service has Requires=openclaw-gateway.service.
#   A synchronous `systemctl restart` would cause systemd to SIGTERM the broker,
#   severing the Unix socket before the response can be delivered.
#   Solution: `systemctl restart --no-block` dispatches the restart job to systemd
#   and returns immediately, allowing the broker to send the response before
#   the restart actually executes. The caller MUST subsequently invoke
#   gateway_health to verify the gateway is healthy after the restart completes.
#
# Design rules (per design-v3.md SS5.6.4):
# 1. Does exactly one thing: dispatch restart of openclaw-gateway.service
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
    "{\"reason\":$(jq -n --arg r "$REASON" '$r'),\"restart_dispatched\":false,\"verification_required\":true,\"service_active_after\":null,\"mode\":\"dry-run\"}" \
    "[STUB] Gateway restart — dry-run, no live execution" \
    "If gateway fails to start, check journalctl -u openclaw-gateway.service"
else
  # [LIVE] Production execution — requires root
  # Uses --no-block to dispatch restart asynchronously.
  # This ensures the broker can send the response BEFORE systemd
  # processes the restart (which would SIGTERM the broker due to
  # Requires=openclaw-gateway.service dependency).
  broker_require_live_capable

  echo "[LIVE] Dispatching gateway restart (--no-block). Reason: $REASON" >&2
  if ! systemctl restart --no-block openclaw-gateway.service 2>&1; then
    broker_error "error" "systemctl restart --no-block dispatch failed" "E_WRAPPER_FAILED"
  fi

  # NOTE: No sleep or post-restart health check here.
  # With --no-block, the restart has been queued but NOT executed yet.
  # The broker must return this response before systemd processes the restart.
  # Caller MUST invoke gateway_health afterward to verify the gateway is healthy.

  broker_emit_result \
    "{\"reason\":$(jq -n --arg r "$REASON" '$r'),\"restart_dispatched\":true,\"verification_required\":true,\"service_active_after\":null,\"mode\":\"live\"}" \
    "Gateway restart dispatched (--no-block). Broker returns before restart completes due to Requires= dependency. Call gateway_health to verify." \
    "If gateway fails to start, check journalctl -u openclaw-gateway.service"
fi
