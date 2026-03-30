#!/usr/bin/env bash
set -euo pipefail

# check-workspace-skills.sh
# Validates that all SKILL.md files in workspace-main-template have proper YAML frontmatter
# Required fields: name, description (per OpenClaw AgentSkills spec)
#
# Usage:
#   bash scripts/check-workspace-skills.sh                    # check template
#   bash scripts/check-workspace-skills.sh /path/to/workspace # check specific workspace

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="${1:-$REPO_ROOT/workspace-main-template}"

echo "=== Workspace Skills Validator ==="
echo "Target: $TARGET"
echo ""

SKILLS_DIR="$TARGET/skills"
if [[ ! -d "$SKILLS_DIR" ]]; then
    echo "No skills/ directory found in $TARGET"
    exit 0
fi

ERRORS=0
CHECKED=0

for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_name=$(basename "$skill_dir")
    skill_md="$skill_dir/SKILL.md"

    if [[ ! -f "$skill_md" ]]; then
        echo "  WARN: $skill_name/ has no SKILL.md"
        continue
    fi

    CHECKED=$((CHECKED + 1))

    # Check for YAML frontmatter (starts with ---)
    first_line=$(head -1 "$skill_md")
    if [[ "$first_line" != "---" ]]; then
        echo "  FAIL: $skill_name/SKILL.md — missing YAML frontmatter (first line is not '---')"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Extract frontmatter and check for required fields
    frontmatter=$(sed -n '2,/^---$/p' "$skill_md" | head -n -1)

    if ! echo "$frontmatter" | grep -q '^name:'; then
        echo "  FAIL: $skill_name/SKILL.md — frontmatter missing 'name' field"
        ERRORS=$((ERRORS + 1))
    fi

    if ! echo "$frontmatter" | grep -q '^description:'; then
        echo "  FAIL: $skill_name/SKILL.md — frontmatter missing 'description' field"
        ERRORS=$((ERRORS + 1))
    else
        # Check description is not empty
        desc_value=$(echo "$frontmatter" | grep '^description:' | sed 's/^description:\s*//')
        if [[ -z "$desc_value" && ! $(echo "$frontmatter" | grep -A1 '^description:' | tail -1 | grep -c '^\s') -gt 0 ]]; then
            # Single-line empty description
            if ! echo "$frontmatter" | grep -q '^description: |'; then
                echo "  FAIL: $skill_name/SKILL.md — 'description' field is empty"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    fi

    # Check name matches directory name
    fm_name=$(echo "$frontmatter" | grep '^name:' | sed 's/^name:\s*//' | tr -d '"' | tr -d "'")
    if [[ -n "$fm_name" && "$fm_name" != "$skill_name" ]]; then
        echo "  WARN: $skill_name/SKILL.md — frontmatter name '$fm_name' does not match directory name '$skill_name'"
    fi

    if [[ $ERRORS -eq 0 ]] || ! echo "$frontmatter" | grep -q '^name:\|^description:' 2>/dev/null; then
        :
    fi
done

echo ""
echo "Checked: $CHECKED skills"

if [[ $ERRORS -gt 0 ]]; then
    echo "ERRORS: $ERRORS"
    echo ""
    echo "Fix: Add YAML frontmatter to SKILL.md files:"
    echo "  ---"
    echo "  name: skill-name"
    echo "  description: |"
    echo "    One-line description of what this skill does."
    echo "  ---"
    exit 1
else
    echo "All skills valid."
    exit 0
fi
