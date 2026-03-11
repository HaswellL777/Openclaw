#!/usr/bin/env bash
# ocw-snapshot-post.sh — Stub wrapper for snapshot_post action
# Status: Phase 2 preparation stub — validates inputs, echoes intended actions, does NOT execute
# Production deployment requires: root ownership, controlled install path, Phase 2 deployment runbook
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: create post-change btrfs snapshot
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
broker_validate_action "snapshot_post"
broker_validate_required_fields

# --- Action-specific validation ---
LABEL=$(jq -r '.inputs.label // empty' "$REQUEST_FILE" 2>/dev/null || true)
REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE" 2>/dev/null || true)

if [ -z "$LABEL" ] || [ -z "$REASON" ]; then
  broker_error "error" "Missing required inputs: label, reason"
fi

broker_validate_label "$LABEL" "label"

# --- STUB: Echo intended action (no live execution) ---
SNAPSHOT_NAME="root-post-${LABEL}"
echo "[STUB] Would create btrfs snapshot: btrfs subvolume snapshot / /.snapshots/$SNAPSHOT_NAME" >&2
echo "[STUB] Label: $LABEL" >&2
echo "[STUB] Reason: $REASON" >&2

# --- Return structured result ---
broker_emit_result \
  "{\"snapshot_name\":\"$SNAPSHOT_NAME\",\"label\":\"$LABEL\",\"reason\":\"$REASON\"}" \
  "[STUB] Post-snapshot — no live execution in Phase 2 prep" \
  "Delete snapshot: btrfs subvolume delete /.snapshots/$SNAPSHOT_NAME"
