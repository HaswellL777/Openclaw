#!/usr/bin/env python3
"""Shared validation helpers for task-runner contract artifacts."""

from __future__ import annotations

from pathlib import Path
import json
import re
from typing import Any


ALLOWED_ACTIONS = {
    "gateway_health",
    "gateway_restart",
    "validate_openclaw_json_candidate",
    "deploy_openclaw_json_candidate",
    "snapshot_pre",
    "snapshot_post",
    "vault_sync",
    "rollback_prepare",
}

FORBIDDEN_ACTIONS = {
    "direct_host_shell",
    "direct_openclaw_config_edit",
    "direct_systemd_control",
    "direct_docker_control",
    "direct_snapshot_manipulation",
    "direct_vault_manipulation",
    "direct_secret_handling",
    "unstructured_operator_commands",
    "user_level_gateway_start",
}

EVIDENCE_KINDS = {
    "design_doc",
    "sop_doc",
    "boundary_doc",
    "repo_file",
    "output_file",
    "schema",
    "fixture",
    "validator_log",
}

FORBIDDEN_INPUT_KEYS = {
    "command",
    "commands",
    "shell",
    "shell_command",
    "bash",
    "script",
}

ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
REQUESTED_BY_RE = re.compile(r"^task-runner(?:[:/][A-Za-z0-9._-]+)?$")


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def ensure(condition: bool, errors: list[str], message: str) -> None:
    if not condition:
        errors.append(message)


def ensure_type(value: Any, expected: type | tuple[type, ...], errors: list[str], message: str) -> bool:
    ok = isinstance(value, expected)
    ensure(ok, errors, message)
    return ok


def is_non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and value.strip() != ""


def is_relative_path(value: Any) -> bool:
    if not is_non_empty_string(value):
        return False
    path = str(value)
    return not path.startswith("/") and ".." not in path.split("/")


def reject_extra_keys(obj: dict[str, Any], allowed: set[str], errors: list[str], where: str) -> None:
    for key in sorted(obj.keys() - allowed):
        errors.append(f"{where}: unexpected key '{key}'")


def validate_schema_file(schema_path: Path, expected_title: str, expected_const: str) -> list[str]:
    errors: list[str] = []
    try:
      data = load_json(schema_path)
    except FileNotFoundError:
        return [f"schema file missing: {schema_path}"]
    except json.JSONDecodeError as exc:
        return [f"schema file is not valid JSON: {schema_path}: {exc}"]

    ensure(isinstance(data, dict), errors, f"schema root must be an object: {schema_path}")
    if errors:
        return errors

    ensure(data.get("$schema") == "https://json-schema.org/draft/2020-12/schema", errors, f"schema must declare draft 2020-12: {schema_path}")
    ensure(data.get("title") == expected_title, errors, f"schema title mismatch in {schema_path}")
    properties = data.get("properties")
    ensure(isinstance(properties, dict), errors, f"schema properties must be an object in {schema_path}")
    if isinstance(properties, dict):
        schema_version = properties.get("schema_version")
        ensure(isinstance(schema_version, dict), errors, f"schema_version property missing in {schema_path}")
        if isinstance(schema_version, dict):
            ensure(schema_version.get("const") == expected_const, errors, f"schema_version const mismatch in {schema_path}")

    return errors


def validate_evidence_refs(evidence_refs: Any, errors: list[str], where: str) -> None:
    if not ensure_type(evidence_refs, list, errors, f"{where} must be an array"):
        return
    ensure(len(evidence_refs) > 0, errors, f"{where} must not be empty")
    for idx, ref in enumerate(evidence_refs):
        item_where = f"{where}[{idx}]"
        if not ensure_type(ref, dict, errors, f"{item_where} must be an object"):
            continue
        reject_extra_keys(ref, {"id", "kind", "path", "description", "sha256"}, errors, item_where)
        ensure(ID_RE.match(str(ref.get("id", ""))) is not None, errors, f"{item_where}.id must match the contract id format")
        ensure(ref.get("kind") in EVIDENCE_KINDS, errors, f"{item_where}.kind must be one of the allowed evidence kinds")
        ensure(is_relative_path(ref.get("path")), errors, f"{item_where}.path must be a relative path without '..'")
        ensure(is_non_empty_string(ref.get("description")), errors, f"{item_where}.description must be a non-empty string")
        if "sha256" in ref:
            ensure(SHA256_RE.match(str(ref["sha256"])) is not None, errors, f"{item_where}.sha256 must be 64 lowercase hex characters")


def contains_forbidden_input_keys(value: Any, path: str = "") -> list[str]:
    found: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}" if path else key
            if key in FORBIDDEN_INPUT_KEYS:
                found.append(child_path)
            found.extend(contains_forbidden_input_keys(child, child_path))
    elif isinstance(value, list):
        for idx, child in enumerate(value):
            found.extend(contains_forbidden_input_keys(child, f"{path}[{idx}]"))
    return found


def validate_forbidden_actions(forbidden_actions: Any, errors: list[str], where: str) -> None:
    if not ensure_type(forbidden_actions, list, errors, f"{where} must be an array"):
        return
    ensure(len(forbidden_actions) > 0, errors, f"{where} must not be empty")
    seen: set[str] = set()
    for idx, action in enumerate(forbidden_actions):
        item_where = f"{where}[{idx}]"
        ensure(action in FORBIDDEN_ACTIONS, errors, f"{item_where} must be one of the allowed forbidden-action labels")
        if action in seen:
            errors.append(f"{item_where} duplicates a previous forbidden action")
        seen.add(str(action))
    ensure("unstructured_operator_commands" in seen, errors, f"{where} must explicitly preserve 'unstructured_operator_commands'")


def validate_requested_host_op(op: Any, errors: list[str], where: str) -> None:
    if not ensure_type(op, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(op, {"sequence", "action", "justification", "inputs"}, errors, where)
    ensure(isinstance(op.get("sequence"), int) and op["sequence"] >= 1, errors, f"{where}.sequence must be an integer >= 1")
    action = op.get("action")
    ensure(action in ALLOWED_ACTIONS, errors, f"{where}.action must be a known broker action")
    ensure(is_non_empty_string(op.get("justification")), errors, f"{where}.justification must be a non-empty string")
    inputs = op.get("inputs")
    if not ensure_type(inputs, dict, errors, f"{where}.inputs must be an object"):
        return

    forbidden_input_paths = contains_forbidden_input_keys(inputs)
    if forbidden_input_paths:
        errors.append(f"{where}.inputs must not contain imperative command keys: {', '.join(forbidden_input_paths)}")

    match action:
        case "gateway_health":
            ensure(inputs == {}, errors, f"{where}.inputs must be empty for gateway_health")
        case "gateway_restart":
            reject_extra_keys(inputs, {"reason"}, errors, f"{where}.inputs")
            ensure(is_non_empty_string(inputs.get("reason")), errors, f"{where}.inputs.reason must be non-empty")
        case "validate_openclaw_json_candidate" | "deploy_openclaw_json_candidate":
            reject_extra_keys(inputs, {"candidate_path", "expected_sha256"}, errors, f"{where}.inputs")
            candidate_path = inputs.get("candidate_path")
            ensure(is_non_empty_string(candidate_path), errors, f"{where}.inputs.candidate_path must be non-empty")
            if isinstance(candidate_path, str):
                ensure(candidate_path.startswith("/var/lib/openclaw/approvals/candidates/"), errors, f"{where}.inputs.candidate_path must stay within /var/lib/openclaw/approvals/candidates/")
                ensure(candidate_path.endswith(".json"), errors, f"{where}.inputs.candidate_path must end with .json")
            ensure(SHA256_RE.match(str(inputs.get("expected_sha256", ""))) is not None, errors, f"{where}.inputs.expected_sha256 must be 64 lowercase hex")
        case "snapshot_pre" | "snapshot_post":
            reject_extra_keys(inputs, {"label", "reason"}, errors, f"{where}.inputs")
            ensure(is_non_empty_string(inputs.get("label")), errors, f"{where}.inputs.label must be non-empty")
            ensure(is_non_empty_string(inputs.get("reason")), errors, f"{where}.inputs.reason must be non-empty")
        case "vault_sync":
            reject_extra_keys(inputs, {"snapshot_name", "incremental"}, errors, f"{where}.inputs")
            ensure(is_non_empty_string(inputs.get("snapshot_name")), errors, f"{where}.inputs.snapshot_name must be non-empty")
            ensure(isinstance(inputs.get("incremental"), bool), errors, f"{where}.inputs.incremental must be boolean")
        case "rollback_prepare":
            reject_extra_keys(inputs, {"target_snapshot", "reason"}, errors, f"{where}.inputs")
            ensure(is_non_empty_string(inputs.get("target_snapshot")), errors, f"{where}.inputs.target_snapshot must be non-empty")
            ensure(is_non_empty_string(inputs.get("reason")), errors, f"{where}.inputs.reason must be non-empty")

