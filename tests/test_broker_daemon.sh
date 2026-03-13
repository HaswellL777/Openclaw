#!/usr/bin/env bash
# test_broker_daemon.sh — End-to-end integration tests for broker daemon dispatch
#
# Tests the full pipeline: broker CLI → envelope validation → wrapper dispatch → result
# All tests run in dry-run mode (BROKER_DRY_RUN=true, the default).
#
# Usage: tests/test_broker_daemon.sh
#
# Tests:
# 1. Happy-path: all 8 actions dispatched through broker daemon
# 2. Result envelope validation (required fields, ok/status invariant, mode:dry-run)
# 3. Negative: broker-level envelope rejection (invalid JSON, unknown action, missing fields)
# 4. Negative: wrapper-level input rejection via daemon dispatch
# 5. Broker daemon contract freeze (action map, version, --help)
# 6. Error_code presence in error responses
# 7. Stderr isolation (broker logs to stderr, result JSON on stdout only)
#
# Dependencies: jq, bash 4+

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BROKER="$REPO_ROOT/broker/openclaw-broker"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; return 0; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; return 0; }

# Temp directory for test fixtures
TMPDIR_TEST=$(mktemp -d "${TMPDIR:-/tmp}/broker-test-XXXXXX")
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

echo "=== Broker Daemon End-to-End Tests ==="
echo ""

# ========================================
# Test 1: Happy-path dispatch for all 8 actions
# ========================================
echo "--- Test 1: Happy-path dispatch (all 8 actions) ---"

declare -A ACTION_FILE_MAP
ACTION_FILE_MAP["gateway_health"]="gateway-health"
ACTION_FILE_MAP["gateway_restart"]="gateway-restart"
ACTION_FILE_MAP["validate_openclaw_json_candidate"]="validate-openclaw-json"
ACTION_FILE_MAP["deploy_openclaw_json_candidate"]="deploy-openclaw-json"
ACTION_FILE_MAP["snapshot_pre"]="snapshot-pre"
ACTION_FILE_MAP["snapshot_post"]="snapshot-post"
ACTION_FILE_MAP["vault_sync"]="vault-sync"
ACTION_FILE_MAP["rollback_prepare"]="rollback-prepare"

ACTIONS=(
  gateway_health
  gateway_restart
  validate_openclaw_json_candidate
  deploy_openclaw_json_candidate
  snapshot_pre
  snapshot_post
  vault_sync
  rollback_prepare
)

for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"
  fixture="$REPO_ROOT/examples/broker/${file_stem}-request.json"

  if [ ! -f "$fixture" ]; then
    fail "Missing fixture for daemon dispatch: ${file_stem}-request.json"
    continue
  fi

  RESULT=""
  STDERR_FILE="$TMPDIR_TEST/stderr-${file_stem}"
  RESULT=$(bash "$BROKER" --dispatch "$fixture" 2>"$STDERR_FILE") || {
    fail "Broker dispatch failed for $action (exit non-zero)"
    continue
  }

  # Verify stdout result is valid JSON
  if echo "$RESULT" | jq empty 2>/dev/null; then
    pass "Valid JSON from daemon: $action"
  else
    fail "Invalid JSON from daemon: $action"
    continue
  fi

  # Verify required result envelope fields
  result_ok=$(echo "$RESULT" | jq -r '.ok')
  result_action=$(echo "$RESULT" | jq -r '.action')
  result_status=$(echo "$RESULT" | jq -r '.status')
  result_req_id=$(echo "$RESULT" | jq -r '.request_id')
  result_task_id=$(echo "$RESULT" | jq -r '.task_id')

  [ "$result_ok" = "true" ] && pass "ok=true via daemon: $action" || fail "ok should be true via daemon: $action (got: $result_ok)"
  [ "$result_action" = "$action" ] && pass "action echo via daemon: $action" || fail "action mismatch via daemon: expected $action, got $result_action"
  [ "$result_status" = "ok" ] && pass "status=ok via daemon: $action" || fail "status should be ok via daemon: $action (got: $result_status)"
  [ -n "$result_req_id" ] && [ "$result_req_id" != "null" ] && pass "request_id present via daemon: $action" || fail "Missing request_id via daemon: $action"
  [ -n "$result_task_id" ] && [ "$result_task_id" != "null" ] && pass "task_id present via daemon: $action" || fail "Missing task_id via daemon: $action"

  # Verify broker logged to stderr
  if [ -f "$STDERR_FILE" ] && [ -s "$STDERR_FILE" ]; then
    pass "Broker stderr has log output: $action"
  else
    fail "Broker stderr empty (expected log lines): $action"
  fi
done

echo ""

# ========================================
# Test 2: Artifact mode=dry-run in all wrapper results
# ========================================
echo "--- Test 2: Mode=dry-run in artifacts ---"

for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"
  fixture="$REPO_ROOT/examples/broker/${file_stem}-request.json"
  [ ! -f "$fixture" ] && continue

  RESULT=$(bash "$BROKER" --dispatch "$fixture" 2>/dev/null) || continue
  artifact_mode=$(echo "$RESULT" | jq -r '.artifacts.mode // empty' 2>/dev/null)

  if [ "$artifact_mode" = "dry-run" ]; then
    pass "artifacts.mode=dry-run: $action"
  else
    fail "artifacts.mode should be dry-run: $action (got: ${artifact_mode:-<missing>})"
  fi
done

echo ""

# ========================================
# Test 3: Broker-level negative tests (envelope rejection)
# ========================================
echo "--- Test 3: Broker envelope rejection ---"

# 3a. Invalid JSON
cat > "$TMPDIR_TEST/invalid-json.txt" <<'EOF'
{this is not valid json
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/invalid-json.txt" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Broker rejects invalid JSON"
  err_code=$(echo "$RESULT" | jq -r '.error_code // empty')
  [ "$err_code" = "E_INVALID_JSON" ] && pass "Error code E_INVALID_JSON for invalid JSON" || fail "Expected E_INVALID_JSON, got: $err_code"
else
  fail "Broker should return ok=false for invalid JSON"
fi

# 3b. Missing action
cat > "$TMPDIR_TEST/no-action.json" <<'EOF'
{"request_id":"test-1","task_id":"t-1","requested_by":"test","inputs":{}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/no-action.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Broker rejects missing action"
  err_code=$(echo "$RESULT" | jq -r '.error_code // empty')
  [ "$err_code" = "E_UNKNOWN_ACTION" ] && pass "Error code E_UNKNOWN_ACTION for missing action" || fail "Expected E_UNKNOWN_ACTION, got: $err_code"
else
  fail "Broker should return ok=false for missing action"
fi

# 3c. Unknown action
cat > "$TMPDIR_TEST/bad-action.json" <<'EOF'
{"action":"delete_everything","request_id":"test-1","task_id":"t-1","requested_by":"test","inputs":{}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/bad-action.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Broker rejects unknown action"
  err_code=$(echo "$RESULT" | jq -r '.error_code // empty')
  [ "$err_code" = "E_UNKNOWN_ACTION" ] && pass "Error code E_UNKNOWN_ACTION for unknown action" || fail "Expected E_UNKNOWN_ACTION, got: $err_code"
else
  fail "Broker should return ok=false for unknown action"
fi

# 3d. Missing request_id and task_id
cat > "$TMPDIR_TEST/no-ids.json" <<'EOF'
{"action":"gateway_health","requested_by":"test","inputs":{}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/no-ids.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Broker rejects missing request_id/task_id"
  err_code=$(echo "$RESULT" | jq -r '.error_code // empty')
  [ "$err_code" = "E_MISSING_FIELD" ] && pass "Error code E_MISSING_FIELD" || fail "Expected E_MISSING_FIELD, got: $err_code"
else
  fail "Broker should return ok=false for missing IDs"
fi

# 3e. Nonexistent request file
RESULT=$(bash "$BROKER" --dispatch "/nonexistent/path/request.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Broker rejects nonexistent file"
  err_code=$(echo "$RESULT" | jq -r '.error_code // empty')
  [ "$err_code" = "E_FILE_NOT_FOUND" ] && pass "Error code E_FILE_NOT_FOUND" || fail "Expected E_FILE_NOT_FOUND, got: $err_code"
else
  fail "Broker should return ok=false for nonexistent file"
fi

# 3f. Empty JSON object
cat > "$TMPDIR_TEST/empty-obj.json" <<'EOF'
{}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/empty-obj.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Broker rejects empty JSON object"
else
  fail "Broker should reject empty JSON object"
fi

echo ""

# ========================================
# Test 4: Wrapper-level rejection via daemon dispatch
# ========================================
echo "--- Test 4: Wrapper rejection via daemon ---"

# 4a. Missing reason for gateway_restart
cat > "$TMPDIR_TEST/no-reason.json" <<'EOF'
{"action":"gateway_restart","request_id":"test-nr","task_id":"t-nr","requested_by":"test","inputs":{}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/no-reason.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Wrapper rejects missing reason via daemon"
  err_code=$(echo "$RESULT" | jq -r '.error_code // empty')
  [ "$err_code" = "E_MISSING_INPUT" ] && pass "Error code E_MISSING_INPUT for missing reason" || fail "Expected E_MISSING_INPUT, got: $err_code"
else
  fail "Daemon should propagate wrapper rejection for missing reason"
fi

# 4b. Bad SHA256 for validate
cat > "$TMPDIR_TEST/bad-sha.json" <<'EOF'
{"action":"validate_openclaw_json_candidate","request_id":"test-bs","task_id":"t-bs","requested_by":"test","inputs":{"candidate_path":"/var/lib/openclaw/approvals/candidates/test.json","expected_sha256":"ZZZZ"}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/bad-sha.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Wrapper rejects bad SHA256 via daemon"
else
  fail "Daemon should propagate wrapper rejection for bad SHA256"
fi

# 4c. Bad label for snapshot_pre
cat > "$TMPDIR_TEST/bad-label.json" <<'EOF'
{"action":"snapshot_pre","request_id":"test-bl","task_id":"t-bl","requested_by":"test","inputs":{"label":"has spaces!!","reason":"test"}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/bad-label.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Wrapper rejects bad label via daemon"
else
  fail "Daemon should propagate wrapper rejection for bad label"
fi

# 4d. Path traversal for deploy
cat > "$TMPDIR_TEST/path-traversal.json" <<'EOF'
{"action":"deploy_openclaw_json_candidate","request_id":"test-pt","task_id":"t-pt","requested_by":"test","inputs":{"candidate_path":"/var/lib/openclaw/approvals/candidates/../../etc/passwd","expected_sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/path-traversal.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Wrapper rejects path traversal via daemon"
  result_status=$(echo "$RESULT" | jq -r '.status // empty')
  [ "$result_status" = "denied" ] && pass "Status=denied for path traversal" || fail "Expected status=denied for path traversal (got: $result_status)"
else
  fail "Daemon should propagate wrapper rejection for path traversal"
fi

# 4e. Missing snapshot_name for vault_sync
cat > "$TMPDIR_TEST/no-snap.json" <<'EOF'
{"action":"vault_sync","request_id":"test-ns","task_id":"t-ns","requested_by":"test","inputs":{}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/no-snap.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Wrapper rejects missing snapshot_name via daemon"
  err_code=$(echo "$RESULT" | jq -r '.error_code // empty')
  [ "$err_code" = "E_MISSING_INPUT" ] && pass "Error code E_MISSING_INPUT for missing snapshot_name" || fail "Expected E_MISSING_INPUT, got: $err_code"
else
  fail "Daemon should propagate wrapper rejection for missing snapshot_name"
fi

# 4f. Missing target_snapshot for rollback_prepare
cat > "$TMPDIR_TEST/no-target.json" <<'EOF'
{"action":"rollback_prepare","request_id":"test-nt","task_id":"t-nt","requested_by":"test","inputs":{"reason":"test"}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/no-target.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Wrapper rejects missing target_snapshot via daemon"
else
  fail "Daemon should propagate wrapper rejection for missing target_snapshot"
fi

# 4g. Extra top-level fields
cat > "$TMPDIR_TEST/extra-fields.json" <<'EOF'
{"action":"gateway_health","request_id":"test-ef","task_id":"t-ef","requested_by":"test","inputs":{},"extra_field":"should_fail"}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/extra-fields.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Wrapper rejects extra top-level fields via daemon"
else
  fail "Daemon should propagate wrapper rejection for extra fields"
fi

# 4h. Missing label for snapshot_post
cat > "$TMPDIR_TEST/no-label-post.json" <<'EOF'
{"action":"snapshot_post","request_id":"test-nlp","task_id":"t-nlp","requested_by":"test","inputs":{"reason":"test"}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/no-label-post.json" 2>/dev/null) || true
if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Wrapper rejects missing label for snapshot_post via daemon"
else
  fail "Daemon should propagate wrapper rejection for missing label (snapshot_post)"
fi

echo ""

# ========================================
# Test 5: Broker daemon contract freeze
# ========================================
echo "--- Test 5: Broker daemon contract freeze ---"

# 5a. Version string format
VERSION_OUT=$(bash "$BROKER" --version 2>/dev/null)
if echo "$VERSION_OUT" | grep -q "^openclaw-broker "; then
  pass "Broker --version outputs version string"
else
  fail "Broker --version format unexpected: $VERSION_OUT"
fi

# 5b. --help exits 0
if bash "$BROKER" --help >/dev/null 2>&1; then
  pass "Broker --help exits 0"
else
  fail "Broker --help should exit 0"
fi

# 5c. No mode exits non-zero
if bash "$BROKER" >/dev/null 2>&1; then
  fail "Broker with no args should exit non-zero"
else
  pass "Broker with no args exits non-zero"
fi

# 5d. Unknown arg exits non-zero
if bash "$BROKER" --unknown-flag >/dev/null 2>&1; then
  fail "Broker with unknown flag should exit non-zero"
else
  pass "Broker with unknown flag exits non-zero"
fi

# 5e. Action wrapper map covers all 8 actions
WRAPPER_MAP_COUNT=$(grep -c '^\s*\[.*\]=' "$BROKER" 2>/dev/null || true)
if [ "$WRAPPER_MAP_COUNT" -eq 8 ]; then
  pass "ACTION_WRAPPER_MAP has 8 entries"
else
  fail "ACTION_WRAPPER_MAP should have 8 entries (got: $WRAPPER_MAP_COUNT)"
fi

# 5f. VALID_ACTIONS count
VALID_ACTIONS_COUNT=$(sed -n '/^readonly VALID_ACTIONS=/,/^)/p' "$BROKER" | grep -cE '^\s+[a-z_]+' || true)
if [ "$VALID_ACTIONS_COUNT" -eq 8 ]; then
  pass "VALID_ACTIONS has 8 entries"
else
  fail "VALID_ACTIONS should have 8 entries (got: $VALID_ACTIONS_COUNT)"
fi

# 5g. Broker daemon action list matches common.sh
BROKER_ACTIONS=$(sed -n '/^readonly VALID_ACTIONS=/,/^)/p' "$BROKER" | grep -oP '^\s+[a-z_]+' | tr -d ' ' | sort)
COMMON_ACTIONS=$(sed -n '/^readonly BROKER_ACTIONS=/,/^)/p' "$REPO_ROOT/broker/wrappers/lib/common.sh" | grep -oP '^\s+[a-z_]+' | tr -d ' ' | sort)

if [ "$BROKER_ACTIONS" = "$COMMON_ACTIONS" ]; then
  pass "Broker VALID_ACTIONS matches common.sh BROKER_ACTIONS"
else
  fail "Broker VALID_ACTIONS does not match common.sh BROKER_ACTIONS"
fi

# 5h. Broker daemon action list matches schema enum
SCHEMA_ACTIONS=$(jq -r '.properties.action.enum[]' "$REPO_ROOT/broker/schemas/host-ops-request.schema.json" 2>/dev/null | sort)
if [ "$BROKER_ACTIONS" = "$SCHEMA_ACTIONS" ]; then
  pass "Broker VALID_ACTIONS matches request schema enum"
else
  fail "Broker VALID_ACTIONS does not match request schema enum"
fi

# 5i. ACTION_WRAPPER_MAP keys match VALID_ACTIONS
MAP_KEYS=$(grep -oP '\[([a-z_]+)\]=' "$BROKER" | tr -d '[]=' | sort)
if [ "$MAP_KEYS" = "$BROKER_ACTIONS" ]; then
  pass "ACTION_WRAPPER_MAP keys match VALID_ACTIONS"
else
  fail "ACTION_WRAPPER_MAP keys do not match VALID_ACTIONS"
fi

# 5j. All wrapper files referenced in map actually exist
ALL_WRAPPERS_EXIST=true
for action in "${ACTIONS[@]}"; do
  wrapper_name=$(grep -oP "\[$action\]=\"[^\"]+\"" "$BROKER" | grep -oP '"[^"]+"' | tr -d '"')
  if [ ! -f "$REPO_ROOT/broker/wrappers/$wrapper_name" ]; then
    fail "Wrapper not found: $wrapper_name (for $action)"
    ALL_WRAPPERS_EXIST=false
  fi
done
[ "$ALL_WRAPPERS_EXIST" = "true" ] && pass "All wrapper files in ACTION_WRAPPER_MAP exist"

echo ""

# ========================================
# Test 6: Error response ok/status invariant
# ========================================
echo "--- Test 6: Error ok/status invariant ---"

# Every error response from the daemon must have ok=false AND status in {error, denied}
ERROR_FIXTURES=(
  "$TMPDIR_TEST/invalid-json.txt"
  "$TMPDIR_TEST/no-action.json"
  "$TMPDIR_TEST/bad-action.json"
  "$TMPDIR_TEST/no-ids.json"
  "$TMPDIR_TEST/no-reason.json"
  "$TMPDIR_TEST/bad-sha.json"
  "$TMPDIR_TEST/bad-label.json"
  "$TMPDIR_TEST/path-traversal.json"
  "$TMPDIR_TEST/no-snap.json"
  "$TMPDIR_TEST/no-target.json"
  "$TMPDIR_TEST/extra-fields.json"
  "$TMPDIR_TEST/no-label-post.json"
)

for err_fix in "${ERROR_FIXTURES[@]}"; do
  [ ! -f "$err_fix" ] && continue
  basename_f=$(basename "$err_fix")
  RESULT=$(bash "$BROKER" --dispatch "$err_fix" 2>/dev/null) || true

  if [ -z "$RESULT" ]; then
    fail "Empty output for error case: $basename_f"
    continue
  fi

  err_ok=$(echo "$RESULT" | jq -r 'if .ok == false then "false" elif .ok == true then "true" else "null" end' 2>/dev/null)
  err_status=$(echo "$RESULT" | jq -r '.status' 2>/dev/null)

  if [ "$err_ok" = "false" ]; then
    pass "ok=false invariant: $basename_f"
  else
    fail "ok should be false: $basename_f (got: $err_ok)"
  fi

  if [ "$err_status" = "error" ] || [ "$err_status" = "denied" ]; then
    pass "status in {error,denied}: $basename_f ($err_status)"
  else
    fail "status should be error or denied: $basename_f (got: $err_status)"
  fi
done

echo ""

# ========================================
# Test 7: Stdout/stderr isolation
# ========================================
echo "--- Test 7: Stdout/stderr isolation ---"

# On success: stdout must be valid JSON, stderr must have broker log lines
fixture="$REPO_ROOT/examples/broker/gateway-health-request.json"
STDOUT_FILE="$TMPDIR_TEST/stdout-isolation"
STDERR_FILE="$TMPDIR_TEST/stderr-isolation"
bash "$BROKER" --dispatch "$fixture" >"$STDOUT_FILE" 2>"$STDERR_FILE" || true

# stdout is pure JSON
if jq empty "$STDOUT_FILE" 2>/dev/null; then
  pass "stdout is pure valid JSON (no log contamination)"
else
  fail "stdout contains non-JSON content"
fi

# stderr has broker log lines
if grep -q '\[broker\]' "$STDERR_FILE" 2>/dev/null; then
  pass "stderr contains broker log lines"
else
  fail "stderr should contain broker log lines"
fi

# stderr has WRAPPER_STDERR lines (STUB markers)
if grep -q 'WRAPPER_STDERR' "$STDERR_FILE" 2>/dev/null; then
  pass "stderr contains forwarded wrapper log lines"
else
  fail "stderr should contain forwarded wrapper STUB lines"
fi

# No JSON on stderr for success case (structured JSON error goes to stderr only on wrapper failure)
if grep -q '^{.*"ok"' "$STDERR_FILE" 2>/dev/null; then
  fail "stderr should not contain JSON result on success"
else
  pass "stderr has no JSON result on success"
fi

# On error: stdout has structured error JSON
STDOUT_ERR_FILE="$TMPDIR_TEST/stdout-err-isolation"
STDERR_ERR_FILE="$TMPDIR_TEST/stderr-err-isolation"
bash "$BROKER" --dispatch "$TMPDIR_TEST/bad-action.json" >"$STDOUT_ERR_FILE" 2>"$STDERR_ERR_FILE" || true

if jq empty "$STDOUT_ERR_FILE" 2>/dev/null; then
  err_ok=$(jq -r '.ok' "$STDOUT_ERR_FILE" 2>/dev/null)
  [ "$err_ok" = "false" ] && pass "Error result on stdout: ok=false" || fail "Error result should have ok=false on stdout"
else
  fail "Error stdout should be valid JSON"
fi

echo ""

# ========================================
# Test 8: Roundtrip request_id/task_id fidelity
# ========================================
echo "--- Test 8: Request ID fidelity ---"

cat > "$TMPDIR_TEST/id-fidelity.json" <<'EOF'
{"action":"gateway_health","request_id":"req-fidelity-abc-123","task_id":"task-fidelity-xyz-789","requested_by":"fidelity-test","inputs":{}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/id-fidelity.json" 2>/dev/null) || true
result_req_id=$(echo "$RESULT" | jq -r '.request_id')
result_task_id=$(echo "$RESULT" | jq -r '.task_id')

[ "$result_req_id" = "req-fidelity-abc-123" ] && pass "request_id roundtrip fidelity" || fail "request_id roundtrip: expected req-fidelity-abc-123, got $result_req_id"
[ "$result_task_id" = "task-fidelity-xyz-789" ] && pass "task_id roundtrip fidelity" || fail "task_id roundtrip: expected task-fidelity-xyz-789, got $result_task_id"

# Error case also preserves IDs
cat > "$TMPDIR_TEST/id-fidelity-err.json" <<'EOF'
{"action":"gateway_restart","request_id":"req-err-abc","task_id":"task-err-xyz","requested_by":"test","inputs":{}}
EOF

RESULT=$(bash "$BROKER" --dispatch "$TMPDIR_TEST/id-fidelity-err.json" 2>/dev/null) || true
result_req_id=$(echo "$RESULT" | jq -r '.request_id')
result_task_id=$(echo "$RESULT" | jq -r '.task_id')

[ "$result_req_id" = "req-err-abc" ] && pass "request_id preserved in error" || fail "request_id in error: expected req-err-abc, got $result_req_id"
[ "$result_task_id" = "task-err-xyz" ] && pass "task_id preserved in error" || fail "task_id in error: expected task-err-xyz, got $result_task_id"

echo ""

# ========================================
# Test 9: BROKER_DRY_RUN enforcement
# ========================================
echo "--- Test 9: BROKER_DRY_RUN enforcement ---"

# Verify BROKER_DRY_RUN=true is the default
DRY_RUN_DEFAULT=$(grep -v '^#' "$BROKER" | grep 'BROKER_DRY_RUN=' | head -1)
if echo "$DRY_RUN_DEFAULT" | grep -q 'BROKER_DRY_RUN:-true'; then
  pass "BROKER_DRY_RUN defaults to true in broker"
else
  fail "BROKER_DRY_RUN should default to true"
fi

DRY_RUN_COMMON=$(grep 'BROKER_DRY_RUN=' "$REPO_ROOT/broker/wrappers/lib/common.sh" | head -1)
if echo "$DRY_RUN_COMMON" | grep -q 'BROKER_DRY_RUN:-true'; then
  pass "BROKER_DRY_RUN defaults to true in common.sh"
else
  fail "BROKER_DRY_RUN should default to true in common.sh"
fi

# Verify broker exports BROKER_DRY_RUN
if grep -q 'export BROKER_DRY_RUN' "$BROKER"; then
  pass "Broker exports BROKER_DRY_RUN to wrappers"
else
  fail "Broker should export BROKER_DRY_RUN"
fi

echo ""

# ========================================
# Test 10: Log file option
# ========================================
echo "--- Test 10: --log-file option ---"

LOG_OUT="$TMPDIR_TEST/broker-log-test.log"
fixture="$REPO_ROOT/examples/broker/gateway-health-request.json"
bash "$BROKER" --dispatch "$fixture" --log-file "$LOG_OUT" >/dev/null 2>/dev/null || true

if [ -f "$LOG_OUT" ] && [ -s "$LOG_OUT" ]; then
  pass "--log-file creates log output"
  if grep -q '\[broker\]' "$LOG_OUT"; then
    pass "Log file contains broker messages"
  else
    fail "Log file should contain broker messages"
  fi
else
  fail "--log-file should create a non-empty log file"
fi

echo ""

# ========================================
# Summary
# ========================================
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
