#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/check-phase3-control-plane-artifact-layout.sh [--output-root DIR]
  scripts/check-phase3-control-plane-artifact-layout.sh --run-dir DIR --case-name CASE

Without arguments, the script replays the default fixture cases through the single-entry
control-plane harness and validates the resulting artifact layout.
EOF
}

OUTPUT_ROOT=""
RUN_DIR=""
CASE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-root)
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --case-name)
      CASE_NAME="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ -n "$RUN_DIR" && -z "$CASE_NAME" ]]; then
  fail "--run-dir requires --case-name"
fi

if [[ -n "$RUN_DIR" && -n "$OUTPUT_ROOT" ]]; then
  fail "--run-dir and --output-root cannot be combined"
fi

if [[ -z "$OUTPUT_ROOT" && -z "$RUN_DIR" ]]; then
  mkdir -p "$REPO_ROOT/.tmp"
  OUTPUT_ROOT="$(mktemp -d "$REPO_ROOT/.tmp/openclaw-phase3-layout.XXXXXX")"
  trap 'rm -rf "$OUTPUT_ROOT"' EXIT
fi

run_id_for_case() {
  local case_name="$1"
  python3 - "$REPO_ROOT/fixtures/task-runner-intake/$case_name/summary.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
print(data["run_id"])
PY
}

assert_case_layout() {
  local run_dir="$1"
  local case_name="$2"
  local expected_decision=""
  local expected_dispatch_status=""
  local -a required_files=()
  local -a missing_files=()

  case "$case_name" in
    valid-readonly|valid-broker-submission-candidate)
      expected_decision="BROKER_SUBMISSION_CANDIDATE"
      expected_dispatch_status="broker_ready"
      required_files=(
        summary.json
        request.normalized.json
        intake-report.json
        routing-decision.json
        broker-submission-envelope.json
        broker-review-bundle.json
        dispatch-intent-ledger.json
        artifact-manifest.json
      )
      missing_files=(
        operator-approval-envelope.json
        operator-review-bundle.json
      )
      ;;
    valid-host-affecting)
      expected_decision="REQUIRES_OPERATOR_APPROVAL"
      expected_dispatch_status="operator_approval_required"
      required_files=(
        summary.json
        request.normalized.json
        intake-report.json
        routing-decision.json
        operator-approval-envelope.json
        operator-review-bundle.json
        dispatch-intent-ledger.json
        artifact-manifest.json
      )
      missing_files=(
        broker-submission-envelope.json
        broker-review-bundle.json
      )
      ;;
    invalid-illegal-request|invalid-forbidden-command)
      expected_decision="LOCAL_REFUSE"
      expected_dispatch_status="refused"
      required_files=(
        summary.json
        request.normalized.json
        intake-report.json
        routing-decision.json
        dispatch-intent-ledger.json
        artifact-manifest.json
      )
      missing_files=(
        broker-submission-envelope.json
        operator-approval-envelope.json
        broker-review-bundle.json
        operator-review-bundle.json
      )
      ;;
    *)
      fail "unknown case name: $case_name"
      ;;
  esac

  python3 "$REPO_ROOT/scripts/validate-control-plane-artifact-manifest.py" --expect-valid \
    "$run_dir/artifact-manifest.json" >/dev/null
  pass "$case_name manifest validates"

  for file_name in "${required_files[@]}"; do
    [[ -f "$run_dir/$file_name" ]] || fail "$case_name required artifact missing: $file_name"
    pass "$case_name required artifact present: $file_name"
  done

  for file_name in "${missing_files[@]}"; do
    [[ ! -e "$run_dir/$file_name" ]] || fail "$case_name forbidden artifact present: $file_name"
    pass "$case_name forbidden artifact absent: $file_name"
  done

  python3 - "$run_dir" "$expected_decision" "$expected_dispatch_status" <<'PY'
import json, sys
from pathlib import Path
run_dir = Path(sys.argv[1])
expected_decision = sys.argv[2]
expected_dispatch_status = sys.argv[3]

routing = json.loads((run_dir / "routing-decision.json").read_text(encoding="utf-8"))
ledger = json.loads((run_dir / "dispatch-intent-ledger.json").read_text(encoding="utf-8"))
manifest = json.loads((run_dir / "artifact-manifest.json").read_text(encoding="utf-8"))

assert routing["decision"] == expected_decision
assert routing["dispatch_status"] == expected_dispatch_status
assert ledger["decision"] == expected_decision
assert ledger["dispatch_status"] == expected_dispatch_status
assert ledger["dispatch_performed"] is False
assert ledger["approval_granted"] is False
assert ledger["runtime_changed"] is False
assert ledger["operator_command_blocks_present"] is False
assert manifest["route_summary"]["decision"] == expected_decision
assert manifest["route_summary"]["dispatch_status"] == expected_dispatch_status
boundary = manifest["boundary_assertions"]
assert boundary["repo_side_only"] is True
assert boundary["live_side_publish_performed"] is False
assert boundary["broker_dispatch_performed"] is False
assert boundary["openclaw_runtime_modified"] is False
assert boundary["operator_command_blocks_present"] is False
PY
  pass "$case_name decision and boundary assertions match expected route"
}

replay_case() {
  local case_name="$1"
  bash "$REPO_ROOT/scripts/run-phase3-control-plane-replay.sh" \
    --fixture-case "$case_name" \
    --output-root "$OUTPUT_ROOT" \
    --force >/dev/null
  local run_id
  run_id="$(run_id_for_case "$case_name")"
  assert_case_layout "$OUTPUT_ROOT/$run_id" "$case_name"
}

if [[ -n "$RUN_DIR" ]]; then
  assert_case_layout "$RUN_DIR" "$CASE_NAME"
  echo "PASS phase3 control-plane artifact layout checks completed"
  exit 0
fi

for case_name in \
  valid-readonly \
  valid-host-affecting \
  invalid-illegal-request \
  invalid-forbidden-command \
  valid-broker-submission-candidate
do
  replay_case "$case_name"
done

echo "PASS phase3 control-plane artifact layout checks completed"
