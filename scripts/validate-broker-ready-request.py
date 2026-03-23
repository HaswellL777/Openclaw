#!/usr/bin/env python3
"""Validate main-side broker-ready request artifacts."""

from __future__ import annotations

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import (  # noqa: E402
    ALLOWED_ACTIONS,
    HOST_AFFECTING_ACTIONS,
    ID_RE,
    REQUESTED_BY_RE,
    classify_requested_host_ops,
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
SCHEMA_PATH = REPO_ROOT / "schemas" / "broker-ready-request.schema.json"


def usage() -> int:
    print("Usage: scripts/validate-broker-ready-request.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
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
        expected_title="BrokerReadyRequest",
        expected_const="openclaw.main.broker-ready-request.v1alpha1",
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
            "original_requested_by",
            "intake_status",
            "dispatch_scope",
            "dispatch_status",
            "requires_operator_approval",
            "source_artifacts",
            "summary_context",
            "validation_status",
            "forbidden_actions",
            "boundary_carry_forward",
            "evidence_refs",
            "broker_requests",
            "refusal_reasons",
        },
        errors,
        str(path),
    )

    ensure(data.get("schema_version") == "openclaw.main.broker-ready-request.v1alpha1", errors, f"{path}: schema_version mismatch")
    for key in ("intake_id", "task_id", "run_id", "source_request_id"):
        ensure(ID_RE.match(str(data.get(key, ""))) is not None, errors, f"{path}: {key} must match contract id format")
    ensure(REQUESTED_BY_RE.match(str(data.get("original_requested_by", ""))) is not None, errors, f"{path}: original_requested_by must start with task-runner")
    ensure(data.get("intake_status") in {"accepted", "refused"}, errors, f"{path}: invalid intake_status")
    ensure(data.get("dispatch_scope") in {"readonly", "host_affecting", "unclassified"}, errors, f"{path}: invalid dispatch_scope")
    ensure(data.get("dispatch_status") in {"broker_ready", "operator_approval_required", "refused"}, errors, f"{path}: invalid dispatch_status")
    ensure(isinstance(data.get("requires_operator_approval"), bool), errors, f"{path}: requires_operator_approval must be boolean")

    source_artifacts = data.get("source_artifacts")
    if ensure_type(source_artifacts, dict, errors, f"{path}: source_artifacts must be an object"):
        reject_extra_keys(source_artifacts, {"summary_path", "host_change_request_path"}, errors, f"{path}.source_artifacts")
        ensure(is_relative_path(source_artifacts.get("summary_path")), errors, f"{path}.source_artifacts.summary_path must be a relative path")
        ensure(is_relative_path(source_artifacts.get("host_change_request_path")), errors, f"{path}.source_artifacts.host_change_request_path must be a relative path")

    summary_context = data.get("summary_context")
    if ensure_type(summary_context, dict, errors, f"{path}: summary_context must be an object"):
        reject_extra_keys(summary_context, {"goal", "outcome", "request_title", "request_scope"}, errors, f"{path}.summary_context")
        for key in ("goal", "outcome", "request_title", "request_scope"):
            ensure(is_non_empty_string(summary_context.get(key)), errors, f"{path}.summary_context.{key} must be a non-empty string")

    validation_status = data.get("validation_status")
    if ensure_type(validation_status, dict, errors, f"{path}: validation_status must be an object"):
        reject_extra_keys(validation_status, {"summary", "host_change_request", "cross_document"}, errors, f"{path}.validation_status")
        for key in ("summary", "host_change_request", "cross_document"):
            ensure(validation_status.get(key) in {"passed", "failed"}, errors, f"{path}.validation_status.{key} must be passed or failed")

    validate_forbidden_actions(data.get("forbidden_actions"), errors, f"{path}.forbidden_actions")
    validate_boundary_carry_forward(data.get("boundary_carry_forward"), errors, f"{path}.boundary_carry_forward")
    validate_evidence_refs(data.get("evidence_refs"), errors, f"{path}.evidence_refs")

    broker_requests = data.get("broker_requests")
    derived_scope = None
    if ensure_type(broker_requests, list, errors, f"{path}: broker_requests must be an array"):
        sequences: list[int] = []
        actions: list[str] = []
        for idx, item in enumerate(broker_requests):
            item_where = f"{path}.broker_requests[{idx}]"
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
                ensure(broker_request.get("task_id") == data.get("task_id"), errors, f"{item_where}.broker_request.task_id must match top-level task_id")
                ensure(is_non_empty_string(broker_request.get("requested_by")), errors, f"{item_where}.broker_request.requested_by must be non-empty")
                ensure(isinstance(broker_request.get("inputs"), dict), errors, f"{item_where}.broker_request.inputs must be an object")
            if isinstance(item.get("sequence"), int):
                sequences.append(item["sequence"])
            if isinstance(item.get("action"), str):
                actions.append(item["action"])

        if sequences:
            ensure(sequences == sorted(sequences), errors, f"{path}: broker_requests sequences must be sorted ascending")
            ensure(len(sequences) == len(set(sequences)), errors, f"{path}: broker_requests sequences must be unique")
        if actions:
            derived_scope = classify_requested_host_ops([{"action": action} for action in actions])

    refusal_reasons = data.get("refusal_reasons")
    if ensure_type(refusal_reasons, list, errors, f"{path}: refusal_reasons must be an array"):
        for idx, reason in enumerate(refusal_reasons):
            ensure(is_non_empty_string(reason), errors, f"{path}.refusal_reasons[{idx}] must be non-empty")

    if data.get("intake_status") == "accepted":
        ensure(validation_status.get("summary") == "passed" if isinstance(validation_status, dict) else False, errors, f"{path}: accepted artifact requires validation_status.summary=passed")
        ensure(validation_status.get("host_change_request") == "passed" if isinstance(validation_status, dict) else False, errors, f"{path}: accepted artifact requires validation_status.host_change_request=passed")
        ensure(validation_status.get("cross_document") == "passed" if isinstance(validation_status, dict) else False, errors, f"{path}: accepted artifact requires validation_status.cross_document=passed")
        ensure(len(broker_requests) > 0 if isinstance(broker_requests, list) else False, errors, f"{path}: accepted artifact requires at least one broker_request")
        ensure(len(refusal_reasons) == 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: accepted artifact must not contain refusal_reasons")
    else:
        ensure(data.get("dispatch_status") == "refused", errors, f"{path}: refused artifact requires dispatch_status=refused")
        ensure(len(broker_requests) == 0 if isinstance(broker_requests, list) else False, errors, f"{path}: refused artifact must not contain broker_requests")
        ensure(len(refusal_reasons) > 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: refused artifact requires refusal_reasons")

    if data.get("dispatch_status") == "operator_approval_required":
        ensure(data.get("requires_operator_approval") is True, errors, f"{path}: operator_approval_required requires requires_operator_approval=true")
    if data.get("dispatch_scope") == "unclassified":
        ensure(data.get("intake_status") == "refused", errors, f"{path}: unclassified scope must be refused")
    if derived_scope is not None and data.get("intake_status") == "accepted":
        ensure(data.get("dispatch_scope") == derived_scope, errors, f"{path}: dispatch_scope does not match broker_requests")

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
