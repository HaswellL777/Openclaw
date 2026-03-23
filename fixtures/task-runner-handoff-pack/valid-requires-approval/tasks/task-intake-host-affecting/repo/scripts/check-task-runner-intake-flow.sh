#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_ROOT="$(mktemp -d /tmp/openclaw-task-runner-intake.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1" >&2
  exit 1
}

expect_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -F -q "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

run_case() {
  local case_name="$1"
  local expected_exit="$2"
  local expected_intake_status="$3"
  local expected_dispatch_scope="$4"
  local expected_dispatch_status="$5"
  local expected_approval="$6"
  local summary_path="$REPO_ROOT/fixtures/task-runner-intake/$case_name/summary.json"
  local request_path="$REPO_ROOT/fixtures/task-runner-intake/$case_name/host-change-request.json"
  local output_dir="$TMP_ROOT/$case_name"

  mkdir -p "$output_dir"

  set +e
  python3 "$REPO_ROOT/scripts/build-broker-ready-request.py" \
    --summary "$summary_path" \
    --host-change-request "$request_path" \
    --output-dir "$output_dir"
  local status=$?
  set -e

  if [[ "$status" -ne "$expected_exit" ]]; then
    fail "$case_name build exit code expected $expected_exit got $status"
  fi
  pass "$case_name build exit code"

  python3 "$REPO_ROOT/scripts/validate-broker-ready-request.py" --expect-valid "$output_dir/request.normalized.json" >/dev/null
  pass "$case_name normalized request validates"

  python3 "$REPO_ROOT/scripts/validate-task-runner-intake-report.py" --expect-valid "$output_dir/intake-report.json" >/dev/null
  pass "$case_name intake report validates"

  expect_contains "$output_dir/request.normalized.json" "\"intake_status\": \"$expected_intake_status\"" "$case_name normalized intake_status"
  expect_contains "$output_dir/request.normalized.json" "\"dispatch_scope\": \"$expected_dispatch_scope\"" "$case_name normalized dispatch_scope"
  expect_contains "$output_dir/request.normalized.json" "\"dispatch_status\": \"$expected_dispatch_status\"" "$case_name normalized dispatch_status"
  expect_contains "$output_dir/request.normalized.json" "\"requires_operator_approval\": $expected_approval" "$case_name normalized requires_operator_approval"
  expect_contains "$output_dir/intake-report.json" "\"status\": \"$expected_intake_status\"" "$case_name report status"
  expect_contains "$output_dir/intake-report.json" "\"dispatch_status\": \"$expected_dispatch_status\"" "$case_name report dispatch_status"
}

python3 "$REPO_ROOT/scripts/validate-task-runner-summary.py" --expect-valid \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-readonly/summary.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-host-affecting/summary.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/invalid-illegal-request/summary.json" >/dev/null
pass "intake summary fixtures validate"

python3 "$REPO_ROOT/scripts/validate-host-change-request.py" --expect-valid \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-readonly/host-change-request.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-host-affecting/host-change-request.json" >/dev/null
pass "accepted intake host-change fixtures validate"

python3 "$REPO_ROOT/scripts/validate-host-change-request.py" --expect-invalid \
  "$REPO_ROOT/fixtures/task-runner-intake/invalid-illegal-request/host-change-request.json" >/dev/null
pass "illegal intake host-change fixture is rejected"

run_case "valid-readonly" 0 "accepted" "readonly" "broker_ready" "false"
run_case "valid-host-affecting" 0 "accepted" "host_affecting" "operator_approval_required" "true"
run_case "invalid-illegal-request" 1 "refused" "host_affecting" "refused" "false"

expect_contains \
  "$TMP_ROOT/invalid-illegal-request/request.normalized.json" \
  "host-affecting requested_host_ops require requires_operator_approval=true" \
  "illegal intake refusal reason preserved"

echo "PASS task-runner intake flow checks completed"
