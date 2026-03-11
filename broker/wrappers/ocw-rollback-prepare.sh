#!/usr/bin/env bash
# ocw-rollback-prepare.sh — Stub wrapper for rollback_prepare action
# Status: Phase 2 preparation stub — validates inputs, echoes intended actions, does NOT execute
# Production deployment requires: root ownership, controlled install path, Phase 2 deployment runbook
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: prepare rollback to a named snapshot
# 2. Validates inputs before acting
# 3. Returns structured JSON result on stdout
# 4. Never executes free-form shell or user-supplied commands
# 5. Logs all actions
# 6. Failure exits non-zero with structured error JSON

set -euo pipefail

# --- Input validation ---
if [ $# -ne 1 ]; then
  echo '{"ok":false,"status":"error","message":"Usage: ocw-rollback-prepare.sh <request-json-path>"}' >&2
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
TARGET_SNAPSHOT=$(jq -r '.inputs.target_snapshot // empty' "$REQUEST_FILE" 2>/dev/null || true)
REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE" 2>/dev/null || true)

if [ "$ACTION" != "rollback_prepare" ]; then
  echo "{\"ok\":false,\"action\":\"$ACTION\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Wrong action: expected rollback_prepare, got $ACTION\"}" >&2
  exit 1
fi

if [ -z "$REQUEST_ID" ] || [ -z "$TASK_ID" ]; then
  echo '{"ok":false,"status":"error","message":"Missing required fields: request_id, task_id"}' >&2
  exit 1
fi

if [ -z "$TARGET_SNAPSHOT" ] || [ -z "$REASON" ]; then
  echo "{\"ok\":false,\"action\":\"rollback_prepare\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Missing required inputs: target_snapshot, reason\"}" >&2
  exit 1
fi

# --- Snapshot name format check ---
if ! echo "$TARGET_SNAPSHOT" | grep -qE '^[a-zA-Z0-9._-]+$'; then
  echo "{\"ok\":false,\"action\":\"rollback_prepare\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Invalid target_snapshot format: alphanumeric, dots, hyphens, underscores only\"}" >&2
  exit 1
fi

# --- STUB: Echo intended action (no live execution) ---
echo "[STUB] Would verify snapshot exists: btrfs subvolume show /.snapshots/$TARGET_SNAPSHOT" >&2
echo "[STUB] Would prepare rollback plan for: $TARGET_SNAPSHOT" >&2
echo "[STUB] Reason: $REASON" >&2
echo "[STUB] NOTE: Actual rollback execution requires separate human confirmation" >&2

# --- Return structured result ---
cat <<EOF
{
  "ok": true,
  "action": "rollback_prepare",
  "request_id": "$REQUEST_ID",
  "task_id": "$TASK_ID",
  "status": "ok",
  "message": "[STUB] Rollback preparation — no live execution in Phase 2 prep",
  "artifacts": {
    "target_snapshot": "$TARGET_SNAPSHOT",
    "reason": "$REASON",
    "rollback_steps": [
      "1. Create safety snapshot of current state",
      "2. Verify target snapshot integrity",
      "3. Execute rollback: btrfs subvolume snapshot /.snapshots/$TARGET_SNAPSHOT /",
      "4. Restart affected services",
      "5. Validate system health"
    ]
  },
  "rollback_hint": "Rollback preparation is read-only; no undo needed"
}
EOF
