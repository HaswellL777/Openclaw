#!/usr/bin/env bash
set -euo pipefail

# check-workspace-main.sh
# Purpose: Validate workspace-main structure and constraints
# Usage: check-workspace-main.sh [TARGET_DIR]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default to checking template in repo
TARGET_DIR="${1:-$REPO_ROOT/workspace-main-template}"

usage() {
    cat <<EOF
Usage: $0 [TARGET_DIR]

Validate workspace-main structure and constraints.

ARGUMENTS:
    TARGET_DIR    Directory to check (default: workspace-main-template in repo)

EXAMPLES:
    # Check template in repo (allows placeholder SOP)
    $0

    # Check published artifact (requires real SOP)
    $0 /tmp/workspace-main-test

CHECKS:
    - Required core files exist (AGENTS.md, IDENTITY.md, etc.)
    - Required control files exist (SOP.md, policies, etc.)
    - Required state files exist
    - Required runbooks exist
    - Required skill definitions exist
    - No prohibited content (secrets, tokens)
    - Basic structure constraints
    - SOP publish status (for published artifacts)

MODES:
    - Template mode: Checking workspace-main-template in repo
      - Allows placeholder SOP.md
      - Allows empty last-sop-hash.txt
    - Published artifact mode: Checking deployed workspace
      - Requires SOP.md to be published (not placeholder)
      - Requires non-empty last-sop-hash.txt

EXIT CODES:
    0    All checks passed
    1    One or more checks failed

EOF
    exit 0
}

if [[ "$TARGET_DIR" == "--help" ]] || [[ "$TARGET_DIR" == "-h" ]]; then
    usage
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: target directory not found: $TARGET_DIR" >&2
    exit 1
fi

echo "=== Checking workspace-main: $TARGET_DIR ==="
echo ""

# Determine if this is template or published artifact
IS_TEMPLATE=0
if [[ "$TARGET_DIR" == "$REPO_ROOT/workspace-main-template" ]]; then
    IS_TEMPLATE=1
    echo "Mode: Template skeleton check"
    echo "(Allows placeholder SOP and empty hash)"
else
    echo "Mode: Published artifact check"
    echo "(Requires real SOP and valid hash)"
fi
echo ""

FAILED=0

# Helper function to check file/dir exists
check_exists() {
    local path="$1"
    local type="$2"  # "file" or "directory"
    local full_path="$TARGET_DIR/$path"

    if [[ "$type" == "file" ]]; then
        if [[ -f "$full_path" ]]; then
            echo "✓ File exists: $path"
            return 0
        else
            echo "✗ File missing: $path"
            FAILED=1
            return 1
        fi
    elif [[ "$type" == "directory" ]]; then
        if [[ -d "$full_path" ]]; then
            echo "✓ Directory exists: $path"
            return 0
        else
            echo "✗ Directory missing: $path"
            FAILED=1
            return 1
        fi
    fi
}

# Check required core files
echo "--- Core files ---"
check_exists "AGENTS.md" "file"
check_exists "IDENTITY.md" "file"
check_exists "SOUL.md" "file"
check_exists "USER.md" "file"
check_exists "HEARTBEAT.md" "file"
check_exists "TOOLS.md" "file"
check_exists "README.md" "file"
check_exists ".gitignore" "file"
echo ""

# Check required directories
echo "--- Required directories ---"
check_exists "control" "directory"
check_exists "control/runbooks" "directory"
check_exists "control/state" "directory"
check_exists "skills" "directory"
check_exists "skills/host-sop" "directory"
check_exists "skills/routing" "directory"
check_exists "skills/approvals" "directory"
check_exists "skills/broker" "directory"
check_exists "memory" "directory"
echo ""

# Check control files
echo "--- Control files ---"
check_exists "control/SOP.md" "file"
check_exists "control/routing-policy.md" "file"
check_exists "control/approval-policy.md" "file"
check_exists "control/allowed-workers.md" "file"
check_exists "control/host-ops-api.md" "file"
echo ""

# Check state files
echo "--- State files ---"
check_exists "control/state/pending-approvals.json" "file"
check_exists "control/state/last-health.md" "file"
check_exists "control/state/last-sop-hash.txt" "file"
check_exists "control/state/last-task-index.json" "file"
echo ""

# Check runbooks
echo "--- Runbooks ---"
check_exists "control/runbooks/openclaw-config-change.md" "file"
check_exists "control/runbooks/gateway-restart.md" "file"
check_exists "control/runbooks/rollback.md" "file"
echo ""

# Check skill definitions
echo "--- Skill definitions ---"
check_exists "skills/host-sop/SKILL.md" "file"
check_exists "skills/routing/SKILL.md" "file"
check_exists "skills/approvals/SKILL.md" "file"
check_exists "skills/broker/SKILL.md" "file"
echo ""

# Check for prohibited content
echo "--- Prohibited content checks ---"
PROHIBITED_PATTERNS=(
    "sk-[a-zA-Z0-9]{20,}"      # OpenAI API keys (at least 20 chars after sk-)
    "xoxb-[a-zA-Z0-9]{20,}"    # Slack tokens
    "ghp_[a-zA-Z0-9]{20,}"     # GitHub tokens
    "AKIA[A-Z0-9]{16}"         # AWS access keys
    "-----BEGIN.*PRIVATE KEY"   # Private keys
)

FOUND_SECRETS=0
for pattern in "${PROHIBITED_PATTERNS[@]}"; do
    # Search in target directory, excluding this script itself
    matches=$(grep -r -E "$pattern" "$TARGET_DIR" 2>/dev/null | grep -v ".git" || true)
    if [[ -n "$matches" ]]; then
        echo "✗ Found potential secret matching pattern: $pattern"
        echo "  $matches"
        FOUND_SECRETS=1
        FAILED=1
    fi
done

if [[ $FOUND_SECRETS -eq 0 ]]; then
    echo "✓ No obvious secrets found"
fi
echo ""

# Check core file content
echo "--- Core file content checks ---"

# Check AGENTS.md mentions main agent
if grep -q "main" "$TARGET_DIR/AGENTS.md" 2>/dev/null; then
    echo "✓ AGENTS.md mentions main agent"
else
    echo "✗ AGENTS.md does not mention main agent"
    FAILED=1
fi

# Check IDENTITY.md mentions workspace-main
if grep -q "workspace-main" "$TARGET_DIR/IDENTITY.md" 2>/dev/null; then
    echo "✓ IDENTITY.md mentions workspace-main"
else
    echo "✗ IDENTITY.md does not mention workspace-main"
    FAILED=1
fi

# Check README.md describes as published artifact
if grep -q "published artifact" "$TARGET_DIR/README.md" 2>/dev/null; then
    echo "✓ README.md describes workspace as published artifact"
else
    echo "✗ README.md does not describe workspace as published artifact"
    FAILED=1
fi

echo ""

# Check control file content
echo "--- Control file content checks ---"

# Check SOP.md mentions authoritative source
if grep -q "authoritative source" "$TARGET_DIR/control/SOP.md" 2>/dev/null; then
    echo "✓ SOP.md mentions authoritative source"
else
    echo "✗ SOP.md does not mention authoritative source"
    FAILED=1
fi

# Check SOP publish status (only for published artifacts)
if [[ $IS_TEMPLATE -eq 0 ]]; then
    # This is a published artifact, check if SOP is really published
    if grep -q "# Placeholder" "$TARGET_DIR/control/SOP.md" 2>/dev/null; then
        echo "✗ SOP.md is still placeholder (not published)"
        FAILED=1
    else
        echo "✓ SOP.md has been published (not placeholder)"
    fi

    # Check if SOP has publication header
    if grep -qE '^\*\*Last published\*\*:' "$TARGET_DIR/control/SOP.md" 2>/dev/null; then
        echo "✓ SOP.md has publication header"
    else
        echo "✗ SOP.md missing publication header"
        FAILED=1
    fi

    # Check if SOP has SHA256
    if grep -qE '^\*\*SHA256\*\*:' "$TARGET_DIR/control/SOP.md" 2>/dev/null; then
        echo "✓ SOP.md has SHA256 hash"

        # Cross-validate: SOP.md embedded hash should match last-sop-hash.txt
        if [[ -s "$TARGET_DIR/control/state/last-sop-hash.txt" ]]; then
            SOP_EMBEDDED_HASH=$(grep -oP '(?<=\*\*SHA256\*\*: `)[a-f0-9]{64}' "$TARGET_DIR/control/SOP.md" 2>/dev/null || echo "")
            STATE_HASH=$(cat "$TARGET_DIR/control/state/last-sop-hash.txt" 2>/dev/null | tr -d '[:space:]')
            if [[ -n "$SOP_EMBEDDED_HASH" && "$SOP_EMBEDDED_HASH" == "$STATE_HASH" ]]; then
                echo "✓ SOP.md embedded hash matches last-sop-hash.txt"
            elif [[ -z "$SOP_EMBEDDED_HASH" ]]; then
                echo "⚠ Could not extract hash from SOP.md header (non-fatal)"
            else
                echo "✗ SOP.md embedded hash ($SOP_EMBEDDED_HASH) does not match last-sop-hash.txt ($STATE_HASH)"
                FAILED=1
            fi
        fi
    else
        echo "✗ SOP.md missing SHA256 hash"
        FAILED=1
    fi
else
    echo "✓ Template mode: SOP placeholder allowed"
fi

# Check routing-policy.md has decision tree
if grep -q "decision tree" "$TARGET_DIR/control/routing-policy.md" 2>/dev/null; then
    echo "✓ routing-policy.md has decision tree"
else
    echo "✗ routing-policy.md missing decision tree"
    FAILED=1
fi

# Check approval-policy.md has categories
if grep -q "Category 1" "$TARGET_DIR/control/approval-policy.md" 2>/dev/null; then
    echo "✓ approval-policy.md has approval categories"
else
    echo "✗ approval-policy.md missing approval categories"
    FAILED=1
fi

echo ""

# Check state file format
echo "--- State file format checks ---"

# Check pending-approvals.json is valid JSON
if jq empty "$TARGET_DIR/control/state/pending-approvals.json" 2>/dev/null; then
    echo "✓ pending-approvals.json is valid JSON"
else
    echo "✗ pending-approvals.json is not valid JSON"
    FAILED=1
fi

# Check last-task-index.json is valid JSON
if jq empty "$TARGET_DIR/control/state/last-task-index.json" 2>/dev/null; then
    echo "✓ last-task-index.json is valid JSON"
else
    echo "✗ last-task-index.json is not valid JSON"
    FAILED=1
fi

# Check last-sop-hash.txt (only for published artifacts)
if [[ $IS_TEMPLATE -eq 0 ]]; then
    # This is a published artifact, check if hash is non-empty
    if [[ -s "$TARGET_DIR/control/state/last-sop-hash.txt" ]]; then
        HASH_CONTENT=$(cat "$TARGET_DIR/control/state/last-sop-hash.txt")
        if [[ ${#HASH_CONTENT} -eq 64 ]]; then
            echo "✓ last-sop-hash.txt contains valid SHA256 hash"
        else
            echo "✗ last-sop-hash.txt does not contain valid SHA256 hash (expected 64 chars, got ${#HASH_CONTENT})"
            FAILED=1
        fi
    else
        echo "✗ last-sop-hash.txt is empty or missing"
        FAILED=1
    fi
else
    echo "✓ Template mode: empty last-sop-hash.txt allowed"
fi

echo ""

# Check skill structure
echo "--- Skill structure checks ---"
for skill in host-sop routing approvals broker; do
    skill_file="$TARGET_DIR/skills/$skill/SKILL.md"
    if [[ -f "$skill_file" ]]; then
        if grep -q "## Skill identity" "$skill_file" 2>/dev/null; then
            echo "✓ Skill $skill has identity section"
        else
            echo "✗ Skill $skill missing identity section"
            FAILED=1
        fi

        if grep -q "## What this skill does" "$skill_file" 2>/dev/null; then
            echo "✓ Skill $skill has purpose section"
        else
            echo "✗ Skill $skill missing purpose section"
            FAILED=1
        fi
    fi
done
echo ""

# Summary
echo "=== CHECK SUMMARY ==="
if [[ $FAILED -eq 0 ]]; then
    echo "✓ All checks passed"
    echo ""
    echo "Workspace-main structure is valid."
    exit 0
else
    echo "✗ Some checks failed"
    echo ""
    echo "Please fix the issues above before deploying."
    exit 1
fi
