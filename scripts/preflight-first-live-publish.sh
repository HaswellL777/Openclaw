#!/usr/bin/env bash
set -euo pipefail

# preflight-first-live-publish.sh
# Purpose: Read-only pre-flight checks before first live scripted publish
# Safety: NEVER writes to any live or system path. NEVER modifies system state.
#         All checks are based on development repo contents and string matching.
# Exit: 0 = Go (all critical checks passed), non-zero = No-Go

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Constants (string references only, never accessed as live paths) ---
EXPECTED_LIVE_TARGET="/var/lib/openclaw/.openclaw/workspace-main"

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
Usage: preflight-first-live-publish.sh [OPTIONS]

Read-only pre-flight checks before first live scripted publish of workspace-main.

This script verifies that the development repo and its artifacts are ready for
the operator to execute the first live publish. It NEVER accesses, reads, or
writes to any live system path.

OPTIONS:
    -h, --help     Show this help
    -q, --quiet    Only show WARN/FAIL items and summary

WHAT IT CHECKS:
    1. Repository state (branch, clean worktree)
    2. Required files exist in dev repo
    3. Template directory completeness
    4. Target path strings match across documents and scripts
    5. Required commands available (bash, rsync, sha256sum, jq, sudo, btrfs)
    6. Cross-document consistency (publish-sop.sh behavior, command references)
    7. Runbook completeness (key steps, commands, and sections present)
    8. No premature "completed" claims for live publish
    9. check-workspace-main.sh passes on template (self-test)

WHAT IT CANNOT CHECK (operator must verify manually):
    - Live gateway health
    - Live workspace-main existence and content
    - openclaw user permissions and path traversal
    - Root snapshot creation
    - Vault availability
    - Actual sudo access for operator
    - TTY availability for interactive confirmation

OUTPUT:
    PASS   Check passed
    WARN   Non-critical issue (does not block Go)
    FAIL   Critical issue (blocks Go)

EXIT CODES:
    0      Go (zero FAIL, may have WARNs)
    1      No-Go (one or more FAILs)

EXAMPLES:
    # Run full preflight
    bash scripts/preflight-first-live-publish.sh

    # Run with only warnings/failures shown
    bash scripts/preflight-first-live-publish.sh --quiet

    # Save output as evidence
    bash scripts/preflight-first-live-publish.sh 2>&1 | tee /tmp/preflight-$(date +%Y%m%d-%H%M%S).txt

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

# Override log_pass in quiet mode to suppress output
if [[ $QUIET -eq 1 ]]; then
    log_pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
fi

echo "================================================================"
echo "  PREFLIGHT: First Live Publish of workspace-main"
echo "================================================================"
echo ""
echo "Repository: $REPO_ROOT"
echo "Timestamp:  $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo ""

# ============================================================
# Section 1: Repository State
# ============================================================
echo "--- 1. Repository state ---"

# 1.1 Check we're in a git repo
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_pass "Inside a git repository"
else
    log_fail "Not inside a git repository"
fi

# 1.2 Check current branch
CURRENT_BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "")
if [[ -n "$CURRENT_BRANCH" ]]; then
    log_pass "On branch: $CURRENT_BRANCH"
else
    log_warn "Detached HEAD or unable to determine branch"
fi

# 1.3 Check working tree is clean
if git -C "$REPO_ROOT" diff --quiet 2>/dev/null && git -C "$REPO_ROOT" diff --cached --quiet 2>/dev/null; then
    UNTRACKED=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null | head -5)
    if [[ -z "$UNTRACKED" ]]; then
        log_pass "Working tree is clean (no staged, unstaged, or untracked changes)"
    else
        log_warn "Working tree has untracked files (staged/unstaged are clean)"
    fi
else
    log_fail "Working tree has uncommitted changes (staged or unstaged)"
fi

# 1.4 Record HEAD commit
HEAD_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")
HEAD_SHORT=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
HEAD_MSG=$(git -C "$REPO_ROOT" log --format='%s' -1 2>/dev/null || echo "unknown")
log_pass "HEAD commit: $HEAD_SHORT ($HEAD_MSG)"

echo ""

# ============================================================
# Section 2: Required Files
# ============================================================
echo "--- 2. Required files ---"

REQUIRED_FILES=(
    "scripts/publish-workspace-main.sh"
    "scripts/publish-sop.sh"
    "scripts/check-workspace-main.sh"
    "scripts/preflight-first-live-publish.sh"
    "docs/host-sop.md"
    "docs/design-v3.md"
    "docs/runbook-first-live-publish.md"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$REPO_ROOT/$f" ]]; then
        log_pass "Exists: $f"
    else
        log_fail "Missing: $f"
    fi
done

# Check scripts are executable (informational; bash <script> still works)
for script in scripts/publish-workspace-main.sh scripts/publish-sop.sh scripts/check-workspace-main.sh; do
    if [[ -x "$REPO_ROOT/$script" ]]; then
        log_pass "Executable: $script"
    else
        log_warn "Not executable: $script (can still run via 'bash $script')"
    fi
done

echo ""

# ============================================================
# Section 3: Template Directory Completeness
# ============================================================
echo "--- 3. Template directory ---"

TEMPLATE_DIR="$REPO_ROOT/workspace-main-template"

if [[ -d "$TEMPLATE_DIR" ]]; then
    log_pass "Template directory exists: workspace-main-template/"
else
    log_fail "Template directory missing: workspace-main-template/"
fi

# Check key template files
TEMPLATE_FILES=(
    "AGENTS.md"
    "IDENTITY.md"
    "SOUL.md"
    "USER.md"
    "HEARTBEAT.md"
    "TOOLS.md"
    "README.md"
    ".gitignore"
    "control/SOP.md"
    "control/routing-policy.md"
    "control/approval-policy.md"
    "control/allowed-workers.md"
    "control/host-ops-api.md"
    "control/state/pending-approvals.json"
    "control/state/last-health.md"
    "control/state/last-sop-hash.txt"
    "control/state/last-task-index.json"
    "control/runbooks/openclaw-config-change.md"
    "control/runbooks/gateway-restart.md"
    "control/runbooks/rollback.md"
    "skills/host-sop/SKILL.md"
    "skills/routing/SKILL.md"
    "skills/approvals/SKILL.md"
    "skills/broker/SKILL.md"
)

for f in "${TEMPLATE_FILES[@]}"; do
    if [[ -f "$TEMPLATE_DIR/$f" ]]; then
        log_pass "Template file: $f"
    else
        log_fail "Template file missing: $f"
    fi
done

# Count template files
if [[ -d "$TEMPLATE_DIR" ]]; then
    TEMPLATE_COUNT=$(find "$TEMPLATE_DIR" -type f 2>/dev/null | wc -l)
    log_pass "Template file count: $TEMPLATE_COUNT"
fi

echo ""

# ============================================================
# Section 4: Target Path String Consistency
# ============================================================
echo "--- 4. Target path consistency (string checks only) ---"

# 4.1 Check that publish script's ALLOWED_LIVE_TARGET matches expected
if grep -q "ALLOWED_LIVE_TARGET=\"$EXPECTED_LIVE_TARGET\"" "$REPO_ROOT/scripts/publish-workspace-main.sh" 2>/dev/null; then
    log_pass "publish-workspace-main.sh ALLOWED_LIVE_TARGET matches: $EXPECTED_LIVE_TARGET"
else
    log_fail "publish-workspace-main.sh ALLOWED_LIVE_TARGET does not match expected: $EXPECTED_LIVE_TARGET"
fi

# 4.2 Check runbook references the same target
if grep -q "$EXPECTED_LIVE_TARGET" "$REPO_ROOT/docs/runbook-first-live-publish.md" 2>/dev/null; then
    log_pass "Runbook references expected live target path"
else
    log_fail "Runbook does not reference expected live target: $EXPECTED_LIVE_TARGET"
fi

# 4.3 Check design-v3 mentions the live target
if grep -q "$EXPECTED_LIVE_TARGET" "$REPO_ROOT/docs/design-v3.md" 2>/dev/null; then
    log_pass "design-v3.md references expected live target path"
else
    log_warn "design-v3.md does not explicitly reference live target path"
fi

# 4.4 Check host-sop.md mentions the live target
if grep -q "$EXPECTED_LIVE_TARGET" "$REPO_ROOT/docs/host-sop.md" 2>/dev/null; then
    log_pass "host-sop.md references expected live target path"
else
    log_warn "host-sop.md does not explicitly reference live target path"
fi

echo ""

# ============================================================
# Section 5: Required Commands
# ============================================================
echo "--- 5. Required commands ---"

REQUIRED_COMMANDS=(bash rsync sha256sum jq sudo btrfs git)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        log_pass "Command available: $cmd"
    else
        log_fail "Command not found: $cmd"
    fi
done

echo ""

# ============================================================
# Section 6: Cross-Document Consistency
# ============================================================
echo "--- 6. Cross-document consistency ---"

# 6.1 Check that publish-sop.sh does NOT have --allow-live-target as a usable flag
# (it should unconditionally refuse live paths; live SOP is handled inline by parent)
if grep -q -- '--allow-live-target)' "$REPO_ROOT/scripts/publish-sop.sh" 2>/dev/null; then
    log_warn "publish-sop.sh has --allow-live-target argument handler (expected: unconditional refusal)"
else
    log_pass "publish-sop.sh has no --allow-live-target flag (unconditionally refuses live paths)"
fi

# 6.2 Check that publish-workspace-main.sh handles live SOP inline
if grep -q "inline SOP publish" "$REPO_ROOT/scripts/publish-workspace-main.sh" 2>/dev/null; then
    log_pass "publish-workspace-main.sh handles live SOP publish inline"
else
    log_warn "Cannot confirm publish-workspace-main.sh handles live SOP inline"
fi

# 6.3 Check that runbook publish command matches expected format
if grep -q "publish-workspace-main.sh.*--apply.*--allow-live-target" "$REPO_ROOT/docs/runbook-first-live-publish.md" 2>/dev/null; then
    log_pass "Runbook publish command includes --apply --allow-live-target"
else
    log_fail "Runbook publish command missing expected flags"
fi

# 6.4 Check that runbook has check command
if grep -q "check-workspace-main.sh" "$REPO_ROOT/docs/runbook-first-live-publish.md" 2>/dev/null; then
    log_pass "Runbook references check-workspace-main.sh"
else
    log_fail "Runbook does not reference check-workspace-main.sh"
fi

# 6.5 Check that runbook has snapshot step
if grep -q "btrfs subvolume snapshot" "$REPO_ROOT/docs/runbook-first-live-publish.md" 2>/dev/null; then
    log_pass "Runbook has btrfs snapshot command"
else
    log_fail "Runbook missing btrfs snapshot command"
fi

# 6.6 Check that runbook has Vault sync step
if grep -q "vault-backup-root-btrfs" "$REPO_ROOT/docs/runbook-first-live-publish.md" 2>/dev/null; then
    log_pass "Runbook has Vault backup command"
else
    log_fail "Runbook missing Vault backup command"
fi

# 6.7 Check check script validates core template files
if grep -q "AGENTS.md" "$REPO_ROOT/scripts/check-workspace-main.sh" 2>/dev/null &&
   grep -q "IDENTITY.md" "$REPO_ROOT/scripts/check-workspace-main.sh" 2>/dev/null &&
   grep -q "SOUL.md" "$REPO_ROOT/scripts/check-workspace-main.sh" 2>/dev/null; then
    log_pass "check-workspace-main.sh verifies core template files"
else
    log_warn "check-workspace-main.sh may not verify all expected core files"
fi

echo ""

# ============================================================
# Section 7: Runbook Completeness
# ============================================================
echo "--- 7. Runbook completeness ---"

RUNBOOK="$REPO_ROOT/docs/runbook-first-live-publish.md"

# 7.1 Runbook has pre-check section
if grep -qE "前置检查|Pre-check" "$RUNBOOK" 2>/dev/null; then
    log_pass "Runbook has pre-check section"
else
    log_fail "Runbook missing pre-check section"
fi

# 7.2 Runbook has gateway health check
if grep -qE "gateway.*health|health.*check" "$RUNBOOK" 2>/dev/null; then
    log_pass "Runbook includes gateway health check"
else
    log_fail "Runbook missing gateway health check"
fi

# 7.3 Runbook has post-publish verification section
if grep -qE "发布后校验|Post.*publish" "$RUNBOOK" 2>/dev/null; then
    log_pass "Runbook has post-publish verification section"
else
    log_fail "Runbook missing post-publish verification section"
fi

# 7.4 Runbook has rollback/failure section
if grep -qE "失败回退|Rollback|failure" "$RUNBOOK" 2>/dev/null; then
    log_pass "Runbook has failure/rollback section"
else
    log_fail "Runbook missing failure/rollback section"
fi

# 7.5 Runbook marked as "待执行" (not completed)
if grep -q "待执行" "$RUNBOOK" 2>/dev/null; then
    log_pass "Runbook correctly marked as pending (待执行)"
else
    log_warn "Runbook may not be clearly marked as pending execution"
fi

# 7.6 Runbook has evidence collection guidance
if grep -qE "证据|evidence" "$RUNBOOK" 2>/dev/null; then
    log_pass "Runbook has evidence collection guidance"
else
    log_warn "Runbook may lack explicit evidence collection guidance"
fi

# 7.7 Runbook has go/no-go checklist
if grep -qE "Go.*No-Go|go/no-go|决策检查表" "$RUNBOOK" 2>/dev/null; then
    log_pass "Runbook has Go/No-Go checklist"
else
    log_warn "Runbook may lack explicit Go/No-Go checklist"
fi

echo ""

# ============================================================
# Section 8: No Premature Completion Claims
# ============================================================
echo "--- 8. No premature completion claims ---"

# 8.1 Check that runbook doesn't claim publish is done
if grep -qE "发布已完成|已成功发布|publish.*completed|已执行完毕" "$RUNBOOK" 2>/dev/null; then
    log_fail "Runbook appears to claim publish is already completed"
else
    log_pass "Runbook does not claim publish is completed"
fi

# 8.2 Check design-v3 Phase 1B still marks live publish as pending
if grep -q "⬚ 待执行" "$REPO_ROOT/docs/design-v3.md" 2>/dev/null; then
    log_pass "design-v3.md still marks live publish as pending (⬚ 待执行)"
else
    log_warn "Cannot confirm design-v3 live publish status marker"
fi

# 8.3 Check host-sop.md doesn't claim first scripted publish is done
# Use grep -v to exclude lines with negation (e.g. "均未将现网发布写为已完成")
if grep -E "首次现网.*已完成|首次脚本化发布已执行" "$REPO_ROOT/docs/host-sop.md" 2>/dev/null \
   | grep -vE "未将.*已完成|不.*已完成|未.*写为已完成" \
   | grep -q .; then
    log_fail "host-sop.md appears to claim first live publish is completed"
else
    log_pass "host-sop.md does not claim first live publish is completed"
fi

echo ""

# ============================================================
# Section 9: check-workspace-main.sh self-test on template
# ============================================================
echo "--- 9. Template self-check (check-workspace-main.sh on template) ---"

if [[ -f "$REPO_ROOT/scripts/check-workspace-main.sh" ]] && [[ -d "$TEMPLATE_DIR" ]]; then
    CHECK_OUTPUT=$(bash "$REPO_ROOT/scripts/check-workspace-main.sh" "$TEMPLATE_DIR" 2>&1) || true
    if echo "$CHECK_OUTPUT" | grep -q "All checks passed"; then
        log_pass "check-workspace-main.sh passes on workspace-main-template (template mode)"
    else
        TEMPLATE_FAILURES=$(echo "$CHECK_OUTPUT" | grep -c "✗" || true)
        if [[ "$TEMPLATE_FAILURES" -gt 0 ]]; then
            log_fail "check-workspace-main.sh has $TEMPLATE_FAILURES failure(s) on template"
        else
            log_warn "check-workspace-main.sh did not clearly pass on template"
        fi
    fi
else
    log_fail "Cannot run template self-check (script or template missing)"
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
    echo "  The operator must still manually verify:"
    echo "    - Live gateway health"
    echo "    - Live workspace-main existence"
    echo "    - openclaw user path permissions"
    echo "    - Pre-change root snapshot"
    echo "    - Vault availability"
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
    echo "  Development repo is ready for first live publish."
    echo ""
    echo "  IMPORTANT: This preflight only verified dev-repo-side readiness."
    echo "  Before executing, the operator MUST still manually verify:"
    echo "    1. Live gateway health (runbook S1.2)"
    echo "    2. Live workspace-main exists (runbook S1.3)"
    echo "    3. openclaw user can read dev repo paths (runbook S1.5)"
    echo "    4. Pre-change root snapshot created (runbook S2)"
    echo "    5. Vault is available for post-change sync (runbook S5)"
    echo "    6. Interactive TTY is available for confirmation prompt"
    exit 0
fi
