#!/usr/bin/env bash
# ocw-deploy-openclaw-json.sh — Stub wrapper for deploy_openclaw_json_candidate action
# Status: Phase 2 preparation stub — validates inputs, echoes intended actions, does NOT execute
# Production deployment requires: root ownership, controlled install path, Phase 2 deployment runbook
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: deploy validated candidate to /etc/openclaw/openclaw.json
# 2. Validates inputs before acting
# 3. Verifies candidate file hash before deploying
# 4. Returns structured JSON result on stdout
# 5. Never executes free-form shell or user-supplied commands
# 6. Logs all actions
# 7. Failure exits non-zero with structured error JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# --- Common validation ---
broker_validate_request_file "$@"
broker_parse_common "$REQUEST_FILE"
broker_validate_action "deploy_openclaw_json_candidate"
broker_validate_required_fields

# --- Action-specific validation ---
CANDIDATE_PATH=$(jq -r '.inputs.candidate_path // empty' "$REQUEST_FILE" 2>/dev/null || true)
EXPECTED_SHA256=$(jq -r '.inputs.expected_sha256 // empty' "$REQUEST_FILE" 2>/dev/null || true)

if [ -z "$CANDIDATE_PATH" ] || [ -z "$EXPECTED_SHA256" ]; then
  broker_error "error" "Missing required inputs: candidate_path, expected_sha256"
fi

broker_validate_path "$CANDIDATE_PATH" "$CANDIDATE_PATH_PREFIX"
broker_validate_sha256 "$EXPECTED_SHA256"

# --- STUB: Echo intended action (no live execution) ---
echo "[STUB] Would verify file exists: $CANDIDATE_PATH" >&2
echo "[STUB] Would verify SHA256: sha256sum $CANDIDATE_PATH == $EXPECTED_SHA256" >&2
echo "[STUB] Would backup current: cp $CONFIG_TARGET_PATH ${CONFIG_TARGET_PATH}.bak" >&2
echo "[STUB] Would deploy: cp $CANDIDATE_PATH $CONFIG_TARGET_PATH" >&2
echo "[STUB] Would verify deployed file hash" >&2
echo "[STUB] Would set permissions: chown root:openclaw $CONFIG_TARGET_PATH && chmod 640 $CONFIG_TARGET_PATH" >&2

# --- Return structured result ---
broker_emit_result \
  "{\"candidate_path\":\"$CANDIDATE_PATH\",\"expected_sha256\":\"$EXPECTED_SHA256\",\"deployed_path\":\"$CONFIG_TARGET_PATH\",\"backup_path\":\"${CONFIG_TARGET_PATH}.bak\",\"deployed_sha256\":null}" \
  "[STUB] Deploy — no live execution in Phase 2 prep" \
  "Restore from backup: cp ${CONFIG_TARGET_PATH}.bak $CONFIG_TARGET_PATH"
