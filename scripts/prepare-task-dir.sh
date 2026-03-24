#!/usr/bin/env bash
# prepare-task-dir.sh — Create per-task directory structure for a task-runner session.
#
# Called by main agent (or orchestration script) BEFORE sessions_spawn("task-runner").
# Creates the task directory tree under the workspace-task-runner tasks/ directory,
# optionally clones a repo, and returns the task-id for use in spawn context.
#
# Usage:
#   sudo -u openclaw bash scripts/prepare-task-dir.sh \
#     --task-id <id> \
#     [--clone-url <url>] \
#     [--clone-ref <branch-or-tag>]
#
# Output (stdout, last line):
#   TASK_DIR=/var/lib/openclaw/.openclaw/workspace-task-runner/tasks/<task-id>

set -euo pipefail

WORKSPACE_TASK_RUNNER="/var/lib/openclaw/.openclaw/workspace-task-runner"
TASK_ID=""
CLONE_URL=""
CLONE_REF=""

usage() {
  echo "Usage: $0 --task-id <id> [--clone-url <url>] [--clone-ref <ref>]" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) TASK_ID="$2"; shift 2 ;;
    --clone-url) CLONE_URL="$2"; shift 2 ;;
    --clone-ref) CLONE_REF="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ -z "$TASK_ID" ]]; then
  # Auto-generate task ID if not provided
  TASK_ID="task-$(date +%Y%m%d-%H%M%S)-$(head -c 4 /dev/urandom | xxd -p)"
fi

# Validate task-id: alphanumeric, dashes, underscores only
if [[ ! "$TASK_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Invalid task-id: must be alphanumeric with dashes/underscores" >&2
  exit 65
fi

TASK_DIR="${WORKSPACE_TASK_RUNNER}/tasks/${TASK_ID}"

if [[ -d "$TASK_DIR" ]]; then
  echo "Task directory already exists: $TASK_DIR" >&2
  exit 66
fi

# Create task directory tree per design-v3 §5.2.4
mkdir -p "${TASK_DIR}/repo"
mkdir -p "${TASK_DIR}/outputs"

# Clone repo if URL provided
if [[ -n "$CLONE_URL" ]]; then
  clone_args=(git clone --depth 1)
  if [[ -n "$CLONE_REF" ]]; then
    clone_args+=(--branch "$CLONE_REF")
  fi
  clone_args+=("$CLONE_URL" "${TASK_DIR}/repo")
  "${clone_args[@]}"
else
  # Initialize empty git repo for task work
  git init "${TASK_DIR}/repo" --quiet
fi

echo "TASK_ID=${TASK_ID}"
echo "TASK_DIR=${TASK_DIR}"
