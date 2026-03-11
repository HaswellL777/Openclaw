#!/usr/bin/env bash
# test_contract_freeze.sh — Freeze and verify broker protocol contract edges
#
# Purpose: Prevent accidental drift of schema shapes, enum values, field names,
# and structural invariants. If any frozen contract edge changes, this test fails.
#
# Usage: tests/test_contract_freeze.sh
#
# Dependencies: jq, bash 4+

set -euo pipefail

# Use C locale for deterministic sort order across systems
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; return 0; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; return 0; }

echo "=== Contract Freeze Tests ==="
echo ""

# ========================================
# Frozen: Action enum (exactly 8, exact names)
# ========================================
echo "--- Frozen: Action enum ---"

FROZEN_ACTIONS="deploy_openclaw_json_candidate
gateway_health
gateway_restart
rollback_prepare
snapshot_post
snapshot_pre
validate_openclaw_json_candidate
vault_sync"

REQ_SCHEMA="$REPO_ROOT/broker/schemas/host-ops-request.schema.json"
SCHEMA_ACTIONS=$(jq -r '.properties.action.enum[]' "$REQ_SCHEMA" 2>/dev/null | sort)

if [ "$SCHEMA_ACTIONS" = "$FROZEN_ACTIONS" ]; then
  pass "Request schema action enum is frozen (8 actions)"
else
  fail "Request schema action enum has changed!"
  echo "    Expected: $(echo "$FROZEN_ACTIONS" | tr '\n' ', ')"
  echo "    Got:      $(echo "$SCHEMA_ACTIONS" | tr '\n' ', ')"
fi

# Check action count
SCHEMA_ACTION_COUNT=$(jq '.properties.action.enum | length' "$REQ_SCHEMA" 2>/dev/null)
if [ "$SCHEMA_ACTION_COUNT" = "8" ]; then
  pass "Action enum count frozen at 8"
else
  fail "Action enum count changed: expected 8, got $SCHEMA_ACTION_COUNT"
fi

echo ""

# ========================================
# Frozen: Request envelope required fields
# ========================================
echo "--- Frozen: Request envelope required fields ---"

FROZEN_REQ_FIELDS="action inputs request_id requested_by task_id"
SCHEMA_REQ_FIELDS=$(jq -r '.required[]' "$REQ_SCHEMA" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')

if [ "$SCHEMA_REQ_FIELDS" = "$FROZEN_REQ_FIELDS" ]; then
  pass "Request schema required fields frozen"
else
  fail "Request schema required fields changed!"
  echo "    Expected: $FROZEN_REQ_FIELDS"
  echo "    Got:      $SCHEMA_REQ_FIELDS"
fi

# additionalProperties must be false
REQ_ADDL=$(jq -r '.additionalProperties' "$REQ_SCHEMA" 2>/dev/null)
if [ "$REQ_ADDL" = "false" ]; then
  pass "Request schema additionalProperties=false"
else
  fail "Request schema additionalProperties changed: expected false, got $REQ_ADDL"
fi

echo ""

# ========================================
# Frozen: Result envelope required fields
# ========================================
echo "--- Frozen: Result envelope required fields ---"

RES_SCHEMA="$REPO_ROOT/broker/schemas/host-ops-result.schema.json"
FROZEN_RES_FIELDS="action ok request_id status task_id"
SCHEMA_RES_FIELDS=$(jq -r '.required[]' "$RES_SCHEMA" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')

if [ "$SCHEMA_RES_FIELDS" = "$FROZEN_RES_FIELDS" ]; then
  pass "Result schema required fields frozen"
else
  fail "Result schema required fields changed!"
  echo "    Expected: $FROZEN_RES_FIELDS"
  echo "    Got:      $SCHEMA_RES_FIELDS"
fi

# Status enum must be exactly ok, error, denied
FROZEN_STATUS_ENUM="denied error ok"
SCHEMA_STATUS_ENUM=$(jq -r '.properties.status.enum[]' "$RES_SCHEMA" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')

if [ "$SCHEMA_STATUS_ENUM" = "$FROZEN_STATUS_ENUM" ]; then
  pass "Result schema status enum frozen (ok, error, denied)"
else
  fail "Result schema status enum changed!"
  echo "    Expected: $FROZEN_STATUS_ENUM"
  echo "    Got:      $SCHEMA_STATUS_ENUM"
fi

echo ""

# ========================================
# Frozen: Per-action schema required fields
# ========================================
echo "--- Frozen: Per-action schema required fields ---"

declare -A FROZEN_ACTION_FIELDS
FROZEN_ACTION_FIELDS["gateway-health"]=""
FROZEN_ACTION_FIELDS["gateway-restart"]="reason"
FROZEN_ACTION_FIELDS["validate-openclaw-json"]="candidate_path expected_sha256"
FROZEN_ACTION_FIELDS["deploy-openclaw-json"]="candidate_path expected_sha256"
FROZEN_ACTION_FIELDS["snapshot-pre"]="label reason"
FROZEN_ACTION_FIELDS["snapshot-post"]="label reason"
FROZEN_ACTION_FIELDS["vault-sync"]="snapshot_name"
FROZEN_ACTION_FIELDS["rollback-prepare"]="reason target_snapshot"

for file_stem in gateway-health gateway-restart validate-openclaw-json deploy-openclaw-json \
                  snapshot-pre snapshot-post vault-sync rollback-prepare; do
  schema_file="$REPO_ROOT/broker/schemas/actions/${file_stem}.schema.json"
  expected="${FROZEN_ACTION_FIELDS[$file_stem]}"

  if [ ! -f "$schema_file" ]; then
    fail "Missing per-action schema: ${file_stem}.schema.json"
    continue
  fi

  # Get required fields (may be empty array or absent)
  actual=$(jq -r '(.required // [])[]' "$schema_file" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')

  if [ "$actual" = "$expected" ]; then
    pass "Frozen required fields: ${file_stem} [${expected:-<none>}]"
  else
    fail "Required fields changed: ${file_stem}"
    echo "    Expected: [${expected:-<none>}]"
    echo "    Got:      [${actual:-<none>}]"
  fi

  # All per-action schemas must have type=object
  schema_type=$(jq -r '.type' "$schema_file" 2>/dev/null)
  if [ "$schema_type" = "object" ]; then
    pass "Type frozen as object: ${file_stem}"
  else
    fail "Type changed: ${file_stem} (expected object, got $schema_type)"
  fi

  # All per-action schemas must have additionalProperties=false
  addl=$(jq -r '.additionalProperties' "$schema_file" 2>/dev/null)
  if [ "$addl" = "false" ]; then
    pass "additionalProperties=false: ${file_stem}"
  else
    fail "additionalProperties changed: ${file_stem} (expected false, got $addl)"
  fi
done

echo ""

# ========================================
# Frozen: ok/status consistency invariant
# ========================================
echo "--- Frozen: ok/status invariant in fixtures ---"

# All success result fixtures must have ok=true AND status=ok
for f in "$REPO_ROOT"/examples/broker/*-result.json; do
  basename_f=$(basename "$f")
  # Skip the bad-path-result which is a negative case
  case "$basename_f" in bad-*) continue ;; esac

  ok_val=$(jq -r '.ok' "$f" 2>/dev/null)
  status_val=$(jq -r '.status' "$f" 2>/dev/null)

  if [ "$ok_val" = "true" ] && [ "$status_val" = "ok" ]; then
    pass "ok/status consistent (ok=true,status=ok): $basename_f"
  elif [ "$ok_val" = "false" ] && [ "$status_val" != "ok" ]; then
    pass "ok/status consistent (ok=false,status=$status_val): $basename_f"
  else
    fail "ok/status INCONSISTENT: $basename_f (ok=$ok_val, status=$status_val)"
  fi
done

# All negative result fixtures must have ok=false AND status != ok
for f in "$REPO_ROOT"/examples/broker/negative/*-result.json; do
  basename_f=$(basename "$f")
  ok_val=$(jq -r '.ok' "$f" 2>/dev/null)
  status_val=$(jq -r '.status' "$f" 2>/dev/null)

  if [ "$ok_val" = "false" ] && [ "$status_val" != "ok" ]; then
    pass "ok/status consistent (ok=false,status=$status_val): negative/$basename_f"
  else
    fail "ok/status INCONSISTENT: negative/$basename_f (ok=$ok_val, status=$status_val)"
  fi
done

# Also check the top-level bad-path
BAD_RES="$REPO_ROOT/examples/broker/bad-path-result.json"
if [ -f "$BAD_RES" ]; then
  ok_val=$(jq -r '.ok' "$BAD_RES" 2>/dev/null)
  status_val=$(jq -r '.status' "$BAD_RES" 2>/dev/null)
  if [ "$ok_val" = "false" ] && [ "$status_val" = "denied" ]; then
    pass "ok/status consistent: bad-path-result.json"
  else
    fail "ok/status INCONSISTENT: bad-path-result.json"
  fi
fi

echo ""

# ========================================
# Frozen: Field naming convention (no old names)
# ========================================
echo "--- Frozen: No deprecated field names ---"

DEPRECATED_FIELDS=("operation" "parameters" "approval_id")
CHECKED_FILES=(
  "$REPO_ROOT/broker/schemas/host-ops-request.schema.json"
  "$REPO_ROOT/broker/schemas/host-ops-result.schema.json"
  "$REPO_ROOT/workspace-main-template/control/host-ops-api.md"
  "$REPO_ROOT/workspace-main-template/skills/broker/SKILL.md"
  "$REPO_ROOT/docs/specs/host-ops-broker-protocol-v1.md"
  "$REPO_ROOT/plugins/host-ops-tool/index.js"
)

for dep_field in "${DEPRECATED_FIELDS[@]}"; do
  for file in "${CHECKED_FILES[@]}"; do
    basename_f=$(basename "$file")
    if grep -q "\"$dep_field\"" "$file" 2>/dev/null; then
      fail "Deprecated field '$dep_field' found in $basename_f"
    else
      pass "No '$dep_field' in $basename_f"
    fi
  done
done

echo ""

# ========================================
# Frozen: Action list consistency across layers
# ========================================
echo "--- Frozen: Action list consistency ---"

# Extract action list from multiple sources and compare
SCHEMA_LIST=$(jq -r '.properties.action.enum[]' "$REQ_SCHEMA" 2>/dev/null | sort)

# common.sh
COMMON_SH="$REPO_ROOT/broker/wrappers/lib/common.sh"
COMMON_LIST=$(sed -n '/^readonly BROKER_ACTIONS=/,/^)/p' "$COMMON_SH" 2>/dev/null | grep -oP '^\s+[a-z_]+' | tr -d ' ' | sort)

if [ "$SCHEMA_LIST" = "$COMMON_LIST" ]; then
  pass "Schema ↔ common.sh action lists match"
else
  fail "Schema ↔ common.sh action list mismatch"
fi

# plugin index.js
PLUGIN_LIST=$(grep -oP '"[a-z_]+"' "$REPO_ROOT/plugins/host-ops-tool/index.js" 2>/dev/null | tr -d '"' | sort -u | grep -E '^(gateway_|validate_|deploy_|snapshot_|vault_|rollback_)')

if [ "$SCHEMA_LIST" = "$PLUGIN_LIST" ]; then
  pass "Schema ↔ plugin index.js action lists match"
else
  fail "Schema ↔ plugin index.js action list mismatch"
fi

# build-request.sh
BUILD_LIST=$(sed -n '/^VALID_ACTIONS=/,/^)/p' "$REPO_ROOT/plugins/host-ops-tool/lib/build-request.sh" 2>/dev/null | grep -oP '^\s+[a-z_]+' | tr -d ' ' | sort)

if [ "$SCHEMA_LIST" = "$BUILD_LIST" ]; then
  pass "Schema ↔ build-request.sh action lists match"
else
  fail "Schema ↔ build-request.sh action list mismatch"
fi

# validate-request.sh
VALIDATE_LIST=$(sed -n '/^VALID_ACTIONS=/,/^)/p' "$REPO_ROOT/plugins/host-ops-tool/lib/validate-request.sh" 2>/dev/null | grep -oP '^\s+[a-z_]+' | tr -d ' ' | sort)

if [ "$SCHEMA_LIST" = "$VALIDATE_LIST" ]; then
  pass "Schema ↔ validate-request.sh action lists match"
else
  fail "Schema ↔ validate-request.sh action list mismatch"
fi

echo ""

# ========================================
# Frozen: Negative fixture coverage
# ========================================
echo "--- Frozen: Negative fixture coverage ---"

EXPECTED_NEGATIVE_FIXTURES=(
  "invalid-action"
  "missing-request-id"
  "missing-task-id"
  "path-traversal"
  "bad-sha256"
  "bad-label"
  "missing-reason"
  "missing-candidate-path"
  "wrong-wrapper-action"
)

for case_name in "${EXPECTED_NEGATIVE_FIXTURES[@]}"; do
  req_file="$REPO_ROOT/examples/broker/negative/${case_name}-request.json"
  res_file="$REPO_ROOT/examples/broker/negative/${case_name}-result.json"

  if [ -f "$req_file" ]; then
    if jq empty "$req_file" 2>/dev/null; then
      pass "Negative fixture exists and valid JSON: ${case_name}-request.json"
    else
      fail "Negative fixture invalid JSON: ${case_name}-request.json"
    fi
  else
    fail "Missing negative fixture: ${case_name}-request.json"
  fi

  if [ -f "$res_file" ]; then
    if jq empty "$res_file" 2>/dev/null; then
      pass "Negative fixture exists and valid JSON: ${case_name}-result.json"
    else
      fail "Negative fixture invalid JSON: ${case_name}-result.json"
    fi
    # Every negative result must have ok=false
    neg_ok=$(jq -r '.ok' "$res_file" 2>/dev/null)
    if [ "$neg_ok" = "false" ]; then
      pass "Negative result ok=false: ${case_name}-result.json"
    else
      fail "Negative result should have ok=false: ${case_name}-result.json (got $neg_ok)"
    fi
    # Every negative result must have status error or denied
    neg_status=$(jq -r '.status' "$res_file" 2>/dev/null)
    if [ "$neg_status" = "error" ] || [ "$neg_status" = "denied" ]; then
      pass "Negative result status=$neg_status: ${case_name}-result.json"
    else
      fail "Negative result status should be error or denied: ${case_name}-result.json (got $neg_status)"
    fi
  else
    fail "Missing negative fixture: ${case_name}-result.json"
  fi
done

# Special case: missing-file has no request file (that's the point)
MISSING_FILE_RES="$REPO_ROOT/examples/broker/negative/missing-file-result.json"
if [ -f "$MISSING_FILE_RES" ]; then
  if jq empty "$MISSING_FILE_RES" 2>/dev/null; then
    pass "Missing-file result exists and valid JSON"
  else
    fail "Missing-file result invalid JSON"
  fi
  mf_ok=$(jq -r '.ok' "$MISSING_FILE_RES" 2>/dev/null)
  if [ "$mf_ok" = "false" ]; then
    pass "Missing-file result ok=false"
  else
    fail "Missing-file result should have ok=false"
  fi
else
  fail "Missing negative fixture: missing-file-result.json"
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
