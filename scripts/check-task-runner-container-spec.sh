#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DOCKERFILE="${REPO_ROOT}/task-runner-container/Dockerfile"
ENTRYPOINT="${REPO_ROOT}/task-runner-container/entrypoint.sh"
BOOTSTRAP_CODEX="${REPO_ROOT}/task-runner-container/bootstrap/bootstrap-codex.sh"
BOOTSTRAP_CLAUDECODE="${REPO_ROOT}/task-runner-container/bootstrap/bootstrap-claudecode.sh"
PREPARE_WORKSPACE="${REPO_ROOT}/task-runner-container/bootstrap/prepare-workspace.sh"

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1" >&2
  exit 1
}

check_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing ${path#${REPO_ROOT}/}"
  pass "found ${path#${REPO_ROOT}/}"
}

check_file "${DOCKERFILE}"
check_file "${ENTRYPOINT}"
check_file "${BOOTSTRAP_CODEX}"
check_file "${BOOTSTRAP_CLAUDECODE}"
check_file "${PREPARE_WORKSPACE}"

bash -n "${ENTRYPOINT}"
pass "entrypoint shell syntax"

bash -n "${BOOTSTRAP_CODEX}"
pass "bootstrap-codex shell syntax"

bash -n "${BOOTSTRAP_CLAUDECODE}"
pass "bootstrap-claudecode shell syntax"

bash -n "${PREPARE_WORKSPACE}"
pass "prepare-workspace shell syntax"

python3 - "${DOCKERFILE}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
required_fragments = [
    "FROM ubuntu:24.04",
    "USER runner",
    "WORKDIR /workspace/repo",
    'ENTRYPOINT ["/usr/local/bin/task-runner-entrypoint"]',
]
missing = [fragment for fragment in required_fragments if fragment not in text]
if missing:
    for fragment in missing:
        print(f"missing required Dockerfile fragment: {fragment}", file=sys.stderr)
    raise SystemExit(1)

instructions = []
buffer = ""
for raw_line in text.splitlines():
    stripped = raw_line.strip()
    if not stripped or stripped.startswith("#"):
      continue
    if buffer:
      buffer += " " + stripped
    else:
      buffer = stripped
    if stripped.endswith("\\"):
      buffer = buffer[:-1].rstrip()
      continue
    instructions.append(buffer)
    buffer = ""

valid = {
    "FROM",
    "RUN",
    "ENV",
    "COPY",
    "USER",
    "WORKDIR",
    "ENTRYPOINT",
}
for idx, instruction in enumerate(instructions, start=1):
    match = re.match(r"^([A-Z]+)\b", instruction)
    if not match or match.group(1) not in valid:
        print(f"unrecognized Dockerfile instruction at logical line {idx}: {instruction}", file=sys.stderr)
        raise SystemExit(1)
PY
pass "dockerfile static syntax"

python3 "${REPO_ROOT}/scripts/validate-task-runner-exec-plan.py" --expect-valid \
  "${REPO_ROOT}/fixtures/task-runner-exec-plan/valid-readonly-workspace.json" \
  "${REPO_ROOT}/fixtures/task-runner-exec-plan/valid-dev-workspace.json" >/dev/null
pass "valid exec-plan fixtures"

python3 "${REPO_ROOT}/scripts/validate-task-runner-exec-plan.py" --expect-invalid \
  "${REPO_ROOT}/fixtures/task-runner-exec-plan/invalid-mount-env.json" \
  "${REPO_ROOT}/fixtures/task-runner-exec-plan/invalid-tool-contract.json" >/dev/null
pass "invalid exec-plan fixtures rejected"

python3 "${REPO_ROOT}/scripts/validate-task-runner-workspace-layout.py" --expect-valid \
  "${REPO_ROOT}/fixtures/task-runner-workspace-layout/valid-readonly-workspace.json" \
  "${REPO_ROOT}/fixtures/task-runner-workspace-layout/valid-dev-workspace.json" >/dev/null
pass "valid workspace-layout fixtures"

python3 "${REPO_ROOT}/scripts/validate-task-runner-workspace-layout.py" --expect-invalid \
  "${REPO_ROOT}/fixtures/task-runner-workspace-layout/invalid-mount-env.json" >/dev/null
pass "invalid workspace-layout fixtures rejected"

echo "PASS task-runner container spec checks completed"
