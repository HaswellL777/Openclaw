#!/usr/bin/env bash
# ocw-gateway-health.sh — Wrapper for gateway_health action
# Status: Phase 2 implementation slice 1 — candidate wrapper, repo-only
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, checks real gateway service health
#
# Design rules (per design-v3.md SS5.6.4):
# 1. Does exactly one thing: check gateway service health
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
broker_validate_action "gateway_health"
broker_validate_required_fields

# --- Execution ---
if [ "${BROKER_DRY_RUN:-true}" = "true" ]; then
  # Dry-run: document intended actions
  echo "[STUB] Would check: systemctl is-active openclaw-gateway.service" >&2
  echo "[STUB] Would check: openclaw gateway health endpoint" >&2

  broker_emit_result \
    '{"service_active":null,"health_endpoint":null,"mode":"dry-run"}' \
    "[STUB] Gateway health check — dry-run, no live execution" \
    "No rollback needed for health check"
else
  # [LIVE] Production execution — requires root
  broker_require_live_capable

  local_service_active="unknown"
  if systemctl is-active --quiet openclaw-gateway.service 2>/dev/null; then
    local_service_active="active"
  else
    local_service_active="inactive"
  fi

  broker_emit_result \
    "{\"service_active\":\"${local_service_active}\",\"health_endpoint\":null,\"mode\":\"live\"}" \
    "Gateway health check completed" \
    "No rollback needed for health check"
fi
