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
  broker_error "error" "Missing required inputs: target_snapshot, reason"
fi

broker_validate_label "$TARGET_SNAPSHOT" "target_snapshot"

# --- STUB: Echo intended action (no live execution) ---
echo "[STUB] Would verify snapshot exists: btrfs subvolume show /.snapshots/$TARGET_SNAPSHOT" >&2
echo "[STUB] Would prepare rollback plan for: $TARGET_SNAPSHOT" >&2
echo "[STUB] Reason: $REASON" >&2
echo "[STUB] NOTE: Actual rollback execution requires separate human confirmation" >&2

# --- Return structured result ---
broker_emit_result \
  "{\"target_snapshot\":\"$TARGET_SNAPSHOT\",\"reason\":\"$REASON\",\"rollback_steps\":[\"1. Create safety snapshot of current state\",\"2. Verify target snapshot integrity\",\"3. Execute rollback: btrfs subvolume snapshot /.snapshots/$TARGET_SNAPSHOT /\",\"4. Restart affected services\",\"5. Validate system health\"]}" \
  "[STUB] Rollback preparation — no live execution in Phase 2 prep" \
  "Rollback preparation is read-only; no undo needed"
