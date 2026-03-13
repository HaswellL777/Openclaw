#!/usr/bin/env bash
# ocw-deploy-openclaw-json.sh — Wrapper for deploy_openclaw_json_candidate action
# Status: Phase 2 implementation slice 1 — candidate wrapper, repo-only
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, deploys validated candidate to /etc/openclaw/openclaw.json
#
# Design rules (per design-v3.md SS5.6.4):
# 1. Does exactly one thing: deploy validated candidate to config target
# 2. Validates inputs before acting (path whitelist, SHA256 format)
# 3. Verifies candidate file hash before deploying
# 4. Returns structured JSON result on stdout
# 5. Never executes free-form shell or user-supplied commands
# 6. Logs all actions to stderr
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
  broker_error "error" "Missing required inputs: candidate_path, expected_sha256" "E_MISSING_INPUT"
fi

broker_validate_path "$CANDIDATE_PATH" "$CANDIDATE_PATH_PREFIX"
broker_validate_sha256 "$EXPECTED_SHA256"

# --- Execution ---
if [ "${BROKER_DRY_RUN:-true}" = "true" ]; then
  echo "[STUB] Would verify file exists: $CANDIDATE_PATH" >&2
  echo "[STUB] Would verify SHA256: sha256sum $CANDIDATE_PATH == $EXPECTED_SHA256" >&2
  echo "[STUB] Would backup current: cp $CONFIG_TARGET_PATH ${CONFIG_TARGET_PATH}.bak" >&2
  echo "[STUB] Would deploy: cp $CANDIDATE_PATH $CONFIG_TARGET_PATH" >&2
  echo "[STUB] Would verify deployed file hash" >&2
  echo "[STUB] Would set permissions: chown root:openclaw $CONFIG_TARGET_PATH && chmod 640 $CONFIG_TARGET_PATH" >&2

  broker_emit_result \
    "{\"candidate_path\":$(jq -n --arg p "$CANDIDATE_PATH" '$p'),\"expected_sha256\":\"$EXPECTED_SHA256\",\"deployed_path\":\"$CONFIG_TARGET_PATH\",\"backup_path\":\"${CONFIG_TARGET_PATH}.bak\",\"deployed_sha256\":null,\"mode\":\"dry-run\"}" \
    "[STUB] Deploy — dry-run, no live execution" \
    "Restore from backup: cp ${CONFIG_TARGET_PATH}.bak $CONFIG_TARGET_PATH"
else
  # [LIVE] Production execution — requires root
  broker_require_live_capable

  # Step 1: File existence
  if [ ! -f "$CANDIDATE_PATH" ]; then
    broker_error "error" "Candidate file not found: $CANDIDATE_PATH" "E_FILE_NOT_FOUND"
  fi

  # Step 2: SHA256 pre-deploy verification
  actual_sha256=$(sha256sum "$CANDIDATE_PATH" | awk '{print $1}')
  if [ "$actual_sha256" != "$EXPECTED_SHA256" ]; then
    broker_error "error" "SHA256 mismatch: expected=$EXPECTED_SHA256 actual=$actual_sha256" "E_WRAPPER_FAILED"
  fi

  # Step 3: Backup current config
  backup_path="${CONFIG_TARGET_PATH}.bak"
  if [ -f "$CONFIG_TARGET_PATH" ]; then
    cp "$CONFIG_TARGET_PATH" "$backup_path"
    echo "[LIVE] Backed up: $CONFIG_TARGET_PATH -> $backup_path" >&2
  fi

  # Step 4: Deploy candidate
  cp "$CANDIDATE_PATH" "$CONFIG_TARGET_PATH"
  chown root:openclaw "$CONFIG_TARGET_PATH"
  chmod 640 "$CONFIG_TARGET_PATH"
  echo "[LIVE] Deployed: $CANDIDATE_PATH -> $CONFIG_TARGET_PATH" >&2

  # Step 5: Post-deploy hash verification
  deployed_sha256=$(sha256sum "$CONFIG_TARGET_PATH" | awk '{print $1}')
  if [ "$deployed_sha256" != "$EXPECTED_SHA256" ]; then
    # Restore backup
    if [ -f "$backup_path" ]; then
      cp "$backup_path" "$CONFIG_TARGET_PATH"
      chown root:openclaw "$CONFIG_TARGET_PATH"
      chmod 640 "$CONFIG_TARGET_PATH"
    fi
    broker_error "error" "Post-deploy SHA256 mismatch — rolled back to backup" "E_WRAPPER_FAILED"
  fi

  broker_emit_result \
    "{\"candidate_path\":$(jq -n --arg p "$CANDIDATE_PATH" '$p'),\"expected_sha256\":\"$EXPECTED_SHA256\",\"deployed_path\":\"$CONFIG_TARGET_PATH\",\"backup_path\":\"$backup_path\",\"deployed_sha256\":\"$deployed_sha256\",\"mode\":\"live\"}" \
    "Config deployed successfully" \
    "Restore from backup: cp ${CONFIG_TARGET_PATH}.bak $CONFIG_TARGET_PATH"
fi
