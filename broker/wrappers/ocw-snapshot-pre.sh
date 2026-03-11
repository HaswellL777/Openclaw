#!/usr/bin/env bash
# ocw-snapshot-pre.sh — Stub wrapper for snapshot_pre action
# Status: Phase 2 preparation stub — validates inputs, echoes intended actions, does NOT execute
# Production deployment requires: root ownership, controlled install path, Phase 2 deployment runbook
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: create pre-change btrfs snapshot
# 2. Validates inputs before acting
# 3. Returns structured JSON result on stdout
# 4. Never executes free-form shell or user-supplied commands
# 5. Logs all actions
# 6. Failure exits non-zero with structured error JSON

set -euo pipefail

# --- Input validation ---
if [ $# -ne 1 ]; then
  echo '{"ok":false,"status":"error","message":"Usage: ocw-snapshot-pre.sh <request-json-path>"}' >&2
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
LABEL=$(jq -r '.inputs.label // empty' "$REQUEST_FILE" 2>/dev/null || true)
REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE" 2>/dev/null || true)

if [ "$ACTION" != "snapshot_pre" ]; then
  echo "{\"ok\":false,\"action\":\"$ACTION\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Wrong action: expected snapshot_pre, got $ACTION\"}" >&2
  exit 1
fi

if [ -z "$REQUEST_ID" ] || [ -z "$TASK_ID" ]; then
  echo '{"ok":false,"status":"error","message":"Missing required fields: request_id, task_id"}' >&2
  exit 1
fi

if [ -z "$LABEL" ] || [ -z "$REASON" ]; then
  echo "{\"ok\":false,\"action\":\"snapshot_pre\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Missing required inputs: label, reason\"}" >&2
  exit 1
fi

# --- Label format check ---
if ! echo "$LABEL" | grep -qE '^[a-zA-Z0-9._-]+$'; then
  echo "{\"ok\":false,\"action\":\"snapshot_pre\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Invalid label format: alphanumeric, dots, hyphens, underscores only\"}" >&2
  exit 1
fi

# --- STUB: Echo intended action (no live execution) ---
SNAPSHOT_NAME="root-pre-${LABEL}"
echo "[STUB] Would create btrfs snapshot: btrfs subvolume snapshot / /.snapshots/$SNAPSHOT_NAME" >&2
echo "[STUB] Label: $LABEL" >&2
echo "[STUB] Reason: $REASON" >&2

# --- Return structured result ---
cat <<EOF
{
  "ok": true,
  "action": "snapshot_pre",
  "request_id": "$REQUEST_ID",
  "task_id": "$TASK_ID",
  "status": "ok",
  "message": "[STUB] Pre-snapshot — no live execution in Phase 2 prep",
  "artifacts": {
    "snapshot_name": "$SNAPSHOT_NAME",
    "label": "$LABEL",
    "reason": "$REASON"
  },
  "rollback_hint": "Delete snapshot: btrfs subvolume delete /.snapshots/$SNAPSHOT_NAME"
}
EOF
