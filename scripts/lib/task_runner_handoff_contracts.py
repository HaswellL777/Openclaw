#!/usr/bin/env python3
"""Shared helpers for task-runner handoff pack assembly and validation."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from task_runner_contracts import ensure, is_non_empty_string, load_json


HANDOFF_MANIFEST_SCHEMA_VERSION = "openclaw.task-runner.handoff-manifest.v1alpha1"
REVIEWED_TASK_SCHEMA_VERSIONS = {
    "openclaw.main.broker-review-bundle.v1alpha1": "broker_review_bundle",
    "openclaw.main.operator-review-bundle.v1alpha1": "operator_review_bundle",
}
WORKSPACE_MODE_BY_DISPATCH_SCOPE = {
    "readonly": "readonly",
    "host_affecting": "dev",
}
POLICY_FILES = [
    "AGENTS.md",
    "TOOLS.md",
    "control/runner-policy.md",
    "control/artifact-contract.md",
]
BOUNDARY_CARRY_FORWARD = {
    "repo_side_only": True,
    "live_side_publish_performed": False,
    "broker_dispatch_performed": False,
    "real_docker_run_required": False,
    "openclaw_runtime_modified": False,
}
IMAGE_REFERENCE = "openclaw-task-claude:2026-03-v3"
RUNNER_NAME = "codex"
RUNNER_BOOTSTRAP_PATH = "/usr/local/bin/bootstrap-codex"
TASK_REQUEST_MD = "inputs/request.md"
TASK_CONTEXT_JSON = "inputs/context.json"
TASK_CONTROL_PLANE_DIR = "inputs/control-plane"
TASK_STAGED_SUMMARY_JSON = "inputs/control-plane/task-runner-summary.json"
TASK_WORKSPACE_LAYOUT = "workspace-layout.json"
TASK_EXEC_PLAN = "exec-plan.json"
TASK_HANDOFF_MANIFEST = "handoff-manifest.json"
REPO_SEED_STRATEGY = "changed_files_subset"


def detect_reviewed_task_kind(document: dict[str, Any]) -> str | None:
    schema_version = document.get("schema_version")
    if isinstance(schema_version, str):
        return REVIEWED_TASK_SCHEMA_VERSIONS.get(schema_version)
    return None


def workspace_mode_from_reviewed_task(document: dict[str, Any]) -> str | None:
    dispatch_scope = document.get("dispatch_scope")
    if isinstance(dispatch_scope, str):
        return WORKSPACE_MODE_BY_DISPATCH_SCOPE.get(dispatch_scope)
    return None


def resolve_input_path(path_value: str, *, preferred_base: Path, repo_root: Path) -> Path:
    candidate = Path(path_value)
    if candidate.is_absolute():
        return candidate.resolve()

    for base in (preferred_base, repo_root):
        resolved = (base / candidate).resolve()
        if resolved.exists():
            return resolved
    return (preferred_base / candidate).resolve()


def to_repo_relpath(path: Path, repo_root: Path) -> str:
    try:
        return str(path.resolve().relative_to(repo_root.resolve()))
    except ValueError:
        return path.resolve().as_posix()


def ensure_reviewed_task_document(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ValueError("reviewed task must be a JSON object")
    kind = detect_reviewed_task_kind(data)
    if kind is None:
        raise ValueError("reviewed task must be a broker-review-bundle or operator-review-bundle")
    workspace_mode = workspace_mode_from_reviewed_task(data)
    if workspace_mode is None:
        raise ValueError("reviewed task dispatch_scope must map to a supported workspace_mode")
    return data


def ensure_summary_document(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ValueError("summary must be a JSON object")
    return data


def load_document(path: Path) -> dict[str, Any]:
    return load_json(path)


def validate_cross_document_basics(
    *,
    reviewed_task: dict[str, Any],
    summary: dict[str, Any],
    reviewed_task_path: Path,
    summary_path: Path,
) -> list[str]:
    errors: list[str] = []
    ensure(
        reviewed_task.get("task_id") == summary.get("task_id"),
        errors,
        f"{reviewed_task_path}: task_id must match {summary_path}",
    )
    ensure(
        reviewed_task.get("run_id") == summary.get("run_id"),
        errors,
        f"{reviewed_task_path}: run_id must match {summary_path}",
    )
    ensure(
        reviewed_task.get("requires_operator_approval") == summary.get("requires_operator_approval"),
        errors,
        f"{reviewed_task_path}: requires_operator_approval must match {summary_path}",
    )

    summary_block = summary.get("summary")
    ensure(
        isinstance(summary_block, dict) and summary_block.get("host_change_needed") is True,
        errors,
        f"{summary_path}: summary.host_change_needed must be true for reviewed task handoff",
    )

    repo_changes = summary.get("repo_changes")
    changed_files = repo_changes.get("changed_files") if isinstance(repo_changes, dict) else None
    ensure(
        isinstance(changed_files, list) and len(changed_files) > 0,
        errors,
        f"{summary_path}: repo_changes.changed_files must not be empty",
    )

    return errors


def non_empty_string(value: Any) -> bool:
    return is_non_empty_string(value)
