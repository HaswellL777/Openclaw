#!/usr/bin/env bash
# ocw-vault-sync.sh — Wrapper for vault_sync action
# Status: Phase 2 — live implementation, send specified snapshot to vault
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, mounts vault, syncs snapshot via btrfs send/receive, unmounts
#
# Design notes:
#   This wrapper sends a SPECIFIED EXISTING snapshot to vault via btrfs send/receive.
#   It does NOT create snapshots (that's snapshot_pre/snapshot_post's job).
#   It reads/writes /var/lib/openclaw/backup/last_sent for incremental send tracking.
#   The authority script /usr/local/sbin/vault-backup-root-btrfs shares the same last_sent
#   file — both paths maintain a single incremental chain.
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
VAULT_SNAPSHOT_DIR="${VAULT_MOUNT}/recv/system"
SOURCE_SNAPSHOT="/.snapshots/${SNAPSHOT_NAME}"
LAST_SENT_FILE="/var/lib/openclaw/backup/last_sent"

# --- Cleanup ---
# Track whether we mounted vault, so cleanup only unmounts if we did
VAULT_MOUNTED_BY_US="false"

cleanup() {
  if [ "$VAULT_MOUNTED_BY_US" = "true" ]; then
    echo "[LIVE] Cleanup: unmounting vault" >&2
    umount "$VAULT_MOUNT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# --- Execution ---
if [ "${BROKER_DRY_RUN:-true}" = "true" ]; then
  echo "[STUB] Would verify source snapshot exists: $SOURCE_SNAPSHOT" >&2
  echo "[STUB] Would mount vault: mount $VAULT_MOUNT" >&2
  if [ "$INCREMENTAL" = "true" ]; then
    echo "[STUB] Would attempt incremental send using last_sent from $LAST_SENT_FILE" >&2
    echo "[STUB] Would check parent snapshot on source (/.snapshots/) and destination ($VAULT_SNAPSHOT_DIR/)" >&2
    echo "[STUB] Would fall back to full send if parent not found on both sides" >&2
  else
    echo "[STUB] Would do full send: btrfs send $SOURCE_SNAPSHOT | btrfs receive $VAULT_SNAPSHOT_DIR/" >&2
  fi
  echo "[STUB] Would update $LAST_SENT_FILE after successful send" >&2
  echo "[STUB] Would unmount vault if mounted by wrapper" >&2

  # Build incremental boolean for JSON
  if [ "$INCREMENTAL" = "true" ]; then
    INCR_JSON="true"
  else
    INCR_JSON="false"
  fi

  broker_emit_result \
    "{\"snapshot_name\":\"$SNAPSHOT_NAME\",\"incremental\":$INCR_JSON,\"actual_mode\":\"dry-run\",\"parent_snapshot\":null,\"vault_path\":\"$VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME\",\"last_sent_updated\":false,\"mode\":\"dry-run\"}" \
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
  if mountpoint -q "$VAULT_MOUNT" 2>/dev/null; then
    echo "[LIVE] Vault already mounted at $VAULT_MOUNT" >&2
  else
    echo "[LIVE] Mounting vault: mount $VAULT_MOUNT" >&2
    if ! mount "$VAULT_MOUNT" >&2; then
      broker_error "error" "Failed to mount vault at $VAULT_MOUNT" "E_WRAPPER_FAILED"
    fi
    VAULT_MOUNTED_BY_US="true"
  fi

  # Step 3: Ensure target directory exists
  if [ ! -d "$VAULT_SNAPSHOT_DIR" ]; then
    mkdir -p "$VAULT_SNAPSHOT_DIR"
  fi

  # Step 4: Determine send mode (incremental vs full)
  ACTUAL_MODE="full"
  PARENT_NAME=""

  if [ "$INCREMENTAL" = "true" ] && [ -f "$LAST_SENT_FILE" ]; then
    PARENT_NAME=$(cat "$LAST_SENT_FILE" 2>/dev/null || true)
    if [ -n "$PARENT_NAME" ]; then
      PARENT_SOURCE="/.snapshots/${PARENT_NAME}"
      PARENT_DEST="${VAULT_SNAPSHOT_DIR}/${PARENT_NAME}"

      # Check parent exists on source and is valid subvolume
      if [ -d "$PARENT_SOURCE" ] && btrfs subvolume show "$PARENT_SOURCE" >/dev/null 2>&1; then
        # Check parent exists on destination and is valid subvolume
        if btrfs subvolume show "$PARENT_DEST" >/dev/null 2>&1; then
          ACTUAL_MODE="incremental"
          echo "[LIVE] Incremental send: parent=${PARENT_NAME} -> new=${SNAPSHOT_NAME}" >&2
        else
          echo "[LIVE] Parent not found on vault destination, falling back to full send" >&2
          PARENT_NAME=""
        fi
      else
        echo "[LIVE] Parent not found on source, falling back to full send" >&2
        PARENT_NAME=""
      fi
    fi
  fi

  # Step 5: btrfs send/receive
  if [ "$ACTUAL_MODE" = "incremental" ]; then
    echo "[LIVE] Executing: btrfs send -p /.snapshots/${PARENT_NAME} $SOURCE_SNAPSHOT | btrfs receive $VAULT_SNAPSHOT_DIR/" >&2
    if ! btrfs send -p "/.snapshots/${PARENT_NAME}" "$SOURCE_SNAPSHOT" | btrfs receive "$VAULT_SNAPSHOT_DIR/" >&2; then
      broker_error "error" "Incremental btrfs send/receive failed for: $SNAPSHOT_NAME (parent: $PARENT_NAME)" "E_WRAPPER_FAILED"
    fi
  else
    echo "[LIVE] Full send: btrfs send $SOURCE_SNAPSHOT | btrfs receive $VAULT_SNAPSHOT_DIR/" >&2
    if ! btrfs send "$SOURCE_SNAPSHOT" | btrfs receive "$VAULT_SNAPSHOT_DIR/" >&2; then
      broker_error "error" "Full btrfs send/receive failed for: $SNAPSHOT_NAME" "E_WRAPPER_FAILED"
    fi
  fi

  # Step 6: Verify sync
  if [ ! -d "$VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME" ]; then
    broker_error "error" "Snapshot not found in vault after sync: $VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME" "E_WRAPPER_FAILED"
  fi

  # Step 7: Update last_sent (only after verified success)
  echo "$SNAPSHOT_NAME" > "$LAST_SENT_FILE"
  chmod 600 "$LAST_SENT_FILE"
  echo "[LIVE] Updated last_sent: $SNAPSHOT_NAME" >&2

  # Step 8: Unmount vault if we mounted it (handled by cleanup trap)

  # Build result JSON fields
  if [ -n "$PARENT_NAME" ]; then
    PARENT_JSON="\"$PARENT_NAME\""
  else
    PARENT_JSON="null"
  fi

  if [ "$ACTUAL_MODE" = "incremental" ]; then
    INCR_JSON="true"
  else
    INCR_JSON="false"
  fi

  broker_emit_result \
    "{\"snapshot_name\":\"$SNAPSHOT_NAME\",\"incremental\":$INCR_JSON,\"actual_mode\":\"$ACTUAL_MODE\",\"parent_snapshot\":$PARENT_JSON,\"vault_path\":\"$VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME\",\"last_sent_updated\":true,\"mode\":\"live\"}" \
    "Vault sync completed (${ACTUAL_MODE})" \
    "Vault sync is additive; remove snapshot from vault if needed: btrfs subvolume delete $VAULT_SNAPSHOT_DIR/$SNAPSHOT_NAME"
fi
