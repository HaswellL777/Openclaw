#!/usr/bin/env python3
"""Validate repo-side operator approval envelope artifacts."""

from __future__ import annotations

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import (  # noqa: E402
    ALLOWED_ACTIONS,
    HOST_AFFECTING_ACTIONS,
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
SCHEMA_PATH = REPO_ROOT / "schemas" / "operator-approval-envelope.schema.json"


def usage() -> int:
    print("Usage: scripts/validate-operator-approval-envelope.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
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


def validate_summary_context(value: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(value, {"goal", "outcome", "request_title", "request_scope"}, errors, where)
    for key in ("goal", "outcome", "request_title", "request_scope"):
        ensure(is_non_empty_string(value.get(key)), errors, f"{where}.{key} must be non-empty")


def validate_validation_status(value: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(value, {"normalized_request", "intake_report", "routing_decision"}, errors, where)
    for key in ("normalized_request", "intake_report", "routing_decision"):
        ensure(value.get(key) in {"passed", "failed"}, errors, f"{where}.{key} must be passed or failed")


def validate_broker_requests(value: object, task_id: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, list, errors, f"{where} must be an array"):
        return
    ensure(len(value) > 0, errors, f"{where} must not be empty")
    sequences: list[int] = []
    actions: list[str] = []
    for idx, item in enumerate(value):
        item_where = f"{where}[{idx}]"
        if not ensure_type(item, dict, errors, f"{item_where} must be an object"):
            continue
        reject_extra_keys(item, {"sequence", "action", "justification", "broker_request"}, errors, item_where)
        ensure(isinstance(item.get("sequence"), int) and item["sequence"] >= 1, errors, f"{item_where}.sequence must be an integer >= 1")
        ensure(item.get("action") in ALLOWED_ACTIONS, errors, f"{item_where}.action must be a known broker action")
        ensure(is_non_empty_string(item.get("justification")), errors, f"{item_where}.justification must be non-empty")
        broker_request = item.get("broker_request")
        if ensure_type(broker_request, dict, errors, f"{item_where}.broker_request must be an object"):
            reject_extra_keys(broker_request, {"action", "request_id", "task_id", "requested_by", "inputs"}, errors, f"{item_where}.broker_request")
            ensure(broker_request.get("action") == item.get("action"), errors, f"{item_where}.broker_request.action must match action")
            ensure(ID_RE.match(str(broker_request.get("request_id", ""))) is not None, errors, f"{item_where}.broker_request.request_id must match contract id format")
            ensure(broker_request.get("task_id") == task_id, errors, f"{item_where}.broker_request.task_id must match top-level task_id")
            ensure(is_non_empty_string(broker_request.get("requested_by")), errors, f"{item_where}.broker_request.requested_by must be non-empty")
            ensure(isinstance(broker_request.get("inputs"), dict), errors, f"{item_where}.broker_request.inputs must be an object")
        if isinstance(item.get("sequence"), int):
            sequences.append(item["sequence"])
        if isinstance(item.get("action"), str):
            actions.append(item["action"])
    if sequences:
        ensure(sequences == sorted(sequences), errors, f"{where} sequences must be sorted ascending")
        ensure(len(sequences) == len(set(sequences)), errors, f"{where} sequences must be unique")
    if actions:
        ensure(any(action in HOST_AFFECTING_ACTIONS for action in actions), errors, f"{where} must include at least one host-affecting broker action")


def validate_document(path: Path) -> list[str]:
    errors = validate_schema_file(
        SCHEMA_PATH,
        expected_title="OperatorApprovalEnvelope",
        expected_const="openclaw.main.operator-approval-envelope.v1alpha1",
    )
    if errors:
        return errors

    try:
        data = load_json(path)
    except FileNotFoundError:
        return [f"{path}: file not found"]
    except Exception as exc:  # pragma: no cover
        return [f"{path}: could not parse JSON: {exc}"]

    if not isinstance(data, dict):
        return [f"{path}: root must be an object"]

    reject_extra_keys(
        data,
        {
            "schema_version",
            "envelope_id",
            "routing_decision_id",
            "envelope_mode",
            "envelope_type",
            "intake_id",
            "task_id",
            "run_id",
            "source_request_id",
            "dispatch_scope",
            "dispatch_status",
            "requires_operator_approval",
            "approval",
            "source_artifacts",
            "summary_context",
            "validation_status",
            "broker_requests",
            "refusal_reasons",
            "forbidden_actions",
            "boundary_carry_forward",
            "evidence_refs",
        },
        errors,
        str(path),
    )

    ensure(data.get("schema_version") == "openclaw.main.operator-approval-envelope.v1alpha1", errors, f"{path}: schema_version mismatch")
    ensure(data.get("envelope_mode") == "repo_side_dry_run", errors, f"{path}: envelope_mode must be repo_side_dry_run")
    ensure(data.get("envelope_type") == "REQUIRES_OPERATOR_APPROVAL", errors, f"{path}: envelope_type must be REQUIRES_OPERATOR_APPROVAL")
    for key in ("envelope_id", "routing_decision_id", "intake_id", "task_id", "run_id", "source_request_id"):
        ensure(ID_RE.match(str(data.get(key, ""))) is not None, errors, f"{path}: {key} must match contract id format")
    ensure(data.get("dispatch_scope") == "host_affecting", errors, f"{path}: dispatch_scope must be host_affecting")
    ensure(data.get("dispatch_status") == "operator_approval_required", errors, f"{path}: dispatch_status must be operator_approval_required")
    ensure(data.get("requires_operator_approval") is True, errors, f"{path}: requires_operator_approval must be true")

    approval = data.get("approval")
    if ensure_type(approval, dict, errors, f"{path}: approval must be an object"):
        reject_extra_keys(approval, {"status", "exact_command_block_present"}, errors, f"{path}.approval")
        ensure(approval.get("status") == "pending_review", errors, f"{path}.approval.status must be pending_review")
        ensure(approval.get("exact_command_block_present") is False, errors, f"{path}.approval.exact_command_block_present must be false")

    source_artifacts = data.get("source_artifacts")
    if ensure_type(source_artifacts, dict, errors, f"{path}: source_artifacts must be an object"):
        reject_extra_keys(source_artifacts, {"normalized_request_path", "intake_report_path", "routing_decision_path"}, errors, f"{path}.source_artifacts")
        for key in ("normalized_request_path", "intake_report_path", "routing_decision_path"):
            ensure(is_relative_path(source_artifacts.get(key)), errors, f"{path}.source_artifacts.{key} must be a relative path")

    validate_summary_context(data.get("summary_context"), errors, f"{path}.summary_context")
    validate_validation_status(data.get("validation_status"), errors, f"{path}.validation_status")
    validate_broker_requests(data.get("broker_requests"), data.get("task_id"), errors, f"{path}.broker_requests")

    refusal_reasons = data.get("refusal_reasons")
    if ensure_type(refusal_reasons, list, errors, f"{path}: refusal_reasons must be an array"):
        ensure(len(refusal_reasons) == 0, errors, f"{path}: refusal_reasons must be empty")

    validate_forbidden_actions(data.get("forbidden_actions"), errors, f"{path}.forbidden_actions")
    validate_boundary_carry_forward(data.get("boundary_carry_forward"), errors, f"{path}.boundary_carry_forward")
    validate_evidence_refs(data.get("evidence_refs"), errors, f"{path}.evidence_refs")

    validation_status = data.get("validation_status")
    if isinstance(validation_status, dict):
        for key in ("normalized_request", "intake_report", "routing_decision"):
            ensure(validation_status.get(key) == "passed", errors, f"{path}: validation_status.{key} must be passed")

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
