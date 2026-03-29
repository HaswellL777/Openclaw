#!/usr/bin/env bash
# Update model context windows in openclaw.json:
#   claude-opus-4-6 (duckcoding-claude + duckcoding-claude-backup):
#     contextWindow 200000 → 500000
#     maxTokens 32000 → 128000
set -euo pipefail

CONFIG="/etc/openclaw/openclaw.json"
BACKUP="/tmp/openclaw.json.backup.$(date +%Y%m%d-%H%M%S)"

echo "=== Backup ==="
sudo cp "$CONFIG" "$BACKUP"
echo "Saved: $BACKUP"

TMPFILE=$(mktemp)
sudo cat "$CONFIG" > "$TMPFILE"

echo ""
echo "=== Before ==="
grep -n 'contextWindow\|maxTokens' "$TMPFILE"

# Targeted replacements: only contextWindow 200000 and maxTokens 32000
# (these values only appear in the two duckcoding-claude providers)
sed -i 's/"contextWindow": 200000/"contextWindow": 500000/g' "$TMPFILE"
sed -i 's/"maxTokens": 32000/"maxTokens": 128000/g' "$TMPFILE"

echo ""
echo "=== After ==="
grep -n 'contextWindow\|maxTokens' "$TMPFILE"

echo ""
echo "=== Diff ==="
diff <(sudo cat "$CONFIG") "$TMPFILE" || true

echo ""
read -p "Apply? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted. Backup: $BACKUP"
  rm "$TMPFILE"
  exit 1
fi

sudo cp "$TMPFILE" "$CONFIG"
rm "$TMPFILE"
echo ""
echo "Applied. Now run:"
echo "  sudo systemctl restart openclaw-gateway"
echo ""
echo "Rollback: sudo cp $BACKUP $CONFIG && sudo systemctl restart openclaw-gateway"
