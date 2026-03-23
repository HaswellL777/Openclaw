#!/usr/bin/env bash
set -euo pipefail

: "${RUNNER_TOOL:?RUNNER_TOOL must be set to codex or claudecode}"
: "${RUNNER_MODE:?RUNNER_MODE must be set}"
: "${WORKSPACE_MODE:?WORKSPACE_MODE must be set}"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "task-runner entrypoint must not run as root" >&2
  exit 1
fi

case "${RUNNER_TOOL}" in
  codex)
    bootstrap="/usr/local/bin/bootstrap-codex"
    ;;
  claudecode)
    bootstrap="/usr/local/bin/bootstrap-claudecode"
    ;;
  *)
    echo "unsupported RUNNER_TOOL: ${RUNNER_TOOL}" >&2
    exit 64
    ;;
esac

/usr/local/bin/prepare-workspace
exec "${bootstrap}" "$@"
