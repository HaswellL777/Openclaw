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
  local expected_review="$4"
  local summary_path="$REPO_ROOT/fixtures/task-runner-intake/$case_name/summary.json"
  local request_path="$REPO_ROOT/fixtures/task-runner-intake/$case_name/host-change-request.json"
  local case_dir="$TMP_ROOT/$case_name"
  local intake_dir="$case_dir/intake"
  local routing_dir="$case_dir/routing"
  local submission_dir="$case_dir/submission"
  local review_dir="$case_dir/review"

  mkdir -p "$intake_dir" "$routing_dir" "$submission_dir" "$review_dir"

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

  python3 "$REPO_ROOT/scripts/build-submission-envelopes.py" \
    --normalized-request "$intake_dir/request.normalized.json" \
    --intake-report "$intake_dir/intake-report.json" \
    --routing-decision "$routing_dir/main-routing-decision.json" \
    --output-dir "$submission_dir"
  pass "$case_name submission envelope build"

  python3 "$REPO_ROOT/scripts/build-review-bundles.py" \
    --normalized-request "$intake_dir/request.normalized.json" \
    --intake-report "$intake_dir/intake-report.json" \
    --routing-decision "$routing_dir/main-routing-decision.json" \
    --submission-dir "$submission_dir" \
    --output-dir "$review_dir"
  pass "$case_name review bundle build"

  python3 "$REPO_ROOT/scripts/build-dispatch-intent-ledger.py" \
    --normalized-request "$intake_dir/request.normalized.json" \
    --intake-report "$intake_dir/intake-report.json" \
    --routing-decision "$routing_dir/main-routing-decision.json" \
    --submission-dir "$submission_dir" \
    --review-dir "$review_dir" \
    --output "$case_dir/dispatch-intent-ledger.json"
  pass "$case_name dispatch intent ledger build"

  python3 "$REPO_ROOT/scripts/validate-dispatch-intent-ledger.py" --expect-valid "$case_dir/dispatch-intent-ledger.json" >/dev/null
  pass "$case_name dispatch intent ledger validates"

  expect_contains "$case_dir/dispatch-intent-ledger.json" "\"dispatch_performed\": false" "$case_name dispatch_performed false"
  expect_contains "$case_dir/dispatch-intent-ledger.json" "\"approval_granted\": false" "$case_name approval_granted false"
  expect_contains "$case_dir/dispatch-intent-ledger.json" "\"runtime_changed\": false" "$case_name runtime_changed false"
  expect_contains "$case_dir/dispatch-intent-ledger.json" "\"operator_command_blocks_present\": false" "$case_name operator_command_blocks_present false"

  case "$expected_review" in
    broker)
      python3 "$REPO_ROOT/scripts/validate-broker-review-bundle.py" --expect-valid "$review_dir/broker-review-bundle.json" >/dev/null
      pass "$case_name broker review bundle validates"
      expect_missing "$review_dir/operator-review-bundle.json" "$case_name operator review bundle absent"
      expect_contains "$case_dir/dispatch-intent-ledger.json" "\"review_bundle_type\": \"BROKER_REVIEW_BUNDLE\"" "$case_name ledger review bundle type"
      ;;
    operator)
      python3 "$REPO_ROOT/scripts/validate-operator-review-bundle.py" --expect-valid "$review_dir/operator-review-bundle.json" >/dev/null
      pass "$case_name operator review bundle validates"
      expect_missing "$review_dir/broker-review-bundle.json" "$case_name broker review bundle absent"
      expect_contains "$case_dir/dispatch-intent-ledger.json" "\"review_bundle_type\": \"OPERATOR_REVIEW_BUNDLE\"" "$case_name ledger review bundle type"
      expect_contains "$case_dir/dispatch-intent-ledger.json" "\"approval_required_reason\":" "$case_name approval_required_reason preserved"
      ;;
    none)
      expect_missing "$review_dir/broker-review-bundle.json" "$case_name broker review bundle absent"
      expect_missing "$review_dir/operator-review-bundle.json" "$case_name operator review bundle absent"
      expect_contains "$case_dir/dispatch-intent-ledger.json" "\"review_bundle\": \"not_applicable\"" "$case_name review bundle not applicable"
      expect_contains "$case_dir/dispatch-intent-ledger.json" "\"refusal_reason\":" "$case_name refusal reason preserved"
      ;;
    *)
      fail "$case_name unknown expected review kind $expected_review"
      ;;
  esac
}

bash "$REPO_ROOT/scripts/check-main-routing-flow.sh" >/dev/null
pass "main routing flow remains green"

python3 "$REPO_ROOT/scripts/validate-broker-review-bundle.py" --expect-valid \
  "$REPO_ROOT/fixtures/main-routing/valid-readonly/broker-review-bundle.json" \
  "$REPO_ROOT/fixtures/main-routing/valid-broker-submission-candidate/broker-review-bundle.json" >/dev/null
pass "committed broker review bundle fixtures validate"

python3 "$REPO_ROOT/scripts/validate-operator-review-bundle.py" --expect-valid \
  "$REPO_ROOT/fixtures/main-routing/valid-host-affecting/operator-review-bundle.json" >/dev/null
pass "committed operator review bundle fixtures validate"

python3 "$REPO_ROOT/scripts/validate-dispatch-intent-ledger.py" --expect-valid \
  "$REPO_ROOT/fixtures/main-routing/valid-readonly/dispatch-intent-ledger.json" \
  "$REPO_ROOT/fixtures/main-routing/valid-host-affecting/dispatch-intent-ledger.json" \
  "$REPO_ROOT/fixtures/main-routing/invalid-forbidden-command/dispatch-intent-ledger.json" \
  "$REPO_ROOT/fixtures/main-routing/valid-broker-submission-candidate/dispatch-intent-ledger.json" >/dev/null
pass "committed dispatch intent ledger fixtures validate"

run_case "valid-readonly" 0 0 "broker"
run_case "valid-host-affecting" 0 0 "operator"
run_case "invalid-forbidden-command" 1 1 "none"
run_case "valid-broker-submission-candidate" 0 0 "broker"

echo "PASS phase3 control-plane dry-run checks completed"
