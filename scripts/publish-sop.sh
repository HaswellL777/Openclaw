#!/usr/bin/env bash
set -euo pipefail

# publish-sop.sh
# Purpose: Publish host-sop.md from development repo to target workspace
# Safety: Default dry-run mode, refuses to write to live system paths

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_SOP="$REPO_ROOT/docs/host-sop.md"

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

Publish host-sop.md from development repo to target workspace.

OPTIONS:
    -n, --dry-run       Dry-run mode (default)
    --apply             Actually perform the publish (disables dry-run)
    -h, --help          Show this help

ARGUMENTS:
    TARGET_DIR          Target workspace directory (must contain control/ subdirectory)

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

SOURCE:
    $SOURCE_SOP

TARGET:
    TARGET_DIR/control/SOP.md
    TARGET_DIR/control/state/last-sop-hash.txt

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

if [[ ! -f "$SOURCE_SOP" ]]; then
    echo "Error: source SOP not found: $SOURCE_SOP" >&2
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

# Compute source hash
SOURCE_HASH=$(sha256sum "$SOURCE_SOP" | awk '{print $1}')
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Show mode
if [[ $DRY_RUN -eq 1 ]]; then
    echo "=== DRY-RUN MODE ==="
    echo "No changes will be made. Use --apply to actually publish."
    echo ""
fi

echo "Source SOP: $SOURCE_SOP"
echo "Source SHA256: $SOURCE_HASH"
echo "Target directory: $TARGET_DIR"
echo "Target SOP: $TARGET_DIR/control/SOP.md"
echo "Target hash file: $TARGET_DIR/control/state/last-sop-hash.txt"
echo "Timestamp: $TIMESTAMP"
echo ""

# Check if target directory exists
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: target directory does not exist: $TARGET_DIR" >&2
    exit 1
fi

if [[ ! -d "$TARGET_DIR/control" ]]; then
    echo "Error: target directory does not contain control/ subdirectory: $TARGET_DIR" >&2
    exit 1
fi

# Check if target SOP already exists and compare hash
TARGET_SOP="$TARGET_DIR/control/SOP.md"
TARGET_HASH_FILE="$TARGET_DIR/control/state/last-sop-hash.txt"

if [[ -f "$TARGET_HASH_FILE" ]]; then
    EXISTING_HASH=$(cat "$TARGET_HASH_FILE" 2>/dev/null || echo "")
    if [[ "$EXISTING_HASH" == "$SOURCE_HASH" ]]; then
        echo "Target SOP is already up-to-date (hash matches)."
        echo "No publish needed."
        exit 0
    else
        echo "Target SOP hash differs from source."
        echo "  Existing: $EXISTING_HASH"
        echo "  Source:   $SOURCE_HASH"
        if [[ $DRY_RUN -eq 0 ]]; then
            echo "Will update target SOP."
        fi
    fi
else
    echo "Target SOP hash file does not exist."
    if [[ $DRY_RUN -eq 0 ]]; then
        echo "Will create initial SOP publish."
    fi
fi

echo ""

# Dry-run: just show what would be done
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Would perform the following operations:"
    echo "  1. Copy $SOURCE_SOP"
    echo "     to $TARGET_SOP"
    echo "  2. Add publication header with:"
    echo "     - Authoritative source: openclaw-dev/docs/host-sop.md"
    echo "     - Last published: $TIMESTAMP"
    echo "     - SHA256: $SOURCE_HASH"
    echo "  3. Write hash to $TARGET_HASH_FILE"
    echo ""
    echo "Run with --apply to actually perform the publish."
    exit 0
fi

# Apply mode: actually do the work
echo "=== APPLYING CHANGES ==="

# Create control/state directory if needed
mkdir -p "$TARGET_DIR/control/state"

# Create target SOP with header
cat > "$TARGET_SOP" <<EOF
# Host SOP (Runtime Copy)

**This is a published copy, not the authoritative source.**

**Authoritative source**: \`openclaw-dev/docs/host-sop.md\` (development repo)

**Last published**: $TIMESTAMP

**SHA256**: \`$SOURCE_HASH\`

---

EOF

# Append source SOP content
cat "$SOURCE_SOP" >> "$TARGET_SOP"

# Write hash to state file
echo "$SOURCE_HASH" > "$TARGET_HASH_FILE"

echo "Published SOP to: $TARGET_SOP"
echo "Updated hash file: $TARGET_HASH_FILE"
echo ""
echo "=== PUBLISH COMPLETE ==="
echo "Source: $SOURCE_SOP"
echo "Target: $TARGET_SOP"
echo "Hash: $SOURCE_HASH"
