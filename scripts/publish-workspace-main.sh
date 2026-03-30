#!/usr/bin/env bash
set -euo pipefail

# publish-workspace-main.sh
# Purpose: Publish workspace-main-template to a target directory
# Safety: Default dry-run mode, refuses to write to live paths

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/workspace-main-template"

# Default: dry-run mode, live target refused
DRY_RUN=1
ALLOW_LIVE=0
TARGET_DIR=""

# Prohibited live paths (safety guard — fail-closed by default)
PROHIBITED_PATHS=(
    "/var/lib/openclaw"
    "/etc/openclaw"
    "/opt/openclaw"
    "/mnt/vault"
    "/srv/openclaw-control"
)

# The only live target that --allow-live-target may unlock
ALLOWED_LIVE_TARGET="/var/lib/openclaw/.openclaw/workspace-main"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] TARGET_DIR

Publish workspace-main-template to TARGET_DIR.

OPTIONS:
    -n, --dry-run           Dry-run mode (default)
    --apply                 Actually perform the publish (disables dry-run)
    --allow-live-target     Unlock the live target path (requires --apply, prompts for confirmation)
    -h, --help              Show this help

EXAMPLES:
    # Dry-run to /tmp/workspace-main-test
    $0 /tmp/workspace-main-test

    # Actually publish to /tmp/workspace-main-test
    $0 --apply /tmp/workspace-main-test

    # Publish to live target (requires explicit flag + interactive confirmation)
    $0 --apply --allow-live-target /var/lib/openclaw/.openclaw/workspace-main

SAFETY:
    - Default mode is dry-run (shows what would be done)
    - Use --apply to actually perform the publish
    - By default, refuses to write to live system paths:
      /var/lib/openclaw, /etc/openclaw, /opt/openclaw, /mnt/vault, /srv/openclaw-control
    - --allow-live-target only unlocks the designated live workspace path:
      /var/lib/openclaw/.openclaw/workspace-main
    - --allow-live-target requires --apply and interactive confirmation (stdin must be a terminal)
    - Creates target directory if it doesn't exist
    - Preserves existing control/state/ directory in target
    - Automatically publishes SOP from docs/host-sop.md

TEMPLATE SOURCE:
    $TEMPLATE_DIR

PUBLISH STEPS:
    1. Copy workspace-main-template to target
    2. Preserve existing control/state/ (if exists)
    3. Publish docs/host-sop.md to target/control/SOP.md
       (non-live targets: delegates to publish-sop.sh;
        live targets: inline SOP publish by this script)

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        --apply)
            DRY_RUN=0
            shift
            ;;
        --allow-live-target)
            ALLOW_LIVE=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ -z "$TARGET_DIR" ]]; then
                TARGET_DIR="$1"
            else
                echo "Error: unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$TARGET_DIR" ]]; then
    echo "Error: TARGET_DIR is required" >&2
    echo "Run '$0 --help' for usage" >&2
    exit 1
fi

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "Error: template directory not found: $TEMPLATE_DIR" >&2
    exit 1
fi

# Safety check: refuse to write to prohibited live paths
# --allow-live-target only unlocks the single designated live workspace path
for prohibited in "${PROHIBITED_PATHS[@]}"; do
    if [[ "$TARGET_DIR" == "$prohibited"* ]]; then
        # Check if this is the allowed live target and the flag is set
        if [[ $ALLOW_LIVE -eq 1 && "$TARGET_DIR" == "$ALLOWED_LIVE_TARGET" ]]; then
            # Allowed — but require --apply and interactive confirmation
            if [[ $DRY_RUN -eq 1 ]]; then
                echo "Error: --allow-live-target requires --apply (cannot dry-run against live target)" >&2
                exit 1
            fi
            if [[ ! -t 0 ]]; then
                echo "Error: --allow-live-target requires an interactive terminal (stdin must be a TTY)" >&2
                echo "This is a safety measure to prevent unattended live publishes." >&2
                exit 1
            fi
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║  WARNING: LIVE TARGET PUBLISH                              ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            echo ""
            echo "  Target: $TARGET_DIR"
            echo "  Source: $TEMPLATE_DIR"
            echo ""
            echo "  This will overwrite the live workspace-main used by the"
            echo "  production main agent. Existing control/state/ will be preserved."
            echo ""
            echo "  Prerequisites (operator must verify):"
            echo "    1. Pre-change root snapshot has been created"
            echo "    2. Gateway health check has passed"
            echo "    3. You are ready to run check-workspace-main.sh after publish"
            echo ""
            read -r -p "  Type 'yes-publish-live' to confirm: " CONFIRM
            if [[ "$CONFIRM" != "yes-publish-live" ]]; then
                echo "Aborted by operator." >&2
                exit 1
            fi
            echo ""
            # Fall through to the publish logic
            break
        fi
        echo "Error: refusing to write to live system path: $TARGET_DIR" >&2
        echo "This path is prohibited for safety: $prohibited" >&2
        echo "" >&2
        if [[ "$TARGET_DIR" == "$ALLOWED_LIVE_TARGET" ]]; then
            echo "To publish to the live workspace, use: --apply --allow-live-target" >&2
        else
            echo "Only the designated live workspace path can be unlocked:" >&2
            echo "  $ALLOWED_LIVE_TARGET" >&2
        fi
        exit 1
    fi
done

# Show mode
if [[ $DRY_RUN -eq 1 ]]; then
    echo "=== DRY-RUN MODE ==="
    echo "No changes will be made. Use --apply to actually publish."
    echo ""
fi

echo "Template source: $TEMPLATE_DIR"
echo "Target directory: $TARGET_DIR"
echo ""

# Check if target exists
if [[ -d "$TARGET_DIR" ]]; then
    echo "Target directory exists: $TARGET_DIR"
    if [[ $DRY_RUN -eq 0 ]]; then
        echo "Will update existing workspace-main"
    fi
else
    echo "Target directory does not exist: $TARGET_DIR"
    if [[ $DRY_RUN -eq 0 ]]; then
        echo "Will create target directory"
    fi
fi

echo ""

# Dry-run: just show what would be done
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Would perform the following operations:"
    echo "  1. Create target directory (if needed): $TARGET_DIR"
    echo "  2. Copy template files from: $TEMPLATE_DIR"
    echo "  3. Preserve existing control/state/ (if exists)"
    echo "  4. Publish SOP from docs/host-sop.md to target/control/SOP.md"
    echo ""
    echo "Files that would be published:"
    (cd "$TEMPLATE_DIR" && find . -type f | sort)
    echo ""
    echo "Run with --apply to actually perform the publish."
    exit 0
fi

# Apply mode: actually do the work

# Pre-publish validation: check skill frontmatter
if [[ -x "$SCRIPT_DIR/check-workspace-skills.sh" ]]; then
    echo "Running skill validation..."
    if ! "$SCRIPT_DIR/check-workspace-skills.sh" "$TEMPLATE_DIR"; then
        echo "" >&2
        echo "Error: Skill validation failed. Fix SKILL.md files before publishing." >&2
        echo "All SKILL.md files must have YAML frontmatter with 'name' and 'description'." >&2
        exit 1
    fi
    echo ""
fi

echo "=== APPLYING CHANGES ==="

# Create target directory if needed
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

# Backup existing control/state if it exists
STATE_BACKUP=""
if [[ -d "$TARGET_DIR/control/state" ]]; then
    STATE_BACKUP=$(mktemp -d)
    echo "Backing up existing control/state to: $STATE_BACKUP"
    cp -a "$TARGET_DIR/control/state" "$STATE_BACKUP/"
fi

# Copy template to target
echo "Copying template files to target..."
rsync -av --delete \
    --exclude='control/state/*' \
    --exclude='control/state/.gitkeep' \
    "$TEMPLATE_DIR/" "$TARGET_DIR/"

# Restore control/state if we backed it up
if [[ -n "$STATE_BACKUP" ]]; then
    echo "Restoring control/state from backup..."
    cp -a "$STATE_BACKUP/state" "$TARGET_DIR/control/"
    rm -rf "$STATE_BACKUP"
else
    # First-time publish: copy state files from template
    echo "First-time publish: copying initial state files from template..."
    mkdir -p "$TARGET_DIR/control/state"
    cp -a "$TEMPLATE_DIR/control/state/"* "$TARGET_DIR/control/state/" 2>/dev/null || true
fi

# Publish SOP from docs/host-sop.md
echo ""
echo "Publishing SOP from docs/host-sop.md..."
if [[ $ALLOW_LIVE -eq 1 ]]; then
    # Live target: inline SOP publish here.
    # publish-sop.sh unconditionally refuses live paths — by design.
    # The SOP publish logic is duplicated here so that the only code path
    # that writes SOP to a live target is inside this script, which has
    # already completed interactive confirmation above.
    SOURCE_SOP="$REPO_ROOT/docs/host-sop.md"
    TARGET_SOP="$TARGET_DIR/control/SOP.md"
    TARGET_HASH_FILE="$TARGET_DIR/control/state/last-sop-hash.txt"
    SOURCE_HASH=$(sha256sum "$SOURCE_SOP" | awk '{print $1}')
    SOP_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

    mkdir -p "$TARGET_DIR/control/state"

    cat > "$TARGET_SOP" <<SOPEOF
# Host SOP (Runtime Copy)

**This is a published copy, not the authoritative source.**

**Authoritative source**: \`openclaw-dev/docs/host-sop.md\` (development repo)

**Last published**: $SOP_TIMESTAMP

**SHA256**: \`$SOURCE_HASH\`

---

SOPEOF
    cat "$SOURCE_SOP" >> "$TARGET_SOP"
    echo "$SOURCE_HASH" > "$TARGET_HASH_FILE"

    echo "Published SOP to: $TARGET_SOP"
    echo "Updated hash file: $TARGET_HASH_FILE"
    echo "Hash: $SOURCE_HASH"
else
    # Non-live target: delegate to publish-sop.sh (safe — it only touches non-live paths)
    "$SCRIPT_DIR/publish-sop.sh" --apply "$TARGET_DIR"
fi

echo ""
echo "=== PUBLISH COMPLETE ==="
echo "Target: $TARGET_DIR"

# Fix ownership for live target — gateway runs as openclaw:openclaw
if [[ $ALLOW_LIVE -eq 1 ]]; then
    echo ""
    echo "Fixing ownership to openclaw:openclaw..."
    chown -R openclaw:openclaw "$TARGET_DIR"
    echo "Ownership fixed."
fi

echo ""
echo "Next steps:"
echo "  1. Run scripts/check-workspace-main.sh $TARGET_DIR"
echo "  2. Validate workspace structure"
echo "  3. Verify SOP has been published (not placeholder)"
