#!/usr/bin/env python3
"""Validate repo-side main routing decision artifacts."""

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
SCHEMA_PATH = REPO_ROOT / "schemas" / "main-routing-decision.schema.json"


def usage() -> int:
    print("Usage: scripts/validate-main-routing-decision.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
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
        ensure(is_non_empty_string(value.get(key)), errors, f"{where}.{key} must be a non-empty string")


def validate_validation_status(value: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(value, {"normalized_request", "intake_report", "cross_document"}, errors, where)
    for key in ("normalized_request", "intake_report", "cross_document"):
        ensure(value.get(key) in {"passed", "failed"}, errors, f"{where}.{key} must be passed or failed")


def validate_document(path: Path) -> list[str]:
    errors = validate_schema_file(
        SCHEMA_PATH,
        expected_title="MainRoutingDecision",
        expected_const="openclaw.main.routing-decision.v1alpha1",
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
            "routing_decision_id",
            "routing_mode",
            "intake_id",
            "task_id",
            "run_id",
            "source_request_id",
            "decision",
            "submission_target",
            "intake_status",
            "dispatch_scope",
            "dispatch_status",
            "requires_operator_approval",
            "source_artifacts",
            "summary_context",
            "validation_status",
            "broker_request_count",
            "refusal_reasons",
            "forbidden_actions",
            "boundary_carry_forward",
            "evidence_refs",
            "reasoning",
        },
        errors,
        str(path),
    )

    ensure(data.get("schema_version") == "openclaw.main.routing-decision.v1alpha1", errors, f"{path}: schema_version mismatch")
    ensure(data.get("routing_mode") == "repo_side_dry_run", errors, f"{path}: routing_mode must be repo_side_dry_run")
    for key in ("routing_decision_id", "intake_id", "task_id", "run_id", "source_request_id"):
        ensure(ID_RE.match(str(data.get(key, ""))) is not None, errors, f"{path}: {key} must match contract id format")
    ensure(data.get("decision") in {"LOCAL_REFUSE", "REQUIRES_OPERATOR_APPROVAL", "BROKER_SUBMISSION_CANDIDATE"}, errors, f"{path}: invalid decision")
    ensure(data.get("submission_target") in {"none", "operator_approval_envelope", "broker_submission_envelope"}, errors, f"{path}: invalid submission_target")
    ensure(data.get("intake_status") in {"accepted", "refused"}, errors, f"{path}: invalid intake_status")
    ensure(data.get("dispatch_scope") in {"readonly", "host_affecting", "unclassified"}, errors, f"{path}: invalid dispatch_scope")
    ensure(data.get("dispatch_status") in {"broker_ready", "operator_approval_required", "refused"}, errors, f"{path}: invalid dispatch_status")
    ensure(isinstance(data.get("requires_operator_approval"), bool), errors, f"{path}: requires_operator_approval must be boolean")
    ensure(isinstance(data.get("broker_request_count"), int) and data.get("broker_request_count", -1) >= 0, errors, f"{path}: broker_request_count must be an integer >= 0")
    ensure(is_non_empty_string(data.get("reasoning")), errors, f"{path}: reasoning must be non-empty")

    source_artifacts = data.get("source_artifacts")
    if ensure_type(source_artifacts, dict, errors, f"{path}: source_artifacts must be an object"):
        reject_extra_keys(source_artifacts, {"normalized_request_path", "intake_report_path"}, errors, f"{path}.source_artifacts")
        ensure(is_relative_path(source_artifacts.get("normalized_request_path")), errors, f"{path}.source_artifacts.normalized_request_path must be a relative path")
        ensure(is_relative_path(source_artifacts.get("intake_report_path")), errors, f"{path}.source_artifacts.intake_report_path must be a relative path")

    validate_summary_context(data.get("summary_context"), errors, f"{path}.summary_context")
    validate_validation_status(data.get("validation_status"), errors, f"{path}.validation_status")
    validate_forbidden_actions(data.get("forbidden_actions"), errors, f"{path}.forbidden_actions")
    validate_boundary_carry_forward(data.get("boundary_carry_forward"), errors, f"{path}.boundary_carry_forward")
    validate_evidence_refs(data.get("evidence_refs"), errors, f"{path}.evidence_refs")

    refusal_reasons = data.get("refusal_reasons")
    if ensure_type(refusal_reasons, list, errors, f"{path}: refusal_reasons must be an array"):
        for idx, reason in enumerate(refusal_reasons):
            ensure(is_non_empty_string(reason), errors, f"{path}.refusal_reasons[{idx}] must be non-empty")

    decision = data.get("decision")
    dispatch_scope = data.get("dispatch_scope")
    dispatch_status = data.get("dispatch_status")
    requires_operator_approval = data.get("requires_operator_approval")
    broker_request_count = data.get("broker_request_count")

    if decision == "LOCAL_REFUSE":
        ensure(data.get("submission_target") == "none", errors, f"{path}: LOCAL_REFUSE requires submission_target=none")
        ensure(len(refusal_reasons) > 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: LOCAL_REFUSE requires refusal_reasons")
    elif decision == "REQUIRES_OPERATOR_APPROVAL":
        ensure(data.get("submission_target") == "operator_approval_envelope", errors, f"{path}: approval route requires operator_approval_envelope")
        ensure(data.get("intake_status") == "accepted", errors, f"{path}: approval route requires accepted intake_status")
        ensure(dispatch_scope == "host_affecting", errors, f"{path}: approval route requires dispatch_scope=host_affecting")
        ensure(dispatch_status == "operator_approval_required", errors, f"{path}: approval route requires dispatch_status=operator_approval_required")
        ensure(requires_operator_approval is True, errors, f"{path}: approval route requires requires_operator_approval=true")
        ensure(broker_request_count > 0, errors, f"{path}: approval route requires broker_request_count > 0")
        ensure(len(refusal_reasons) == 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: approval route must not contain refusal_reasons")
    else:
        ensure(data.get("submission_target") == "broker_submission_envelope", errors, f"{path}: broker submission route requires broker_submission_envelope")
        ensure(data.get("intake_status") == "accepted", errors, f"{path}: broker submission route requires accepted intake_status")
        ensure(dispatch_scope == "readonly", errors, f"{path}: broker submission route requires dispatch_scope=readonly")
        ensure(dispatch_status == "broker_ready", errors, f"{path}: broker submission route requires dispatch_status=broker_ready")
        ensure(requires_operator_approval is False, errors, f"{path}: broker submission route requires requires_operator_approval=false")
        ensure(broker_request_count > 0, errors, f"{path}: broker submission route requires broker_request_count > 0")
        ensure(len(refusal_reasons) == 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: broker submission route must not contain refusal_reasons")

    validation_status = data.get("validation_status")
    if isinstance(validation_status, dict) and decision != "LOCAL_REFUSE":
        for key in ("normalized_request", "intake_report", "cross_document"):
            ensure(validation_status.get(key) == "passed", errors, f"{path}: accepted routes require validation_status.{key}=passed")

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
