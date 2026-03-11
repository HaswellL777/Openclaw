#!/usr/bin/env bash
# ocw-gateway-restart.sh — Stub wrapper for gateway_restart action
# Status: Phase 2 preparation stub — validates inputs, echoes intended actions, does NOT execute
# Production deployment requires: root ownership, controlled install path, Phase 2 deployment runbook
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: restart openclaw-gateway.service
# 2. Validates inputs before acting
# 3. Returns structured JSON result on stdout
# 4. Never executes free-form shell or user-supplied commands
# 5. Logs all actions
# 6. Failure exits non-zero with structured error JSON

set -euo pipefail

# --- Input validation ---
if [ $# -ne 1 ]; then
  echo '{"ok":false,"status":"error","message":"Usage: ocw-gateway-restart.sh <request-json-path>"}' >&2
  exit 1
fi

REQUEST_FILE="$1"
if [ ! -f "$REQUEST_FILE" ]; then
  echo "{\"ok\":false,\"status\":\"error\",\"message\":\"Request file not found: $REQUEST_FILE\"}" >&2
  exit 1
fi

# --- Parse request ---
ACTION=$(jq -r '.action // empty' "$REQUEST_FILE" 2>/dev/null || true)
REQUEST_ID=$(jq -r '.request_id // empty' "$REQUEST_FILE" 2>/dev/null || true)
TASK_ID=$(jq -r '.task_id // empty' "$REQUEST_FILE" 2>/dev/null || true)
REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE" 2>/dev/null || true)

if [ "$ACTION" != "gateway_restart" ]; then
  echo "{\"ok\":false,\"action\":\"$ACTION\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Wrong action: expected gateway_restart, got $ACTION\"}" >&2
  exit 1
fi

if [ -z "$REQUEST_ID" ] || [ -z "$TASK_ID" ]; then
  echo '{"ok":false,"status":"error","message":"Missing required fields: request_id, task_id"}' >&2
  exit 1
fi

if [ -z "$REASON" ]; then
  echo "{\"ok\":false,\"action\":\"gateway_restart\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Missing required input: reason\"}" >&2
  exit 1
fi

# --- STUB: Echo intended action (no live execution) ---
echo "[STUB] Would run: systemctl restart openclaw-gateway.service" >&2
echo "[STUB] Reason: $REASON" >&2
echo "[STUB] Would verify: systemctl is-active openclaw-gateway.service" >&2

# --- Return structured result ---
cat <<EOF
{
  "ok": true,
  "action": "gateway_restart",
  "request_id": "$REQUEST_ID",
  "task_id": "$TASK_ID",
  "status": "ok",
  "message": "[STUB] Gateway restart — no live execution in Phase 2 prep",
  "artifacts": {
    "reason": "$REASON",
    "service_active_after": null
  },
  "rollback_hint": "If gateway fails to start, check journalctl -u openclaw-gateway.service"
}
EOF
