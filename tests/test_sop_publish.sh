#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/publish-sop.sh"
SRC="/srv/openclaw-control/docs/host-sop.md"
DST="$REPO_ROOT/docs/host-sop.md"
META="$REPO_ROOT/docs/.meta/host-sop.publish.json"
LOG="$REPO_ROOT/logs/publish-sop.log"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

[ -x "$SCRIPT" ] || fail "publish script missing or not executable: $SCRIPT"
[ -s "$SRC" ] || fail "authoritative SOP missing or empty: $SRC"

mkdir -p "$REPO_ROOT/docs/.meta" "$REPO_ROOT/logs"

before_src_sha="$(sha256sum "$SRC" | awk '{print $1}')"
before_dst_sha=""
if [ -s "$DST" ]; then
  before_dst_sha="$(sha256sum "$DST" | awk '{print $1}')"
fi

bash "$SCRIPT"

[ -s "$DST" ] || fail "published dev SOP missing or empty: $DST"
[ -s "$META" ] || fail "publish metadata missing or empty: $META"
[ -s "$LOG" ] || fail "publish log missing or empty: $LOG"

after_dst_sha="$(sha256sum "$DST" | awk '{print $1}')"
[ "$before_src_sha" = "$after_dst_sha" ] || fail "destination SHA mismatch after publish"

meta_sha="$(python3 - <<'PY' "$META"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
print(data["sha256"])
PY
)"
[ "$meta_sha" = "$before_src_sha" ] || fail "metadata SHA mismatch"

grep -Eq 'PUBLISH|SKIP unchanged' "$LOG" || fail "publish log does not contain expected status"

echo "== summary =="
echo "src_sha=$before_src_sha"
echo "dst_sha=$after_dst_sha"
echo "meta=$META"
echo "log=$LOG"

pass "publish-sop chain is consistent"
