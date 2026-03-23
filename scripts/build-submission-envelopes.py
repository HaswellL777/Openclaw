#!/usr/bin/env python3
"""Build repo-side dry-run submission envelopes from routing decisions."""

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
validate_main_routing_decision = load_validator("validate-main-routing-decision")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build repo-side dry-run submission envelopes from main routing decisions.",
    )
    parser.add_argument("--normalized-request", required=True, help="Path to request.normalized.json")
    parser.add_argument("--intake-report", required=True, help="Path to intake-report.json")
    parser.add_argument("--routing-decision", required=True, help="Path to main-routing-decision.json")
    parser.add_argument("--output-dir", required=True, help="Directory for envelope outputs")
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


def build_source_artifacts(normalized_path: Path, intake_path: Path, decision_path: Path) -> dict[str, str]:
    return {
        "normalized_request_path": to_repo_relpath(normalized_path),
        "intake_report_path": to_repo_relpath(intake_path),
        "routing_decision_path": to_repo_relpath(decision_path),
    }


def build_validation_status(
    normalized_errors: list[str],
    intake_errors: list[str],
    decision_errors: list[str],
) -> dict[str, str]:
    return {
        "normalized_request": "passed" if not normalized_errors else "failed",
        "intake_report": "passed" if not intake_errors else "failed",
        "routing_decision": "passed" if not decision_errors else "failed",
    }


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    normalized_path = Path(args.normalized_request)
    intake_path = Path(args.intake_report)
    decision_path = Path(args.routing_decision)
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

    if normalized.get("intake_id") != decision.get("intake_id") or intake.get("intake_id") != decision.get("intake_id"):
        raise SystemExit("input artifacts must share the same intake_id")

    validation_status = build_validation_status(normalized_errors, intake_errors, decision_errors)
    common = {
        "routing_decision_id": decision.get("routing_decision_id"),
        "envelope_mode": "repo_side_dry_run",
        "intake_id": decision.get("intake_id"),
        "task_id": decision.get("task_id"),
        "run_id": decision.get("run_id"),
        "source_request_id": decision.get("source_request_id"),
        "source_artifacts": build_source_artifacts(normalized_path, intake_path, decision_path),
        "summary_context": normalized.get("summary_context"),
        "validation_status": validation_status,
        "broker_requests": normalized.get("broker_requests"),
        "refusal_reasons": [],
        "forbidden_actions": decision.get("forbidden_actions"),
        "boundary_carry_forward": decision.get("boundary_carry_forward"),
        "evidence_refs": merge_evidence_refs(
            normalized.get("evidence_refs"),
            intake.get("evidence_refs"),
            decision.get("evidence_refs"),
        ),
    }

    route = decision.get("decision")
    if route == "BROKER_SUBMISSION_CANDIDATE":
        envelope = {
            "schema_version": "openclaw.main.broker-submission-envelope.v1alpha1",
            "envelope_id": f"submission:{decision.get('intake_id')}",
            "envelope_type": "BROKER_SUBMISSION_CANDIDATE",
            "dispatch_scope": normalized.get("dispatch_scope"),
            "dispatch_status": normalized.get("dispatch_status"),
            "requires_operator_approval": normalized.get("requires_operator_approval"),
            **common,
        }
        (output_dir / "broker-submission-envelope.json").write_text(
            json.dumps(envelope, indent=2) + "\n",
            encoding="utf-8",
        )
    elif route == "REQUIRES_OPERATOR_APPROVAL":
        envelope = {
            "schema_version": "openclaw.main.operator-approval-envelope.v1alpha1",
            "envelope_id": f"approval:{decision.get('intake_id')}",
            "envelope_type": "REQUIRES_OPERATOR_APPROVAL",
            "dispatch_scope": normalized.get("dispatch_scope"),
            "dispatch_status": normalized.get("dispatch_status"),
            "requires_operator_approval": normalized.get("requires_operator_approval"),
            "approval": {
                "status": "pending_review",
                "exact_command_block_present": False,
            },
            **common,
        }
        (output_dir / "operator-approval-envelope.json").write_text(
            json.dumps(envelope, indent=2) + "\n",
            encoding="utf-8",
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
