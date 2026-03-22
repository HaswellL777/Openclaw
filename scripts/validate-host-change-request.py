#!/usr/bin/env python3
"""Validate task-runner host-change-request artifacts."""

from __future__ import annotations

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import (  # noqa: E402
    ID_RE,
    REQUESTED_BY_RE,
    ensure,
    ensure_type,
    is_non_empty_string,
    is_relative_path,
    load_json,
    reject_extra_keys,
    validate_evidence_refs,
    validate_forbidden_actions,
    validate_requested_host_op,
    validate_schema_file,
)


REPO_ROOT = SCRIPT_DIR.parent
SCHEMA_PATH = REPO_ROOT / "schemas" / "host-change-request.schema.json"


def usage() -> int:
    print("Usage: scripts/validate-host-change-request.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
    return 2


def validate_document(path: Path) -> list[str]:
    errors = validate_schema_file(
        SCHEMA_PATH,
        expected_title="TaskRunnerHostChangeRequest",
        expected_const="openclaw.task-runner.host-change-request.v1alpha1",
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
            "request_id",
            "task_id",
            "requested_by",
            "status",
            "summary",
            "repo_context",
            "requires_operator_approval",
            "requested_host_ops",
            "forbidden_actions",
            "evidence_refs",
            "required_evidence",
            "rollback_considerations",
            "handoff",
        },
        errors,
        str(path),
    )

    ensure(
        data.get("schema_version") == "openclaw.task-runner.host-change-request.v1alpha1",
        errors,
        f"{path}: schema_version mismatch",
    )
    ensure(ID_RE.match(str(data.get("request_id", ""))) is not None, errors, f"{path}: request_id must match contract id format")
    ensure(ID_RE.match(str(data.get("task_id", ""))) is not None, errors, f"{path}: task_id must match contract id format")
    ensure(REQUESTED_BY_RE.match(str(data.get("requested_by", ""))) is not None, errors, f"{path}: requested_by must start with task-runner")
    ensure(data.get("status") == "proposed", errors, f"{path}: status must be 'proposed'")
    ensure(data.get("requires_operator_approval") is True, errors, f"{path}: requires_operator_approval must be true")

    summary = data.get("summary")
    if ensure_type(summary, dict, errors, f"{path}: summary must be an object"):
        reject_extra_keys(summary, {"title", "why", "scope", "impact"}, errors, f"{path}.summary")
        for key in ("title", "why", "scope", "impact"):
            ensure(is_non_empty_string(summary.get(key)), errors, f"{path}.summary.{key} must be a non-empty string")

    repo_context = data.get("repo_context")
    if ensure_type(repo_context, dict, errors, f"{path}: repo_context must be an object"):
        reject_extra_keys(repo_context, {"repo_relpath", "branch", "changed_files"}, errors, f"{path}.repo_context")
        repo_relpath = repo_context.get("repo_relpath")
        ensure(repo_relpath in {"repo", "repo/"} or (isinstance(repo_relpath, str) and repo_relpath.startswith("repo/")), errors, f"{path}.repo_context.repo_relpath must stay inside repo/")
        changed_files = repo_context.get("changed_files")
        if ensure_type(changed_files, list, errors, f"{path}.repo_context.changed_files must be an array"):
            ensure(len(changed_files) > 0, errors, f"{path}.repo_context.changed_files must not be empty")
            for idx, changed_file in enumerate(changed_files):
                ensure(is_relative_path(changed_file), errors, f"{path}.repo_context.changed_files[{idx}] must be a relative path")
        if "branch" in repo_context:
            ensure(is_non_empty_string(repo_context.get("branch")), errors, f"{path}.repo_context.branch must be non-empty when present")

    requested_host_ops = data.get("requested_host_ops")
    if ensure_type(requested_host_ops, list, errors, f"{path}: requested_host_ops must be an array"):
        ensure(len(requested_host_ops) > 0, errors, f"{path}: requested_host_ops must not be empty")
        sequences: list[int] = []
        for idx, op in enumerate(requested_host_ops):
            validate_requested_host_op(op, errors, f"{path}.requested_host_ops[{idx}]")
            if isinstance(op, dict) and isinstance(op.get("sequence"), int):
                sequences.append(op["sequence"])
        if sequences:
            ensure(sequences == sorted(sequences), errors, f"{path}: requested_host_ops sequences must be sorted ascending")
            ensure(len(sequences) == len(set(sequences)), errors, f"{path}: requested_host_ops sequences must be unique")

    validate_forbidden_actions(data.get("forbidden_actions"), errors, f"{path}.forbidden_actions")
    validate_evidence_refs(data.get("evidence_refs"), errors, f"{path}.evidence_refs")

    required_evidence = data.get("required_evidence")
    if ensure_type(required_evidence, list, errors, f"{path}: required_evidence must be an array"):
        ensure(len(required_evidence) > 0, errors, f"{path}: required_evidence must not be empty")
        for idx, item in enumerate(required_evidence):
            item_where = f"{path}.required_evidence[{idx}]"
            if not ensure_type(item, dict, errors, f"{item_where} must be an object"):
                continue
            reject_extra_keys(item, {"id", "when", "description"}, errors, item_where)
            ensure(ID_RE.match(str(item.get("id", ""))) is not None, errors, f"{item_where}.id must match contract id format")
            ensure(item.get("when") in {"before_main_review", "before_broker_dispatch", "after_broker_execution"}, errors, f"{item_where}.when must be a known lifecycle stage")
            ensure(is_non_empty_string(item.get("description")), errors, f"{item_where}.description must be non-empty")

    if "rollback_considerations" in data:
        rollback_considerations = data.get("rollback_considerations")
        if ensure_type(rollback_considerations, list, errors, f"{path}: rollback_considerations must be an array"):
            for idx, note in enumerate(rollback_considerations):
                ensure(is_non_empty_string(note), errors, f"{path}.rollback_considerations[{idx}] must be non-empty")

    handoff = data.get("handoff")
    if ensure_type(handoff, dict, errors, f"{path}: handoff must be an object"):
        reject_extra_keys(handoff, {"next_consumer", "delivery_artifact", "broker_request_ready", "review_required"}, errors, f"{path}.handoff")
        ensure(handoff.get("next_consumer") == "main", errors, f"{path}.handoff.next_consumer must be 'main'")
        ensure(handoff.get("delivery_artifact") == "outputs/host-change-request.json", errors, f"{path}.handoff.delivery_artifact must be outputs/host-change-request.json")
        ensure(isinstance(handoff.get("broker_request_ready"), bool), errors, f"{path}.handoff.broker_request_ready must be boolean")
        ensure(handoff.get("review_required") is True, errors, f"{path}.handoff.review_required must be true")

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
