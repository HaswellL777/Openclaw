#!/usr/bin/env bash
set -euo pipefail

# hotfix-cleanup-keep.sh
# Purpose: Force cleanup="keep" for all sessions_spawn calls
# Root cause: GPT-5.4 passes cleanup:"delete" despite skill instructions,
#   causing subagent runs to be deleted from runs.json and sessions to be
#   permanently removed after completion.
# Fix: Override cleanup to always be "keep" regardless of model input.
# Scope: pi-embedded-CbCYZxIb.js line where cleanup is resolved

DIST_DIR="/opt/openclaw/node_modules/openclaw/dist"
TARGET_FILE="$DIST_DIR/pi-embedded-CbCYZxIb.js"
PATTERN='const cleanup = params.cleanup === "keep" || params.cleanup === "delete" ? params.cleanup : "keep";'
REPLACEMENT='const cleanup = "keep"; // [hotfix] force keep — GPT-5.4 sends "delete" despite skill instructions'

echo "=== OpenClaw cleanup=keep Hotfix ==="

if [[ ! -f "$TARGET_FILE" ]]; then
    echo "ERROR: Target file not found" >&2; exit 1
fi

BEFORE_HASH=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
echo "Before SHA256: $BEFORE_HASH"

MATCH_COUNT=$(grep -cF 'params.cleanup === "keep" || params.cleanup === "delete" ? params.cleanup : "keep"' "$TARGET_FILE" || true)
echo "Pattern matches: $MATCH_COUNT"

if [[ "$MATCH_COUNT" -eq 0 ]]; then
    echo "No matches. Already patched or wrong version."; exit 0
fi

echo ""
echo "=== Before ==="
grep -n 'params.cleanup === "keep"' "$TARGET_FILE"

if [[ "${1:-}" != "--apply" ]]; then
    echo ""; echo "DRY RUN — use --apply to patch"; exit 0
fi

cp "$TARGET_FILE" "${TARGET_FILE}.pre-cleanup-hotfix"

sed -i 's/const cleanup = params.cleanup === "keep" || params.cleanup === "delete" ? params.cleanup : "keep";/const cleanup = "keep"; \/\/ [hotfix] force keep — GPT-5.4 sends "delete" despite skill instructions/' "$TARGET_FILE"

# Also patch the other spawn entry point (line 115060 area)
sed -i 's/const cleanup = spawnMode === "session" ? "keep" : params.cleanup === "keep" || params.cleanup === "delete" ? params.cleanup : "keep";/const cleanup = "keep"; \/\/ [hotfix] force keep for all spawn paths/' "$TARGET_FILE"

AFTER_HASH=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
echo "After SHA256:  $AFTER_HASH"

echo ""
echo "=== After ==="
grep -n '\[hotfix\] force keep' "$TARGET_FILE"

MARKER=$(grep -c '\[hotfix\] force keep' "$TARGET_FILE" || true)
if [[ "$MARKER" -ge 1 ]]; then
    echo ""; echo "PATCH APPLIED."
    echo "sudo systemctl restart openclaw-gateway.service"
else
    echo "ERROR: Verification failed!" >&2
    cp "${TARGET_FILE}.pre-cleanup-hotfix" "$TARGET_FILE"
    exit 1
fi
