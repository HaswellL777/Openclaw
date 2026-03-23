#!/usr/bin/env python3
"""Build repo-side main routing decisions from normalized intake artifacts."""

from __future__ import annotations

from pathlib import Path
import argparse
import importlib.util
import json
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import load_json  # noqa: E402


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


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a repo-side main routing decision from normalized intake artifacts.",
    )
    parser.add_argument("--normalized-request", required=True, help="Path to request.normalized.json")
    parser.add_argument("--intake-report", required=True, help="Path to intake-report.json")
    parser.add_argument("--output", required=True, help="Path to write main-routing-decision.json")
    return parser.parse_args(argv)


def to_repo_relpath(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT.resolve()))
    except ValueError:
        return path.as_posix()


def merge_evidence_refs(*groups: object) -> list[dict[str, object]]:
    merged: list[dict[str, object]] = []
    seen: set[tuple[str, str, str]] = set()
    for group in groups:
        if not isinstance(group, list):
            continue
        for item in group:
            if not isinstance(item, dict):
                continue
            marker = (
                str(item.get("id", "")),
                str(item.get("kind", "")),
                str(item.get("path", "")),
            )
            if marker in seen:
                continue
            seen.add(marker)
            merged.append(item)
    return merged


def merge_strings(*groups: object) -> list[str]:
    merged: list[str] = []
    seen: set[str] = set()
    for group in groups:
        if not isinstance(group, list):
            continue
        for item in group:
            if not isinstance(item, str):
                continue
            if item in seen:
                continue
            seen.add(item)
            merged.append(item)
    return merged


def compute_cross_errors(normalized: dict[str, object], intake: dict[str, object]) -> list[str]:
    errors: list[str] = []
    checks = [
        ("intake_id", "intake_id"),
        ("task_id", "task_id"),
        ("run_id", "run_id"),
        ("source_request_id", "source_request_id"),
        ("intake_status", "status"),
        ("dispatch_scope", "dispatch_scope"),
        ("dispatch_status", "dispatch_status"),
        ("requires_operator_approval", "requires_operator_approval"),
    ]
    for normalized_key, intake_key in checks:
        if normalized.get(normalized_key) != intake.get(intake_key):
            errors.append(f"{normalized_key} must match between normalized request and intake report")

    if normalized.get("boundary_carry_forward") != intake.get("boundary_carry_forward"):
        errors.append("boundary_carry_forward must match between normalized request and intake report")
    if normalized.get("forbidden_actions") != intake.get("forbidden_actions"):
        errors.append("forbidden_actions must match between normalized request and intake report")
    if normalized.get("refusal_reasons") != intake.get("refusal_reasons"):
        errors.append("refusal_reasons must match between normalized request and intake report")

    dispatch_scope = normalized.get("dispatch_scope")
    dispatch_status = normalized.get("dispatch_status")
    requires_operator_approval = normalized.get("requires_operator_approval")
    broker_requests = normalized.get("broker_requests")

    if dispatch_scope == "host_affecting" and dispatch_status == "operator_approval_required" and requires_operator_approval is not True:
        errors.append("host-affecting normalized requests must keep requires_operator_approval=true")
    if dispatch_status == "broker_ready" and (not isinstance(broker_requests, list) or len(broker_requests) == 0):
        errors.append("broker_ready normalized requests require at least one broker_request")

    return errors


def determine_decision(
    intake_status: str,
    dispatch_status: str,
    requires_operator_approval: bool,
    broker_request_count: int,
    refusal_reasons: list[str],
    validation_status: dict[str, str],
) -> tuple[str, str, str]:
    if (
        intake_status != "accepted"
        or dispatch_status == "refused"
        or refusal_reasons
        or any(value != "passed" for value in validation_status.values())
    ):
        return (
            "LOCAL_REFUSE",
            "none",
            "Main keeps the request local because intake or cross-document validation refused it.",
        )
    if requires_operator_approval or dispatch_status == "operator_approval_required":
        return (
            "REQUIRES_OPERATOR_APPROVAL",
            "operator_approval_envelope",
            "Main preserves operator approval for an accepted host-affecting request and emits only a dry-run approval envelope.",
        )
    if dispatch_status == "broker_ready" and broker_request_count > 0:
        return (
            "BROKER_SUBMISSION_CANDIDATE",
            "broker_submission_envelope",
            "Main preserves the accepted readonly request as a dry-run broker submission candidate without dispatching it.",
        )
    return (
        "LOCAL_REFUSE",
        "none",
        "Main keeps the request local because the normalized intake did not resolve to an accepted dry-run route.",
    )


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    normalized_path = Path(args.normalized_request)
    intake_path = Path(args.intake_report)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    normalized_errors = validate_broker_ready_request(normalized_path)
    intake_errors = validate_task_runner_intake_report(intake_path)

    normalized = load_json(normalized_path)
    intake = load_json(intake_path)
    if not isinstance(normalized, dict) or not isinstance(intake, dict):
        raise SystemExit("normalized request and intake report must both be JSON objects")

    cross_errors = compute_cross_errors(normalized, intake)
    refusal_reasons = merge_strings(
        normalized.get("refusal_reasons"),
        intake.get("refusal_reasons"),
        normalized_errors,
        intake_errors,
        cross_errors,
    )
    validation_status = {
        "normalized_request": "passed" if not normalized_errors else "failed",
        "intake_report": "passed" if not intake_errors else "failed",
        "cross_document": "passed" if not cross_errors else "failed",
    }
    broker_requests = normalized.get("broker_requests")
    broker_request_count = len(broker_requests) if isinstance(broker_requests, list) else 0
    requires_operator_approval = bool(normalized.get("requires_operator_approval"))
    decision, submission_target, reasoning = determine_decision(
        intake_status=str(normalized.get("intake_status", "")),
        dispatch_status=str(normalized.get("dispatch_status", "")),
        requires_operator_approval=requires_operator_approval,
        broker_request_count=broker_request_count,
        refusal_reasons=refusal_reasons,
        validation_status=validation_status,
    )

    routing_decision = {
        "schema_version": "openclaw.main.routing-decision.v1alpha1",
        "routing_decision_id": f"route:{normalized.get('intake_id', 'unknown')}",
        "routing_mode": "repo_side_dry_run",
        "intake_id": normalized.get("intake_id"),
        "task_id": normalized.get("task_id"),
        "run_id": normalized.get("run_id"),
        "source_request_id": normalized.get("source_request_id"),
        "decision": decision,
        "submission_target": submission_target,
        "intake_status": normalized.get("intake_status"),
        "dispatch_scope": normalized.get("dispatch_scope"),
        "dispatch_status": normalized.get("dispatch_status"),
        "requires_operator_approval": requires_operator_approval,
        "source_artifacts": {
            "normalized_request_path": to_repo_relpath(normalized_path),
            "intake_report_path": to_repo_relpath(intake_path),
        },
        "summary_context": normalized.get("summary_context"),
        "validation_status": validation_status,
        "broker_request_count": broker_request_count,
        "refusal_reasons": refusal_reasons,
        "forbidden_actions": merge_strings(
            normalized.get("forbidden_actions"),
            intake.get("forbidden_actions"),
        ),
        "boundary_carry_forward": normalized.get("boundary_carry_forward"),
        "evidence_refs": merge_evidence_refs(
            normalized.get("evidence_refs"),
            intake.get("evidence_refs"),
        ),
        "reasoning": reasoning,
    }

    output_path.write_text(json.dumps(routing_decision, indent=2) + "\n", encoding="utf-8")
    return 0 if decision != "LOCAL_REFUSE" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
