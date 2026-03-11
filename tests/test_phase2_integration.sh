#!/usr/bin/env bash
# test_phase2_integration.sh — Integration tests for Phase 2 dev-repo prep
#
# Usage: tests/test_phase2_integration.sh
#
# Tests:
# 1. Broker schema validation (delegated)
# 2. Wrapper stub execution with common.sh
# 3. Plugin request builder -> wrapper pipeline
# 4. Plugin request validator
# 5. Negative tests: wrong action, bad path, path traversal, missing fields
# 6. Contract drift detection
# 7. Common.sh shared validation helper tests
#
# Dependencies: jq, bash 4+

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; return 0; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; return 0; }

echo "=== Phase 2 Integration Tests ==="
echo ""

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

declare -A ACTION_FILE_MAP
ACTION_FILE_MAP["gateway_health"]="gateway-health"
ACTION_FILE_MAP["gateway_restart"]="gateway-restart"
ACTION_FILE_MAP["validate_openclaw_json_candidate"]="validate-openclaw-json"
ACTION_FILE_MAP["deploy_openclaw_json_candidate"]="deploy-openclaw-json"
ACTION_FILE_MAP["snapshot_pre"]="snapshot-pre"
ACTION_FILE_MAP["snapshot_post"]="snapshot-post"
ACTION_FILE_MAP["vault_sync"]="vault-sync"
ACTION_FILE_MAP["rollback_prepare"]="rollback-prepare"

# ========================================
# Test 1: Schema validation (delegated)
# ========================================
echo "--- Test 1: Schema validation ---"
if bash "$REPO_ROOT/scripts/validate-broker-schemas.sh" --verbose >/dev/null 2>&1; then
  pass "validate-broker-schemas.sh exits 0"
else
  fail "validate-broker-schemas.sh exits non-zero"
fi
echo ""

# ========================================
# Test 2: Wrapper stub execution (using common.sh)
# ========================================
echo "--- Test 2: Wrapper stub execution (with common.sh) ---"

for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"
  wrapper="$REPO_ROOT/broker/wrappers/ocw-${file_stem}.sh"
  fixture="$REPO_ROOT/examples/broker/${file_stem}-request.json"

  if [ ! -f "$wrapper" ] || [ ! -f "$fixture" ]; then
    fail "Missing wrapper or fixture for $action"
    continue
  fi

  RESULT_JSON=""
  RESULT_JSON=$(bash "$wrapper" "$fixture" 2>/tmp/test_phase2_stderr) || {
    STDERR_OUTPUT=$(cat /tmp/test_phase2_stderr 2>/dev/null || true)
    fail "Wrapper exited non-zero for $action: $STDERR_OUTPUT"
    continue
  }
  STDERR_OUTPUT=$(cat /tmp/test_phase2_stderr 2>/dev/null || true)

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

  [ "$RESULT_OK" = "true" ] && pass "ok=true: $action" || fail "ok should be true: $action (got: $RESULT_OK)"
  [ "$RESULT_ACTION" = "$action" ] && pass "action echo: $action" || fail "wrong action: $action (got: $RESULT_ACTION)"
  [ "$RESULT_STATUS" = "ok" ] && pass "status=ok: $action" || fail "status should be ok: $action (got: $RESULT_STATUS)"
  [ -n "$RESULT_REQ_ID" ] && [ "$RESULT_REQ_ID" != "null" ] && pass "request_id present: $action" || fail "Missing request_id: $action"
  [ -n "$RESULT_TASK_ID" ] && [ "$RESULT_TASK_ID" != "null" ] && pass "task_id present: $action" || fail "Missing task_id: $action"

  # Verify STUB markers in stderr
  echo "$STDERR_OUTPUT" | grep -q '\[STUB\]' && pass "STUB markers: $action" || fail "Missing STUB markers: $action"
done

echo ""

# ========================================
# Test 3: Plugin request builder -> wrapper pipeline
# ========================================
echo "--- Test 3: Plugin builder -> wrapper pipeline ---"

BUILD_REQUEST="$REPO_ROOT/plugins/host-ops-tool/lib/build-request.sh"

# gateway_health: no inputs needed
TMPFILE=$(mktemp)
if bash "$BUILD_REQUEST" gateway_health > "$TMPFILE" 2>/dev/null; then
  pass "build-request.sh gateway_health produces output"
  if jq empty "$TMPFILE" 2>/dev/null; then
    pass "build-request.sh output is valid JSON"
    # Feed to wrapper
    if RESULT=$(bash "$REPO_ROOT/broker/wrappers/ocw-gateway-health.sh" "$TMPFILE" 2>/dev/null); then
      if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
        pass "Builder -> wrapper pipeline: gateway_health"
      else
        fail "Builder -> wrapper pipeline: gateway_health (wrapper returned ok!=true)"
      fi
    else
      fail "Builder -> wrapper pipeline: gateway_health (wrapper failed)"
    fi
  else
    fail "build-request.sh output is not valid JSON"
  fi
else
  fail "build-request.sh gateway_health failed"
fi
rm -f "$TMPFILE"

# gateway_restart: needs reason
TMPFILE=$(mktemp)
if bash "$BUILD_REQUEST" gateway_restart "reason=test restart" > "$TMPFILE" 2>/dev/null; then
  if RESULT=$(bash "$REPO_ROOT/broker/wrappers/ocw-gateway-restart.sh" "$TMPFILE" 2>/dev/null); then
    if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
      pass "Builder -> wrapper pipeline: gateway_restart"
    else
      fail "Builder -> wrapper pipeline: gateway_restart (ok!=true)"
    fi
  else
    fail "Builder -> wrapper pipeline: gateway_restart (wrapper failed)"
  fi
else
  fail "build-request.sh gateway_restart failed"
fi
rm -f "$TMPFILE"

# snapshot_pre: needs label + reason
TMPFILE=$(mktemp)
if bash "$BUILD_REQUEST" snapshot_pre "label=test-20260311" "reason=test snapshot" > "$TMPFILE" 2>/dev/null; then
  if RESULT=$(bash "$REPO_ROOT/broker/wrappers/ocw-snapshot-pre.sh" "$TMPFILE" 2>/dev/null); then
    if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
      pass "Builder -> wrapper pipeline: snapshot_pre"
    else
      fail "Builder -> wrapper pipeline: snapshot_pre (ok!=true)"
    fi
  else
    fail "Builder -> wrapper pipeline: snapshot_pre (wrapper failed)"
  fi
else
  fail "build-request.sh snapshot_pre failed"
fi
rm -f "$TMPFILE"

# snapshot_post: needs label + reason
TMPFILE=$(mktemp)
if bash "$BUILD_REQUEST" snapshot_post "label=post-config-20260311" "reason=post-change snapshot" > "$TMPFILE" 2>/dev/null; then
  if RESULT=$(bash "$REPO_ROOT/broker/wrappers/ocw-snapshot-post.sh" "$TMPFILE" 2>/dev/null); then
    if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
      pass "Builder -> wrapper pipeline: snapshot_post"
    else
      fail "Builder -> wrapper pipeline: snapshot_post (ok!=true)"
    fi
  else
    fail "Builder -> wrapper pipeline: snapshot_post (wrapper failed)"
  fi
else
  fail "build-request.sh snapshot_post failed"
fi
rm -f "$TMPFILE"

# validate_openclaw_json_candidate: needs candidate_path + expected_sha256
TMPFILE=$(mktemp)
if bash "$BUILD_REQUEST" validate_openclaw_json_candidate \
  "candidate_path=/var/lib/openclaw/approvals/candidates/openclaw.json" \
  "expected_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" > "$TMPFILE" 2>/dev/null; then
  if RESULT=$(bash "$REPO_ROOT/broker/wrappers/ocw-validate-openclaw-json.sh" "$TMPFILE" 2>/dev/null); then
    if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
      pass "Builder -> wrapper pipeline: validate_openclaw_json_candidate"
    else
      fail "Builder -> wrapper pipeline: validate_openclaw_json_candidate (ok!=true)"
    fi
  else
    fail "Builder -> wrapper pipeline: validate_openclaw_json_candidate (wrapper failed)"
  fi
else
  fail "build-request.sh validate_openclaw_json_candidate failed"
fi
rm -f "$TMPFILE"

# deploy_openclaw_json_candidate: needs candidate_path + expected_sha256
TMPFILE=$(mktemp)
if bash "$BUILD_REQUEST" deploy_openclaw_json_candidate \
  "candidate_path=/var/lib/openclaw/approvals/candidates/openclaw.json" \
  "expected_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" > "$TMPFILE" 2>/dev/null; then
  if RESULT=$(bash "$REPO_ROOT/broker/wrappers/ocw-deploy-openclaw-json.sh" "$TMPFILE" 2>/dev/null); then
    if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
      pass "Builder -> wrapper pipeline: deploy_openclaw_json_candidate"
    else
      fail "Builder -> wrapper pipeline: deploy_openclaw_json_candidate (ok!=true)"
    fi
  else
    fail "Builder -> wrapper pipeline: deploy_openclaw_json_candidate (wrapper failed)"
  fi
else
  fail "build-request.sh deploy_openclaw_json_candidate failed"
fi
rm -f "$TMPFILE"

# vault_sync: needs snapshot_name
TMPFILE=$(mktemp)
if bash "$BUILD_REQUEST" vault_sync "snapshot_name=root-20260311-pre" > "$TMPFILE" 2>/dev/null; then
  if RESULT=$(bash "$REPO_ROOT/broker/wrappers/ocw-vault-sync.sh" "$TMPFILE" 2>/dev/null); then
    if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
      pass "Builder -> wrapper pipeline: vault_sync"
    else
      fail "Builder -> wrapper pipeline: vault_sync (ok!=true)"
    fi
  else
    fail "Builder -> wrapper pipeline: vault_sync (wrapper failed)"
  fi
else
  fail "build-request.sh vault_sync failed"
fi
rm -f "$TMPFILE"

# rollback_prepare: needs target_snapshot + reason
TMPFILE=$(mktemp)
if bash "$BUILD_REQUEST" rollback_prepare "target_snapshot=root-20260310-pre" "reason=rollback test" > "$TMPFILE" 2>/dev/null; then
  if RESULT=$(bash "$REPO_ROOT/broker/wrappers/ocw-rollback-prepare.sh" "$TMPFILE" 2>/dev/null); then
    if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
      pass "Builder -> wrapper pipeline: rollback_prepare"
    else
      fail "Builder -> wrapper pipeline: rollback_prepare (ok!=true)"
    fi
  else
    fail "Builder -> wrapper pipeline: rollback_prepare (wrapper failed)"
  fi
else
  fail "build-request.sh rollback_prepare failed"
fi
rm -f "$TMPFILE"

echo ""

# ========================================
# Test 4: Plugin request validator
# ========================================
echo "--- Test 4: Plugin request validator ---"

VALIDATE_REQUEST="$REPO_ROOT/plugins/host-ops-tool/lib/validate-request.sh"

# Valid fixtures should pass
for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"
  req_file="$REPO_ROOT/examples/broker/${file_stem}-request.json"
  if [ -f "$req_file" ]; then
    if bash "$VALIDATE_REQUEST" "$req_file" >/dev/null 2>&1; then
      pass "Validator accepts fixture: ${file_stem}-request.json"
    else
      fail "Validator rejects valid fixture: ${file_stem}-request.json"
    fi
  fi
done

# Invalid: bad-path fixture should fail
BAD_PATH_REQ="$REPO_ROOT/examples/broker/bad-path-request.json"
if [ -f "$BAD_PATH_REQ" ]; then
  if bash "$VALIDATE_REQUEST" "$BAD_PATH_REQ" >/dev/null 2>&1; then
    fail "Validator should reject bad-path request"
  else
    pass "Validator rejects bad-path request"
  fi
fi

echo ""

# ========================================
# Test 5: Negative tests
# ========================================
echo "--- Test 5: Negative tests ---"

# 5a. Wrong action
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

if bash "$REPO_ROOT/broker/wrappers/ocw-gateway-restart.sh" "$TMPFILE" >/dev/null 2>&1; then
  fail "Wrapper should reject wrong action"
else
  pass "Wrapper rejects wrong action"
fi
rm -f "$TMPFILE"

# 5b. Missing request_id
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "gateway_health",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {}
}
EOF

if bash "$REPO_ROOT/broker/wrappers/ocw-gateway-health.sh" "$TMPFILE" >/dev/null 2>&1; then
  fail "Wrapper should reject missing request_id"
else
  pass "Wrapper rejects missing request_id"
fi
rm -f "$TMPFILE"

# 5c. Missing task_id
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "gateway_health",
  "request_id": "req-test",
  "requested_by": "test",
  "inputs": {}
}
EOF

if bash "$REPO_ROOT/broker/wrappers/ocw-gateway-health.sh" "$TMPFILE" >/dev/null 2>&1; then
  fail "Wrapper should reject missing task_id"
else
  pass "Wrapper rejects missing task_id"
fi
rm -f "$TMPFILE"

# 5d. Bad path (non-whitelisted)
if [ -f "$BAD_PATH_REQ" ]; then
  if bash "$REPO_ROOT/broker/wrappers/ocw-deploy-openclaw-json.sh" "$BAD_PATH_REQ" >/dev/null 2>&1; then
    fail "Deploy wrapper should reject non-whitelisted path"
  else
    pass "Deploy wrapper rejects non-whitelisted path"
  fi
fi

# 5e. Path traversal
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
  fail "Deploy wrapper should reject path traversal"
else
  pass "Deploy wrapper rejects path traversal"
fi
rm -f "$TMPFILE"

# 5f. Missing request file
if bash "$REPO_ROOT/broker/wrappers/ocw-gateway-health.sh" "/nonexistent/file.json" >/dev/null 2>&1; then
  fail "Wrapper should reject nonexistent file"
else
  pass "Wrapper rejects nonexistent request file"
fi

# 5g. Bad SHA256 format
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "validate_openclaw_json_candidate",
  "request_id": "req-test-badsha",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/openclaw.json",
    "expected_sha256": "not-a-valid-sha256"
  }
}
EOF

if bash "$REPO_ROOT/broker/wrappers/ocw-validate-openclaw-json.sh" "$TMPFILE" >/dev/null 2>&1; then
  fail "Validate wrapper should reject bad SHA256"
else
  pass "Validate wrapper rejects bad SHA256 format"
fi
rm -f "$TMPFILE"

# 5h. Bad label format
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "snapshot_pre",
  "request_id": "req-test-badlabel",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {
    "label": "has spaces and $pecial",
    "reason": "test"
  }
}
EOF

if bash "$REPO_ROOT/broker/wrappers/ocw-snapshot-pre.sh" "$TMPFILE" >/dev/null 2>&1; then
  fail "Snapshot wrapper should reject bad label format"
else
  pass "Snapshot wrapper rejects bad label format"
fi
rm -f "$TMPFILE"

# 5i. Missing required inputs (gateway_restart without reason)
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "gateway_restart",
  "request_id": "req-test-noreason",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {}
}
EOF

if bash "$REPO_ROOT/broker/wrappers/ocw-gateway-restart.sh" "$TMPFILE" >/dev/null 2>&1; then
  fail "Restart wrapper should reject missing reason"
else
  pass "Restart wrapper rejects missing reason"
fi
rm -f "$TMPFILE"

# 5j. Plugin validator rejects missing action
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "request_id": "req-test",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {}
}
EOF

if bash "$VALIDATE_REQUEST" "$TMPFILE" >/dev/null 2>&1; then
  fail "Plugin validator should reject missing action"
else
  pass "Plugin validator rejects missing action"
fi
rm -f "$TMPFILE"

# 5k. Plugin validator rejects invalid action
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "delete_everything",
  "request_id": "req-test",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {}
}
EOF

if bash "$VALIDATE_REQUEST" "$TMPFILE" >/dev/null 2>&1; then
  fail "Plugin validator should reject invalid action"
else
  pass "Plugin validator rejects invalid action"
fi
rm -f "$TMPFILE"

# 5l. Plugin validator rejects negative fixtures
echo ""
echo "--- Test 5 (cont): Negative fixture validation ---"

NEGATIVE_DIR="$REPO_ROOT/examples/broker/negative"
NEGATIVE_CASES_WITH_REQUEST=(
  "invalid-action"
  "missing-request-id"
  "missing-task-id"
  "bad-sha256"
  "bad-label"
  "missing-reason"
  "missing-candidate-path"
  "path-traversal"
  "empty-reason"
  "empty-label"
  "empty-sha256"
  "missing-snapshot-name"
  "missing-target-snapshot"
  "missing-label"
  "empty-action"
  "extra-fields"
  "null-action"
  "null-inputs"
  "array-inputs"
  "numeric-action"
)

for case_name in "${NEGATIVE_CASES_WITH_REQUEST[@]}"; do
  req_file="$NEGATIVE_DIR/${case_name}-request.json"
  if [ -f "$req_file" ]; then
    if bash "$VALIDATE_REQUEST" "$req_file" >/dev/null 2>&1; then
      fail "Validator should reject negative fixture: ${case_name}"
    else
      pass "Validator correctly rejects: ${case_name}"
    fi
  else
    fail "Missing negative fixture: ${case_name}-request.json"
  fi
done

echo ""

# ========================================
# Test 6: Contract drift detection
# ========================================
echo "--- Test 6: Contract drift detection ---"

# Check that host-ops-api.md does NOT use old field names
API_DOC="$REPO_ROOT/workspace-main-template/control/host-ops-api.md"
if [ -f "$API_DOC" ]; then
  grep -q '"operation"' "$API_DOC" && fail "host-ops-api.md uses deprecated 'operation'" || pass "host-ops-api.md no deprecated 'operation'"
  grep -q '"parameters"' "$API_DOC" && fail "host-ops-api.md uses deprecated 'parameters'" || pass "host-ops-api.md no deprecated 'parameters'"
  grep -q '"approval_id"' "$API_DOC" && fail "host-ops-api.md uses deprecated 'approval_id'" || pass "host-ops-api.md no deprecated 'approval_id'"
fi

# Check that SKILL.md does NOT use old field names
SKILL_DOC="$REPO_ROOT/workspace-main-template/skills/broker/SKILL.md"
if [ -f "$SKILL_DOC" ]; then
  grep -q '"operation"' "$SKILL_DOC" && fail "SKILL.md uses deprecated 'operation'" || pass "SKILL.md no deprecated 'operation'"
  grep -q '"parameters"' "$SKILL_DOC" && fail "SKILL.md uses deprecated 'parameters'" || pass "SKILL.md no deprecated 'parameters'"
  grep -q '"approval_id"' "$SKILL_DOC" && fail "SKILL.md uses deprecated 'approval_id'" || pass "SKILL.md no deprecated 'approval_id'"
fi

# Check plugin index.js action list matches schema
REQ_SCHEMA="$REPO_ROOT/broker/schemas/host-ops-request.schema.json"
SCHEMA_ACTIONS=$(jq -r '.properties.action.enum[]' "$REQ_SCHEMA" 2>/dev/null | sort)
for action in "${ACTIONS[@]}"; do
  if echo "$SCHEMA_ACTIONS" | grep -q "^${action}$"; then
    pass "Action '$action' in both code and schema"
  else
    fail "Action '$action' missing from schema"
  fi
done

echo ""

# ========================================
# Test 7: Common.sh helper tests
# ========================================
echo "--- Test 7: Common.sh helper tests ---"

# Test broker_validate_sha256 via wrapper
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "validate_openclaw_json_candidate",
  "request_id": "req-test-sha",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/test.json",
    "expected_sha256": "ZZZZ"
  }
}
EOF
if bash "$REPO_ROOT/broker/wrappers/ocw-validate-openclaw-json.sh" "$TMPFILE" >/dev/null 2>&1; then
  fail "SHA256 validation should reject 'ZZZZ'"
else
  pass "SHA256 validation rejects invalid format"
fi
rm -f "$TMPFILE"

# Test valid SHA256 passes
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "validate_openclaw_json_candidate",
  "request_id": "req-test-sha-valid",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/test.json",
    "expected_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
EOF
if bash "$REPO_ROOT/broker/wrappers/ocw-validate-openclaw-json.sh" "$TMPFILE" >/dev/null 2>&1; then
  pass "SHA256 validation accepts valid hash"
else
  fail "SHA256 validation rejects valid hash"
fi
rm -f "$TMPFILE"

# Test label validation
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'EOF'
{
  "action": "snapshot_pre",
  "request_id": "req-test-label",
  "task_id": "task-test",
  "requested_by": "test",
  "inputs": {
    "label": "valid-label.2026_03",
    "reason": "test"
  }
}
EOF
if bash "$REPO_ROOT/broker/wrappers/ocw-snapshot-pre.sh" "$TMPFILE" >/dev/null 2>&1; then
  pass "Label validation accepts valid label"
else
  fail "Label validation rejects valid label"
fi
rm -f "$TMPFILE"

# Test no-args wrapper invocation
if bash "$REPO_ROOT/broker/wrappers/ocw-gateway-health.sh" >/dev/null 2>&1; then
  fail "Wrapper should reject no arguments"
else
  pass "Wrapper rejects no arguments"
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
