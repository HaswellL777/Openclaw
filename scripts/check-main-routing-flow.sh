#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$REPO_ROOT/.tmp"
TMP_ROOT="$(mktemp -d "$REPO_ROOT/.tmp/openclaw-main-routing.XXXXXX")"
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

expect_missing() {
  local file="$1"
  local label="$2"
  if [[ ! -e "$file" ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}

run_case() {
  local case_name="$1"
  local expected_build_exit="$2"
  local expected_route_exit="$3"
  local expected_decision="$4"
  local expected_submission_target="$5"
  local expected_envelope="$6"
  local summary_path="$REPO_ROOT/fixtures/task-runner-intake/$case_name/summary.json"
  local request_path="$REPO_ROOT/fixtures/task-runner-intake/$case_name/host-change-request.json"
  local case_dir="$TMP_ROOT/$case_name"
  local intake_dir="$case_dir/intake"
  local routing_dir="$case_dir/routing"
  local envelope_dir="$case_dir/envelopes"

  mkdir -p "$intake_dir" "$routing_dir" "$envelope_dir"

  set +e
  python3 "$REPO_ROOT/scripts/build-broker-ready-request.py" \
    --summary "$summary_path" \
    --host-change-request "$request_path" \
    --output-dir "$intake_dir"
  local build_status=$?
  set -e
  if [[ "$build_status" -ne "$expected_build_exit" ]]; then
    fail "$case_name build exit code expected $expected_build_exit got $build_status"
  fi
  pass "$case_name build exit code"

  python3 "$REPO_ROOT/scripts/validate-broker-ready-request.py" --expect-valid "$intake_dir/request.normalized.json" >/dev/null
  pass "$case_name normalized request validates"

  python3 "$REPO_ROOT/scripts/validate-task-runner-intake-report.py" --expect-valid "$intake_dir/intake-report.json" >/dev/null
  pass "$case_name intake report validates"

  set +e
  python3 "$REPO_ROOT/scripts/build-main-routing-decision.py" \
    --normalized-request "$intake_dir/request.normalized.json" \
    --intake-report "$intake_dir/intake-report.json" \
    --output "$routing_dir/main-routing-decision.json"
  local route_status=$?
  set -e
  if [[ "$route_status" -ne "$expected_route_exit" ]]; then
    fail "$case_name routing exit code expected $expected_route_exit got $route_status"
  fi
  pass "$case_name routing exit code"

  python3 "$REPO_ROOT/scripts/validate-main-routing-decision.py" --expect-valid "$routing_dir/main-routing-decision.json" >/dev/null
  pass "$case_name routing decision validates"

  expect_contains "$routing_dir/main-routing-decision.json" "\"decision\": \"$expected_decision\"" "$case_name decision"
  expect_contains "$routing_dir/main-routing-decision.json" "\"submission_target\": \"$expected_submission_target\"" "$case_name submission target"

  python3 "$REPO_ROOT/scripts/build-submission-envelopes.py" \
    --normalized-request "$intake_dir/request.normalized.json" \
    --intake-report "$intake_dir/intake-report.json" \
    --routing-decision "$routing_dir/main-routing-decision.json" \
    --output-dir "$envelope_dir"
  pass "$case_name envelope build"

  case "$expected_envelope" in
    broker)
      python3 "$REPO_ROOT/scripts/validate-broker-submission-envelope.py" --expect-valid "$envelope_dir/broker-submission-envelope.json" >/dev/null
      pass "$case_name broker envelope validates"
      expect_missing "$envelope_dir/operator-approval-envelope.json" "$case_name operator envelope absent"
      ;;
    approval)
      python3 "$REPO_ROOT/scripts/validate-operator-approval-envelope.py" --expect-valid "$envelope_dir/operator-approval-envelope.json" >/dev/null
      pass "$case_name operator approval envelope validates"
      expect_missing "$envelope_dir/broker-submission-envelope.json" "$case_name broker envelope absent"
      ;;
    none)
      expect_missing "$envelope_dir/broker-submission-envelope.json" "$case_name broker envelope absent"
      expect_missing "$envelope_dir/operator-approval-envelope.json" "$case_name operator envelope absent"
      ;;
    *)
      fail "$case_name unknown expected envelope type $expected_envelope"
      ;;
  esac
}

python3 "$REPO_ROOT/scripts/validate-task-runner-summary.py" --expect-valid \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-readonly/summary.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-host-affecting/summary.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-broker-submission-candidate/summary.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/invalid-illegal-request/summary.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/invalid-forbidden-command/summary.json" >/dev/null
pass "routing source summary fixtures validate"

python3 "$REPO_ROOT/scripts/validate-host-change-request.py" --expect-valid \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-readonly/host-change-request.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-host-affecting/host-change-request.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/valid-broker-submission-candidate/host-change-request.json" >/dev/null
pass "routing source accepted host-change fixtures validate"

python3 "$REPO_ROOT/scripts/validate-host-change-request.py" --expect-invalid \
  "$REPO_ROOT/fixtures/task-runner-intake/invalid-illegal-request/host-change-request.json" \
  "$REPO_ROOT/fixtures/task-runner-intake/invalid-forbidden-command/host-change-request.json" >/dev/null
pass "routing source invalid host-change fixtures are rejected"

python3 "$REPO_ROOT/scripts/validate-main-routing-decision.py" --expect-valid \
  "$REPO_ROOT/fixtures/main-routing/valid-readonly/main-routing-decision.json" \
  "$REPO_ROOT/fixtures/main-routing/valid-host-affecting/main-routing-decision.json" \
  "$REPO_ROOT/fixtures/main-routing/invalid-forbidden-command/main-routing-decision.json" \
  "$REPO_ROOT/fixtures/main-routing/valid-broker-submission-candidate/main-routing-decision.json" >/dev/null
pass "committed routing decision fixtures validate"

python3 "$REPO_ROOT/scripts/validate-broker-submission-envelope.py" --expect-valid \
  "$REPO_ROOT/fixtures/main-routing/valid-readonly/broker-submission-envelope.json" \
  "$REPO_ROOT/fixtures/main-routing/valid-broker-submission-candidate/broker-submission-envelope.json" >/dev/null
pass "committed broker submission envelope fixtures validate"

python3 "$REPO_ROOT/scripts/validate-operator-approval-envelope.py" --expect-valid \
  "$REPO_ROOT/fixtures/main-routing/valid-host-affecting/operator-approval-envelope.json" >/dev/null
pass "committed operator approval envelope fixtures validate"

run_case "valid-readonly" 0 0 "BROKER_SUBMISSION_CANDIDATE" "broker_submission_envelope" "broker"
run_case "valid-host-affecting" 0 0 "REQUIRES_OPERATOR_APPROVAL" "operator_approval_envelope" "approval"
run_case "invalid-forbidden-command" 1 1 "LOCAL_REFUSE" "none" "none"
run_case "valid-broker-submission-candidate" 0 0 "BROKER_SUBMISSION_CANDIDATE" "broker_submission_envelope" "broker"

expect_contains \
  "$TMP_ROOT/invalid-forbidden-command/routing/main-routing-decision.json" \
  "imperative command keys" \
  "forbidden command refusal reason preserved"

echo "PASS main routing flow checks completed"
