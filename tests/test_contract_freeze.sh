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

# additionalProperties must be false
RES_ADDL=$(jq -r '.additionalProperties' "$RES_SCHEMA" 2>/dev/null)
if [ "$RES_ADDL" = "false" ]; then
  pass "Result schema additionalProperties=false"
else
  fail "Result schema additionalProperties changed: expected false, got $RES_ADDL"
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
# Frozen: Per-action schema property types
# ========================================
echo "--- Frozen: Per-action schema property types ---"

# Freeze the type of every property in each per-action schema
declare -A FROZEN_PROP_TYPES
FROZEN_PROP_TYPES["gateway-restart:reason"]="string"
FROZEN_PROP_TYPES["validate-openclaw-json:candidate_path"]="string"
FROZEN_PROP_TYPES["validate-openclaw-json:expected_sha256"]="string"
FROZEN_PROP_TYPES["deploy-openclaw-json:candidate_path"]="string"
FROZEN_PROP_TYPES["deploy-openclaw-json:expected_sha256"]="string"
FROZEN_PROP_TYPES["snapshot-pre:label"]="string"
FROZEN_PROP_TYPES["snapshot-pre:reason"]="string"
FROZEN_PROP_TYPES["snapshot-post:label"]="string"
FROZEN_PROP_TYPES["snapshot-post:reason"]="string"
FROZEN_PROP_TYPES["vault-sync:snapshot_name"]="string"
FROZEN_PROP_TYPES["vault-sync:incremental"]="boolean"
FROZEN_PROP_TYPES["rollback-prepare:target_snapshot"]="string"
FROZEN_PROP_TYPES["rollback-prepare:reason"]="string"

for key in $(echo "${!FROZEN_PROP_TYPES[@]}" | tr ' ' '\n' | sort); do
  schema_stem="${key%%:*}"
  prop_name="${key#*:}"
  expected_type="${FROZEN_PROP_TYPES[$key]}"
  schema_file="$REPO_ROOT/broker/schemas/actions/${schema_stem}.schema.json"
  actual_type=$(jq -r ".properties.${prop_name}.type" "$schema_file" 2>/dev/null)
  if [ "$actual_type" = "$expected_type" ]; then
    pass "Property type frozen: ${schema_stem}.${prop_name} = ${expected_type}"
  else
    fail "Property type changed: ${schema_stem}.${prop_name} (expected ${expected_type}, got ${actual_type})"
  fi
done

# Freeze maxLength constraint on label-like fields
for schema_stem in snapshot-pre snapshot-post vault-sync rollback-prepare; do
  schema_file="$REPO_ROOT/broker/schemas/actions/${schema_stem}.schema.json"
  # Get first required field that has maxLength
  for prop in label snapshot_name target_snapshot; do
    max_len=$(jq -r ".properties.${prop}.maxLength // empty" "$schema_file" 2>/dev/null)
    if [ -n "$max_len" ]; then
      if [ "$max_len" = "128" ]; then
        pass "maxLength=128 frozen: ${schema_stem}.${prop}"
      else
        fail "maxLength changed: ${schema_stem}.${prop} (expected 128, got ${max_len})"
      fi
    fi
  done
done

echo ""

# ========================================
# Frozen: Result envelope property types
# ========================================
echo "--- Frozen: Result envelope property types ---"

RES_SCHEMA="$REPO_ROOT/broker/schemas/host-ops-result.schema.json"

declare -A FROZEN_RES_PROP_TYPES
FROZEN_RES_PROP_TYPES["ok"]="boolean"
FROZEN_RES_PROP_TYPES["action"]="string"
FROZEN_RES_PROP_TYPES["request_id"]="string"
FROZEN_RES_PROP_TYPES["task_id"]="string"
FROZEN_RES_PROP_TYPES["status"]="string"
FROZEN_RES_PROP_TYPES["message"]="string"
FROZEN_RES_PROP_TYPES["artifacts"]="object"
FROZEN_RES_PROP_TYPES["rollback_hint"]="string"
FROZEN_RES_PROP_TYPES["error_code"]="string"

for prop in $(echo "${!FROZEN_RES_PROP_TYPES[@]}" | tr ' ' '\n' | sort); do
  expected_type="${FROZEN_RES_PROP_TYPES[$prop]}"
  actual_type=$(jq -r ".properties.${prop}.type" "$RES_SCHEMA" 2>/dev/null)
  if [ "$actual_type" = "$expected_type" ]; then
    pass "Result property type frozen: ${prop} = ${expected_type}"
  else
    fail "Result property type changed: ${prop} (expected ${expected_type}, got ${actual_type})"
  fi
done

# Freeze minLength on required string fields
for prop in action request_id task_id; do
  min_len=$(jq -r ".properties.${prop}.minLength // empty" "$RES_SCHEMA" 2>/dev/null)
  if [ "$min_len" = "1" ]; then
    pass "Result minLength=1 frozen: ${prop}"
  else
    fail "Result minLength changed: ${prop} (expected 1, got ${min_len:-<none>})"
  fi
done

# Freeze reserved error_code field
ERROR_CODE_TYPE=$(jq -r '.properties.error_code.type' "$RES_SCHEMA" 2>/dev/null)
if [ "$ERROR_CODE_TYPE" = "string" ]; then
  pass "Reserved error_code field exists (type=string)"
else
  fail "Reserved error_code field missing or wrong type (expected string, got $ERROR_CODE_TYPE)"
fi

# Freeze ok/status invariant enforcement (if/then/else)
INVARIANT_IF=$(jq -r '.if.properties.ok.const' "$RES_SCHEMA" 2>/dev/null)
INVARIANT_THEN=$(jq -r '.then.properties.status.const' "$RES_SCHEMA" 2>/dev/null)
if [ "$INVARIANT_IF" = "true" ] && [ "$INVARIANT_THEN" = "ok" ]; then
  pass "ok/status invariant schema-enforced (if ok=true then status=ok)"
else
  fail "ok/status invariant not schema-enforced"
fi

echo ""

# ========================================
# Frozen: Wrapper stub existence
# ========================================
echo "--- Frozen: Wrapper stub existence ---"

FROZEN_WRAPPERS=(
  "ocw-gateway-health.sh"
  "ocw-gateway-restart.sh"
  "ocw-validate-openclaw-json.sh"
  "ocw-deploy-openclaw-json.sh"
  "ocw-snapshot-pre.sh"
  "ocw-snapshot-post.sh"
  "ocw-vault-sync.sh"
  "ocw-rollback-prepare.sh"
)

for wrapper in "${FROZEN_WRAPPERS[@]}"; do
  if [ -f "$REPO_ROOT/broker/wrappers/$wrapper" ]; then
    pass "Wrapper exists: $wrapper"
  else
    fail "Missing wrapper: $wrapper"
  fi
done

WRAPPER_COUNT=$(find "$REPO_ROOT/broker/wrappers" -maxdepth 1 -name 'ocw-*.sh' -type f | wc -l)
if [ "$WRAPPER_COUNT" -eq 8 ]; then
  pass "Wrapper count frozen at 8"
else
  fail "Wrapper count changed: expected 8, got $WRAPPER_COUNT"
fi

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
  # Skip ok-status-mismatch which is an intentional invariant violation demo
  case "$basename_f" in ok-status-mismatch-*) continue ;; esac
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
# Frozen: No deprecated field names in fixtures
# ========================================
echo "--- Frozen: No deprecated field names in fixtures ---"

for dep_field in "${DEPRECATED_FIELDS[@]}"; do
  for f in "$REPO_ROOT"/examples/broker/*-request.json "$REPO_ROOT"/examples/broker/*-result.json; do
    basename_f=$(basename "$f")
    if grep -q "\"$dep_field\"" "$f" 2>/dev/null; then
      fail "Deprecated field '$dep_field' in fixture: $basename_f"
    fi
  done
  for f in "$REPO_ROOT"/examples/broker/negative/*-request.json "$REPO_ROOT"/examples/broker/negative/*-result.json; do
    basename_f=$(basename "$f")
    if grep -q "\"$dep_field\"" "$f" 2>/dev/null; then
      fail "Deprecated field '$dep_field' in negative fixture: $basename_f"
    fi
  done
  pass "No '$dep_field' in any fixtures"
done

echo ""

# ========================================
# Frozen: Action inventory single-source file
# ========================================
echo "--- Frozen: Action inventory file ---"

INVENTORY_FILE="$REPO_ROOT/broker/schemas/action-inventory.json"
if [ -f "$INVENTORY_FILE" ]; then
  if jq empty "$INVENTORY_FILE" 2>/dev/null; then
    pass "action-inventory.json is valid JSON"
  else
    fail "action-inventory.json is invalid JSON"
  fi

  # Verify frozen flag
  inv_frozen=$(jq -r '.frozen' "$INVENTORY_FILE" 2>/dev/null)
  if [ "$inv_frozen" = "true" ]; then
    pass "action-inventory.json has frozen=true"
  else
    fail "action-inventory.json should have frozen=true"
  fi

  # Verify action count matches
  inv_count=$(jq '.actions | length' "$INVENTORY_FILE" 2>/dev/null)
  if [ "$inv_count" = "8" ]; then
    pass "action-inventory.json has 8 actions"
  else
    fail "action-inventory.json action count: expected 8, got $inv_count"
  fi

  # Verify action names match schema enum
  INV_ACTIONS=$(jq -r '.actions[].name' "$INVENTORY_FILE" 2>/dev/null | sort)
  if [ "$INV_ACTIONS" = "$FROZEN_ACTIONS" ]; then
    pass "action-inventory.json names match frozen enum"
  else
    fail "action-inventory.json names do not match frozen enum"
  fi

  # Verify each action has schema, wrapper, fixture
  for action_name in $(jq -r '.actions[].name' "$INVENTORY_FILE" 2>/dev/null); do
    schema_ref=$(jq -r --arg a "$action_name" '.actions[] | select(.name==$a) | .schema' "$INVENTORY_FILE" 2>/dev/null)
    wrapper_ref=$(jq -r --arg a "$action_name" '.actions[] | select(.name==$a) | .wrapper' "$INVENTORY_FILE" 2>/dev/null)
    fixture_ref=$(jq -r --arg a "$action_name" '.actions[] | select(.name==$a) | .fixture' "$INVENTORY_FILE" 2>/dev/null)

    if [ -f "$REPO_ROOT/broker/schemas/$schema_ref" ]; then
      pass "Inventory schema exists: $schema_ref"
    else
      fail "Inventory schema missing: $schema_ref"
    fi

    if [ -f "$REPO_ROOT/broker/wrappers/$wrapper_ref" ]; then
      pass "Inventory wrapper exists: $wrapper_ref"
    else
      fail "Inventory wrapper missing: $wrapper_ref"
    fi

    if [ -f "$REPO_ROOT/examples/broker/${fixture_ref}-request.json" ]; then
      pass "Inventory fixture exists: ${fixture_ref}-request.json"
    else
      fail "Inventory fixture missing: ${fixture_ref}-request.json"
    fi
  done
else
  fail "action-inventory.json missing"
fi

echo ""

# ========================================
# Frozen: Fixture registry consistency
# ========================================
echo "--- Frozen: Fixture registry ---"

REGISTRY_FILE="$REPO_ROOT/examples/broker/fixture-registry.json"
if [ -f "$REGISTRY_FILE" ]; then
  if jq empty "$REGISTRY_FILE" 2>/dev/null; then
    pass "fixture-registry.json is valid JSON"
  else
    fail "fixture-registry.json is invalid JSON"
  fi

  # All happy-path stems must have files on disk
  for stem in $(jq -r '.happy_path[].stem' "$REGISTRY_FILE" 2>/dev/null); do
    if [ -f "$REPO_ROOT/examples/broker/${stem}-request.json" ] && [ -f "$REPO_ROOT/examples/broker/${stem}-result.json" ]; then
      pass "Registry happy-path on disk: $stem"
    else
      fail "Registry happy-path missing on disk: $stem"
    fi
  done

  # All negative stems with has_request=true must have request file
  for entry in $(jq -r '.negative[] | select(.has_request==true) | .stem' "$REGISTRY_FILE" 2>/dev/null); do
    if [ -f "$REPO_ROOT/examples/broker/negative/${entry}-request.json" ]; then
      pass "Registry negative on disk: ${entry}-request.json"
    else
      fail "Registry negative missing: ${entry}-request.json"
    fi
    if [ -f "$REPO_ROOT/examples/broker/negative/${entry}-result.json" ]; then
      pass "Registry negative on disk: ${entry}-result.json"
    else
      fail "Registry negative missing: ${entry}-result.json"
    fi
  done

  # Negative stems with has_request=false should only have result file
  for entry in $(jq -r '.negative[] | select(.has_request==false) | .stem' "$REGISTRY_FILE" 2>/dev/null); do
    if [ -f "$REPO_ROOT/examples/broker/negative/${entry}-result.json" ]; then
      pass "Registry result-only on disk: ${entry}-result.json"
    else
      fail "Registry result-only missing: ${entry}-result.json"
    fi
  done
else
  fail "fixture-registry.json missing"
fi

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

# Special case: ok-status-mismatch is result-only (demonstrates invariant violation)
MISMATCH_RES="$REPO_ROOT/examples/broker/negative/ok-status-mismatch-result.json"
if [ -f "$MISMATCH_RES" ]; then
  if jq empty "$MISMATCH_RES" 2>/dev/null; then
    pass "ok-status-mismatch result exists and valid JSON"
  else
    fail "ok-status-mismatch result invalid JSON"
  fi
  # This fixture intentionally has ok=true + status=error (the violation)
  mm_ok=$(jq -r '.ok' "$MISMATCH_RES" 2>/dev/null)
  mm_status=$(jq -r '.status' "$MISMATCH_RES" 2>/dev/null)
  if [ "$mm_ok" = "true" ] && [ "$mm_status" != "ok" ]; then
    pass "ok-status-mismatch demonstrates invariant violation (ok=true, status=$mm_status)"
  else
    fail "ok-status-mismatch fixture not shaped as expected"
  fi
else
  fail "Missing negative fixture: ok-status-mismatch-result.json"
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
