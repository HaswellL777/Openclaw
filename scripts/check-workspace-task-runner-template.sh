#!/usr/bin/env bash
set -euo pipefail

# check-workspace-task-runner-template.sh
# Purpose: Validate workspace-task-runner template structure and constraints
# Usage: check-workspace-task-runner-template.sh [TARGET_DIR]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="${1:-$REPO_ROOT/workspace-task-runner-template}"

usage() {
    cat <<EOF
Usage: $0 [TARGET_DIR]

Validate workspace-task-runner template structure and constraints.

ARGUMENTS:
    TARGET_DIR    Directory to check (default: workspace-task-runner-template in repo)

CHECKS:
    - Required core files exist
    - Required control files exist
    - Required tasks/ directory exists
    - Basic content checks for AGENTS.md, TOOLS.md, and control docs
    - No obvious embedded secrets

EXIT CODES:
    0    All checks passed
    1    One or more checks failed
EOF
    exit 0
}

if [[ "${TARGET_DIR}" == "--help" ]] || [[ "${TARGET_DIR}" == "-h" ]]; then
    usage
fi

if [[ ! -d "${TARGET_DIR}" ]]; then
    echo "Error: target directory not found: ${TARGET_DIR}" >&2
    exit 1
fi

echo "=== Checking workspace-task-runner template: ${TARGET_DIR} ==="
echo ""

FAILED=0

check_exists() {
    local path="$1"
    local type="$2"
    local full_path="${TARGET_DIR}/${path}"

    if [[ "${type}" == "file" ]]; then
        if [[ -f "${full_path}" ]]; then
            echo "✓ File exists: ${path}"
        else
            echo "✗ File missing: ${path}"
            FAILED=1
        fi
    elif [[ "${type}" == "directory" ]]; then
        if [[ -d "${full_path}" ]]; then
            echo "✓ Directory exists: ${path}"
        else
            echo "✗ Directory missing: ${path}"
            FAILED=1
        fi
    fi
}

echo "--- Core files ---"
check_exists "AGENTS.md" "file"
check_exists "TOOLS.md" "file"
echo ""

echo "--- Control files ---"
check_exists "control" "directory"
check_exists "control/runner-policy.md" "file"
check_exists "control/artifact-contract.md" "file"
echo ""

echo "--- Task root ---"
check_exists "tasks" "directory"
check_exists "tasks/.gitkeep" "file"
echo ""

echo "--- Content checks ---"
if grep -q "task-runner" "${TARGET_DIR}/AGENTS.md" 2>/dev/null; then
    echo "✓ AGENTS.md mentions task-runner"
else
    echo "✗ AGENTS.md does not mention task-runner"
    FAILED=1
fi

if grep -q "outputs/host-change-request.json" "${TARGET_DIR}/AGENTS.md" 2>/dev/null; then
    echo "✓ AGENTS.md mentions host-change-request output"
else
    echo "✗ AGENTS.md missing host-change-request output"
    FAILED=1
fi

if grep -q "control/runner-policy.md" "${TARGET_DIR}/TOOLS.md" 2>/dev/null && grep -q "control/artifact-contract.md" "${TARGET_DIR}/TOOLS.md" 2>/dev/null; then
    echo "✓ TOOLS.md references control policy files"
else
    echo "✗ TOOLS.md missing control policy references"
    FAILED=1
fi

if grep -q "main -> broker" "${TARGET_DIR}/control/artifact-contract.md" 2>/dev/null; then
    echo "✓ artifact-contract.md references future main -> broker handoff"
else
    echo "✗ artifact-contract.md missing future main -> broker handoff"
    FAILED=1
fi

if grep -q "repo-side template" "${TARGET_DIR}/control/runner-policy.md" 2>/dev/null || grep -q "repo-side policy" "${TARGET_DIR}/control/runner-policy.md" 2>/dev/null; then
    echo "✓ runner-policy.md states repo-side scope"
else
    echo "✗ runner-policy.md missing repo-side scope note"
    FAILED=1
fi
echo ""

echo "--- Prohibited content checks ---"
PROHIBITED_PATTERNS=(
    "sk-[a-zA-Z0-9]{20,}"
    "xoxb-[a-zA-Z0-9]{20,}"
    "ghp_[a-zA-Z0-9]{20,}"
    "AKIA[A-Z0-9]{16}"
    "-----BEGIN.*PRIVATE KEY"
)

FOUND_SECRETS=0
for pattern in "${PROHIBITED_PATTERNS[@]}"; do
    matches=$(grep -r -E "${pattern}" "${TARGET_DIR}" 2>/dev/null | grep -v ".git" || true)
    if [[ -n "${matches}" ]]; then
        echo "✗ Found potential secret matching pattern: ${pattern}"
        echo "  ${matches}"
        FOUND_SECRETS=1
        FAILED=1
    fi
done

if [[ ${FOUND_SECRETS} -eq 0 ]]; then
    echo "✓ No obvious secrets found"
fi
echo ""

echo "=== CHECK SUMMARY ==="
if [[ ${FAILED} -eq 0 ]]; then
    echo "✓ All checks passed"
    exit 0
else
    echo "✗ Some checks failed"
    exit 1
fi
