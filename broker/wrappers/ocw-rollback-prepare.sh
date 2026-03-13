#!/usr/bin/env bash
# ocw-rollback-prepare.sh — Wrapper for rollback_prepare action
# Status: Phase 2 implementation slice 1 — candidate wrapper, repo-only
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, verifies target snapshot exists and is valid
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: prepare rollback to a named snapshot
# 2. Validates inputs before acting (snapshot name format)
# 3. Returns structured JSON result on stdout
# 4. Never executes free-form shell or user-supplied commands
# 5. Logs all actions to stderr
# 6. Failure exits non-zero with structured error JSON
#
# NOTE: This wrapper only PREPARES a rollback plan. Actual rollback
# execution requires separate human confirmation — by design.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# --- Common validation ---
broker_validate_request_file "$@"
broker_parse_common "$REQUEST_FILE"
broker_validate_action "rollback_prepare"
broker_validate_required_fields

# --- Action-specific validation ---
TARGET_SNAPSHOT=$(jq -r '.inputs.target_snapshot // empty' "$REQUEST_FILE" 2>/dev/null || true)
REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE" 2>/dev/null || true)

if [ -z "$TARGET_SNAPSHOT" ] || [ -z "$REASON" ]; then
  broker_error "error" "Missing required inputs: target_snapshot, reason" "E_MISSING_INPUT"
fi

broker_validate_label "$TARGET_SNAPSHOT" "target_snapshot"

SNAPSHOT_PATH="/.snapshots/${TARGET_SNAPSHOT}"
ROLLBACK_STEPS='["1. Create safety snapshot of current state","2. Verify target snapshot integrity","3. Execute rollback: btrfs subvolume snapshot /.snapshots/'"$TARGET_SNAPSHOT"' /","4. Restart affected services","5. Validate system health"]'

# --- Execution ---
if [ "${BROKER_DRY_RUN:-true}" = "true" ]; then
  echo "[STUB] Would verify snapshot exists: btrfs subvolume show $SNAPSHOT_PATH" >&2
  echo "[STUB] Would prepare rollback plan for: $TARGET_SNAPSHOT" >&2
  echo "[STUB] Reason: $REASON" >&2
  echo "[STUB] NOTE: Actual rollback execution requires separate human confirmation" >&2

  broker_emit_result \
    "{\"target_snapshot\":\"$TARGET_SNAPSHOT\",\"reason\":$(jq -n --arg r "$REASON" '$r'),\"snapshot_path\":\"$SNAPSHOT_PATH\",\"snapshot_verified\":null,\"rollback_steps\":$ROLLBACK_STEPS,\"mode\":\"dry-run\"}" \
    "[STUB] Rollback preparation — dry-run, no live execution" \
    "Rollback preparation is read-only; no undo needed"
else
  # [LIVE] Production execution — requires root
  broker_require_live_capable

  # Step 1: Verify target snapshot exists
  if [ ! -d "$SNAPSHOT_PATH" ]; then
    broker_error "error" "Target snapshot not found: $SNAPSHOT_PATH" "E_FILE_NOT_FOUND"
  fi

  # Step 2: Verify it's a valid btrfs subvolume
  snapshot_verified="false"
  if btrfs subvolume show "$SNAPSHOT_PATH" >/dev/null 2>&1; then
    snapshot_verified="true"
    echo "[LIVE] Target snapshot verified: $SNAPSHOT_PATH" >&2
  else
    broker_error "error" "Target path is not a valid btrfs subvolume: $SNAPSHOT_PATH" "E_WRAPPER_FAILED"
  fi

  # Step 3: Emit rollback plan (does NOT execute rollback)
  echo "[LIVE] Rollback plan prepared for: $TARGET_SNAPSHOT" >&2
  echo "[LIVE] NOTE: Actual rollback execution requires separate human confirmation" >&2

  broker_emit_result \
    "{\"target_snapshot\":\"$TARGET_SNAPSHOT\",\"reason\":$(jq -n --arg r "$REASON" '$r'),\"snapshot_path\":\"$SNAPSHOT_PATH\",\"snapshot_verified\":${snapshot_verified},\"rollback_steps\":$ROLLBACK_STEPS,\"mode\":\"live\"}" \
    "Rollback preparation completed — awaiting human confirmation to execute" \
    "Rollback preparation is read-only; no undo needed"
fi
