#!/usr/bin/env python3
"""Shared validation helpers for task-runner container contracts."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from task_runner_contracts import (
    ID_RE,
    ensure,
    ensure_type,
    is_non_empty_string,
    is_relative_path,
    load_json,
    reject_extra_keys,
    validate_schema_file,
)


WORKSPACE_MODES = {"readonly", "dev"}
RUNNER_TOOLS = {"codex", "claudecode"}
NETWORK_MODES = {"none", "restricted-egress"}
REQUIRED_ALLOWED_ENV = {
    "TASK_ID",
    "RUN_ID",
    "RUNNER_TOOL",
    "RUNNER_MODE",
    "WORKSPACE_MODE",
    "TASK_REPO_PATH",
    "TASK_INPUTS_PATH",
    "TASK_OUTPUTS_PATH",
    "ARTIFACT_EXPORT_PATH",
}
REQUIRED_FORBIDDEN_ENV = {
    "OPENCLAW_CONFIG_PATH",
    "OPENCLAW_STATE_DIR",
    "DOCKER_HOST",
    "OPENAI_API_KEY",
    "ANTHROPIC_AUTH_TOKEN",
    "OPENCLAW_BROKER_SOCKET",
}
REQUIRED_AGENT_ALLOW = {"read", "write", "edit", "apply_patch", "exec", "process"}
REQUIRED_AGENT_DENY = {"sessions_spawn", "elevated"}
REQUIRED_AVAILABLE_BINARIES = {"bash", "git", "jq", "python3", "rg"}
REQUIRED_UNAVAILABLE_BINARIES = {"docker", "sudo", "systemctl", "mount", "umount"}
RUNNER_BOOTSTRAP_PATH = {
    "codex": "/usr/local/bin/bootstrap-codex",
    "claudecode": "/usr/local/bin/bootstrap-claudecode",
}
REQUIRED_POLICY_FILES = {
    "AGENTS.md",
    "TOOLS.md",
    "control/runner-policy.md",
    "control/artifact-contract.md",
}
REQUIRED_OUTPUT_ARTIFACTS = {
    "/workspace/outputs/summary.md",
    "/workspace/outputs/summary.json",
    "/workspace/outputs/diff.patch",
}
REQUIRED_RETAINED_ARTIFACTS = {"summary.md", "summary.json", "diff.patch"}
REQUIRED_TMPFS_PATHS = {"/tmp", "/var/tmp", "/run"}
VALID_MOUNT_NAMES = {"repo", "inputs", "outputs"}
EXPECTED_MOUNT_PATHS = {
    "repo": "/workspace/repo",
    "inputs": "/workspace/inputs",
    "outputs": "/workspace/outputs",
}


def validate_boundary_flags(value: Any, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(
        value,
        {
            "repo_side_only",
            "live_side_publish_performed",
            "broker_dispatch_performed",
            "real_docker_run_required",
            "openclaw_runtime_modified",
        },
        errors,
        where,
    )
    ensure(value.get("repo_side_only") is True, errors, f"{where}.repo_side_only must be true")
    ensure(value.get("live_side_publish_performed") is False, errors, f"{where}.live_side_publish_performed must be false")
    ensure(value.get("broker_dispatch_performed") is False, errors, f"{where}.broker_dispatch_performed must be false")
    ensure(value.get("real_docker_run_required") is False, errors, f"{where}.real_docker_run_required must be false")
    ensure(value.get("openclaw_runtime_modified") is False, errors, f"{where}.openclaw_runtime_modified must be false")


def validate_env_name_list(value: Any, errors: list[str], where: str) -> set[str]:
    names: set[str] = set()
    if not ensure_type(value, list, errors, f"{where} must be an array"):
        return names
    ensure(len(value) > 0, errors, f"{where} must not be empty")
    for idx, item in enumerate(value):
        item_where = f"{where}[{idx}]"
        ensure(is_non_empty_string(item), errors, f"{item_where} must be a non-empty string")
        if isinstance(item, str):
            ensure(item == item.upper(), errors, f"{item_where} must be uppercase")
            ensure(item.replace("_", "").isalnum(), errors, f"{item_where} must use A-Z, 0-9, and _ only")
            if item in names:
                errors.append(f"{item_where} duplicates a previous environment name")
            names.add(item)
    return names


def validate_container_path(value: Any, errors: list[str], where: str, *, prefix: str) -> None:
    ensure(is_non_empty_string(value), errors, f"{where} must be a non-empty string")
    if isinstance(value, str):
        ensure(value.startswith(prefix), errors, f"{where} must stay within {prefix}")


def validate_mount_source_relpath(value: Any, errors: list[str], where: str) -> None:
    ensure(is_relative_path(value), errors, f"{where} must be a relative path without '..'")
    if isinstance(value, str):
        ensure(value.startswith("tasks/"), errors, f"{where} must stay under tasks/")


def load_document(path: Path) -> dict[str, Any]:
    data = load_json(path)
    if not isinstance(data, dict):
        raise ValueError("root must be an object")
    return data
