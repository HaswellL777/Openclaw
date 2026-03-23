#!/usr/bin/env python3
"""Run the repo-side null-transport dispatch adapter and emit a record-only result."""

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
validate_dispatch_intent_ledger = load_validator("validate-dispatch-intent-ledger")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the repo-side null-transport dispatch adapter and emit a record-only result artifact.",
    )
    parser.add_argument("--normalized-request", required=True, help="Path to request.normalized.json")
    parser.add_argument("--intake-report", required=True, help="Path to intake-report.json")
    parser.add_argument("--routing-decision", required=True, help="Path to main-routing-decision.json")
    parser.add_argument("--dispatch-intent-ledger", required=True, help="Path to dispatch-intent-ledger.json")
    parser.add_argument("--submission-dir", required=True, help="Directory containing submission envelopes")
    parser.add_argument("--review-dir", required=True, help="Directory containing review bundle outputs")
    parser.add_argument("--output", required=True, help="Path to write dispatch-adapter-result.json")
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
    ledger_path = Path(args.dispatch_intent_ledger)
    submission_dir = Path(args.submission_dir)
    review_dir = Path(args.review_dir)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    normalized_errors = validate_broker_ready_request(normalized_path)
    intake_errors = validate_task_runner_intake_report(intake_path)
    decision_errors = validate_main_routing_decision(decision_path)
    ledger_errors = validate_dispatch_intent_ledger(ledger_path)

    normalized = load_json(normalized_path)
    intake = load_json(intake_path)
    decision = load_json(decision_path)
    ledger = load_json(ledger_path)
    if not isinstance(normalized, dict) or not isinstance(intake, dict) or not isinstance(decision, dict) or not isinstance(ledger, dict):
        raise SystemExit("normalized request, intake report, routing decision, and dispatch intent ledger must all be JSON objects")

    route = str(decision.get("decision", ""))
    submission_path: Path | None = None
    submission_doc: dict[str, object] | None = None
    submission_errors: list[str] = []
    review_path: Path | None = None
    review_doc: dict[str, object] | None = None
    review_errors: list[str] = []
    review_bundle_id: str | None = None
    review_bundle_type: str | None = None
    blocked_reason = "null_transport_record_only"
    adapter_status = "broker_candidate_recorded"

    if route == "BROKER_SUBMISSION_CANDIDATE":
        submission_path = submission_dir / "broker-submission-envelope.json"
        submission_errors = validate_broker_submission_envelope(submission_path)
        submission = load_json(submission_path)
        if not isinstance(submission, dict):
            raise SystemExit("broker submission envelope must be a JSON object")
        submission_doc = submission

        review_path = review_dir / "broker-review-bundle.json"
        review_errors = validate_broker_review_bundle(review_path)
        review = load_json(review_path)
        if not isinstance(review, dict):
            raise SystemExit("broker review bundle must be a JSON object")
        review_doc = review
        review_bundle_id = str(review.get("bundle_id"))
        review_bundle_type = str(review.get("bundle_type"))
    elif route == "REQUIRES_OPERATOR_APPROVAL":
        submission_path = submission_dir / "operator-approval-envelope.json"
        submission_errors = validate_operator_approval_envelope(submission_path)
        submission = load_json(submission_path)
        if not isinstance(submission, dict):
            raise SystemExit("operator approval envelope must be a JSON object")
        submission_doc = submission

        review_path = review_dir / "operator-review-bundle.json"
        review_errors = validate_operator_review_bundle(review_path)
        review = load_json(review_path)
        if not isinstance(review, dict):
            raise SystemExit("operator review bundle must be a JSON object")
        review_doc = review
        review_bundle_id = str(review.get("bundle_id"))
        review_bundle_type = str(review.get("bundle_type"))
        blocked_reason = "operator_approval_required"
        adapter_status = "approval_pending_recorded"
    else:
        blocked_reason = str(ledger.get("refusal_reason") or first_reason(ledger.get("refusal_reasons")) or "routing_refused")
        adapter_status = "refusal_recorded"

    source_artifacts = {
        "normalized_request_path": to_repo_relpath(normalized_path),
        "intake_report_path": to_repo_relpath(intake_path),
        "routing_decision_path": to_repo_relpath(decision_path),
        "dispatch_intent_ledger_path": to_repo_relpath(ledger_path),
    }
    if submission_path is not None:
        source_artifacts["submission_envelope_path"] = to_repo_relpath(submission_path)
    if review_path is not None:
        source_artifacts["review_bundle_path"] = to_repo_relpath(review_path)

    result = {
        "schema_version": "openclaw.main.dispatch-adapter-result.v1alpha1",
        "adapter_result_id": f"adapter:{decision.get('intake_id')}",
        "adapter_mode": "dry_run",
        "transport": "null_transport",
        "recording_mode": "record_only",
        "ledger_id": ledger.get("ledger_id"),
        "routing_decision_id": decision.get("routing_decision_id"),
        "intake_id": decision.get("intake_id"),
        "task_id": decision.get("task_id"),
        "run_id": decision.get("run_id"),
        "source_request_id": decision.get("source_request_id"),
        "decision": decision.get("decision"),
        "submission_target": decision.get("submission_target"),
        "review_target": ledger.get("review_target"),
        "review_bundle_present": review_path is not None,
        "review_bundle_id": review_bundle_id,
        "review_bundle_type": review_bundle_type,
        "adapter_status": adapter_status,
        "dispatch_scope": decision.get("dispatch_scope"),
        "dispatch_status": decision.get("dispatch_status"),
        "requires_operator_approval": decision.get("requires_operator_approval"),
        "dispatch_candidate_count": len(ledger.get("dispatch_intents", [])) if isinstance(ledger.get("dispatch_intents"), list) else 0,
        "blocked_reason": blocked_reason,
        "rationale": ledger.get("rationale"),
        "source_artifacts": source_artifacts,
        "summary_context": normalized.get("summary_context"),
        "validation_status": {
            "normalized_request": "passed" if not normalized_errors else "failed",
            "intake_report": "passed" if not intake_errors else "failed",
            "routing_decision": "passed" if not decision_errors else "failed",
            "submission_envelope": "not_applicable" if submission_path is None else ("passed" if not submission_errors else "failed"),
            "review_bundle": "not_applicable" if review_path is None else ("passed" if not review_errors else "failed"),
            "dispatch_intent_ledger": "passed" if not ledger_errors else "failed",
        },
        "dispatch_intents": ledger.get("dispatch_intents"),
        "forbidden_actions": decision.get("forbidden_actions"),
        "boundary_carry_forward": decision.get("boundary_carry_forward"),
        "dispatch_attempted": False,
        "broker_dispatch_performed": False,
        "approval_granted": False,
        "runtime_changed": False,
        "operator_command_blocks_present": False,
        "evidence_refs": merge_evidence_refs(
            normalized.get("evidence_refs"),
            intake.get("evidence_refs"),
            decision.get("evidence_refs"),
            submission_doc.get("evidence_refs") if submission_doc is not None else None,
            review_doc.get("evidence_refs") if review_doc is not None else None,
            ledger.get("evidence_refs"),
        ),
    }

    output_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
