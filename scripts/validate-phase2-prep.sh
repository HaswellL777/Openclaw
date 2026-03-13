#!/usr/bin/env bash
# validate-phase2-prep.sh — Aggregated validation for Phase 2 dev-repo prep artifacts
#
# Usage: scripts/validate-phase2-prep.sh [--verbose]
#
# Validates the complete Phase 2 repo-only prep surface:
# 1. Broker schemas (delegates to validate-broker-schemas.sh)
# 2. Wrapper stub syntax and common.sh sourcing
# 3. Plugin skeleton validity
# 4. Fixture validity (delegates + plugin request builder)
# 5. Protocol spec consistency
# 6. Cross-layer contract alignment
#
# Dependencies: jq, bash 4+
# Does NOT require: npm, node (JS validation is syntax-only)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERBOSE="${1:-}"

PASS=0
FAIL=0
WARN=0

pass() { PASS=$((PASS + 1)); [ "$VERBOSE" = "--verbose" ] && echo "  PASS: $1"; return 0; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; return 0; }
warn() { WARN=$((WARN + 1)); echo "  WARN: $1"; return 0; }

echo "=== Phase 2 Dev-Repo Prep Validation ==="
echo ""

# --- Check dependencies ---
if ! command -v jq &>/dev/null; then
  echo "FATAL: jq is required but not installed"
  exit 1
fi

# ========================================
# Section 1: Broker schema validation
# ========================================
echo "--- Section 1: Broker schemas (delegated) ---"
if bash "$REPO_ROOT/scripts/validate-broker-schemas.sh" >/dev/null 2>&1; then
  pass "validate-broker-schemas.sh passes"
else
  fail "validate-broker-schemas.sh fails"
fi
echo ""

# ========================================
# Section 2: Wrapper stubs
# ========================================
echo "--- Section 2: Wrapper stub validation ---"

# Check common.sh exists and has no syntax errors
COMMON_SH="$REPO_ROOT/broker/wrappers/lib/common.sh"
if [ -f "$COMMON_SH" ]; then
  pass "common.sh exists"
  if bash -n "$COMMON_SH" 2>/dev/null; then
    pass "common.sh has no syntax errors"
  else
    fail "common.sh has syntax errors"
  fi
else
  fail "common.sh missing"
fi

# Validate each wrapper sources common.sh
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

for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"
  wrapper="$REPO_ROOT/broker/wrappers/ocw-${file_stem}.sh"

  if [ ! -f "$wrapper" ]; then
    fail "Missing wrapper: ocw-${file_stem}.sh"
    continue
  fi

  # Syntax check
  if bash -n "$wrapper" 2>/dev/null; then
    pass "No syntax errors: ocw-${file_stem}.sh"
  else
    fail "Syntax errors: ocw-${file_stem}.sh"
  fi

  # Sources common.sh
  if grep -q 'source.*lib/common\.sh' "$wrapper"; then
    pass "Sources common.sh: ocw-${file_stem}.sh"
  else
    fail "Does not source common.sh: ocw-${file_stem}.sh"
  fi

  # Uses common validation functions
  if grep -q 'broker_validate_request_file' "$wrapper"; then
    pass "Uses broker_validate_request_file: ocw-${file_stem}.sh"
  else
    fail "Does not use broker_validate_request_file: ocw-${file_stem}.sh"
  fi

  if grep -q 'broker_validate_action' "$wrapper"; then
    pass "Uses broker_validate_action: ocw-${file_stem}.sh"
  else
    fail "Does not use broker_validate_action: ocw-${file_stem}.sh"
  fi

  if grep -q 'broker_emit_result' "$wrapper"; then
    pass "Uses broker_emit_result: ocw-${file_stem}.sh"
  else
    fail "Does not use broker_emit_result: ocw-${file_stem}.sh"
  fi

  # Has STUB markers
  if grep -q '\[STUB\]' "$wrapper"; then
    pass "Has STUB marker: ocw-${file_stem}.sh"
  else
    warn "Missing STUB marker: ocw-${file_stem}.sh"
  fi
done

echo ""

# ========================================
# Section 3: Plugin skeleton
# ========================================
echo "--- Section 3: Plugin skeleton ---"

PLUGIN_DIR="$REPO_ROOT/plugins/host-ops-tool"

# Check core files exist
for f in index.js package.json README.md manifest-notes.md; do
  if [ -f "$PLUGIN_DIR/$f" ]; then
    pass "Plugin file exists: $f"
  else
    fail "Plugin file missing: $f"
  fi
done

# Check package.json is valid JSON
if jq empty "$PLUGIN_DIR/package.json" 2>/dev/null; then
  pass "package.json is valid JSON"
else
  fail "package.json is not valid JSON"
fi

# Check package.json marks as private
if jq -e '.private == true' "$PLUGIN_DIR/package.json" >/dev/null 2>&1; then
  pass "package.json is private"
else
  fail "package.json should be private"
fi

# Check lib scripts exist
for f in lib/build-request.sh lib/validate-request.sh; do
  if [ -f "$PLUGIN_DIR/$f" ]; then
    pass "Plugin file exists: $f"
    if bash -n "$PLUGIN_DIR/$f" 2>/dev/null; then
      pass "No syntax errors: $f"
    else
      fail "Syntax errors: $f"
    fi
  else
    fail "Plugin file missing: $f"
  fi
done

# Check index.js references all 8 actions
for action in "${ACTIONS[@]}"; do
  if grep -q "\"$action\"" "$PLUGIN_DIR/index.js"; then
    pass "index.js references action: $action"
  else
    fail "index.js missing action: $action"
  fi
done

# Check no HTTP/WebSocket/localhost references (Unix socket transport is expected)
if grep -qiE '(ws://|http://|localhost|127\.0\.0\.1)' "$PLUGIN_DIR/index.js"; then
  fail "index.js appears to reference HTTP/WebSocket/network connections"
else
  pass "index.js has no HTTP/WebSocket/network connection references"
fi

echo ""

# ========================================
# Section 4: Fixture validation
# ========================================
echo "--- Section 4: Fixture validation ---"

FIXTURES_DIR="$REPO_ROOT/examples/broker"

# Validate all example request fixtures with plugin validator
for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"
  req_file="$FIXTURES_DIR/${file_stem}-request.json"
  if [ -f "$req_file" ]; then
    if bash "$PLUGIN_DIR/lib/validate-request.sh" "$req_file" >/dev/null 2>&1; then
      pass "Plugin validator accepts: ${file_stem}-request.json"
    else
      fail "Plugin validator rejects: ${file_stem}-request.json"
    fi
  else
    fail "Missing fixture: ${file_stem}-request.json"
  fi
done

# Test request builder produces valid output
for action in gateway_health gateway_restart snapshot_pre vault_sync rollback_prepare; do
  TMPFILE=$(mktemp)
  case "$action" in
    gateway_health)
      bash "$PLUGIN_DIR/lib/build-request.sh" "$action" > "$TMPFILE" 2>/dev/null
      ;;
    gateway_restart)
      bash "$PLUGIN_DIR/lib/build-request.sh" "$action" "reason=test" > "$TMPFILE" 2>/dev/null
      ;;
    snapshot_pre)
      bash "$PLUGIN_DIR/lib/build-request.sh" "$action" "label=test-20260311" "reason=test" > "$TMPFILE" 2>/dev/null
      ;;
    vault_sync)
      bash "$PLUGIN_DIR/lib/build-request.sh" "$action" "snapshot_name=root-20260311-pre" > "$TMPFILE" 2>/dev/null
      ;;
    rollback_prepare)
      bash "$PLUGIN_DIR/lib/build-request.sh" "$action" "target_snapshot=root-20260310-pre" "reason=test" > "$TMPFILE" 2>/dev/null
      ;;
  esac
  if [ -s "$TMPFILE" ] && jq empty "$TMPFILE" 2>/dev/null; then
    pass "build-request.sh produces valid JSON for: $action"
    if bash "$PLUGIN_DIR/lib/validate-request.sh" "$TMPFILE" >/dev/null 2>&1; then
      pass "build-request.sh output passes validation for: $action"
    else
      fail "build-request.sh output fails validation for: $action"
    fi
  else
    fail "build-request.sh fails for: $action"
  fi
  rm -f "$TMPFILE"
done

echo ""

# ========================================
# Section 5: Protocol spec consistency
# ========================================
echo "--- Section 5: Protocol spec ---"

SPEC_DOC="$REPO_ROOT/docs/specs/host-ops-broker-protocol-v1.md"

if [ -f "$SPEC_DOC" ]; then
  pass "Protocol spec exists"

  # Check it references all 8 actions
  for action in "${ACTIONS[@]}"; do
    if grep -q "$action" "$SPEC_DOC"; then
      pass "Spec references action: $action"
    else
      fail "Spec missing action: $action"
    fi
  done

  # Check it uses correct field names (not old ones)
  # Spec uses backtick-quoted field names, e.g. `action`
  if grep -q '`action`' "$SPEC_DOC"; then
    pass "Spec uses 'action' field"
  else
    fail "Spec missing 'action' field"
  fi
  if grep -q '`inputs`' "$SPEC_DOC"; then
    pass "Spec uses 'inputs' field"
  else
    fail "Spec missing 'inputs' field"
  fi
  if grep -q '`requested_by`' "$SPEC_DOC"; then
    pass "Spec uses 'requested_by' field"
  else
    fail "Spec missing 'requested_by' field"
  fi

  # Should not use old field names
  if grep -q '"operation"' "$SPEC_DOC"; then
    fail "Spec uses deprecated 'operation' field"
  else
    pass "Spec does not use deprecated 'operation' field"
  fi
  if grep -q '"parameters"' "$SPEC_DOC"; then
    fail "Spec uses deprecated 'parameters' field"
  else
    pass "Spec does not use deprecated 'parameters' field"
  fi
  if grep -q '"approval_id"' "$SPEC_DOC"; then
    fail "Spec uses deprecated 'approval_id' field"
  else
    pass "Spec does not use deprecated 'approval_id' field"
  fi

  # Check phase boundary statement
  if grep -q "not yet deployed" "$SPEC_DOC"; then
    pass "Spec states broker not yet deployed"
  else
    fail "Spec missing 'not yet deployed' statement"
  fi
else
  fail "Protocol spec missing"
fi

echo ""

# ========================================
# Section 6: Cross-layer contract alignment
# ========================================
echo "--- Section 6: Cross-layer contract alignment ---"

# Check host-ops-api.md uses current field names
API_DOC="$REPO_ROOT/workspace-main-template/control/host-ops-api.md"
if [ -f "$API_DOC" ]; then
  if grep -q '"action"' "$API_DOC" && grep -q '"inputs"' "$API_DOC" && grep -q '"requested_by"' "$API_DOC"; then
    pass "host-ops-api.md uses current field names"
  else
    fail "host-ops-api.md has field name drift"
  fi
  if grep -q '"operation"' "$API_DOC" || grep -q '"parameters"' "$API_DOC" || grep -q '"approval_id"' "$API_DOC"; then
    fail "host-ops-api.md still uses deprecated field names"
  else
    pass "host-ops-api.md no deprecated field names"
  fi
fi

# Check SKILL.md uses current field names
SKILL_DOC="$REPO_ROOT/workspace-main-template/skills/broker/SKILL.md"
if [ -f "$SKILL_DOC" ]; then
  if grep -q '"action"' "$SKILL_DOC" && grep -q '"inputs"' "$SKILL_DOC" && grep -q '"requested_by"' "$SKILL_DOC"; then
    pass "broker SKILL.md uses current field names"
  else
    fail "broker SKILL.md has field name drift"
  fi
  if grep -q '"operation"' "$SKILL_DOC" || grep -q '"parameters"' "$SKILL_DOC" || grep -q '"approval_id"' "$SKILL_DOC"; then
    fail "broker SKILL.md still uses deprecated field names"
  else
    pass "broker SKILL.md no deprecated field names"
  fi
fi

# Check plugin index.js action list matches schema action enum
REQ_SCHEMA="$REPO_ROOT/broker/schemas/host-ops-request.schema.json"
if [ -f "$REQ_SCHEMA" ]; then
  SCHEMA_ACTIONS=$(jq -r '.properties.action.enum[]' "$REQ_SCHEMA" 2>/dev/null | sort)
  # Extract actions from common.sh BROKER_ACTIONS array
  COMMON_ACTIONS=$(sed -n '/^readonly BROKER_ACTIONS=/,/^)/p' "$COMMON_SH" 2>/dev/null | grep -oP '^  [a-z_]+$' | tr -d ' ' | sort)
  if [ "$SCHEMA_ACTIONS" = "$COMMON_ACTIONS" ]; then
    pass "common.sh action list matches request schema enum"
  else
    fail "common.sh action list does not match request schema enum"
  fi
fi

# Check wrapper count matches action count
WRAPPER_COUNT=$(find "$REPO_ROOT/broker/wrappers" -name 'ocw-*.sh' -type f | wc -l)
if [ "$WRAPPER_COUNT" -eq 8 ]; then
  pass "Wrapper count matches: 8"
else
  fail "Wrapper count mismatch: expected 8, got $WRAPPER_COUNT"
fi

# Check fixture count
FIXTURE_REQ_COUNT=$(find "$FIXTURES_DIR" -maxdepth 1 -name '*-request.json' -not -name 'bad-*' -type f 2>/dev/null | wc -l)
FIXTURE_RES_COUNT=$(find "$FIXTURES_DIR" -maxdepth 1 -name '*-result.json' -not -name 'bad-*' -type f 2>/dev/null | wc -l)
if [ "$FIXTURE_REQ_COUNT" -eq 8 ]; then
  pass "Request fixture count matches: 8"
else
  fail "Request fixture count mismatch: expected 8, got $FIXTURE_REQ_COUNT"
fi
if [ "$FIXTURE_RES_COUNT" -eq 8 ]; then
  pass "Result fixture count matches: 8"
else
  fail "Result fixture count mismatch: expected 8, got $FIXTURE_RES_COUNT"
fi

echo ""

# ========================================
# Section 7: Negative fixture validation
# ========================================
echo "--- Section 7: Negative fixture validation ---"

NEGATIVE_DIR="$REPO_ROOT/examples/broker/negative"

EXPECTED_NEGATIVES=(
  "invalid-action"
  "missing-request-id"
  "missing-task-id"
  "path-traversal"
  "bad-sha256"
  "bad-label"
  "missing-reason"
  "missing-candidate-path"
  "wrong-wrapper-action"
  "empty-reason"
  "empty-label"
  "empty-sha256"
  "missing-snapshot-name"
  "missing-target-snapshot"
  "missing-label"
  "type-error-reason"
  "empty-action"
  "extra-fields"
  "null-action"
  "null-inputs"
  "array-inputs"
  "numeric-action"
)

for case_name in "${EXPECTED_NEGATIVES[@]}"; do
  req_file="$NEGATIVE_DIR/${case_name}-request.json"
  res_file="$NEGATIVE_DIR/${case_name}-result.json"

  if [ -f "$req_file" ] && jq empty "$req_file" 2>/dev/null; then
    pass "Negative fixture valid: ${case_name}-request.json"
  else
    fail "Missing or invalid negative fixture: ${case_name}-request.json"
  fi

  if [ -f "$res_file" ] && jq empty "$res_file" 2>/dev/null; then
    # Verify ok=false
    neg_ok=$(jq -r '.ok' "$res_file" 2>/dev/null)
    neg_status=$(jq -r '.status' "$res_file" 2>/dev/null)
    if [ "$neg_ok" = "false" ] && { [ "$neg_status" = "error" ] || [ "$neg_status" = "denied" ]; }; then
      pass "Negative fixture valid: ${case_name}-result.json (ok=false, status=$neg_status)"
    else
      fail "Negative fixture bad envelope: ${case_name}-result.json (ok=$neg_ok, status=$neg_status)"
    fi
  else
    fail "Missing or invalid negative fixture: ${case_name}-result.json"
  fi
done

# Special: missing-file-result.json (no request file, that's the point)
MISSING_FILE_RES="$NEGATIVE_DIR/missing-file-result.json"
if [ -f "$MISSING_FILE_RES" ] && jq empty "$MISSING_FILE_RES" 2>/dev/null; then
  pass "Negative fixture valid: missing-file-result.json"
else
  fail "Missing or invalid: missing-file-result.json"
fi

# Special: ok-status-mismatch-result.json (result-only invariant violation demo)
MISMATCH_RES="$NEGATIVE_DIR/ok-status-mismatch-result.json"
if [ -f "$MISMATCH_RES" ] && jq empty "$MISMATCH_RES" 2>/dev/null; then
  mm_ok=$(jq -r '.ok' "$MISMATCH_RES" 2>/dev/null)
  mm_status=$(jq -r '.status' "$MISMATCH_RES" 2>/dev/null)
  if [ "$mm_ok" = "true" ] && [ "$mm_status" != "ok" ]; then
    pass "Negative fixture valid: ok-status-mismatch-result.json (invariant violation demo)"
  else
    fail "ok-status-mismatch fixture not shaped correctly"
  fi
else
  fail "Missing or invalid: ok-status-mismatch-result.json"
fi

# Validate negative fixtures are rejected by the validator
VALIDATE_REQUEST="$PLUGIN_DIR/lib/validate-request.sh"
VALIDATOR_NEGATIVE_CASES=(
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

for case_name in "${VALIDATOR_NEGATIVE_CASES[@]}"; do
  req_file="$NEGATIVE_DIR/${case_name}-request.json"
  if [ -f "$req_file" ]; then
    if bash "$VALIDATE_REQUEST" "$req_file" >/dev/null 2>&1; then
      fail "Validator should reject: ${case_name}"
    else
      pass "Validator correctly rejects: ${case_name}"
    fi
  fi
done

echo ""

# ========================================
# Section 7b: Schema maxLength consistency
# ========================================
echo "--- Section 7b: Schema maxLength consistency ---"

SCHEMAS_DIR="$REPO_ROOT/broker/schemas/actions"
for schema_stem in snapshot-pre snapshot-post vault-sync rollback-prepare; do
  schema_file="$SCHEMAS_DIR/${schema_stem}.schema.json"
  if [ -f "$schema_file" ]; then
    for prop in label snapshot_name target_snapshot; do
      max_len=$(jq -r ".properties.${prop}.maxLength // empty" "$schema_file" 2>/dev/null)
      if [ -n "$max_len" ]; then
        if [ "$max_len" = "128" ]; then
          pass "maxLength=128: ${schema_stem}.${prop}"
        else
          fail "Unexpected maxLength: ${schema_stem}.${prop} (got ${max_len}, expected 128)"
        fi
      fi
    done
  fi
done

echo ""

# ========================================
# Section 7c: Result schema hardening checks
# ========================================
echo "--- Section 7c: Result schema hardening ---"

RES_SCHEMA="$REPO_ROOT/broker/schemas/host-ops-result.schema.json"
if [ -f "$RES_SCHEMA" ]; then
  # additionalProperties must be false
  res_addl=$(jq -r '.additionalProperties' "$RES_SCHEMA" 2>/dev/null)
  if [ "$res_addl" = "false" ]; then
    pass "Result schema additionalProperties=false"
  else
    fail "Result schema additionalProperties should be false (got $res_addl)"
  fi

  # minLength on required string fields
  for prop in action request_id task_id; do
    min_len=$(jq -r ".properties.${prop}.minLength // empty" "$RES_SCHEMA" 2>/dev/null)
    if [ "$min_len" = "1" ]; then
      pass "Result schema minLength=1: $prop"
    else
      fail "Result schema missing minLength=1: $prop"
    fi
  done

  # ok/status invariant enforcement
  inv_if=$(jq -r '.if.properties.ok.const' "$RES_SCHEMA" 2>/dev/null)
  inv_then=$(jq -r '.then.properties.status.const' "$RES_SCHEMA" 2>/dev/null)
  if [ "$inv_if" = "true" ] && [ "$inv_then" = "ok" ]; then
    pass "Result schema ok/status invariant enforced"
  else
    fail "Result schema ok/status invariant not enforced"
  fi

  # Reserved error_code field
  ec_type=$(jq -r '.properties.error_code.type' "$RES_SCHEMA" 2>/dev/null)
  if [ "$ec_type" = "string" ]; then
    pass "Result schema has reserved error_code field"
  else
    fail "Result schema missing reserved error_code field"
  fi
fi

echo ""

# ========================================
# Section 8: Error taxonomy spec
# ========================================
echo "--- Section 8: Error taxonomy spec ---"

ERROR_SPEC="$REPO_ROOT/docs/specs/error-taxonomy-v1.md"
if [ -f "$ERROR_SPEC" ]; then
  pass "Error taxonomy spec exists"
  # Check it references key error codes
  for code in E_UNKNOWN_ACTION E_MISSING_FIELD E_INVALID_SHA256 D_PATH_WHITELIST D_PATH_TRAVERSAL; do
    if grep -q "$code" "$ERROR_SPEC"; then
      pass "Error taxonomy defines: $code"
    else
      fail "Error taxonomy missing: $code"
    fi
  done
  # Check it states Phase 2 not started
  if grep -q "not yet deployed" "$ERROR_SPEC"; then
    pass "Error taxonomy states broker not yet deployed"
  else
    fail "Error taxonomy missing 'not yet deployed' statement"
  fi
else
  fail "Error taxonomy spec missing"
fi

echo ""

# ========================================
# Section 9: Contract freeze test
# ========================================
echo "--- Section 9: Contract freeze test (delegated) ---"
if bash "$REPO_ROOT/tests/test_contract_freeze.sh" >/dev/null 2>&1; then
  pass "test_contract_freeze.sh passes"
else
  fail "test_contract_freeze.sh fails"
fi
echo ""

# ========================================
# Section 10: Cross-layer SHA256 example consistency
# ========================================
echo "--- Section 10: SHA256 example consistency ---"

# host-ops-api.md should not contain placeholder SHA256 like "abc123..."
API_DOC="$REPO_ROOT/workspace-main-template/control/host-ops-api.md"
if [ -f "$API_DOC" ]; then
  if grep -q '"abc123' "$API_DOC"; then
    fail "host-ops-api.md still contains placeholder SHA256 'abc123...'"
  else
    pass "host-ops-api.md uses proper SHA256 examples"
  fi
fi

echo ""

# ========================================
# Section 11: Workspace template check (delegated)
# ========================================
echo "--- Section 11: Workspace template check (delegated) ---"
if bash "$REPO_ROOT/scripts/check-workspace-main.sh" >/dev/null 2>&1; then
  pass "check-workspace-main.sh passes on template"
else
  fail "check-workspace-main.sh fails on template"
fi
echo ""

# ========================================
# Section 12: Action inventory validation
# ========================================
echo "--- Section 12: Action inventory ---"

INVENTORY_FILE="$REPO_ROOT/broker/schemas/action-inventory.json"
if [ -f "$INVENTORY_FILE" ]; then
  if jq empty "$INVENTORY_FILE" 2>/dev/null; then
    pass "action-inventory.json is valid JSON"
  else
    fail "action-inventory.json is invalid JSON"
  fi
  inv_count=$(jq '.actions | length' "$INVENTORY_FILE" 2>/dev/null)
  if [ "$inv_count" = "8" ]; then
    pass "action-inventory.json has 8 actions"
  else
    fail "action-inventory.json action count: expected 8, got $inv_count"
  fi
  inv_frozen=$(jq -r '.frozen' "$INVENTORY_FILE" 2>/dev/null)
  if [ "$inv_frozen" = "true" ]; then
    pass "action-inventory.json frozen=true"
  else
    fail "action-inventory.json should have frozen=true"
  fi
else
  fail "action-inventory.json missing"
fi
echo ""

# ========================================
# Section 13: Fixture registry validation
# ========================================
echo "--- Section 13: Fixture registry ---"

REGISTRY_FILE="$REPO_ROOT/examples/broker/fixture-registry.json"
if [ -f "$REGISTRY_FILE" ]; then
  if jq empty "$REGISTRY_FILE" 2>/dev/null; then
    pass "fixture-registry.json is valid JSON"
  else
    fail "fixture-registry.json is invalid JSON"
  fi
  happy_count=$(jq '.happy_path | length' "$REGISTRY_FILE" 2>/dev/null)
  if [ "$happy_count" = "8" ]; then
    pass "fixture-registry.json has 8 happy-path entries"
  else
    fail "fixture-registry.json happy-path count: expected 8, got $happy_count"
  fi
  neg_count=$(jq '.negative | length' "$REGISTRY_FILE" 2>/dev/null)
  if [ "$neg_count" -ge 22 ]; then
    pass "fixture-registry.json has $neg_count negative entries (>=22)"
  else
    fail "fixture-registry.json negative count too low: $neg_count"
  fi
else
  fail "fixture-registry.json missing"
fi
echo ""

# ========================================
# Section 14: Prep entry-gate document
# ========================================
echo "--- Section 14: Prep entry-gate ---"

GATE_DOC="$REPO_ROOT/docs/specs/phase2-repo-prep-gate.md"
if [ -f "$GATE_DOC" ]; then
  pass "phase2-repo-prep-gate.md exists"
  if grep -q "not yet deployed" "$GATE_DOC" || grep -q "has not started" "$GATE_DOC"; then
    pass "Prep gate states broker not yet deployed"
  else
    fail "Prep gate missing 'not yet deployed' statement"
  fi
  if grep -q "Explicitly deferred" "$GATE_DOC"; then
    pass "Prep gate has deferred items section"
  else
    fail "Prep gate missing deferred items section"
  fi
else
  fail "phase2-repo-prep-gate.md missing"
fi
echo ""

# ========================================
# Section 15: Validator parity freeze
# ========================================
echo "--- Section 15: Validator parity freeze ---"

# Verify that common.sh, validate-request.sh, and index.js all enforce the same validation rules
# by checking key function/pattern presence

COMMON_SH_FILE="$REPO_ROOT/broker/wrappers/lib/common.sh"
VALIDATE_SH="$REPO_ROOT/plugins/host-ops-tool/lib/validate-request.sh"
PLUGIN_JS="$REPO_ROOT/plugins/host-ops-tool/index.js"

# SHA256 validation parity
for f in "$COMMON_SH_FILE" "$VALIDATE_SH"; do
  if grep -Fq '[a-f0-9]{64}' "$f" 2>/dev/null; then
    pass "SHA256 regex present: $(basename "$f")"
  else
    fail "SHA256 regex missing: $(basename "$f")"
  fi
done
if grep -Fq '[a-f0-9]{64}' "$PLUGIN_JS" 2>/dev/null; then
  pass "SHA256 regex present: index.js"
else
  fail "SHA256 regex missing: index.js"
fi

# Label validation parity
for f in "$COMMON_SH_FILE" "$VALIDATE_SH"; do
  if grep -q '\[a-zA-Z0-9._-\]' "$f" 2>/dev/null; then
    pass "Label regex present: $(basename "$f")"
  else
    fail "Label regex missing: $(basename "$f")"
  fi
done
if grep -q '\[a-zA-Z0-9._-\]' "$PLUGIN_JS" 2>/dev/null; then
  pass "Label regex present: index.js"
else
  fail "Label regex missing: index.js"
fi

# Path prefix parity
for f in "$COMMON_SH_FILE" "$VALIDATE_SH" "$PLUGIN_JS"; do
  if grep -q '/var/lib/openclaw/approvals/candidates/' "$f" 2>/dev/null; then
    pass "Path prefix present: $(basename "$f")"
  else
    fail "Path prefix missing: $(basename "$f")"
  fi
done

# Path traversal parity
for f in "$COMMON_SH_FILE" "$VALIDATE_SH" "$PLUGIN_JS"; do
  if grep -q '\.\.' "$f" 2>/dev/null; then
    pass "Path traversal check present: $(basename "$f")"
  else
    fail "Path traversal check missing: $(basename "$f")"
  fi
done

# maxLength=128 parity
for f in "$COMMON_SH_FILE" "$VALIDATE_SH" "$PLUGIN_JS"; do
  if grep -q '128' "$f" 2>/dev/null; then
    pass "maxLength=128 check present: $(basename "$f")"
  else
    fail "maxLength=128 check missing: $(basename "$f")"
  fi
done

echo ""

# ========================================
# Summary
# ========================================
echo "=== Summary ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  WARN: $WARN"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL ($FAIL failures)"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo "RESULT: PASS with warnings ($WARN warnings)"
  exit 0
else
  echo "RESULT: PASS (all checks passed)"
  exit 0
fi
