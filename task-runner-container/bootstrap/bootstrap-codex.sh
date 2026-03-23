#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "codex bootstrap must not run as root" >&2
  exit 1
fi

if [[ "${RUNNER_MODE:-}" != "non_interactive" ]]; then
  echo "codex bootstrap requires RUNNER_MODE=non_interactive" >&2
  exit 64
fi

: "${TASK_REPO_PATH:?TASK_REPO_PATH must be set}"
cd "${TASK_REPO_PATH}"

if [[ "$#" -eq 0 ]]; then
  echo "codex bootstrap expects the future runtime to provide a non-interactive command argv" >&2
  exit 64
fi

exec "$@"
