#!/usr/bin/env python3
"""Build repo-side operator or broker review bundles from submission envelopes."""

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


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build repo-side review bundles from validated submission envelopes.",
    )
    parser.add_argument("--normalized-request", required=True, help="Path to request.normalized.json")
    parser.add_argument("--intake-report", required=True, help="Path to intake-report.json")
    parser.add_argument("--routing-decision", required=True, help="Path to main-routing-decision.json")
    parser.add_argument("--submission-dir", required=True, help="Directory containing submission envelopes")
    parser.add_argument("--output-dir", required=True, help="Directory for review bundle outputs")
    return parser.parse_args(argv)


def to_repo_relpath(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT.resolve()))
    except ValueError:
        return path.as_posix()


def build_validation_status(
    normalized_errors: list[str],
    intake_errors: list[str],
    decision_errors: list[str],
    envelope_errors: list[str],
) -> dict[str, str]:
    return {
        "normalized_request": "passed" if not normalized_errors else "failed",
        "intake_report": "passed" if not intake_errors else "failed",
        "routing_decision": "passed" if not decision_errors else "failed",
        "submission_envelope": "passed" if not envelope_errors else "failed",
    }


def build_common(
    normalized: dict[str, object],
    intake: dict[str, object],
    decision: dict[str, object],
    envelope: dict[str, object],
    normalized_path: Path,
    intake_path: Path,
    decision_path: Path,
    submission_path: Path,
    validation_status: dict[str, str],
) -> dict[str, object]:
    return {
        "routing_decision_id": decision.get("routing_decision_id"),
        "intake_id": decision.get("intake_id"),
        "task_id": decision.get("task_id"),
        "run_id": decision.get("run_id"),
        "source_request_id": decision.get("source_request_id"),
        "decision": decision.get("decision"),
        "submission_target": decision.get("submission_target"),
        "dispatch_scope": decision.get("dispatch_scope"),
        "dispatch_status": decision.get("dispatch_status"),
        "requires_operator_approval": decision.get("requires_operator_approval"),
        "rationale": decision.get("reasoning"),
        "refusal_reason": None,
        "refusal_reasons": decision.get("refusal_reasons"),
        "source_artifacts": {
            "normalized_request_path": to_repo_relpath(normalized_path),
            "intake_report_path": to_repo_relpath(intake_path),
            "routing_decision_path": to_repo_relpath(decision_path),
            "submission_envelope_path": to_repo_relpath(submission_path),
        },
        "summary_context": normalized.get("summary_context"),
        "validation_status": validation_status,
        "broker_requests": normalized.get("broker_requests"),
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
            envelope.get("evidence_refs"),
        ),
    }


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    normalized_path = Path(args.normalized_request)
    intake_path = Path(args.intake_report)
    decision_path = Path(args.routing_decision)
    submission_dir = Path(args.submission_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    normalized_errors = validate_broker_ready_request(normalized_path)
    intake_errors = validate_task_runner_intake_report(intake_path)
    decision_errors = validate_main_routing_decision(decision_path)

    normalized = load_json(normalized_path)
    intake = load_json(intake_path)
    decision = load_json(decision_path)
    if not isinstance(normalized, dict) or not isinstance(intake, dict) or not isinstance(decision, dict):
        raise SystemExit("normalized request, intake report, and routing decision must all be JSON objects")

    route = decision.get("decision")
    if route == "BROKER_SUBMISSION_CANDIDATE":
        submission_path = submission_dir / "broker-submission-envelope.json"
        envelope_errors = validate_broker_submission_envelope(submission_path)
        envelope = load_json(submission_path)
        if not isinstance(envelope, dict):
            raise SystemExit("broker submission envelope must be a JSON object")

        bundle = {
            "schema_version": "openclaw.main.broker-review-bundle.v1alpha1",
            "bundle_id": f"review:broker:{decision.get('intake_id')}",
            "bundle_type": "BROKER_REVIEW_BUNDLE",
            "review_target": "broker",
            "review_status": "pending_broker_review",
            "submission_envelope_id": envelope.get("envelope_id"),
            "submission_envelope_type": envelope.get("envelope_type"),
            "approval_required_reason": None,
            **build_common(
                normalized,
                intake,
                decision,
                envelope,
                normalized_path,
                intake_path,
                decision_path,
                submission_path,
                build_validation_status(normalized_errors, intake_errors, decision_errors, envelope_errors),
            ),
        }
        (output_dir / "broker-review-bundle.json").write_text(json.dumps(bundle, indent=2) + "\n", encoding="utf-8")
    elif route == "REQUIRES_OPERATOR_APPROVAL":
        submission_path = submission_dir / "operator-approval-envelope.json"
        envelope_errors = validate_operator_approval_envelope(submission_path)
        envelope = load_json(submission_path)
        if not isinstance(envelope, dict):
            raise SystemExit("operator approval envelope must be a JSON object")

        bundle = {
            "schema_version": "openclaw.main.operator-review-bundle.v1alpha1",
            "bundle_id": f"review:operator:{decision.get('intake_id')}",
            "bundle_type": "OPERATOR_REVIEW_BUNDLE",
            "review_target": "operator",
            "review_status": "pending_operator_review",
            "submission_envelope_id": envelope.get("envelope_id"),
            "submission_envelope_type": envelope.get("envelope_type"),
            "approval": envelope.get("approval"),
            "approval_required_reason": decision.get("reasoning"),
            **build_common(
                normalized,
                intake,
                decision,
                envelope,
                normalized_path,
                intake_path,
                decision_path,
                submission_path,
                build_validation_status(normalized_errors, intake_errors, decision_errors, envelope_errors),
            ),
        }
        (output_dir / "operator-review-bundle.json").write_text(json.dumps(bundle, indent=2) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
