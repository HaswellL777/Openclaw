#!/usr/bin/env bash
set -euo pipefail

SRC="/srv/openclaw-control/docs/host-sop.md"
DST_DEV="$HOME/projects/openclaw-dev/docs/host-sop.md"
META_DIR="$HOME/projects/openclaw-dev/docs/.meta"
LOG_DIR="$HOME/projects/openclaw-dev/logs"
META_FILE="$META_DIR/host-sop.publish.json"

STAMP="$(date -Iseconds)"

mkdir -p "$META_DIR" "$LOG_DIR"

if [ ! -f "$SRC" ]; then
  echo "ERROR: source missing: $SRC" >&2
  exit 1
fi

if [ ! -s "$SRC" ]; then
  echo "ERROR: source empty: $SRC" >&2
  exit 1
fi

SRC_SHA="$(sha256sum "$SRC" | awk '{print $1}')"
DST_SHA=""

if [ -f "$DST_DEV" ] && [ -s "$DST_DEV" ]; then
  DST_SHA="$(sha256sum "$DST_DEV" | awk '{print $1}')"
fi

write_meta() {
  local action="$1"
  cat > "$META_FILE" <<JSON
{
  "published_at": "$STAMP",
  "source": "$SRC",
  "destination": "$DST_DEV",
  "sha256": "$SRC_SHA",
  "action": "$action"
}
JSON
}

if [ "$SRC_SHA" = "$DST_SHA" ] && [ -n "$DST_SHA" ]; then
  write_meta "skip"
  echo "[$STAMP] SKIP unchanged sha256=$SRC_SHA dst=$DST_DEV" | tee -a "$LOG_DIR/publish-sop.log"
  exit 0
fi

TMP="$(mktemp)"
cp "$SRC" "$TMP"
install -m 0644 "$TMP" "$DST_DEV"
rm -f "$TMP"

write_meta "publish"
echo "[$STAMP] PUBLISH sha256=$SRC_SHA src=$SRC dst=$DST_DEV" | tee -a "$LOG_DIR/publish-sop.log"
