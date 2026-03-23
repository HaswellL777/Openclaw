#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$REPO_ROOT/.tmp"
TMP_ROOT="$(mktemp -d "$REPO_ROOT/.tmp/openclaw-phase3-dispatch-adapter.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1" >&2
  exit 1
}

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

assert_adapter_case() {
  local run_dir="$1"
  local case_name="$2"
  local expected_status=""
  local expected_blocked_reason=""
  local expected_dispatch_count=""

  case "$case_name" in
    valid-readonly)
      expected_status="broker_candidate_recorded"
      expected_blocked_reason="null_transport_record_only"
      expected_dispatch_count="3"
      ;;
    valid-broker-submission-candidate)
      expected_status="broker_candidate_recorded"
      expected_blocked_reason="null_transport_record_only"
      expected_dispatch_count="2"
      ;;
    valid-host-affecting)
      expected_status="approval_pending_recorded"
      expected_blocked_reason="operator_approval_required"
      expected_dispatch_count="6"
      ;;
    invalid-illegal-request)
      expected_status="refusal_recorded"
      expected_blocked_reason="host-affecting requested_host_ops require requires_operator_approval=true"
      expected_dispatch_count="0"
      ;;
    invalid-forbidden-command)
      expected_status="refusal_recorded"
      expected_blocked_reason="must not contain imperative command keys"
      expected_dispatch_count="0"
      ;;
    *)
      fail "unknown case name: $case_name"
      ;;
  esac

  python3 "$REPO_ROOT/scripts/validate-dispatch-adapter-result.py" --expect-valid \
    "$run_dir/dispatch-adapter-result.json" >/dev/null
  pass "$case_name dispatch adapter result validates"

  python3 - "$run_dir/dispatch-adapter-result.json" "$expected_status" "$expected_blocked_reason" "$expected_dispatch_count" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
expected_status = sys.argv[2]
expected_blocked_reason = sys.argv[3]
expected_dispatch_count = int(sys.argv[4])

data = json.loads(path.read_text(encoding="utf-8"))
assert data["adapter_mode"] == "dry_run"
assert data["transport"] == "null_transport"
assert data["recording_mode"] == "record_only"
assert data["adapter_status"] == expected_status
assert expected_blocked_reason in data["blocked_reason"]
assert data["dispatch_candidate_count"] == expected_dispatch_count
assert len(data["dispatch_intents"]) == expected_dispatch_count
assert data["dispatch_attempted"] is False
assert data["broker_dispatch_performed"] is False
assert data["approval_granted"] is False
assert data["runtime_changed"] is False
assert data["operator_command_blocks_present"] is False
assert data["boundary_carry_forward"]["repo_side_only"] is True
assert data["boundary_carry_forward"]["broker_dispatch_performed"] is False
assert data["boundary_carry_forward"]["openclaw_runtime_modified"] is False
assert data["source_artifacts"]["dispatch_intent_ledger_path"] == "dispatch-intent-ledger.json"
PY
  pass "$case_name dispatch adapter boundary invariants match"
}

for case_name in \
  valid-readonly \
  valid-host-affecting \
  invalid-illegal-request \
  invalid-forbidden-command \
  valid-broker-submission-candidate
do
  python3 "$REPO_ROOT/scripts/run-phase3-control-plane-replay.py" \
    --fixture-case "$case_name" \
    --output-root "$TMP_ROOT/generated" \
    --force >/dev/null

  run_id="$(run_id_for_case "$case_name")"
  generated_dir="$TMP_ROOT/generated/$run_id"
  golden_dir="$REPO_ROOT/fixtures/control-plane-replay/$case_name"

  assert_adapter_case "$generated_dir" "$case_name"
  diff -u "$golden_dir/dispatch-adapter-result.json" "$generated_dir/dispatch-adapter-result.json" >/dev/null \
    || fail "$case_name dispatch-adapter-result matches golden"
  pass "$case_name dispatch-adapter-result matches golden"
done

echo "PASS phase3 dispatch adapter flow checks completed"
