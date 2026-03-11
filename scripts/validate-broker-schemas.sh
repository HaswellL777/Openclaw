#!/usr/bin/env bash
# validate-broker-schemas.sh — Validate broker JSON schemas and example fixtures
#
# Usage: scripts/validate-broker-schemas.sh [--verbose]
#
# Checks:
# 1. All schema files are valid JSON
# 2. All schema files have required $schema field
# 3. All example request fixtures are valid JSON
# 4. All example result fixtures are valid JSON
# 5. Example requests have required fields per host-ops-request.schema.json
# 6. Example results have required fields per host-ops-result.schema.json
# 7. Per-action schemas are valid JSON with required fields
# 8. All 8 actions have corresponding per-action schema
# 9. All 8 actions have corresponding wrapper stub
# 10. All 8 actions have corresponding example request/result pair
#
# Dependencies: jq (required), bash 4+ (required)
# Does NOT require: ajv, jsonschema, or any npm packages

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERBOSE="${1:-}"

PASS=0
FAIL=0
WARN=0

pass() { PASS=$((PASS + 1)); [ "$VERBOSE" = "--verbose" ] && echo "  PASS: $1"; return 0; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; return 0; }
warn() { WARN=$((WARN + 1)); echo "  WARN: $1"; return 0; }

echo "=== Broker Schema Validation ==="
echo ""

# --- Check dependencies ---
if ! command -v jq &>/dev/null; then
  echo "FATAL: jq is required but not installed"
  exit 1
fi

# --- Define expected actions ---
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

# Map action names to file stems
declare -A ACTION_FILE_MAP
ACTION_FILE_MAP["gateway_health"]="gateway-health"
ACTION_FILE_MAP["gateway_restart"]="gateway-restart"
ACTION_FILE_MAP["validate_openclaw_json_candidate"]="validate-openclaw-json"
ACTION_FILE_MAP["deploy_openclaw_json_candidate"]="deploy-openclaw-json"
ACTION_FILE_MAP["snapshot_pre"]="snapshot-pre"
ACTION_FILE_MAP["snapshot_post"]="snapshot-post"
ACTION_FILE_MAP["vault_sync"]="vault-sync"
ACTION_FILE_MAP["rollback_prepare"]="rollback-prepare"

# --- 1. Validate top-level schemas ---
echo "--- Top-level schemas ---"

for schema_file in "$REPO_ROOT/broker/schemas/host-ops-request.schema.json" \
                    "$REPO_ROOT/broker/schemas/host-ops-result.schema.json"; do
  basename_f="$(basename "$schema_file")"
  if [ ! -f "$schema_file" ]; then
    fail "Missing: $basename_f"
    continue
  fi
  if jq empty "$schema_file" 2>/dev/null; then
    pass "Valid JSON: $basename_f"
  else
    fail "Invalid JSON: $basename_f"
    continue
  fi
  if jq -e '."$schema"' "$schema_file" >/dev/null 2>&1; then
    pass "Has \$schema field: $basename_f"
  else
    fail "Missing \$schema field: $basename_f"
  fi
done

# Check request schema has correct action enum
REQ_SCHEMA="$REPO_ROOT/broker/schemas/host-ops-request.schema.json"
SCHEMA_ACTIONS=$(jq -r '.properties.action.enum[]' "$REQ_SCHEMA" 2>/dev/null | sort)
EXPECTED_ACTIONS=$(printf '%s\n' "${ACTIONS[@]}" | sort)
if [ "$SCHEMA_ACTIONS" = "$EXPECTED_ACTIONS" ]; then
  pass "Request schema action enum matches expected 8 actions"
else
  fail "Request schema action enum mismatch"
  echo "    Expected: $EXPECTED_ACTIONS"
  echo "    Got: $SCHEMA_ACTIONS"
fi

# Check required fields in request schema
for field in action request_id task_id requested_by inputs; do
  if jq -e ".required | index(\"$field\")" "$REQ_SCHEMA" >/dev/null 2>&1; then
    pass "Request schema requires: $field"
  else
    fail "Request schema missing required field: $field"
  fi
done

# Check required fields in result schema
RES_SCHEMA="$REPO_ROOT/broker/schemas/host-ops-result.schema.json"
for field in ok action request_id task_id status; do
  if jq -e ".required | index(\"$field\")" "$RES_SCHEMA" >/dev/null 2>&1; then
    pass "Result schema requires: $field"
  else
    fail "Result schema missing required field: $field"
  fi
done

echo ""

# --- 2. Validate per-action schemas ---
echo "--- Per-action input schemas ---"

for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"
  schema_file="$REPO_ROOT/broker/schemas/actions/${file_stem}.schema.json"
  if [ ! -f "$schema_file" ]; then
    fail "Missing per-action schema: ${file_stem}.schema.json"
    continue
  fi
  if jq empty "$schema_file" 2>/dev/null; then
    pass "Valid JSON: actions/${file_stem}.schema.json"
  else
    fail "Invalid JSON: actions/${file_stem}.schema.json"
    continue
  fi
  if jq -e '."$schema"' "$schema_file" >/dev/null 2>&1; then
    pass "Has \$schema field: actions/${file_stem}.schema.json"
  else
    fail "Missing \$schema field: actions/${file_stem}.schema.json"
  fi
  # Check type is object
  SCHEMA_TYPE=$(jq -r '.type' "$schema_file" 2>/dev/null)
  if [ "$SCHEMA_TYPE" = "object" ]; then
    pass "Type is object: actions/${file_stem}.schema.json"
  else
    fail "Type is not object: actions/${file_stem}.schema.json (got: $SCHEMA_TYPE)"
  fi
done

echo ""

# --- 3. Validate wrapper stubs ---
echo "--- Wrapper stubs ---"

for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"
  wrapper="$REPO_ROOT/broker/wrappers/ocw-${file_stem}.sh"
  if [ ! -f "$wrapper" ]; then
    fail "Missing wrapper: ocw-${file_stem}.sh"
    continue
  fi
  pass "Exists: ocw-${file_stem}.sh"
  if [ -x "$wrapper" ]; then
    pass "Executable: ocw-${file_stem}.sh"
  else
    fail "Not executable: ocw-${file_stem}.sh"
  fi
  # Check it starts with shebang
  if head -1 "$wrapper" | grep -q '^#!/usr/bin/env bash'; then
    pass "Has bash shebang: ocw-${file_stem}.sh"
  else
    fail "Missing bash shebang: ocw-${file_stem}.sh"
  fi
  # Check it has set -euo pipefail
  if grep -q 'set -euo pipefail' "$wrapper"; then
    pass "Has strict mode: ocw-${file_stem}.sh"
  else
    warn "Missing strict mode (set -euo pipefail): ocw-${file_stem}.sh"
  fi
  # Check it validates the action name
  if grep -q "\"$action\"" "$wrapper"; then
    pass "Validates action name: ocw-${file_stem}.sh"
  else
    fail "Does not validate action name: ocw-${file_stem}.sh"
  fi
  # Check it has STUB marker
  if grep -q '\[STUB\]' "$wrapper"; then
    pass "Has STUB marker: ocw-${file_stem}.sh"
  else
    warn "Missing STUB marker: ocw-${file_stem}.sh"
  fi
done

echo ""

# --- 4. Validate example fixtures ---
echo "--- Example fixtures ---"

for action in "${ACTIONS[@]}"; do
  file_stem="${ACTION_FILE_MAP[$action]}"

  req_file="$REPO_ROOT/examples/broker/${file_stem}-request.json"
  res_file="$REPO_ROOT/examples/broker/${file_stem}-result.json"

  # Request fixture
  if [ ! -f "$req_file" ]; then
    fail "Missing request fixture: ${file_stem}-request.json"
  else
    if jq empty "$req_file" 2>/dev/null; then
      pass "Valid JSON: ${file_stem}-request.json"
    else
      fail "Invalid JSON: ${file_stem}-request.json"
    fi
    # Check required request fields
    REQ_ACTION=$(jq -r '.action' "$req_file" 2>/dev/null)
    if [ "$REQ_ACTION" = "$action" ]; then
      pass "Correct action in fixture: ${file_stem}-request.json"
    else
      fail "Wrong action in fixture: ${file_stem}-request.json (expected $action, got $REQ_ACTION)"
    fi
    for field in request_id task_id requested_by inputs; do
      if jq -e ".$field" "$req_file" >/dev/null 2>&1; then
        pass "Has $field: ${file_stem}-request.json"
      else
        fail "Missing $field: ${file_stem}-request.json"
      fi
    done
  fi

  # Result fixture
  if [ ! -f "$res_file" ]; then
    fail "Missing result fixture: ${file_stem}-result.json"
  else
    if jq empty "$res_file" 2>/dev/null; then
      pass "Valid JSON: ${file_stem}-result.json"
    else
      fail "Invalid JSON: ${file_stem}-result.json"
    fi
    # Check required result fields
    for field in ok action request_id task_id status; do
      if jq -e ".$field" "$res_file" >/dev/null 2>&1; then
        pass "Has $field: ${file_stem}-result.json"
      else
        fail "Missing $field: ${file_stem}-result.json"
      fi
    done
  fi
done

# Check bad-path example (negative test case)
BAD_REQ="$REPO_ROOT/examples/broker/bad-path-request.json"
BAD_RES="$REPO_ROOT/examples/broker/bad-path-result.json"
if [ -f "$BAD_REQ" ] && [ -f "$BAD_RES" ]; then
  if jq empty "$BAD_REQ" 2>/dev/null && jq empty "$BAD_RES" 2>/dev/null; then
    pass "Valid JSON: bad-path negative test pair"
  else
    fail "Invalid JSON in bad-path negative test pair"
  fi
  BAD_STATUS=$(jq -r '.status' "$BAD_RES" 2>/dev/null)
  BAD_OK=$(jq -r '.ok' "$BAD_RES" 2>/dev/null)
  if [ "$BAD_STATUS" = "denied" ] && [ "$BAD_OK" = "false" ]; then
    pass "Bad-path result correctly shows denied + ok=false"
  else
    fail "Bad-path result should have status=denied, ok=false"
  fi
fi

echo ""

# --- 5. Cross-references ---
echo "--- Cross-references ---"

# Check host-ops-api.md exists in workspace-main-template
API_DOC="$REPO_ROOT/workspace-main-template/control/host-ops-api.md"
if [ -f "$API_DOC" ]; then
  pass "host-ops-api.md exists in workspace-main-template"
  # Check it references the correct field names
  if grep -q '"action"' "$API_DOC"; then
    pass "host-ops-api.md uses 'action' field (matches design-v3.md)"
  else
    fail "host-ops-api.md does not use 'action' field"
  fi
  if grep -q '"inputs"' "$API_DOC"; then
    pass "host-ops-api.md uses 'inputs' field (matches design-v3.md)"
  else
    fail "host-ops-api.md does not use 'inputs' field"
  fi
  if grep -q '"requested_by"' "$API_DOC"; then
    pass "host-ops-api.md uses 'requested_by' field (matches design-v3.md)"
  else
    fail "host-ops-api.md does not use 'requested_by' field"
  fi
  # Negative: should NOT use old field names
  if grep -q '"operation"' "$API_DOC"; then
    fail "host-ops-api.md still uses old 'operation' field (should use 'action')"
  else
    pass "host-ops-api.md no longer uses old 'operation' field"
  fi
  if grep -q '"parameters"' "$API_DOC"; then
    fail "host-ops-api.md still uses old 'parameters' field (should use 'inputs')"
  else
    pass "host-ops-api.md no longer uses old 'parameters' field"
  fi
  if grep -q '"approval_id"' "$API_DOC"; then
    fail "host-ops-api.md still uses old 'approval_id' field (should use 'requested_by')"
  else
    pass "host-ops-api.md no longer uses old 'approval_id' field"
  fi
else
  fail "host-ops-api.md missing from workspace-main-template"
fi

echo ""

# --- Summary ---
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
