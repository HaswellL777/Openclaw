#!/usr/bin/env bash
set -euo pipefail

SRC="/srv/openclaw-control/docs/host-sop.md"
DST="$HOME/projects/openclaw-dev/workspace-main/control/SOP.md"
HASHFILE="$HOME/projects/openclaw-dev/workspace-main/control/state/last-sop-hash.txt"

[ -s "$SRC" ] || { echo "ERROR: source SOP missing or empty: $SRC" >&2; exit 1; }

mkdir -p "$(dirname "$DST")" "$(dirname "$HASHFILE")"

install -m 0644 "$SRC" "$DST"
sha256sum "$SRC" | awk '{print $1}' > "$HASHFILE"

echo "Published SOP to $DST"
echo "Hash recorded in $HASHFILE"
