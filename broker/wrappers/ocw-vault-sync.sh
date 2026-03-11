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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# --- Common validation ---
broker_validate_request_file "$@"
broker_parse_common "$REQUEST_FILE"
broker_validate_action "vault_sync"
broker_validate_required_fields

# --- Action-specific validation ---
SNAPSHOT_NAME=$(jq -r '.inputs.snapshot_name // empty' "$REQUEST_FILE" 2>/dev/null || true)
INCREMENTAL=$(jq -r '.inputs.incremental // "true"' "$REQUEST_FILE" 2>/dev/null || true)

if [ -z "$SNAPSHOT_NAME" ]; then
  broker_error "error" "Missing required input: snapshot_name"
fi

broker_validate_label "$SNAPSHOT_NAME" "snapshot_name"

# --- STUB: Echo intended action (no live execution) ---
echo "[STUB] Would mount vault: mount /mnt/vault" >&2
echo "[STUB] Would sync snapshot: btrfs send /.snapshots/$SNAPSHOT_NAME | btrfs receive /mnt/vault/snapshots/" >&2
echo "[STUB] Incremental: $INCREMENTAL" >&2
echo "[STUB] Would unmount vault: umount /mnt/vault" >&2

# --- Return structured result ---
broker_emit_result \
  "{\"snapshot_name\":\"$SNAPSHOT_NAME\",\"incremental\":$INCREMENTAL,\"vault_path\":\"/mnt/vault/snapshots/$SNAPSHOT_NAME\"}" \
  "[STUB] Vault sync — no live execution in Phase 2 prep" \
  "Vault sync is additive; remove snapshot from vault if needed: btrfs subvolume delete /mnt/vault/snapshots/$SNAPSHOT_NAME"
