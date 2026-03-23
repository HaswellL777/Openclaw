#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "missing required environment variable: ${name}" >&2
    exit 64
  fi
}

ensure_workspace_path() {
  local path="$1"
  case "${path}" in
    /workspace|/workspace/*)
      ;;
    *)
      echo "path must stay inside /workspace: ${path}" >&2
      exit 64
      ;;
  esac
}

require_env TASK_REPO_PATH
require_env TASK_INPUTS_PATH
require_env TASK_OUTPUTS_PATH
require_env ARTIFACT_EXPORT_PATH
require_env WORKSPACE_MODE

for workspace_path in \
  "${TASK_REPO_PATH}" \
  "${TASK_INPUTS_PATH}" \
  "${TASK_OUTPUTS_PATH}" \
  "${ARTIFACT_EXPORT_PATH}"; do
  ensure_workspace_path "${workspace_path}"
done

mkdir -p "${TASK_INPUTS_PATH}" "${TASK_OUTPUTS_PATH}" "${ARTIFACT_EXPORT_PATH}"

if [[ ! -d "${TASK_REPO_PATH}" ]]; then
  echo "task repo path is missing: ${TASK_REPO_PATH}" >&2
  exit 66
fi

case "${WORKSPACE_MODE}" in
  readonly|dev)
    ;;
  *)
    echo "unsupported WORKSPACE_MODE: ${WORKSPACE_MODE}" >&2
    exit 64
    ;;
esac

if [[ "${WORKSPACE_MODE}" == "readonly" && -w "${TASK_REPO_PATH}" ]]; then
  echo "readonly workspace mode expects repo mount to stay read-only" >&2
  exit 65
fi
