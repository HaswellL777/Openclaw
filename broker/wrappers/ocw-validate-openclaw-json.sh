#!/usr/bin/env bash
# ocw-validate-openclaw-json.sh — Wrapper for validate_openclaw_json_candidate action
# Status: Phase 2 implementation slice 1 — candidate wrapper, repo-only
# In dry-run mode (default): echoes intended actions, does NOT execute
# In live mode: requires root, validates candidate config file
#
# Design rules (per design-v3.md SS5.6.4):
# 1. Does exactly one thing: validate a candidate openclaw.json file
# 2. Validates inputs before acting (path whitelist, SHA256 format)
# 3. Verifies candidate file hash
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
broker_validate_action "validate_openclaw_json_candidate"
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
  echo "[STUB] Would validate JSON syntax: jq empty $CANDIDATE_PATH" >&2
  echo "[STUB] Would validate against openclaw config schema" >&2

  broker_emit_result \
    "{\"candidate_path\":$(jq -n --arg p "$CANDIDATE_PATH" '$p'),\"expected_sha256\":\"$EXPECTED_SHA256\",\"sha256_match\":null,\"json_valid\":null,\"schema_valid\":null,\"mode\":\"dry-run\"}" \
    "[STUB] Validation — dry-run, no live execution" \
    "No rollback needed for validation (read-only)"
else
  # [LIVE] Production execution — requires root
  broker_require_live_capable

  # Step 1: File existence
  if [ ! -f "$CANDIDATE_PATH" ]; then
    broker_error "error" "Candidate file not found: $CANDIDATE_PATH" "E_FILE_NOT_FOUND"
  fi

  # Step 2: SHA256 verification
  actual_sha256=$(sha256sum "$CANDIDATE_PATH" | awk '{print $1}')
  sha256_match="false"
  if [ "$actual_sha256" = "$EXPECTED_SHA256" ]; then
    sha256_match="true"
  else
    broker_error "error" "SHA256 mismatch: expected=$EXPECTED_SHA256 actual=$actual_sha256" "E_WRAPPER_FAILED"
  fi

  # Step 3: JSON syntax validation
  json_valid="false"
  if jq empty "$CANDIDATE_PATH" 2>/dev/null; then
    json_valid="true"
  else
    broker_error "error" "Candidate file is not valid JSON" "E_WRAPPER_FAILED"
  fi

  broker_emit_result \
    "{\"candidate_path\":$(jq -n --arg p "$CANDIDATE_PATH" '$p'),\"expected_sha256\":\"$EXPECTED_SHA256\",\"sha256_match\":${sha256_match},\"json_valid\":${json_valid},\"schema_valid\":null,\"mode\":\"live\"}" \
    "Candidate validation passed" \
    "No rollback needed for validation (read-only)"
fi
