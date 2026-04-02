#!/usr/bin/env bash
set -euo pipefail

# hotfix-json-file-chmod.sh
# Purpose: Change saveJsonFile chmod from 0600 to 0640 so group (openclaw) members can read
# This fixes: runs.json ACL being stripped on every write, preventing GUI from reading
# Scope: json-file-Dl3Z1jL1.js — the chmod value in saveJsonFile
# Type: Live-side hotfix

DIST_DIR="/opt/openclaw/node_modules/openclaw/dist"
TARGET_FILE="$DIST_DIR/json-file-Dl3Z1jL1.js"

echo "=== OpenClaw json-file chmod Hotfix ==="

if [[ ! -f "$TARGET_FILE" ]]; then
    echo "ERROR: Target file not found: $TARGET_FILE" >&2
    exit 1
fi

BEFORE_HASH=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
echo "Before SHA256: $BEFORE_HASH"

# Pattern: fs.chmodSync(pathname, 384) — 384 = 0600
MATCH_COUNT=$(grep -c 'chmodSync(pathname, 384)' "$TARGET_FILE" || true)
echo "Pattern matches: $MATCH_COUNT"

if [[ "$MATCH_COUNT" -eq 0 ]]; then
    echo "No matches found. Either already patched or wrong version."
    exit 0
fi

echo ""
echo "=== Before ==="
grep -n 'chmodSync(pathname' "$TARGET_FILE"

if [[ "${1:-}" != "--apply" ]]; then
    echo ""
    echo "DRY RUN — use --apply to patch"
    echo "Change: chmod 0600 (384) → 0640 (416)"
    exit 0
fi

cp "$TARGET_FILE" "${TARGET_FILE}.pre-chmod-hotfix"
echo "Backup: ${TARGET_FILE}.pre-chmod-hotfix"

# 416 = 0640 (owner rw, group r)
sed -i 's/chmodSync(pathname, 384)/chmodSync(pathname, 416)/' "$TARGET_FILE"

AFTER_HASH=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
echo "After SHA256:  $AFTER_HASH"

echo ""
echo "=== After ==="
grep -n 'chmodSync(pathname' "$TARGET_FILE"

echo ""
echo "PATCH APPLIED. Restart gateway to take effect."
echo "Then add nick to openclaw group: sudo usermod -aG openclaw nick"
echo ""
echo "Rollback:"
echo "  cp ${TARGET_FILE}.pre-chmod-hotfix $TARGET_FILE"
echo "  sudo systemctl restart openclaw-gateway.service"
