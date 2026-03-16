#!/usr/bin/env bash
# ocw-gateway-restart.sh — Wrapper for gateway_restart action
# Status: Phase 2 — deferred dispatch via systemd-run transient timer
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, schedules restart via systemd-run transient timer,
#               returns before restart executes
#
# Contract note (2026-03-16, revised):
#   openclaw-broker.service has Requires=openclaw-gateway.service.
#   A synchronous `systemctl restart` (or even --no-block) causes systemd to
#   SIGTERM the broker before the response can be delivered, because the After=
#   reverse stop order kills broker BEFORE gateway in the restart sequence.
#   --no-block was attempted and FAILED in live testing (E_BROKER_INTERNAL / -15).
#
#   Solution: `systemd-run --on-active=2s` creates a transient timer unit that
#   executes `systemctl restart openclaw-gateway.service` ~2 seconds later,
#   in an independent cgroup outside the broker's process tree.
#   This completely decouples the restart execution from the broker lifecycle.
#
#   IMPORTANT: systemd-run success (exit code 0) means the transient timer/unit
#   was successfully created. It does NOT mean the gateway restart has completed.
#   Completion criteria: subsequent operator `systemctl is-active` check +
#   agent `gateway_health` call.
#
# Design rules (per design-v3.md SS5.6.4):
# 1. Does exactly one thing: schedule restart of openclaw-gateway.service via transient timer
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
  echo "[STUB] Would run: systemd-run --on-active=2s ... -- systemctl restart openclaw-gateway.service" >&2
  echo "[STUB] Reason: $REASON" >&2
  echo "[STUB] Would verify post-restart via separate gateway_health call" >&2

  broker_emit_result \
    "{\"reason\":$(jq -n --arg r "$REASON" '$r'),\"restart_scheduled\":false,\"delay_seconds\":2,\"dispatch_method\":\"systemd-run-transient-timer\",\"verification_required\":true,\"service_active_after\":null,\"mode\":\"dry-run\"}" \
    "[STUB] Gateway restart — dry-run, no live execution" \
    "If gateway fails to start, check journalctl -u openclaw-gateway.service"
else
  # [LIVE] Production execution — requires root
  # Uses systemd-run to create a transient timer unit that executes the restart
  # ~2 seconds later, in an independent cgroup outside the broker's process tree.
  # This completely decouples restart execution from the broker lifecycle,
  # avoiding the SIGTERM race that killed the --no-block approach.
  broker_require_live_capable

  echo "[LIVE] Scheduling gateway restart via systemd-run transient timer (delay=2s). Reason: $REASON" >&2
  if ! systemd-run --on-active=2s --timer-property=AccuracySec=100ms \
    --unit=openclaw-gateway-restart-deferred \
    --description="Deferred gateway restart (host-ops broker)" \
    -- systemctl restart openclaw-gateway.service >&2; then
    broker_error "error" "systemd-run transient timer creation failed" "E_WRAPPER_FAILED"
  fi

  # NOTE: systemd-run returning exit code 0 means the transient timer/unit was
  # successfully created and registered with systemd. It does NOT mean the gateway
  # restart has completed or will succeed. The actual restart executes ~2s later
  # in an independent cgroup. Caller MUST invoke gateway_health afterward to
  # verify the gateway is healthy after the restart completes.

  broker_emit_result \
    "{\"reason\":$(jq -n --arg r "$REASON" '$r'),\"restart_scheduled\":true,\"delay_seconds\":2,\"dispatch_method\":\"systemd-run-transient-timer\",\"verification_required\":true,\"service_active_after\":null,\"mode\":\"live\"}" \
    "Gateway restart scheduled via systemd-run transient timer (delay=2s). Restart has NOT been executed yet — it will execute ~2s after this response. Broker returns before restart occurs due to Requires= dependency. Call gateway_health after 5-10s to verify." \
    "If gateway fails to start, check journalctl -u openclaw-gateway.service"
fi
