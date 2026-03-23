#!/usr/bin/env python3
"""Validate task-runner intake report artifacts."""

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
SCHEMA_PATH = REPO_ROOT / "schemas" / "task-runner-intake-report.schema.json"


def usage() -> int:
    print("Usage: scripts/validate-task-runner-intake-report.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
    return 2


def validate_boundary_carry_forward(value: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(
        value,
        {
            "repo_side_only",
            "live_side_publish_performed",
            "broker_dispatch_performed",
            "openclaw_runtime_modified",
            "operator_command_blocks_present",
        },
        errors,
        where,
    )
    ensure(value.get("repo_side_only") is True, errors, f"{where}.repo_side_only must be true")
    ensure(value.get("live_side_publish_performed") is False, errors, f"{where}.live_side_publish_performed must be false")
    ensure(value.get("broker_dispatch_performed") is False, errors, f"{where}.broker_dispatch_performed must be false")
    ensure(value.get("openclaw_runtime_modified") is False, errors, f"{where}.openclaw_runtime_modified must be false")
    ensure(value.get("operator_command_blocks_present") is False, errors, f"{where}.operator_command_blocks_present must be false")


def validate_document(path: Path) -> list[str]:
    errors = validate_schema_file(
        SCHEMA_PATH,
        expected_title="TaskRunnerIntakeReport",
        expected_const="openclaw.main.task-runner-intake-report.v1alpha1",
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
            "intake_id",
            "task_id",
            "run_id",
            "source_request_id",
            "status",
            "dispatch_scope",
            "dispatch_status",
            "requires_operator_approval",
            "source_artifacts",
            "validation_results",
            "refusal_reasons",
            "forbidden_actions",
            "boundary_carry_forward",
            "evidence_refs",
        },
        errors,
        str(path),
    )

    ensure(data.get("schema_version") == "openclaw.main.task-runner-intake-report.v1alpha1", errors, f"{path}: schema_version mismatch")
    for key in ("intake_id", "task_id", "run_id", "source_request_id"):
        ensure(ID_RE.match(str(data.get(key, ""))) is not None, errors, f"{path}: {key} must match contract id format")
    ensure(data.get("status") in {"accepted", "refused"}, errors, f"{path}: invalid status")
    ensure(data.get("dispatch_scope") in {"readonly", "host_affecting", "unclassified"}, errors, f"{path}: invalid dispatch_scope")
    ensure(data.get("dispatch_status") in {"broker_ready", "operator_approval_required", "refused"}, errors, f"{path}: invalid dispatch_status")
    ensure(isinstance(data.get("requires_operator_approval"), bool), errors, f"{path}: requires_operator_approval must be boolean")

    source_artifacts = data.get("source_artifacts")
    if ensure_type(source_artifacts, dict, errors, f"{path}: source_artifacts must be an object"):
        reject_extra_keys(source_artifacts, {"summary_path", "host_change_request_path"}, errors, f"{path}.source_artifacts")
        ensure(is_relative_path(source_artifacts.get("summary_path")), errors, f"{path}.source_artifacts.summary_path must be a relative path")
        ensure(is_relative_path(source_artifacts.get("host_change_request_path")), errors, f"{path}.source_artifacts.host_change_request_path must be a relative path")

    validation_results = data.get("validation_results")
    if ensure_type(validation_results, list, errors, f"{path}: validation_results must be an array"):
        ensure(len(validation_results) >= 3, errors, f"{path}: validation_results must include summary, host_change_request, and cross_document")
        seen_names: set[str] = set()
        for idx, item in enumerate(validation_results):
            item_where = f"{path}.validation_results[{idx}]"
            if not ensure_type(item, dict, errors, f"{item_where} must be an object"):
                continue
            reject_extra_keys(item, {"name", "status", "issues"}, errors, item_where)
            name = item.get("name")
            ensure(is_non_empty_string(name), errors, f"{item_where}.name must be non-empty")
            ensure(item.get("status") in {"passed", "failed"}, errors, f"{item_where}.status must be passed or failed")
            issues = item.get("issues")
            if ensure_type(issues, list, errors, f"{item_where}.issues must be an array"):
                for issue_idx, issue in enumerate(issues):
                    ensure(is_non_empty_string(issue), errors, f"{item_where}.issues[{issue_idx}] must be non-empty")
            if isinstance(name, str):
                seen_names.add(name)
        for name in ("summary", "host_change_request", "cross_document"):
            ensure(name in seen_names, errors, f"{path}: validation_results missing '{name}' entry")

    refusal_reasons = data.get("refusal_reasons")
    if ensure_type(refusal_reasons, list, errors, f"{path}: refusal_reasons must be an array"):
        for idx, reason in enumerate(refusal_reasons):
            ensure(is_non_empty_string(reason), errors, f"{path}.refusal_reasons[{idx}] must be non-empty")

    validate_forbidden_actions(data.get("forbidden_actions"), errors, f"{path}.forbidden_actions")
    validate_boundary_carry_forward(data.get("boundary_carry_forward"), errors, f"{path}.boundary_carry_forward")
    validate_evidence_refs(data.get("evidence_refs"), errors, f"{path}.evidence_refs")

    if data.get("status") == "accepted":
        ensure(len(refusal_reasons) == 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: accepted report must not contain refusal_reasons")
    else:
        ensure(data.get("dispatch_status") == "refused", errors, f"{path}: refused report requires dispatch_status=refused")
        ensure(len(refusal_reasons) > 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: refused report requires refusal_reasons")

    if data.get("dispatch_status") == "operator_approval_required":
        ensure(data.get("requires_operator_approval") is True, errors, f"{path}: operator_approval_required requires requires_operator_approval=true")
    if data.get("dispatch_scope") == "unclassified":
        ensure(data.get("status") == "refused", errors, f"{path}: unclassified scope must be refused")

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
