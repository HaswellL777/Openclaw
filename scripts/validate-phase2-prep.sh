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

# Check no live socket references
if grep -qiE '(connect|socket|ws://|http://|localhost|127\.0\.0\.1)' "$PLUGIN_DIR/index.js"; then
  fail "index.js appears to reference live connections"
else
  pass "index.js has no live connection references"
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
for action in gateway_health gateway_restart; do
  TMPFILE=$(mktemp)
  case "$action" in
    gateway_health)
      bash "$PLUGIN_DIR/lib/build-request.sh" "$action" > "$TMPFILE" 2>/dev/null
      ;;
    gateway_restart)
      bash "$PLUGIN_DIR/lib/build-request.sh" "$action" "reason=test" > "$TMPFILE" 2>/dev/null
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
FIXTURE_REQ_COUNT=$(find "$FIXTURES_DIR" -name '*-request.json' -not -name 'bad-*' -type f 2>/dev/null | wc -l)
FIXTURE_RES_COUNT=$(find "$FIXTURES_DIR" -name '*-result.json' -not -name 'bad-*' -type f 2>/dev/null | wc -l)
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
# Section 7: Workspace template check
# ========================================
echo "--- Section 7: Workspace template check (delegated) ---"
if bash "$REPO_ROOT/scripts/check-workspace-main.sh" >/dev/null 2>&1; then
  pass "check-workspace-main.sh passes on template"
else
  fail "check-workspace-main.sh fails on template"
fi
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
