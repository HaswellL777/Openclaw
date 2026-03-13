#!/usr/bin/env bash
# ocw-snapshot-pre.sh — Wrapper for snapshot_pre action
# Status: Phase 2 implementation slice 1 — candidate wrapper, repo-only
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, creates pre-change btrfs snapshot
#
# Design rules (per design-v3.md SS5.6.4):
# 1. Does exactly one thing: create pre-change btrfs snapshot
# 2. Validates inputs before acting (label format)
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
broker_validate_action "snapshot_pre"
broker_validate_required_fields

# --- Action-specific validation ---
LABEL=$(jq -r '.inputs.label // empty' "$REQUEST_FILE" 2>/dev/null || true)
REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE" 2>/dev/null || true)

if [ -z "$LABEL" ] || [ -z "$REASON" ]; then
  broker_error "error" "Missing required inputs: label, reason" "E_MISSING_INPUT"
fi

broker_validate_label "$LABEL" "label"

SNAPSHOT_NAME="root-pre-${LABEL}"

# --- Execution ---
if [ "${BROKER_DRY_RUN:-true}" = "true" ]; then
  echo "[STUB] Would create btrfs snapshot: btrfs subvolume snapshot -r / /.snapshots/$SNAPSHOT_NAME" >&2
  echo "[STUB] Label: $LABEL" >&2
  echo "[STUB] Reason: $REASON" >&2

  broker_emit_result \
    "{\"snapshot_name\":\"$SNAPSHOT_NAME\",\"label\":\"$LABEL\",\"reason\":$(jq -n --arg r "$REASON" '$r'),\"snapshot_path\":\"/.snapshots/$SNAPSHOT_NAME\",\"mode\":\"dry-run\"}" \
    "[STUB] Pre-snapshot — dry-run, no live execution" \
    "Delete snapshot: btrfs subvolume delete /.snapshots/$SNAPSHOT_NAME"
else
  # [LIVE] Production execution — requires root
  broker_require_live_capable

  local snapshot_path="/.snapshots/${SNAPSHOT_NAME}"

  # Check snapshot doesn't already exist
  if [ -d "$snapshot_path" ]; then
    broker_error "error" "Snapshot already exists: $snapshot_path" "E_WRAPPER_FAILED"
  fi

  # Create read-only snapshot
  echo "[LIVE] Creating snapshot: btrfs subvolume snapshot -r / $snapshot_path" >&2
  if ! btrfs subvolume snapshot -r / "$snapshot_path" 2>&1; then
    broker_error "error" "btrfs snapshot failed for: $snapshot_path" "E_WRAPPER_FAILED"
  fi

  # Verify snapshot exists
  if [ ! -d "$snapshot_path" ]; then
    broker_error "error" "Snapshot not found after creation: $snapshot_path" "E_WRAPPER_FAILED"
  fi

  broker_emit_result \
    "{\"snapshot_name\":\"$SNAPSHOT_NAME\",\"label\":\"$LABEL\",\"reason\":$(jq -n --arg r "$REASON" '$r'),\"snapshot_path\":\"$snapshot_path\",\"mode\":\"live\"}" \
    "Pre-change snapshot created" \
    "Delete snapshot: btrfs subvolume delete $snapshot_path"
fi
