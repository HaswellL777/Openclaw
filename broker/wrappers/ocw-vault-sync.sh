#!/usr/bin/env bash
# ocw-vault-sync.sh — Wrapper for vault_sync action
# Status: Phase 2 implementation slice 1 — candidate wrapper, repo-only
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, mounts vault, syncs snapshot via btrfs send/receive, unmounts
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: sync a snapshot to vault
# 2. Validates inputs before acting (snapshot_name format)
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
broker_validate_action "vault_sync"
broker_validate_required_fields

# --- Action-specific validation ---
SNAPSHOT_NAME=$(jq -r '.inputs.snapshot_name // empty' "$REQUEST_FILE" 2>/dev/null || true)
INCREMENTAL=$(jq -r '.inputs.incremental // "true"' "$REQUEST_FILE" 2>/dev/null || true)

if [ -z "$SNAPSHOT_NAME" ]; then
  broker_error "error" "Missing required input: snapshot_name" "E_MISSING_INPUT"
fi

broker_validate_label "$SNAPSHOT_NAME" "snapshot_name"

VAULT_MOUNT="/mnt/vault"
VAULT_SNAPSHOT_DIR="${VAULT_MOUNT}/snapshots"
SOURCE_SNAPSHOT="/.snapshots/${SNAPSHOT_NAME}"

# --- Execution ---
if [ "${BROKER_DRY_RUN:-true}" = "true" ]; then
  echo "[STUB] Would mount vault: mount $VAULT_MOUNT" >&2
  echo "[STUB] Would sync snapshot: btrfs send $SOURCE_SNAPSHOT | btrfs receive $VAULT_SNAPSHOT_DIR/" >&2
  echo "[STUB] Incremental: $INCREMENTAL" >&2
  echo "[STUB] Would unmount vault: umount $VAULT_MOUNT" >&2

  broker_emit_result \
    "{\"snapshot_name\":\"$SNAPSHOT_NAME\",\"incremental\":$INCREMENTAL,\"vault_path\":\"$VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME\",\"mode\":\"dry-run\"}" \
    "[STUB] Vault sync — dry-run, no live execution" \
    "Vault sync is additive; remove snapshot from vault if needed: btrfs subvolume delete $VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME"
else
  # [LIVE] Production execution — requires root
  broker_require_live_capable

  # Step 1: Verify source snapshot exists
  if [ ! -d "$SOURCE_SNAPSHOT" ]; then
    broker_error "error" "Source snapshot not found: $SOURCE_SNAPSHOT" "E_FILE_NOT_FOUND"
  fi

  # Step 2: Mount vault (noauto by default per host-sop.md)
  vault_was_mounted="false"
  if mountpoint -q "$VAULT_MOUNT" 2>/dev/null; then
    vault_was_mounted="true"
    echo "[LIVE] Vault already mounted at $VAULT_MOUNT" >&2
  else
    echo "[LIVE] Mounting vault: mount $VAULT_MOUNT" >&2
    if ! mount "$VAULT_MOUNT" 2>&1; then
      broker_error "error" "Failed to mount vault at $VAULT_MOUNT" "E_WRAPPER_FAILED"
    fi
  fi

  # Step 3: Ensure target directory exists
  if [ ! -d "$VAULT_SNAPSHOT_DIR" ]; then
    mkdir -p "$VAULT_SNAPSHOT_DIR"
  fi

  # Step 4: btrfs send/receive
  echo "[LIVE] Syncing snapshot: btrfs send $SOURCE_SNAPSHOT | btrfs receive $VAULT_SNAPSHOT_DIR/" >&2
  if ! btrfs send "$SOURCE_SNAPSHOT" | btrfs receive "$VAULT_SNAPSHOT_DIR/" 2>&1; then
    # Attempt unmount on failure if we mounted it
    if [ "$vault_was_mounted" = "false" ]; then
      umount "$VAULT_MOUNT" 2>/dev/null || true
    fi
    broker_error "error" "btrfs send/receive failed for: $SNAPSHOT_NAME" "E_WRAPPER_FAILED"
  fi

  # Step 5: Verify sync
  if [ ! -d "$VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME" ]; then
    if [ "$vault_was_mounted" = "false" ]; then
      umount "$VAULT_MOUNT" 2>/dev/null || true
    fi
    broker_error "error" "Snapshot not found in vault after sync: $VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME" "E_WRAPPER_FAILED"
  fi

  # Step 6: Unmount vault if we mounted it
  if [ "$vault_was_mounted" = "false" ]; then
    echo "[LIVE] Unmounting vault: umount $VAULT_MOUNT" >&2
    umount "$VAULT_MOUNT" 2>/dev/null || true
  fi

  broker_emit_result \
    "{\"snapshot_name\":\"$SNAPSHOT_NAME\",\"incremental\":$INCREMENTAL,\"vault_path\":\"$VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME\",\"mode\":\"live\"}" \
    "Vault sync completed" \
    "Vault sync is additive; remove snapshot from vault if needed: btrfs subvolume delete $VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME"
fi
