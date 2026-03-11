#!/usr/bin/env bash
set -euo pipefail

# preflight-phase2-broker-deployment.sh
# Purpose: Read-only pre-flight checks before Phase 2 broker deployment
# Safety: NEVER writes to any live or system path. NEVER modifies system state.
#         All checks are based on development repo contents and string matching.
# Exit: 0 = Go (all critical checks passed), non-zero = No-Go

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Counters ---
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# --- Output helpers ---
log_pass() {
    echo "  PASS  $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

log_warn() {
    echo "  WARN  $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

log_fail() {
    echo "  FAIL  $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

usage() {
    cat <<'EOF'
Usage: preflight-phase2-broker-deployment.sh [OPTIONS]

Read-only pre-flight checks for Phase 2 broker deployment.

This script verifies that the development repo artifacts are ready for the
operator to execute the Phase 2 broker deployment. It NEVER accesses, reads,
or writes to any live system path.

OPTIONS:
    -h, --help     Show this help
    -q, --quiet    Only show WARN/FAIL items and summary

WHAT IT CHECKS:
    1. Repository state (git repo, clean worktree)
    2. Required repo files exist (schemas, wrappers, docs, scripts, tests)
    3. Wrapper stub inventory (all 8 stubs + common.sh present)
    4. Schema validation (jq syntax, required fields)
    5. Shell script syntax (bash -n on all .sh files)
    6. Action inventory consistency (8 frozen actions)
    7. Cross-document consistency (protocol spec, layout spec, runbook)
    8. Prep gate satisfaction (validate-phase2-prep.sh passes)
    9. Contract freeze tests pass
    10. No false phase claims (Phase 2 not claimed as started/deployed)

WHAT IT CANNOT CHECK (operator must verify manually at deployment time):
    - Live gateway health
    - Live disk space sufficiency
    - Pre-existing broker installation
    - Root snapshot creation
    - Vault availability
    - Actual sudo access
    - Broker daemon implementation readiness (stubs vs production logic)

OUTPUT:
    PASS   Check passed
    WARN   Non-critical issue (does not block Go)
    FAIL   Critical issue (blocks Go)

EXIT CODES:
    0      Go (zero FAIL, may have WARNs)
    1      No-Go (one or more FAILs)

EXAMPLES:
    # Run full preflight
    bash scripts/preflight-phase2-broker-deployment.sh

    # Run with only warnings/failures shown
    bash scripts/preflight-phase2-broker-deployment.sh --quiet

    # Save output as evidence
    bash scripts/preflight-phase2-broker-deployment.sh 2>&1 | tee /tmp/preflight-phase2-$(date +%Y%m%d-%H%M%S).txt

EOF
    exit 0
}

# --- Parse arguments ---
QUIET=0
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage ;;
        -q|--quiet) QUIET=1; shift ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done

# Override log_pass in quiet mode
if [[ $QUIET -eq 1 ]]; then
    log_pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
fi

echo "================================================================"
echo "  PREFLIGHT: Phase 2 Broker Deployment"
echo "================================================================"
echo ""
echo "Repository: $REPO_ROOT"
echo "Timestamp:  $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo ""

# ============================================================
# Section 1: Repository State
# ============================================================
echo "--- 1. Repository state ---"

if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_pass "Inside a git repository"
else
    log_fail "Not inside a git repository"
fi

CURRENT_BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "")
if [[ -n "$CURRENT_BRANCH" ]]; then
    log_pass "On branch: $CURRENT_BRANCH"
else
    log_warn "Detached HEAD or unable to determine branch"
fi

if git -C "$REPO_ROOT" diff --quiet 2>/dev/null && git -C "$REPO_ROOT" diff --cached --quiet 2>/dev/null; then
    UNTRACKED=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null | head -5)
    if [[ -z "$UNTRACKED" ]]; then
        log_pass "Working tree is clean"
    else
        log_warn "Working tree has untracked files (staged/unstaged are clean)"
    fi
else
    log_fail "Working tree has uncommitted changes"
fi

HEAD_SHORT=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
HEAD_MSG=$(git -C "$REPO_ROOT" log --format='%s' -1 2>/dev/null || echo "unknown")
log_pass "HEAD commit: $HEAD_SHORT ($HEAD_MSG)"

echo ""

# ============================================================
# Section 2: Required Repo Files
# ============================================================
echo "--- 2. Required repo files ---"

REQUIRED_FILES=(
    # Schemas
    "broker/schemas/host-ops-request.schema.json"
    "broker/schemas/host-ops-result.schema.json"
    "broker/schemas/action-inventory.json"
    # Wrapper stubs
    "broker/wrappers/lib/common.sh"
    "broker/wrappers/ocw-gateway-health.sh"
    "broker/wrappers/ocw-gateway-restart.sh"
    "broker/wrappers/ocw-validate-openclaw-json.sh"
    "broker/wrappers/ocw-deploy-openclaw-json.sh"
    "broker/wrappers/ocw-snapshot-pre.sh"
    "broker/wrappers/ocw-snapshot-post.sh"
    "broker/wrappers/ocw-vault-sync.sh"
    "broker/wrappers/ocw-rollback-prepare.sh"
    # Plugin
    "plugins/host-ops-tool/index.js"
    "plugins/host-ops-tool/lib/build-request.sh"
    "plugins/host-ops-tool/lib/validate-request.sh"
    # Docs
    "docs/specs/host-ops-broker-protocol-v1.md"
    "docs/specs/phase2-broker-deployment-layout.md"
    "docs/runbook-phase2-broker-deployment.md"
    "docs/execution-pack-phase2-broker-deployment.md"
    "docs/templates/phase2-broker-deployment-record-template.md"
    "docs/templates/phase2-broker-deployment-syncback-template.md"
    # Validation scripts
    "scripts/validate-phase2-prep.sh"
    "scripts/validate-broker-schemas.sh"
    # Tests
    "tests/test_contract_freeze.sh"
    "tests/test_phase2_integration.sh"
    "tests/test_broker_schemas.sh"
    # Fixtures
    "examples/broker/fixture-registry.json"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$REPO_ROOT/$f" ]]; then
        log_pass "Exists: $f"
    else
        log_fail "Missing: $f"
    fi
done

echo ""

# ============================================================
# Section 3: Wrapper Stub Inventory
# ============================================================
echo "--- 3. Wrapper stub inventory ---"

EXPECTED_WRAPPERS=(
    ocw-gateway-health.sh
    ocw-gateway-restart.sh
    ocw-validate-openclaw-json.sh
    ocw-deploy-openclaw-json.sh
    ocw-snapshot-pre.sh
    ocw-snapshot-post.sh
    ocw-vault-sync.sh
    ocw-rollback-prepare.sh
)

WRAPPER_DIR="$REPO_ROOT/broker/wrappers"
WRAPPER_COUNT=0

for wrapper in "${EXPECTED_WRAPPERS[@]}"; do
    if [[ -f "$WRAPPER_DIR/$wrapper" ]]; then
        WRAPPER_COUNT=$((WRAPPER_COUNT + 1))
        # Check for STUB marker (expected in dev-repo stubs)
        if grep -q '\[STUB\]' "$WRAPPER_DIR/$wrapper" 2>/dev/null; then
            log_pass "Stub wrapper: $wrapper (has [STUB] marker — expected in dev-repo)"
        else
            log_warn "Wrapper $wrapper missing [STUB] marker (may already have production logic)"
        fi
    else
        log_fail "Missing wrapper stub: $wrapper"
    fi
done

if [[ $WRAPPER_COUNT -eq 8 ]]; then
    log_pass "All 8 wrapper stubs present"
else
    log_fail "Expected 8 wrapper stubs, found $WRAPPER_COUNT"
fi

# Check common.sh
if [[ -f "$WRAPPER_DIR/lib/common.sh" ]]; then
    log_pass "Shared library exists: lib/common.sh"
    # Verify BROKER_ACTIONS array
    if grep -q 'BROKER_ACTIONS=' "$WRAPPER_DIR/lib/common.sh" 2>/dev/null; then
        log_pass "common.sh defines BROKER_ACTIONS array"
    else
        log_fail "common.sh missing BROKER_ACTIONS array"
    fi
else
    log_fail "Missing shared library: lib/common.sh"
fi

echo ""

# ============================================================
# Section 4: Schema Validation (jq syntax)
# ============================================================
echo "--- 4. Schema validation ---"

if command -v jq >/dev/null 2>&1; then
    SCHEMA_FILES=(
        "broker/schemas/host-ops-request.schema.json"
        "broker/schemas/host-ops-result.schema.json"
        "broker/schemas/action-inventory.json"
        "examples/broker/fixture-registry.json"
    )

    for sf in "${SCHEMA_FILES[@]}"; do
        if [[ -f "$REPO_ROOT/$sf" ]]; then
            if jq empty "$REPO_ROOT/$sf" 2>/dev/null; then
                log_pass "Valid JSON: $sf"
            else
                log_fail "Invalid JSON: $sf"
            fi
        fi
    done

    # Check per-action schemas
    ACTION_SCHEMA_DIR="$REPO_ROOT/broker/schemas/actions"
    if [[ -d "$ACTION_SCHEMA_DIR" ]]; then
        ACTION_SCHEMA_COUNT=0
        ACTION_SCHEMA_VALID=0
        for schema_file in "$ACTION_SCHEMA_DIR"/*.schema.json; do
            [[ -f "$schema_file" ]] || continue
            ACTION_SCHEMA_COUNT=$((ACTION_SCHEMA_COUNT + 1))
            if jq empty "$schema_file" 2>/dev/null; then
                ACTION_SCHEMA_VALID=$((ACTION_SCHEMA_VALID + 1))
            else
                log_fail "Invalid JSON: $schema_file"
            fi
        done
        if [[ $ACTION_SCHEMA_COUNT -eq 8 ]]; then
            log_pass "All 8 per-action schemas found"
        else
            log_fail "Expected 8 per-action schemas, found $ACTION_SCHEMA_COUNT"
        fi
        if [[ $ACTION_SCHEMA_VALID -eq $ACTION_SCHEMA_COUNT ]]; then
            log_pass "All per-action schemas are valid JSON"
        fi
    else
        log_fail "Per-action schema directory missing: broker/schemas/actions/"
    fi
else
    log_warn "jq not available — skipping JSON validation"
fi

echo ""

# ============================================================
# Section 5: Shell Script Syntax (bash -n)
# ============================================================
echo "--- 5. Shell script syntax ---"

SHELL_FILES=(
    "broker/wrappers/lib/common.sh"
    "broker/wrappers/ocw-gateway-health.sh"
    "broker/wrappers/ocw-gateway-restart.sh"
    "broker/wrappers/ocw-validate-openclaw-json.sh"
    "broker/wrappers/ocw-deploy-openclaw-json.sh"
    "broker/wrappers/ocw-snapshot-pre.sh"
    "broker/wrappers/ocw-snapshot-post.sh"
    "broker/wrappers/ocw-vault-sync.sh"
    "broker/wrappers/ocw-rollback-prepare.sh"
    "plugins/host-ops-tool/lib/build-request.sh"
    "plugins/host-ops-tool/lib/validate-request.sh"
    "scripts/validate-phase2-prep.sh"
    "scripts/validate-broker-schemas.sh"
    "scripts/preflight-phase2-broker-deployment.sh"
    "tests/test_contract_freeze.sh"
    "tests/test_phase2_integration.sh"
    "tests/test_broker_schemas.sh"
)

for sf in "${SHELL_FILES[@]}"; do
    if [[ -f "$REPO_ROOT/$sf" ]]; then
        if bash -n "$REPO_ROOT/$sf" 2>/dev/null; then
            log_pass "bash -n OK: $sf"
        else
            log_fail "bash -n FAIL: $sf"
        fi
    fi
done

echo ""

# ============================================================
# Section 6: Action Inventory Consistency
# ============================================================
echo "--- 6. Action inventory consistency ---"

INVENTORY="$REPO_ROOT/broker/schemas/action-inventory.json"
if [[ -f "$INVENTORY" ]] && command -v jq >/dev/null 2>&1; then
    # Check frozen flag
    FROZEN=$(jq -r '.frozen // false' "$INVENTORY" 2>/dev/null)
    if [[ "$FROZEN" == "true" ]]; then
        log_pass "Action inventory is frozen"
    else
        log_fail "Action inventory is NOT frozen"
    fi

    # Check action count (actions may be array or object)
    ACTION_COUNT=$(jq '.actions | length' "$INVENTORY" 2>/dev/null || echo "0")
    if [[ "$ACTION_COUNT" -eq 8 ]]; then
        log_pass "Action inventory has 8 actions"
    else
        log_fail "Action inventory has $ACTION_COUNT actions (expected 8)"
    fi

    # Check expected actions present (handle both array-of-objects and object formats)
    EXPECTED_ACTIONS=(
        gateway_health
        gateway_restart
        validate_openclaw_json_candidate
        deploy_openclaw_json_candidate
        snapshot_pre
        snapshot_post
        vault_sync
        rollback_prepare
    )

    # Detect format: array or object
    ACTIONS_TYPE=$(jq -r '.actions | type' "$INVENTORY" 2>/dev/null || echo "unknown")

    for action in "${EXPECTED_ACTIONS[@]}"; do
        if [[ "$ACTIONS_TYPE" == "array" ]]; then
            if jq -e ".actions[] | select(.name == \"$action\")" "$INVENTORY" >/dev/null 2>&1; then
                log_pass "Action present: $action"
            else
                log_fail "Action missing from inventory: $action"
            fi
        elif [[ "$ACTIONS_TYPE" == "object" ]]; then
            if jq -e ".actions[\"$action\"]" "$INVENTORY" >/dev/null 2>&1; then
                log_pass "Action present: $action"
            else
                log_fail "Action missing from inventory: $action"
            fi
        else
            log_fail "Unknown actions format in inventory: $ACTIONS_TYPE"
        fi
    done
else
    if [[ ! -f "$INVENTORY" ]]; then
        log_fail "Action inventory file missing"
    else
        log_warn "jq not available — skipping action inventory checks"
    fi
fi

echo ""

# ============================================================
# Section 7: Cross-Document Consistency
# ============================================================
echo "--- 7. Cross-document consistency ---"

# 7.1 Protocol spec references all 8 actions
PROTOCOL="$REPO_ROOT/docs/specs/host-ops-broker-protocol-v1.md"
if [[ -f "$PROTOCOL" ]]; then
    PROTO_ACTIONS_FOUND=0
    for action in gateway_health gateway_restart validate_openclaw_json_candidate deploy_openclaw_json_candidate snapshot_pre snapshot_post vault_sync rollback_prepare; do
        if grep -q "$action" "$PROTOCOL" 2>/dev/null; then
            PROTO_ACTIONS_FOUND=$((PROTO_ACTIONS_FOUND + 1))
        fi
    done
    if [[ $PROTO_ACTIONS_FOUND -eq 8 ]]; then
        log_pass "Protocol spec references all 8 actions"
    else
        log_fail "Protocol spec only references $PROTO_ACTIONS_FOUND/8 actions"
    fi
else
    log_fail "Protocol spec missing"
fi

# 7.2 Deployment layout spec exists and references broker paths
LAYOUT="$REPO_ROOT/docs/specs/phase2-broker-deployment-layout.md"
if [[ -f "$LAYOUT" ]]; then
    log_pass "Deployment layout spec exists"
    if grep -q '/opt/openclaw/broker/' "$LAYOUT" 2>/dev/null; then
        log_pass "Layout spec references /opt/openclaw/broker/"
    else
        log_fail "Layout spec missing /opt/openclaw/broker/ path"
    fi
    if grep -q '/run/openclaw/broker.sock' "$LAYOUT" 2>/dev/null; then
        log_pass "Layout spec references broker socket path"
    else
        log_fail "Layout spec missing broker socket path"
    fi
    if grep -q 'openclaw-broker.service' "$LAYOUT" 2>/dev/null; then
        log_pass "Layout spec references systemd unit"
    else
        log_fail "Layout spec missing systemd unit reference"
    fi
else
    log_fail "Deployment layout spec missing"
fi

# 7.3 Runbook references layout spec and execution pack
RUNBOOK="$REPO_ROOT/docs/runbook-phase2-broker-deployment.md"
if [[ -f "$RUNBOOK" ]]; then
    log_pass "Deployment runbook exists"
    if grep -q 'phase2-broker-deployment-layout.md' "$RUNBOOK" 2>/dev/null; then
        log_pass "Runbook references layout spec"
    else
        log_fail "Runbook missing layout spec reference"
    fi
    if grep -q 'execution-pack-phase2-broker-deployment.md' "$RUNBOOK" 2>/dev/null; then
        log_pass "Runbook references execution pack"
    else
        log_fail "Runbook missing execution pack reference"
    fi
else
    log_fail "Deployment runbook missing"
fi

# 7.4 Execution pack references runbook
EXECPACK="$REPO_ROOT/docs/execution-pack-phase2-broker-deployment.md"
if [[ -f "$EXECPACK" ]]; then
    log_pass "Execution pack exists"
    if grep -q 'runbook-phase2-broker-deployment.md' "$EXECPACK" 2>/dev/null; then
        log_pass "Execution pack references runbook"
    else
        log_fail "Execution pack missing runbook reference"
    fi
else
    log_fail "Execution pack missing"
fi

echo ""

# ============================================================
# Section 8: Prep Gate Satisfaction
# ============================================================
echo "--- 8. Prep gate satisfaction ---"

PREP_SCRIPT="$REPO_ROOT/scripts/validate-phase2-prep.sh"
if [[ -f "$PREP_SCRIPT" ]]; then
    if bash "$PREP_SCRIPT" --quiet >/dev/null 2>&1; then
        log_pass "validate-phase2-prep.sh passes"
    else
        log_fail "validate-phase2-prep.sh fails — prep gate not satisfied"
    fi
else
    log_fail "validate-phase2-prep.sh not found"
fi

echo ""

# ============================================================
# Section 9: Contract Freeze Tests
# ============================================================
echo "--- 9. Contract freeze tests ---"

FREEZE_TEST="$REPO_ROOT/tests/test_contract_freeze.sh"
if [[ -f "$FREEZE_TEST" ]]; then
    if bash "$FREEZE_TEST" >/dev/null 2>&1; then
        log_pass "test_contract_freeze.sh passes"
    else
        log_fail "test_contract_freeze.sh fails — contract freeze broken"
    fi
else
    log_fail "test_contract_freeze.sh not found"
fi

echo ""

# ============================================================
# Section 10: No False Phase Claims
# ============================================================
echo "--- 10. No false phase claims ---"

# 10.1 Deployment docs must NOT claim broker is deployed
for doc in "$LAYOUT" "$RUNBOOK" "$EXECPACK"; do
    docname=$(basename "$doc")
    if [[ -f "$doc" ]]; then
        if grep -qiE 'broker.*deployed|broker.*running|phase 2.*complete|phase 2.*started' "$doc" 2>/dev/null \
           && ! grep -qiE 'NOT yet deployed|NOT.*started|design.*artifact|not.*deployed' "$doc" 2>/dev/null; then
            log_fail "$docname may falsely claim broker is deployed"
        else
            log_pass "$docname does not falsely claim broker is deployed"
        fi
    fi
done

# 10.2 Syncback template must have deployment guard
SYNCBACK="$REPO_ROOT/docs/templates/phase2-broker-deployment-syncback-template.md"
if [[ -f "$SYNCBACK" ]]; then
    if grep -qi 'NOT yet deployed\|NOT.*started\|do not apply.*before' "$SYNCBACK" 2>/dev/null; then
        log_pass "Syncback template has deployment guard language"
    else
        log_warn "Syncback template may lack clear deployment guard"
    fi
else
    log_fail "Syncback template missing"
fi

# 10.3 Record template must have Phase 2 guard
RECORD="$REPO_ROOT/docs/templates/phase2-broker-deployment-record-template.md"
if [[ -f "$RECORD" ]]; then
    if grep -qi 'NOT yet deployed\|NOT.*started' "$RECORD" 2>/dev/null; then
        log_pass "Record template has Phase 2 guard language"
    else
        log_warn "Record template may lack clear Phase 2 guard"
    fi
else
    log_fail "Record template missing"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "================================================================"
echo "  PREFLIGHT SUMMARY"
echo "================================================================"
echo ""
echo "  PASS: $PASS_COUNT"
echo "  WARN: $WARN_COUNT"
echo "  FAIL: $FAIL_COUNT"
echo ""
echo "  Git HEAD: $HEAD_SHORT ($HEAD_MSG)"
echo "  Branch:   ${CURRENT_BRANCH:-(detached)}"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "  +--------------------+"
    echo "  |  RESULT: NO-GO     |"
    echo "  +--------------------+"
    echo ""
    echo "  $FAIL_COUNT critical check(s) failed. Resolve before proceeding."
    echo ""
    echo "  NOTE: This preflight only verifies development repo readiness."
    echo "  The operator must still manually verify at deployment time:"
    echo "    - Live gateway health"
    echo "    - Disk space on target host"
    echo "    - No pre-existing broker installation"
    echo "    - Pre-change root snapshot capability"
    echo "    - Vault availability for post-deployment sync"
    echo "    - Broker daemon implementation readiness (stubs vs production)"
    exit 1
else
    echo "  +--------------------+"
    echo "  |  RESULT: GO        |"
    echo "  +--------------------+"
    echo ""
    if [[ $WARN_COUNT -gt 0 ]]; then
        echo "  $WARN_COUNT warning(s) noted but not blocking."
        echo ""
    fi
    echo "  Development repo artifacts are ready for Phase 2 broker deployment."
    echo ""
    echo "  IMPORTANT: This preflight only verified dev-repo-side readiness."
    echo "  Before executing deployment, the operator MUST still manually verify:"
    echo "    1. Live gateway health (runbook §4.2)"
    echo "    2. Disk space on /opt/openclaw, /var/log/openclaw, /var/lib/openclaw"
    echo "    3. No pre-existing broker installation at /opt/openclaw/broker/"
    echo "    4. No pre-existing openclaw-broker.service systemd unit"
    echo "    5. Pre-change root snapshot creation capability"
    echo "    6. Vault available for post-deployment sync"
    echo "    7. Wrapper stubs have been upgraded to production logic (no [STUB] markers)"
    echo "    8. Broker daemon has been implemented"
    echo "    9. Interactive TTY available for deployment"
    exit 0
fi
