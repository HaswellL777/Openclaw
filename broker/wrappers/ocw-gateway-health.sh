#!/usr/bin/env bash
# ocw-gateway-health.sh — Stub wrapper for gateway_health action
# Status: Phase 2 preparation stub — validates inputs, echoes intended actions, does NOT execute
# Production deployment requires: root ownership, controlled install path, Phase 2 deployment runbook
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: check gateway service health
# 2. Validates inputs before acting
# 3. Returns structured JSON result on stdout
# 4. Never executes free-form shell or user-supplied commands
# 5. Logs all actions
# 6. Failure exits non-zero with structured error JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# --- Common validation ---
broker_validate_request_file "$@"
broker_parse_common "$REQUEST_FILE"
broker_validate_action "gateway_health"
broker_validate_required_fields

# --- STUB: Echo intended action (no live execution) ---
echo "[STUB] Would check: systemctl is-active openclaw-gateway.service" >&2
echo "[STUB] Would check: openclaw gateway health endpoint" >&2

# --- Return structured result ---
broker_emit_result \
  '{"service_active":null,"health_endpoint":null}' \
  "[STUB] Gateway health check — no live execution in Phase 2 prep" \
  "No rollback needed for health check"
