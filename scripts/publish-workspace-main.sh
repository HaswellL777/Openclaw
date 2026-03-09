#!/usr/bin/env bash
set -euo pipefail

# publish-workspace-main.sh
# Purpose: Publish workspace-main-template to a target directory
# Safety: Default dry-run mode, refuses to write to live paths

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/workspace-main-template"

# Default: dry-run mode
DRY_RUN=1
TARGET_DIR=""

# Prohibited live paths (safety guard)
PROHIBITED_PATHS=(
    "/var/lib/openclaw"
    "/etc/openclaw"
    "/opt/openclaw"
    "/mnt/vault"
    "/srv/openclaw-control"
)

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] TARGET_DIR

Publish workspace-main-template to TARGET_DIR.

OPTIONS:
    -n, --dry-run       Dry-run mode (default)
    --apply             Actually perform the publish (disables dry-run)
    -h, --help          Show this help

EXAMPLES:
    # Dry-run to /tmp/workspace-main-test
    $0 /tmp/workspace-main-test

    # Actually publish to /tmp/workspace-main-test
    $0 --apply /tmp/workspace-main-test

SAFETY:
    - Default mode is dry-run (shows what would be done)
    - Use --apply to actually perform the publish
    - Refuses to write to live system paths:
      - /var/lib/openclaw
      - /etc/openclaw
      - /opt/openclaw
      - /mnt/vault
      - /srv/openclaw-control
    - Future: may add --allow-live-target flag with explicit confirmation
    - Creates target directory if it doesn't exist
    - Preserves existing control/state/ directory in target
    - Automatically publishes SOP from docs/host-sop.md

TEMPLATE SOURCE:
    $TEMPLATE_DIR

PUBLISH STEPS:
    1. Copy workspace-main-template to target
    2. Preserve existing control/state/ (if exists)
    3. Call publish-sop.sh to publish docs/host-sop.md to target/control/SOP.md

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
for prohibited in "${PROHIBITED_PATHS[@]}"; do
    if [[ "$TARGET_DIR" == "$prohibited"* ]]; then
        echo "Error: refusing to write to live system path: $TARGET_DIR" >&2
        echo "This path is prohibited for safety: $prohibited" >&2
        echo "" >&2
        echo "Current implementation only supports publishing to test/development paths." >&2
        echo "Future: may add --allow-live-target flag with explicit confirmation." >&2
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
"$SCRIPT_DIR/publish-sop.sh" --apply "$TARGET_DIR"

echo ""
echo "=== PUBLISH COMPLETE ==="
echo "Target: $TARGET_DIR"
echo ""
echo "Next steps:"
echo "  1. Run scripts/check-workspace-main.sh $TARGET_DIR"
echo "  2. Validate workspace structure"
echo "  3. Verify SOP has been published (not placeholder)"
