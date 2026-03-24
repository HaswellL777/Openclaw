#!/usr/bin/env bash
# cleanup-task-dir.sh — Archive or remove a completed task directory.
#
# Usage:
#   sudo -u openclaw bash scripts/cleanup-task-dir.sh \
#     --task-id <id> \
#     [--mode archive|remove]
#
# Modes:
#   archive (default): Move outputs/ to an archive location, remove repo/
#   remove: Delete the entire task directory

set -euo pipefail

WORKSPACE_TASK_RUNNER="/var/lib/openclaw/.openclaw/workspace-task-runner"
ARCHIVE_DIR="${WORKSPACE_TASK_RUNNER}/archive"
TASK_ID=""
MODE="archive"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) TASK_ID="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 64 ;;
  esac
done

if [[ -z "$TASK_ID" ]]; then
  echo "Missing --task-id" >&2
  exit 64
fi

if [[ ! "$TASK_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Invalid task-id" >&2
  exit 65
fi

TASK_DIR="${WORKSPACE_TASK_RUNNER}/tasks/${TASK_ID}"

if [[ ! -d "$TASK_DIR" ]]; then
  echo "Task directory does not exist: $TASK_DIR" >&2
  exit 66
fi

case "$MODE" in
  archive)
    mkdir -p "$ARCHIVE_DIR"
    # Preserve outputs for review, discard the working repo
    if [[ -d "${TASK_DIR}/outputs" ]]; then
      mv "${TASK_DIR}/outputs" "${ARCHIVE_DIR}/${TASK_ID}-outputs"
      echo "Archived: ${ARCHIVE_DIR}/${TASK_ID}-outputs"
    fi
    rm -rf "$TASK_DIR"
    echo "Removed task dir: $TASK_DIR"
    ;;
  remove)
    rm -rf "$TASK_DIR"
    echo "Removed task dir: $TASK_DIR"
    ;;
  *)
    echo "Unknown mode: $MODE (expected archive|remove)" >&2
    exit 64
    ;;
esac
