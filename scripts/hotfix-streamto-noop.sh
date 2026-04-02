#!/usr/bin/env bash
set -euo pipefail

# hotfix-streamto-noop.sh
# Purpose: Patch OpenClaw gateway to silently ignore streamTo for non-ACP runtime
# Scope: ONLY the streamTo guard; does NOT touch resumeSessionId
# Type: Live-side hotfix (not a formal fix; upstream issue tracks proper resolution)
# Requires: sudo, pre-change snapshot
#
# Root cause: sessions_spawn schema exposes streamTo to all runtimes,
# but the validator rejects it with hard error for runtime=subagent.
# GPT-5.4 (and similar schema-following models) auto-fill streamTo: "parent"
# because the field is visible in the tool schema.
#
# Fix: Comment out the hard error return for streamTo + non-ACP runtime.
# The streamTo variable is only consumed by spawnAcpDirect (ACP path);
# spawnSubagentDirect (subagent path) never references it.
# So removing the guard is safe — streamTo is naturally ignored on the subagent path.

DIST_DIR="/opt/openclaw/node_modules/openclaw/dist"
TARGET_FILE="$DIST_DIR/pi-embedded-CbCYZxIb.js"
PATTERN='if (streamTo && runtime !== "acp") return jsonResult({'

echo "=== OpenClaw streamTo Hotfix ==="
echo ""

# Step 1: Verify target file exists
if [[ ! -f "$TARGET_FILE" ]]; then
    echo "ERROR: Target file not found: $TARGET_FILE" >&2
    exit 1
fi

# Step 2: Record before-hash
BEFORE_HASH=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
echo "Before SHA256: $BEFORE_HASH"

# Step 3: Count pattern matches
MATCH_COUNT=$(grep -c 'streamTo is only supported for runtime=acp' "$TARGET_FILE" || true)
echo "Pattern matches: $MATCH_COUNT"

if [[ "$MATCH_COUNT" -eq 0 ]]; then
    echo "No matches found. Either already patched or wrong file version."
    exit 0
fi

if [[ "$MATCH_COUNT" -gt 1 ]]; then
    echo "WARNING: Multiple matches ($MATCH_COUNT). Expected exactly 1. Aborting for safety." >&2
    exit 1
fi

# Step 4: Show context before patching
echo ""
echo "=== Before (context) ==="
grep -n -B1 -A3 'streamTo is only supported for runtime=acp' "$TARGET_FILE"

# Step 5: Apply patch — comment out the 3-line guard block
# Pattern: if (streamTo && runtime !== "acp") return jsonResult({
#              status: "error",
#              error: `streamTo is only supported for runtime=acp; got runtime=${runtime}`
#          });
#
# Replace with: commented-out version (preserves line numbers for debugging)
if [[ "${1:-}" != "--apply" ]]; then
    echo ""
    echo "DRY RUN — use --apply to actually patch"
    exit 0
fi

# Create backup
cp "$TARGET_FILE" "${TARGET_FILE}.pre-streamto-hotfix"
echo "Backup: ${TARGET_FILE}.pre-streamto-hotfix"

# Patch: replace the hard error with a no-op comment
sed -i 's/if (streamTo && runtime !== "acp") return jsonResult({/\/\/ [hotfix] streamTo guard disabled — silent ignore for non-ACP (see upstream issue)\n\t\t\tif (false \&\& streamTo \&\& runtime !== "acp") return jsonResult({/' "$TARGET_FILE"

# Step 6: Verify patch applied
AFTER_HASH=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
echo "After SHA256:  $AFTER_HASH"

POST_MATCH_COUNT=$(grep -c 'streamTo is only supported for runtime=acp' "$TARGET_FILE" || true)
HOTFIX_MARKER=$(grep -c '\[hotfix\] streamTo guard disabled' "$TARGET_FILE" || true)

echo ""
echo "=== After (context) ==="
grep -n -B1 -A3 'streamTo guard disabled' "$TARGET_FILE"

echo ""
echo "=== Verification ==="
echo "Error pattern still present: $POST_MATCH_COUNT (expected: 1, now unreachable)"
echo "Hotfix marker present:       $HOTFIX_MARKER (expected: 1)"

if [[ "$HOTFIX_MARKER" -eq 1 ]]; then
    echo ""
    echo "PATCH APPLIED SUCCESSFULLY"
    echo ""
    echo "Next steps:"
    echo "  1. sudo systemctl restart openclaw-gateway.service"
    echo "  2. Verify: journalctl -u openclaw-gateway.service -f"
    echo "  3. Test: send sessions_spawn(agentId: 'task-runner', task: '...') via Feishu"
    echo "  4. Confirm no 'streamTo is only supported' errors in log"
    echo ""
    echo "Rollback:"
    echo "  cp ${TARGET_FILE}.pre-streamto-hotfix $TARGET_FILE"
    echo "  sudo systemctl restart openclaw-gateway.service"
else
    echo "ERROR: Patch verification failed!" >&2
    echo "Restoring backup..."
    cp "${TARGET_FILE}.pre-streamto-hotfix" "$TARGET_FILE"
    exit 1
fi
