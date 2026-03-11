#!/usr/bin/env bash
# test_broker_schemas.sh — Test broker schemas, wrapper stubs, and example fixtures
#
# Usage: tests/test_broker_schemas.sh
#
# This test:
# 1. Runs the schema validation script
# 2. Runs each wrapper stub against its example request fixture
# 3. Validates wrapper stub output is valid JSON with required fields
# 4. Tests negative cases (bad path, wrong action)
#
# Dependencies: jq, bash 4+

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; return 0; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; return 0; }

echo "=== Broker Schema + Wrapper Stub Tests ==="
echo ""

# --- Test 1: Run schema validation ---
echo "--- Test 1: Schema validation script ---"
if bash "$REPO_ROOT/scripts/validate-broker-schemas.sh" --verbose >/dev/null 2>&1; then
  pass "validate-broker-schemas.sh exits 0"
else
  fail "validate-broker-schemas.sh exits non-zero"
fi

echo ""

# --- Test 2: Wrapper stub execution with valid requests ---
echo "--- Test 2: Wrapper stub execution (valid requests) ---"

ACTIONS=(
  "gateway_health"
  "gateway_restart"
  "validate_openclaw_json_candidate"
  "deploy_openclaw_json_candidate"
  "snapshot_pre"
  "snapshot_post"
  "vault_sync"
  "rollback_prepare"
)

declare -A ACTION_FILE_MAP
ACTION_FILE_MAP["gateway_health"]="gateway-health"
ACTION_FILE_MAP["gateway_restart"]="gateway-restart"
ACTION_FILE_MAP["validate_openclaw_json_candidate"]="validate-openclaw-json"
ACTION_FILE_MAP["deploy_openclaw_json_candidate"]="deploy-openclaw-json"
ACTION_FILE_MAP["snapshot_pre"]="snapshot-pre"
ACTION_FILE_MAP["snapshot_post"]="snapshot-post"
ACTION_FILE_MAP["vault_sync"]="vault-sync"
ACTION_FILE_MAP["rollback_prepare"]="rollback-prepare"

for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"
  wrapper="$REPO_ROOT/broker/wrappers/ocw-${file_stem}.sh"
  fixture="$REPO_ROOT/examples/broker/${file_stem}-request.json"

  if [ ! -f "$wrapper" ] || [ ! -f "$fixture" ]; then
    fail "Missing wrapper or fixture for $action"
    continue
  fi

  # Run wrapper with fixture, capture stdout (JSON result) and stderr (STUB messages)
  RESULT_JSON=""
  STDERR_OUTPUT=""
  RESULT_JSON=$(bash "$wrapper" "$fixture" 2>/tmp/test_broker_stderr) || {
    STDERR_OUTPUT=$(cat /tmp/test_broker_stderr 2>/dev/null || true)
    fail "Wrapper exited non-zero for $action: $STDERR_OUTPUT"
    continue
  }
  STDERR_OUTPUT=$(cat /tmp/test_broker_stderr 2>/dev/null || true)

  # Verify stdout is valid JSON
  if echo "$RESULT_JSON" | jq empty 2>/dev/null; then
    pass "Valid JSON output: ocw-${file_stem}.sh"
  else
    fail "Invalid JSON output: ocw-${file_stem}.sh"
    continue
  fi

  # Verify required result fields
  RESULT_OK=$(echo "$RESULT_JSON" | jq -r '.ok')
  RESULT_ACTION=$(echo "$RESULT_JSON" | jq -r '.action')
  RESULT_STATUS=$(echo "$RESULT_JSON" | jq -r '.status')
  RESULT_REQ_ID=$(echo "$RESULT_JSON" | jq -r '.request_id')
  RESULT_TASK_ID=$(echo "$RESULT_JSON" | jq -r '.task_id')

  if [ "$RESULT_OK" = "true" ]; then
    pass "ok=true: ocw-${file_stem}.sh"
  else
    fail "ok should be true for valid request: ocw-${file_stem}.sh (got: $RESULT_OK)"
  fi

  if [ "$RESULT_ACTION" = "$action" ]; then
    pass "Correct action echo: ocw-${file_stem}.sh"
  else
    fail "Wrong action in result: ocw-${file_stem}.sh (expected $action, got $RESULT_ACTION)"
  fi

  if [ "$RESULT_STATUS" = "ok" ]; then
    pass "status=ok: ocw-${file_stem}.sh"
  else
    fail "status should be ok for valid request: ocw-${file_stem}.sh (got: $RESULT_STATUS)"
  fi

  if [ -n "$RESULT_REQ_ID" ] && [ "$RESULT_REQ_ID" != "null" ]; then
    pass "request_id present: ocw-${file_stem}.sh"
  else
    fail "Missing request_id: ocw-${file_stem}.sh"
  fi

  if [ -n "$RESULT_TASK_ID" ] && [ "$RESULT_TASK_ID" != "null" ]; then
    pass "task_id present: ocw-${file_stem}.sh"
  else
    fail "Missing task_id: ocw-${file_stem}.sh"
  fi

  # Verify STUB markers in stderr
  if echo "$STDERR_OUTPUT" | grep -q '\[STUB\]'; then
    pass "STUB markers in stderr: ocw-${file_stem}.sh"
  else
    fail "Missing STUB markers in stderr: ocw-${file_stem}.sh"
  fi
done

echo ""

# --- Test 3: Negative test — wrong action ---
echo "--- Test 3: Negative test (wrong action) ---"

TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "gateway_health",
  "request_id": "req-test-wrong-action",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {}
}
EOF

# Try sending a gateway_health request to gateway_restart wrapper
if bash "$REPO_ROOT/broker/wrappers/ocw-gateway-restart.sh" "$TMPFILE" >/dev/null 2>&1; then
  fail "gateway_restart wrapper should reject gateway_health action"
else
  pass "gateway_restart wrapper correctly rejects wrong action"
fi

rm -f "$TMPFILE"

echo ""

# --- Test 4: Negative test — bad path ---
echo "--- Test 4: Negative test (bad path) ---"

BAD_PATH_REQ="$REPO_ROOT/examples/broker/bad-path-request.json"
if [ -f "$BAD_PATH_REQ" ]; then
  # deploy wrapper should reject /etc/passwd path
  if bash "$REPO_ROOT/broker/wrappers/ocw-deploy-openclaw-json.sh" "$BAD_PATH_REQ" >/dev/null 2>&1; then
    fail "deploy wrapper should reject non-whitelisted path"
  else
    pass "deploy wrapper correctly rejects non-whitelisted path"
  fi

  # validate wrapper should also reject
  BAD_VALIDATE_REQ=$(mktemp)
  jq '.action = "validate_openclaw_json_candidate"' "$BAD_PATH_REQ" > "$BAD_VALIDATE_REQ"
  if bash "$REPO_ROOT/broker/wrappers/ocw-validate-openclaw-json.sh" "$BAD_VALIDATE_REQ" >/dev/null 2>&1; then
    fail "validate wrapper should reject non-whitelisted path"
  else
    pass "validate wrapper correctly rejects non-whitelisted path"
  fi
  rm -f "$BAD_VALIDATE_REQ"
else
  fail "Missing bad-path-request.json fixture"
fi

echo ""

# --- Test 5: Negative test — path traversal ---
echo "--- Test 5: Negative test (path traversal) ---"

TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "deploy_openclaw_json_candidate",
  "request_id": "req-test-traversal",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/../../etc/passwd",
    "expected_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
EOF

if bash "$REPO_ROOT/broker/wrappers/ocw-deploy-openclaw-json.sh" "$TMPFILE" >/dev/null 2>&1; then
  fail "deploy wrapper should reject path traversal"
else
  pass "deploy wrapper correctly rejects path traversal"
fi

rm -f "$TMPFILE"

echo ""

# --- Test 6: Negative test — missing request file ---
echo "--- Test 6: Negative test (missing request file) ---"

if bash "$REPO_ROOT/broker/wrappers/ocw-gateway-health.sh" "/nonexistent/file.json" >/dev/null 2>&1; then
  fail "Wrapper should reject nonexistent request file"
else
  pass "Wrapper correctly rejects nonexistent request file"
fi

echo ""

# --- Summary ---
echo "=== Summary ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL ($FAIL failures)"
  exit 1
else
  echo "RESULT: ALL TESTS PASSED"
  exit 0
fi
