#!/usr/bin/env bash
# ocw-vault-sync.sh — Stub wrapper for vault_sync action
# Status: Phase 2 preparation stub — validates inputs, echoes intended actions, does NOT execute
# Production deployment requires: root ownership, controlled install path, Phase 2 deployment runbook
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: sync a snapshot to vault
# 2. Validates inputs before acting
# 3. Returns structured JSON result on stdout
# 4. Never executes free-form shell or user-supplied commands
# 5. Logs all actions
# 6. Failure exits non-zero with structured error JSON

set -euo pipefail

# --- Input validation ---
if [ $# -ne 1 ]; then
  echo '{"ok":false,"status":"error","message":"Usage: ocw-vault-sync.sh <request-json-path>"}' >&2
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
SNAPSHOT_NAME=$(jq -r '.inputs.snapshot_name // empty' "$REQUEST_FILE" 2>/dev/null || true)
INCREMENTAL=$(jq -r '.inputs.incremental // "true"' "$REQUEST_FILE" 2>/dev/null || true)

if [ "$ACTION" != "vault_sync" ]; then
  echo "{\"ok\":false,\"action\":\"$ACTION\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Wrong action: expected vault_sync, got $ACTION\"}" >&2
  exit 1
fi

if [ -z "$REQUEST_ID" ] || [ -z "$TASK_ID" ]; then
  echo '{"ok":false,"status":"error","message":"Missing required fields: request_id, task_id"}' >&2
  exit 1
fi

if [ -z "$SNAPSHOT_NAME" ]; then
  echo "{\"ok\":false,\"action\":\"vault_sync\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Missing required input: snapshot_name\"}" >&2
  exit 1
fi

# --- Snapshot name format check ---
if ! echo "$SNAPSHOT_NAME" | grep -qE '^[a-zA-Z0-9._-]+$'; then
  echo "{\"ok\":false,\"action\":\"vault_sync\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Invalid snapshot_name format: alphanumeric, dots, hyphens, underscores only\"}" >&2
  exit 1
fi

# --- STUB: Echo intended action (no live execution) ---
echo "[STUB] Would mount vault: mount /mnt/vault" >&2
echo "[STUB] Would sync snapshot: btrfs send /.snapshots/$SNAPSHOT_NAME | btrfs receive /mnt/vault/snapshots/" >&2
echo "[STUB] Incremental: $INCREMENTAL" >&2
echo "[STUB] Would unmount vault: umount /mnt/vault" >&2

# --- Return structured result ---
cat <<EOF
{
  "ok": true,
  "action": "vault_sync",
  "request_id": "$REQUEST_ID",
  "task_id": "$TASK_ID",
  "status": "ok",
  "message": "[STUB] Vault sync — no live execution in Phase 2 prep",
  "artifacts": {
    "snapshot_name": "$SNAPSHOT_NAME",
    "incremental": $INCREMENTAL,
    "vault_path": "/mnt/vault/snapshots/$SNAPSHOT_NAME"
  },
  "rollback_hint": "Vault sync is additive; remove snapshot from vault if needed: btrfs subvolume delete /mnt/vault/snapshots/$SNAPSHOT_NAME"
}
EOF
