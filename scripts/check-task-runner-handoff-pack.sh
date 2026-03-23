#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

readonly_case="$TMP_DIR/readonly"
approval_case="$TMP_DIR/requires-approval"

python3 "$REPO_ROOT/scripts/build-task-runner-handoff-pack.py" \
  --reviewed-task "$REPO_ROOT/fixtures/control-plane-replay/valid-readonly/broker-review-bundle.json" \
  --summary "$REPO_ROOT/fixtures/control-plane-replay/valid-readonly/summary.json" \
  --output-root "$readonly_case"

python3 "$REPO_ROOT/scripts/validate-task-runner-handoff-manifest.py" \
  "$readonly_case/tasks/task-intake-readonly/handoff-manifest.json"

python3 "$REPO_ROOT/scripts/build-task-runner-handoff-pack.py" \
  --reviewed-task "$REPO_ROOT/fixtures/control-plane-replay/valid-host-affecting/operator-review-bundle.json" \
  --summary "$REPO_ROOT/fixtures/control-plane-replay/valid-host-affecting/summary.json" \
  --output-root "$approval_case"

python3 "$REPO_ROOT/scripts/validate-task-runner-handoff-manifest.py" \
  "$approval_case/tasks/task-intake-host-affecting/handoff-manifest.json"

if python3 "$REPO_ROOT/scripts/build-task-runner-handoff-pack.py" \
  --reviewed-task "$REPO_ROOT/fixtures/task-runner-handoff-pack/invalid-reviewed-task/operator-review-bundle.invalid.json" \
  --summary "$REPO_ROOT/fixtures/control-plane-replay/valid-host-affecting/summary.json" \
  --output-root "$TMP_DIR/invalid" \
  >/dev/null 2>&1; then
  echo "expected invalid reviewed task to be rejected"
  exit 1
fi

python3 "$REPO_ROOT/scripts/validate-task-runner-handoff-manifest.py" \
  "$REPO_ROOT/fixtures/task-runner-handoff-pack/valid-readonly/tasks/task-intake-readonly/handoff-manifest.json"

python3 "$REPO_ROOT/scripts/validate-task-runner-handoff-manifest.py" \
  "$REPO_ROOT/fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/handoff-manifest.json"

echo "PASS task-runner handoff pack checks"
