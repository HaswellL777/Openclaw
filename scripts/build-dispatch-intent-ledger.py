#!/usr/bin/env python3
"""Build repo-side dispatch intent ledgers from review bundles and routing artifacts."""

from __future__ import annotations

from pathlib import Path
import argparse
import importlib.util
import json
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import load_json, merge_evidence_refs  # noqa: E402


REPO_ROOT = SCRIPT_DIR.parent


def load_validator(script_name: str):
    module_name = script_name.replace("-", "_")
    script_path = SCRIPT_DIR / f"{script_name}.py"
    spec = importlib.util.spec_from_file_location(module_name, script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load validator module: {script_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.validate_document


validate_broker_ready_request = load_validator("validate-broker-ready-request")
validate_task_runner_intake_report = load_validator("validate-task-runner-intake-report")
validate_main_routing_decision = load_validator("validate-main-routing-decision")
validate_broker_submission_envelope = load_validator("validate-broker-submission-envelope")
validate_operator_approval_envelope = load_validator("validate-operator-approval-envelope")
validate_broker_review_bundle = load_validator("validate-broker-review-bundle")
validate_operator_review_bundle = load_validator("validate-operator-review-bundle")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a repo-side dispatch intent ledger from validated control-plane dry-run artifacts.",
    )
    parser.add_argument("--normalized-request", required=True, help="Path to request.normalized.json")
    parser.add_argument("--intake-report", required=True, help="Path to intake-report.json")
    parser.add_argument("--routing-decision", required=True, help="Path to main-routing-decision.json")
    parser.add_argument("--submission-dir", required=True, help="Directory containing submission envelopes")
    parser.add_argument("--review-dir", required=True, help="Directory containing review bundle outputs")
    parser.add_argument("--output", required=True, help="Path to write dispatch-intent-ledger.json")
    return parser.parse_args(argv)


def to_repo_relpath(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT.resolve()))
    except ValueError:
        return path.as_posix()


def first_reason(value: object) -> str | None:
    if not isinstance(value, list):
        return None
    for item in value:
        if isinstance(item, str) and item.strip():
            return item
    return None


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    normalized_path = Path(args.normalized_request)
    intake_path = Path(args.intake_report)
    decision_path = Path(args.routing_decision)
    submission_dir = Path(args.submission_dir)
    review_dir = Path(args.review_dir)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    normalized_errors = validate_broker_ready_request(normalized_path)
    intake_errors = validate_task_runner_intake_report(intake_path)
    decision_errors = validate_main_routing_decision(decision_path)

    normalized = load_json(normalized_path)
    intake = load_json(intake_path)
    decision = load_json(decision_path)
    if not isinstance(normalized, dict) or not isinstance(intake, dict) or not isinstance(decision, dict):
        raise SystemExit("normalized request, intake report, and routing decision must all be JSON objects")

    route = str(decision.get("decision", ""))
    submission_path: Path | None = None
    submission_doc: dict[str, object] | None = None
    submission_errors: list[str] = []
    submission_id: str | None = None
    submission_type: str | None = None
    review_path: Path | None = None
    review_doc: dict[str, object] | None = None
    review_errors: list[str] = []
    review_id: str | None = None
    review_type: str | None = None
    review_target = "none"
    intent_status = "refused_no_dispatch"
    approval_required_reason: str | None = None
    refusal_reason = first_reason(decision.get("refusal_reasons"))
    dispatch_intents = decision.get("decision") and normalized.get("broker_requests") or []

    if route == "BROKER_SUBMISSION_CANDIDATE":
        submission_path = submission_dir / "broker-submission-envelope.json"
        submission_errors = validate_broker_submission_envelope(submission_path)
        submission = load_json(submission_path)
        if not isinstance(submission, dict):
            raise SystemExit("broker submission envelope must be a JSON object")
        submission_doc = submission
        submission_id = str(submission.get("envelope_id"))
        submission_type = str(submission.get("envelope_type"))

        review_path = review_dir / "broker-review-bundle.json"
        review_errors = validate_broker_review_bundle(review_path)
        review = load_json(review_path)
        if not isinstance(review, dict):
            raise SystemExit("broker review bundle must be a JSON object")
        review_doc = review
        review_id = str(review.get("bundle_id"))
        review_type = str(review.get("bundle_type"))
        review_target = "broker"
        intent_status = "pending_broker_review"
        refusal_reason = None
        dispatch_intents = normalized.get("broker_requests")
    elif route == "REQUIRES_OPERATOR_APPROVAL":
        submission_path = submission_dir / "operator-approval-envelope.json"
        submission_errors = validate_operator_approval_envelope(submission_path)
        submission = load_json(submission_path)
        if not isinstance(submission, dict):
            raise SystemExit("operator approval envelope must be a JSON object")
        submission_doc = submission
        submission_id = str(submission.get("envelope_id"))
        submission_type = str(submission.get("envelope_type"))

        review_path = review_dir / "operator-review-bundle.json"
        review_errors = validate_operator_review_bundle(review_path)
        review = load_json(review_path)
        if not isinstance(review, dict):
            raise SystemExit("operator review bundle must be a JSON object")
        review_doc = review
        review_id = str(review.get("bundle_id"))
        review_type = str(review.get("bundle_type"))
        review_target = "operator"
        intent_status = "pending_operator_review"
        approval_required_reason = str(review.get("approval_required_reason"))
        refusal_reason = None
        dispatch_intents = normalized.get("broker_requests")

    source_artifacts = {
        "normalized_request_path": to_repo_relpath(normalized_path),
        "intake_report_path": to_repo_relpath(intake_path),
        "routing_decision_path": to_repo_relpath(decision_path),
    }
    if submission_path is not None:
        source_artifacts["submission_envelope_path"] = to_repo_relpath(submission_path)
    if review_path is not None:
        source_artifacts["review_bundle_path"] = to_repo_relpath(review_path)

    ledger = {
        "schema_version": "openclaw.main.dispatch-intent-ledger.v1alpha1",
        "ledger_id": f"ledger:{decision.get('intake_id')}",
        "routing_decision_id": decision.get("routing_decision_id"),
        "intake_id": decision.get("intake_id"),
        "task_id": decision.get("task_id"),
        "run_id": decision.get("run_id"),
        "source_request_id": decision.get("source_request_id"),
        "decision": decision.get("decision"),
        "submission_target": decision.get("submission_target"),
        "submission_envelope_present": submission_path is not None,
        "submission_envelope_id": submission_id,
        "submission_envelope_type": submission_type,
        "review_target": review_target,
        "review_bundle_present": review_path is not None,
        "review_bundle_id": review_id,
        "review_bundle_type": review_type,
        "intent_status": intent_status,
        "dispatch_scope": decision.get("dispatch_scope"),
        "dispatch_status": decision.get("dispatch_status"),
        "requires_operator_approval": decision.get("requires_operator_approval"),
        "rationale": decision.get("reasoning"),
        "approval_required_reason": approval_required_reason,
        "refusal_reason": refusal_reason,
        "refusal_reasons": decision.get("refusal_reasons"),
        "source_artifacts": source_artifacts,
        "summary_context": normalized.get("summary_context"),
        "validation_status": {
            "normalized_request": "passed" if not normalized_errors else "failed",
            "intake_report": "passed" if not intake_errors else "failed",
            "routing_decision": "passed" if not decision_errors else "failed",
            "submission_envelope": "not_applicable" if submission_path is None else ("passed" if not submission_errors else "failed"),
            "review_bundle": "not_applicable" if review_path is None else ("passed" if not review_errors else "failed"),
        },
        "dispatch_intents": dispatch_intents,
        "forbidden_actions": decision.get("forbidden_actions"),
        "boundary_carry_forward": decision.get("boundary_carry_forward"),
        "dispatch_performed": False,
        "approval_granted": False,
        "runtime_changed": False,
        "operator_command_blocks_present": False,
        "evidence_refs": merge_evidence_refs(
            normalized.get("evidence_refs"),
            intake.get("evidence_refs"),
            decision.get("evidence_refs"),
            submission_doc.get("evidence_refs") if submission_doc is not None else None,
            review_doc.get("evidence_refs") if review_doc is not None else None,
        ),
    }

    output_path.write_text(json.dumps(ledger, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
