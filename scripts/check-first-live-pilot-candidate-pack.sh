#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

pass() {
  echo "PASS $1"
}

bash "$REPO_ROOT/scripts/check-phase3-control-plane-dry-run.sh" >/dev/null
pass "phase3 control-plane dry-run assets remain green"

bash "$REPO_ROOT/scripts/check-task-runner-container-spec.sh" >/dev/null
pass "task-runner container scaffold remains green"

bash "$REPO_ROOT/scripts/check-workspace-task-runner-template.sh" >/dev/null
pass "task-runner workspace template remains green"

bash "$REPO_ROOT/scripts/check-task-runner-handoff-pack.sh" >/dev/null
pass "task-runner handoff pack assets remain green"

python3 "$REPO_ROOT/scripts/build-first-live-pilot-candidate-pack.py" --force >/dev/null
pass "first-live-pilot candidate pack rebuilt"

python3 "$REPO_ROOT/scripts/validate-first-live-pilot-candidate-pack.py" --expect-valid >/dev/null
pass "first-live-pilot candidate pack validates"

echo "PASS first-live-pilot candidate pack checks completed"
