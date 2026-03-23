#!/usr/bin/env python3
"""Validate repo-side dispatch intent ledger artifacts."""

from __future__ import annotations

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import (  # noqa: E402
    ALLOWED_ACTIONS,
    ID_RE,
    LEDGER_VALIDATION_RESULTS,
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
SCHEMA_PATH = REPO_ROOT / "schemas" / "dispatch-intent-ledger.schema.json"


def usage() -> int:
    print("Usage: scripts/validate-dispatch-intent-ledger.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
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
    reject_extra_keys(
        value,
        {"normalized_request", "intake_report", "routing_decision", "submission_envelope", "review_bundle"},
        errors,
        where,
    )
    for key in ("normalized_request", "intake_report", "routing_decision", "submission_envelope", "review_bundle"):
        ensure(value.get(key) in LEDGER_VALIDATION_RESULTS, errors, f"{where}.{key} must be passed, failed, or not_applicable")


def validate_dispatch_intents(value: object, task_id: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, list, errors, f"{where} must be an array"):
        return
    sequences: list[int] = []
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
    if sequences:
        ensure(sequences == sorted(sequences), errors, f"{where} sequences must be sorted ascending")
        ensure(len(sequences) == len(set(sequences)), errors, f"{where} sequences must be unique")


def validate_nullable_id(value: object, errors: list[str], where: str) -> None:
    if value is None:
        return
    ensure(ID_RE.match(str(value)) is not None, errors, f"{where} must be null or match the contract id format")


def validate_document(path: Path) -> list[str]:
    errors = validate_schema_file(
        SCHEMA_PATH,
        expected_title="DispatchIntentLedger",
        expected_const="openclaw.main.dispatch-intent-ledger.v1alpha1",
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
            "ledger_id",
            "routing_decision_id",
            "intake_id",
            "task_id",
            "run_id",
            "source_request_id",
            "decision",
            "submission_target",
            "submission_envelope_present",
            "submission_envelope_id",
            "submission_envelope_type",
            "review_target",
            "review_bundle_present",
            "review_bundle_id",
            "review_bundle_type",
            "intent_status",
            "dispatch_scope",
            "dispatch_status",
            "requires_operator_approval",
            "rationale",
            "approval_required_reason",
            "refusal_reason",
            "refusal_reasons",
            "source_artifacts",
            "summary_context",
            "validation_status",
            "dispatch_intents",
            "forbidden_actions",
            "boundary_carry_forward",
            "dispatch_performed",
            "approval_granted",
            "runtime_changed",
            "operator_command_blocks_present",
            "evidence_refs",
        },
        errors,
        str(path),
    )

    ensure(data.get("schema_version") == "openclaw.main.dispatch-intent-ledger.v1alpha1", errors, f"{path}: schema_version mismatch")
    for key in ("ledger_id", "routing_decision_id", "intake_id", "task_id", "run_id", "source_request_id"):
        ensure(ID_RE.match(str(data.get(key, ""))) is not None, errors, f"{path}: {key} must match contract id format")
    validate_nullable_id(data.get("submission_envelope_id"), errors, f"{path}: submission_envelope_id")
    validate_nullable_id(data.get("review_bundle_id"), errors, f"{path}: review_bundle_id")
    ensure(data.get("decision") in {"LOCAL_REFUSE", "REQUIRES_OPERATOR_APPROVAL", "BROKER_SUBMISSION_CANDIDATE"}, errors, f"{path}: invalid decision")
    ensure(data.get("submission_target") in {"none", "operator_approval_envelope", "broker_submission_envelope"}, errors, f"{path}: invalid submission_target")
    ensure(data.get("submission_envelope_present") in {True, False}, errors, f"{path}: submission_envelope_present must be boolean")
    ensure(data.get("review_target") in {"none", "operator", "broker"}, errors, f"{path}: invalid review_target")
    ensure(data.get("review_bundle_present") in {True, False}, errors, f"{path}: review_bundle_present must be boolean")
    ensure(data.get("review_bundle_type") in {"OPERATOR_REVIEW_BUNDLE", "BROKER_REVIEW_BUNDLE", None}, errors, f"{path}: invalid review_bundle_type")
    ensure(data.get("submission_envelope_type") in {"REQUIRES_OPERATOR_APPROVAL", "BROKER_SUBMISSION_CANDIDATE", None}, errors, f"{path}: invalid submission_envelope_type")
    ensure(data.get("intent_status") in {"refused_no_dispatch", "pending_operator_review", "pending_broker_review"}, errors, f"{path}: invalid intent_status")
    ensure(data.get("dispatch_scope") in {"readonly", "host_affecting", "unclassified"}, errors, f"{path}: invalid dispatch_scope")
    ensure(data.get("dispatch_status") in {"broker_ready", "operator_approval_required", "refused"}, errors, f"{path}: invalid dispatch_status")
    ensure(isinstance(data.get("requires_operator_approval"), bool), errors, f"{path}: requires_operator_approval must be boolean")
    ensure(is_non_empty_string(data.get("rationale")), errors, f"{path}: rationale must be non-empty")
    ensure(data.get("dispatch_performed") is False, errors, f"{path}: dispatch_performed must be false")
    ensure(data.get("approval_granted") is False, errors, f"{path}: approval_granted must be false")
    ensure(data.get("runtime_changed") is False, errors, f"{path}: runtime_changed must be false")
    ensure(data.get("operator_command_blocks_present") is False, errors, f"{path}: operator_command_blocks_present must be false")

    approval_required_reason = data.get("approval_required_reason")
    if approval_required_reason is not None:
        ensure(is_non_empty_string(approval_required_reason), errors, f"{path}: approval_required_reason must be null or non-empty")
    refusal_reason = data.get("refusal_reason")
    if refusal_reason is not None:
        ensure(is_non_empty_string(refusal_reason), errors, f"{path}: refusal_reason must be null or non-empty")

    source_artifacts = data.get("source_artifacts")
    if ensure_type(source_artifacts, dict, errors, f"{path}: source_artifacts must be an object"):
        reject_extra_keys(
            source_artifacts,
            {"normalized_request_path", "intake_report_path", "routing_decision_path", "submission_envelope_path", "review_bundle_path"},
            errors,
            f"{path}.source_artifacts",
        )
        for key in ("normalized_request_path", "intake_report_path", "routing_decision_path"):
            ensure(is_relative_path(source_artifacts.get(key)), errors, f"{path}.source_artifacts.{key} must be a relative path")
        for key in ("submission_envelope_path", "review_bundle_path"):
            if key in source_artifacts:
                ensure(is_relative_path(source_artifacts.get(key)), errors, f"{path}.source_artifacts.{key} must be a relative path")

    validate_summary_context(data.get("summary_context"), errors, f"{path}.summary_context")
    validate_validation_status(data.get("validation_status"), errors, f"{path}.validation_status")
    validate_dispatch_intents(data.get("dispatch_intents"), data.get("task_id"), errors, f"{path}.dispatch_intents")

    refusal_reasons = data.get("refusal_reasons")
    if ensure_type(refusal_reasons, list, errors, f"{path}: refusal_reasons must be an array"):
        for idx, reason in enumerate(refusal_reasons):
            ensure(is_non_empty_string(reason), errors, f"{path}.refusal_reasons[{idx}] must be non-empty")

    validate_forbidden_actions(data.get("forbidden_actions"), errors, f"{path}.forbidden_actions")
    validate_boundary_carry_forward(data.get("boundary_carry_forward"), errors, f"{path}.boundary_carry_forward")
    validate_evidence_refs(data.get("evidence_refs"), errors, f"{path}.evidence_refs")

    decision = data.get("decision")
    validation_status = data.get("validation_status")
    dispatch_intents = data.get("dispatch_intents")
    if decision == "LOCAL_REFUSE":
        ensure(data.get("submission_target") == "none", errors, f"{path}: LOCAL_REFUSE requires submission_target=none")
        ensure(data.get("submission_envelope_present") is False, errors, f"{path}: LOCAL_REFUSE requires submission_envelope_present=false")
        ensure(data.get("submission_envelope_id") is None, errors, f"{path}: LOCAL_REFUSE requires submission_envelope_id=null")
        ensure(data.get("submission_envelope_type") is None, errors, f"{path}: LOCAL_REFUSE requires submission_envelope_type=null")
        ensure(data.get("review_target") == "none", errors, f"{path}: LOCAL_REFUSE requires review_target=none")
        ensure(data.get("review_bundle_present") is False, errors, f"{path}: LOCAL_REFUSE requires review_bundle_present=false")
        ensure(data.get("review_bundle_id") is None, errors, f"{path}: LOCAL_REFUSE requires review_bundle_id=null")
        ensure(data.get("review_bundle_type") is None, errors, f"{path}: LOCAL_REFUSE requires review_bundle_type=null")
        ensure(data.get("intent_status") == "refused_no_dispatch", errors, f"{path}: LOCAL_REFUSE requires intent_status=refused_no_dispatch")
        ensure(data.get("dispatch_status") == "refused", errors, f"{path}: LOCAL_REFUSE requires dispatch_status=refused")
        ensure(len(dispatch_intents) == 0 if isinstance(dispatch_intents, list) else False, errors, f"{path}: LOCAL_REFUSE requires empty dispatch_intents")
        ensure(is_non_empty_string(refusal_reason), errors, f"{path}: LOCAL_REFUSE requires refusal_reason")
        ensure(len(refusal_reasons) > 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: LOCAL_REFUSE requires refusal_reasons")
        ensure(approval_required_reason is None, errors, f"{path}: LOCAL_REFUSE requires approval_required_reason=null")
        if isinstance(validation_status, dict):
            ensure(validation_status.get("submission_envelope") == "not_applicable", errors, f"{path}: LOCAL_REFUSE requires submission_envelope=not_applicable")
            ensure(validation_status.get("review_bundle") == "not_applicable", errors, f"{path}: LOCAL_REFUSE requires review_bundle=not_applicable")
    elif decision == "REQUIRES_OPERATOR_APPROVAL":
        ensure(data.get("submission_target") == "operator_approval_envelope", errors, f"{path}: approval route requires submission_target=operator_approval_envelope")
        ensure(data.get("submission_envelope_present") is True, errors, f"{path}: approval route requires submission_envelope_present=true")
        ensure(data.get("submission_envelope_type") == "REQUIRES_OPERATOR_APPROVAL", errors, f"{path}: approval route requires submission_envelope_type=REQUIRES_OPERATOR_APPROVAL")
        ensure(data.get("review_target") == "operator", errors, f"{path}: approval route requires review_target=operator")
        ensure(data.get("review_bundle_present") is True, errors, f"{path}: approval route requires review_bundle_present=true")
        ensure(data.get("review_bundle_type") == "OPERATOR_REVIEW_BUNDLE", errors, f"{path}: approval route requires review_bundle_type=OPERATOR_REVIEW_BUNDLE")
        ensure(data.get("intent_status") == "pending_operator_review", errors, f"{path}: approval route requires intent_status=pending_operator_review")
        ensure(data.get("dispatch_scope") == "host_affecting", errors, f"{path}: approval route requires dispatch_scope=host_affecting")
        ensure(data.get("dispatch_status") == "operator_approval_required", errors, f"{path}: approval route requires dispatch_status=operator_approval_required")
        ensure(data.get("requires_operator_approval") is True, errors, f"{path}: approval route requires requires_operator_approval=true")
        ensure(is_non_empty_string(approval_required_reason), errors, f"{path}: approval route requires approval_required_reason")
        ensure(refusal_reason is None, errors, f"{path}: approval route requires refusal_reason=null")
        ensure(len(refusal_reasons) == 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: approval route requires empty refusal_reasons")
        ensure(len(dispatch_intents) > 0 if isinstance(dispatch_intents, list) else False, errors, f"{path}: approval route requires dispatch_intents")
        if isinstance(validation_status, dict):
            ensure(validation_status.get("submission_envelope") == "passed", errors, f"{path}: approval route requires submission_envelope=passed")
            ensure(validation_status.get("review_bundle") == "passed", errors, f"{path}: approval route requires review_bundle=passed")
    else:
        ensure(data.get("submission_target") == "broker_submission_envelope", errors, f"{path}: broker route requires submission_target=broker_submission_envelope")
        ensure(data.get("submission_envelope_present") is True, errors, f"{path}: broker route requires submission_envelope_present=true")
        ensure(data.get("submission_envelope_type") == "BROKER_SUBMISSION_CANDIDATE", errors, f"{path}: broker route requires submission_envelope_type=BROKER_SUBMISSION_CANDIDATE")
        ensure(data.get("review_target") == "broker", errors, f"{path}: broker route requires review_target=broker")
        ensure(data.get("review_bundle_present") is True, errors, f"{path}: broker route requires review_bundle_present=true")
        ensure(data.get("review_bundle_type") == "BROKER_REVIEW_BUNDLE", errors, f"{path}: broker route requires review_bundle_type=BROKER_REVIEW_BUNDLE")
        ensure(data.get("intent_status") == "pending_broker_review", errors, f"{path}: broker route requires intent_status=pending_broker_review")
        ensure(data.get("dispatch_scope") == "readonly", errors, f"{path}: broker route requires dispatch_scope=readonly")
        ensure(data.get("dispatch_status") == "broker_ready", errors, f"{path}: broker route requires dispatch_status=broker_ready")
        ensure(data.get("requires_operator_approval") is False, errors, f"{path}: broker route requires requires_operator_approval=false")
        ensure(approval_required_reason is None, errors, f"{path}: broker route requires approval_required_reason=null")
        ensure(refusal_reason is None, errors, f"{path}: broker route requires refusal_reason=null")
        ensure(len(refusal_reasons) == 0 if isinstance(refusal_reasons, list) else False, errors, f"{path}: broker route requires empty refusal_reasons")
        ensure(len(dispatch_intents) > 0 if isinstance(dispatch_intents, list) else False, errors, f"{path}: broker route requires dispatch_intents")
        if isinstance(validation_status, dict):
            ensure(validation_status.get("submission_envelope") == "passed", errors, f"{path}: broker route requires submission_envelope=passed")
            ensure(validation_status.get("review_bundle") == "passed", errors, f"{path}: broker route requires review_bundle=passed")

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
