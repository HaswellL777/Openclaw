#!/usr/bin/env python3
"""Validate task-runner summary artifacts."""

from __future__ import annotations

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import (  # noqa: E402
    ID_RE,
    ensure,
    ensure_type,
    is_non_empty_string,
    is_relative_path,
    load_json,
    reject_extra_keys,
    validate_evidence_refs,
    validate_forbidden_actions,
    validate_schema_file,
)


REPO_ROOT = SCRIPT_DIR.parent
SCHEMA_PATH = REPO_ROOT / "schemas" / "task-runner-summary.schema.json"


def usage() -> int:
    print("Usage: scripts/validate-task-runner-summary.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
    return 2


def validate_document(path: Path) -> list[str]:
    errors = validate_schema_file(
        SCHEMA_PATH,
        expected_title="TaskRunnerSummary",
        expected_const="openclaw.task-runner.summary.v1alpha1",
    )
    if errors:
        return errors

    try:
        data = load_json(path)
    except FileNotFoundError:
        return [f"{path}: file not found"]
    except Exception as exc:  # pragma: no cover - stdlib JSON errors collapse here
        return [f"{path}: could not parse JSON: {exc}"]

    if not isinstance(data, dict):
        return [f"{path}: root must be an object"]

    reject_extra_keys(
        data,
        {
            "schema_version",
            "task_id",
            "run_id",
            "status",
            "summary",
            "repo_changes",
            "validation_results",
            "outputs",
            "requires_operator_approval",
            "forbidden_actions",
            "evidence_refs",
            "next_handoff",
        },
        errors,
        str(path),
    )

    ensure(
        data.get("schema_version") == "openclaw.task-runner.summary.v1alpha1",
        errors,
        f"{path}: schema_version mismatch",
    )
    ensure(ID_RE.match(str(data.get("task_id", ""))) is not None, errors, f"{path}: task_id must match contract id format")
    ensure(ID_RE.match(str(data.get("run_id", ""))) is not None, errors, f"{path}: run_id must match contract id format")
    ensure(data.get("status") in {"completed", "completed_with_followup", "failed", "blocked"}, errors, f"{path}: invalid status")
    ensure(isinstance(data.get("requires_operator_approval"), bool), errors, f"{path}: requires_operator_approval must be boolean")

    summary = data.get("summary")
    host_change_needed = None
    if ensure_type(summary, dict, errors, f"{path}: summary must be an object"):
        reject_extra_keys(summary, {"goal", "outcome", "host_change_needed"}, errors, f"{path}.summary")
        ensure(is_non_empty_string(summary.get("goal")), errors, f"{path}.summary.goal must be non-empty")
        ensure(is_non_empty_string(summary.get("outcome")), errors, f"{path}.summary.outcome must be non-empty")
        host_change_needed = summary.get("host_change_needed")
        ensure(isinstance(host_change_needed, bool), errors, f"{path}.summary.host_change_needed must be boolean")

    repo_changes = data.get("repo_changes")
    if ensure_type(repo_changes, dict, errors, f"{path}: repo_changes must be an object"):
        reject_extra_keys(repo_changes, {"changed_files", "diff_path"}, errors, f"{path}.repo_changes")
        changed_files = repo_changes.get("changed_files")
        if ensure_type(changed_files, list, errors, f"{path}.repo_changes.changed_files must be an array"):
            ensure(len(changed_files) > 0, errors, f"{path}.repo_changes.changed_files must not be empty")
            for idx, changed_file in enumerate(changed_files):
                ensure(is_relative_path(changed_file), errors, f"{path}.repo_changes.changed_files[{idx}] must be a relative path")
        ensure(is_relative_path(repo_changes.get("diff_path")), errors, f"{path}.repo_changes.diff_path must be a relative path")

    validation_results = data.get("validation_results")
    if ensure_type(validation_results, list, errors, f"{path}: validation_results must be an array"):
        ensure(len(validation_results) > 0, errors, f"{path}: validation_results must not be empty")
        for idx, result in enumerate(validation_results):
            item_where = f"{path}.validation_results[{idx}]"
            if not ensure_type(result, dict, errors, f"{item_where} must be an object"):
                continue
            reject_extra_keys(result, {"name", "status", "artifact_path"}, errors, item_where)
            ensure(is_non_empty_string(result.get("name")), errors, f"{item_where}.name must be non-empty")
            ensure(result.get("status") in {"passed", "failed", "not_run"}, errors, f"{item_where}.status must be passed, failed, or not_run")
            if "artifact_path" in result:
                ensure(is_relative_path(result.get("artifact_path")), errors, f"{item_where}.artifact_path must be a relative path")

    outputs = data.get("outputs")
    if ensure_type(outputs, dict, errors, f"{path}: outputs must be an object"):
        reject_extra_keys(outputs, {"summary_md", "summary_json", "diff_patch", "host_change_request", "logs"}, errors, f"{path}.outputs")
        ensure(is_relative_path(outputs.get("summary_md")), errors, f"{path}.outputs.summary_md must be a relative path")
        ensure(outputs.get("summary_json") == "outputs/summary.json", errors, f"{path}.outputs.summary_json must be outputs/summary.json")
        ensure(is_relative_path(outputs.get("diff_patch")), errors, f"{path}.outputs.diff_patch must be a relative path")
        if "logs" in outputs:
            logs = outputs.get("logs")
            if ensure_type(logs, list, errors, f"{path}.outputs.logs must be an array"):
                for idx, log_path in enumerate(logs):
                    ensure(is_relative_path(log_path), errors, f"{path}.outputs.logs[{idx}] must be a relative path")

    validate_forbidden_actions(data.get("forbidden_actions"), errors, f"{path}.forbidden_actions")
    validate_evidence_refs(data.get("evidence_refs"), errors, f"{path}.evidence_refs")

    next_handoff = data.get("next_handoff")
    if ensure_type(next_handoff, dict, errors, f"{path}: next_handoff must be an object"):
        reject_extra_keys(next_handoff, {"consumer", "action", "host_change_request_path"}, errors, f"{path}.next_handoff")
        ensure(next_handoff.get("consumer") in {"none", "main"}, errors, f"{path}.next_handoff.consumer must be none or main")
        ensure(next_handoff.get("action") in {"none", "review_host_change_request"}, errors, f"{path}.next_handoff.action must be none or review_host_change_request")

    requires_operator_approval = data.get("requires_operator_approval")
    if host_change_needed is True:
        ensure(data.get("status") == "completed_with_followup", errors, f"{path}: summary.host_change_needed=true requires status completed_with_followup")
        if isinstance(outputs, dict):
            ensure(outputs.get("host_change_request") == "outputs/host-change-request.json", errors, f"{path}: summary.host_change_needed=true requires outputs.host_change_request")
        if isinstance(next_handoff, dict):
            ensure(next_handoff.get("consumer") == "main", errors, f"{path}: summary.host_change_needed=true requires next_handoff.consumer=main")
            ensure(next_handoff.get("action") == "review_host_change_request", errors, f"{path}: summary.host_change_needed=true requires next_handoff.action=review_host_change_request")
            ensure(next_handoff.get("host_change_request_path") == "outputs/host-change-request.json", errors, f"{path}: summary.host_change_needed=true requires next_handoff.host_change_request_path")
    elif host_change_needed is False:
        if isinstance(outputs, dict):
            ensure("host_change_request" not in outputs, errors, f"{path}: summary.host_change_needed=false must not include outputs.host_change_request")
        if isinstance(next_handoff, dict):
            ensure(next_handoff.get("consumer") == "none", errors, f"{path}: summary.host_change_needed=false requires next_handoff.consumer=none")
            ensure(next_handoff.get("action") == "none", errors, f"{path}: summary.host_change_needed=false requires next_handoff.action=none")
            ensure("host_change_request_path" not in next_handoff, errors, f"{path}: summary.host_change_needed=false must not include next_handoff.host_change_request_path")

    if requires_operator_approval is True:
        ensure(host_change_needed is True, errors, f"{path}: requires_operator_approval=true requires summary.host_change_needed=true")

    return errors


def main(argv: list[str]) -> int:
    expectation = "valid"
    paths: list[str] = []
    for arg in argv:
        if arg == "--expect-valid":
            expectation = "valid"
        elif arg == "--expect-invalid":
            expectation = "invalid"
        else:
            paths.append(arg)

    if not paths:
        return usage()

    overall_ok = True
    for raw_path in paths:
        path = Path(raw_path)
        errors = validate_document(path)
        is_valid = not errors

        if expectation == "valid":
            if is_valid:
                print(f"PASS {path}")
            else:
                overall_ok = False
                print(f"FAIL {path}")
                for error in errors:
                    print(f"  - {error}")
        else:
            if is_valid:
                overall_ok = False
                print(f"FAIL {path}")
                print("  - expected invalid document, but validation passed")
            else:
                print(f"PASS {path} rejected as expected")
                for error in errors:
                    print(f"  - {error}")

    return 0 if overall_ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
