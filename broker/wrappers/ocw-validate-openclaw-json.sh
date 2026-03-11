#!/usr/bin/env bash
# ocw-validate-openclaw-json.sh — Stub wrapper for validate_openclaw_json_candidate action
# Status: Phase 2 preparation stub — validates inputs, echoes intended actions, does NOT execute
# Production deployment requires: root ownership, controlled install path, Phase 2 deployment runbook
#
# Design rules (per design-v3.md §5.6.4):
# 1. Does exactly one thing: validate a candidate openclaw.json file
# 2. Validates inputs before acting
# 3. Verifies candidate file hash
# 4. Returns structured JSON result on stdout
# 5. Never executes free-form shell or user-supplied commands
# 6. Logs all actions
# 7. Failure exits non-zero with structured error JSON

set -euo pipefail

ALLOWED_PATH_PREFIX="/var/lib/openclaw/approvals/candidates/"

# --- Input validation ---
if [ $# -ne 1 ]; then
  echo '{"ok":false,"status":"error","message":"Usage: ocw-validate-openclaw-json.sh <request-json-path>"}' >&2
  exit 1
fi

REQUEST_FILE="$1"
if [ ! -f "$REQUEST_FILE" ]; then
  echo "{\"ok\":false,\"status\":\"error\",\"message\":\"Request file not found: $REQUEST_FILE\"}" >&2
  exit 1
fi

# --- Parse request ---
ACTION=$(jq -r '.action // empty' "$REQUEST_FILE" 2>/dev/null || true)
REQUEST_ID=$(jq -r '.request_id // empty' "$REQUEST_FILE" 2>/dev/null || true)
TASK_ID=$(jq -r '.task_id // empty' "$REQUEST_FILE" 2>/dev/null || true)
CANDIDATE_PATH=$(jq -r '.inputs.candidate_path // empty' "$REQUEST_FILE" 2>/dev/null || true)
EXPECTED_SHA256=$(jq -r '.inputs.expected_sha256 // empty' "$REQUEST_FILE" 2>/dev/null || true)

if [ "$ACTION" != "validate_openclaw_json_candidate" ]; then
  echo "{\"ok\":false,\"action\":\"$ACTION\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Wrong action: expected validate_openclaw_json_candidate, got $ACTION\"}" >&2
  exit 1
fi

if [ -z "$REQUEST_ID" ] || [ -z "$TASK_ID" ]; then
  echo '{"ok":false,"status":"error","message":"Missing required fields: request_id, task_id"}' >&2
  exit 1
fi

if [ -z "$CANDIDATE_PATH" ] || [ -z "$EXPECTED_SHA256" ]; then
  echo "{\"ok\":false,\"action\":\"validate_openclaw_json_candidate\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Missing required inputs: candidate_path, expected_sha256\"}" >&2
  exit 1
fi

# --- Path whitelist check ---
case "$CANDIDATE_PATH" in
  "$ALLOWED_PATH_PREFIX"*)
    # Path is within allowed prefix
    ;;
  *)
    echo "{\"ok\":false,\"action\":\"validate_openclaw_json_candidate\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"denied\",\"message\":\"Path not in whitelist: must start with $ALLOWED_PATH_PREFIX\"}" >&2
    exit 1
    ;;
esac

# --- Check for path traversal ---
case "$CANDIDATE_PATH" in
  *".."*)
    echo "{\"ok\":false,\"action\":\"validate_openclaw_json_candidate\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"denied\",\"message\":\"Path traversal detected\"}" >&2
    exit 1
    ;;
esac

# --- SHA256 format check ---
if ! echo "$EXPECTED_SHA256" | grep -qE '^[a-f0-9]{64}$'; then
  echo "{\"ok\":false,\"action\":\"validate_openclaw_json_candidate\",\"request_id\":\"$REQUEST_ID\",\"task_id\":\"$TASK_ID\",\"status\":\"error\",\"message\":\"Invalid SHA256 format\"}" >&2
  exit 1
fi

# --- STUB: Echo intended action (no live execution) ---
echo "[STUB] Would verify file exists: $CANDIDATE_PATH" >&2
echo "[STUB] Would verify SHA256: sha256sum $CANDIDATE_PATH == $EXPECTED_SHA256" >&2
echo "[STUB] Would validate JSON syntax: jq empty $CANDIDATE_PATH" >&2
echo "[STUB] Would validate against openclaw config schema" >&2

# --- Return structured result ---
cat <<EOF
{
  "ok": true,
  "action": "validate_openclaw_json_candidate",
  "request_id": "$REQUEST_ID",
  "task_id": "$TASK_ID",
  "status": "ok",
  "message": "[STUB] Validation — no live execution in Phase 2 prep",
  "artifacts": {
    "candidate_path": "$CANDIDATE_PATH",
    "expected_sha256": "$EXPECTED_SHA256",
    "sha256_match": null,
    "json_valid": null,
    "schema_valid": null
  },
  "rollback_hint": "No rollback needed for validation (read-only)"
}
EOF
