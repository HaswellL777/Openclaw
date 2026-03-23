#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$REPO_ROOT/.tmp"
TMP_ROOT="$(mktemp -d "$REPO_ROOT/.tmp/openclaw-phase3-control-plane.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1" >&2
  exit 1
}

diff_case() {
  local case_name="$1"
  local run_id
  run_id="$(python3 - "$REPO_ROOT/fixtures/task-runner-intake/$case_name/summary.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
print(data["run_id"])
PY
)"
  local generated_dir="$TMP_ROOT/generated/$run_id"
  local golden_dir="$REPO_ROOT/fixtures/control-plane-replay/$case_name"

  [[ -d "$golden_dir" ]] || fail "$case_name golden directory missing"
  diff -ru "$golden_dir" "$generated_dir" >/dev/null || fail "$case_name replay output matches golden"
  pass "$case_name replay output matches golden"
}

bash "$REPO_ROOT/scripts/check-main-routing-flow.sh" >/dev/null
pass "main routing flow remains green"

for case_name in \
  valid-readonly \
  valid-host-affecting \
  invalid-illegal-request \
  invalid-forbidden-command \
  valid-broker-submission-candidate
do
  bash "$REPO_ROOT/scripts/check-phase3-control-plane-artifact-layout.sh" \
    --run-dir "$REPO_ROOT/fixtures/control-plane-replay/$case_name" \
    --case-name "$case_name" >/dev/null
done
pass "committed replay golden fixtures validate"

bash "$REPO_ROOT/scripts/check-phase3-control-plane-artifact-layout.sh" \
  --output-root "$TMP_ROOT/generated" >/dev/null
pass "single-entry replay harness layout checks remain green"

for case_name in \
  valid-readonly \
  valid-host-affecting \
  invalid-illegal-request \
  invalid-forbidden-command \
  valid-broker-submission-candidate
do
  diff_case "$case_name"
done

echo "PASS phase3 control-plane dry-run checks completed"
