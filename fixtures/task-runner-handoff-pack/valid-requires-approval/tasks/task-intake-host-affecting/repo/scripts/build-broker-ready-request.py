#!/usr/bin/env python3
"""Build repo-side broker-ready request and intake report artifacts."""

from __future__ import annotations

from pathlib import Path
import argparse
import importlib.util
import json
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import (  # noqa: E402
    classify_requested_host_ops,
    load_json,
)


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


validate_host_change_request = load_validator("validate-host-change-request")
validate_task_runner_summary = load_validator("validate-task-runner-summary")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate task-runner outputs and assemble repo-side broker-ready dry-run artifacts.",
    )
    parser.add_argument("--summary", required=True, help="Path to outputs/summary.json")
    parser.add_argument("--host-change-request", required=True, help="Path to outputs/host-change-request.json")
    parser.add_argument("--output-dir", required=True, help="Directory to write request.normalized.json and intake-report.json")
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


def merge_forbidden_actions(*groups: object) -> list[str]:
    merged: set[str] = set()
    for group in groups:
        if not isinstance(group, list):
            continue
        for item in group:
            if isinstance(item, str):
                merged.add(item)
    return sorted(merged)


def determine_dispatch_status(intake_status: str, requires_operator_approval: bool) -> str:
    if intake_status == "refused":
        return "refused"
    if requires_operator_approval:
        return "operator_approval_required"
    return "broker_ready"


def build_validation_results(
    summary_errors: list[str],
    request_errors: list[str],
    cross_errors: list[str],
) -> list[dict[str, object]]:
    return [
        {
            "name": "summary",
            "status": "passed" if not summary_errors else "failed",
            "issues": summary_errors,
        },
        {
            "name": "host_change_request",
            "status": "passed" if not request_errors else "failed",
            "issues": request_errors,
        },
        {
            "name": "cross_document",
            "status": "passed" if not cross_errors else "failed",
            "issues": cross_errors,
        },
    ]


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    summary_path = Path(args.summary)
    request_path = Path(args.host_change_request)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    summary_errors = validate_task_runner_summary(summary_path)
    request_errors = validate_host_change_request(request_path)

    summary_data = load_json(summary_path)
    request_data = load_json(request_path)

    cross_errors: list[str] = []
    if isinstance(summary_data, dict) and isinstance(request_data, dict):
        if summary_data.get("task_id") != request_data.get("task_id"):
            cross_errors.append("summary.task_id must match host-change-request.task_id")
        if summary_data.get("requires_operator_approval") != request_data.get("requires_operator_approval"):
            cross_errors.append("requires_operator_approval must match between summary and host-change-request")

        summary_block = summary_data.get("summary")
        if not isinstance(summary_block, dict) or summary_block.get("host_change_needed") is not True:
            cross_errors.append("summary.summary.host_change_needed must be true when assembling host-change intake")

        outputs = summary_data.get("outputs")
        if not isinstance(outputs, dict) or outputs.get("host_change_request") != "outputs/host-change-request.json":
            cross_errors.append("summary.outputs.host_change_request must be outputs/host-change-request.json")

        handoff = summary_data.get("next_handoff")
        if not isinstance(handoff, dict) or handoff.get("consumer") != "main" or handoff.get("action") != "review_host_change_request":
            cross_errors.append("summary.next_handoff must route host-change review to main")

        request_handoff = request_data.get("handoff")
        if not isinstance(request_handoff, dict) or request_handoff.get("broker_request_ready") is not True:
            cross_errors.append("host-change-request.handoff.broker_request_ready must be true")

    requested_host_ops = request_data.get("requested_host_ops") if isinstance(request_data, dict) else None
    dispatch_scope = classify_requested_host_ops(requested_host_ops) or "unclassified"
    intake_status = "accepted" if not (summary_errors or request_errors or cross_errors or dispatch_scope == "unclassified") else "refused"
    requires_operator_approval = bool(request_data.get("requires_operator_approval")) if isinstance(request_data, dict) else False
    dispatch_status = determine_dispatch_status(intake_status, requires_operator_approval)
    refusal_reasons = [*summary_errors, *request_errors, *cross_errors]

    source_artifacts = {
        "summary_path": to_repo_relpath(summary_path),
        "host_change_request_path": to_repo_relpath(request_path),
    }
    summary_context = {
        "goal": str(summary_data.get("summary", {}).get("goal", "")) if isinstance(summary_data, dict) else "",
        "outcome": str(summary_data.get("summary", {}).get("outcome", "")) if isinstance(summary_data, dict) else "",
        "request_title": str(request_data.get("summary", {}).get("title", "")) if isinstance(request_data, dict) else "",
        "request_scope": str(request_data.get("summary", {}).get("scope", "")) if isinstance(request_data, dict) else "",
    }
    validation_status = {
        "summary": "passed" if not summary_errors else "failed",
        "host_change_request": "passed" if not request_errors else "failed",
        "cross_document": "passed" if not cross_errors else "failed",
    }
    forbidden_actions = merge_forbidden_actions(
        summary_data.get("forbidden_actions") if isinstance(summary_data, dict) else None,
        request_data.get("forbidden_actions") if isinstance(request_data, dict) else None,
    )
    evidence_refs = merge_evidence_refs(
        summary_data.get("evidence_refs") if isinstance(summary_data, dict) else None,
        request_data.get("evidence_refs") if isinstance(request_data, dict) else None,
    )
    boundary_carry_forward = {
        "repo_side_only": True,
        "live_side_publish_performed": False,
        "broker_dispatch_performed": False,
        "openclaw_runtime_modified": False,
        "operator_command_blocks_present": False,
    }

    broker_requests: list[dict[str, object]] = []
    if intake_status == "accepted" and isinstance(requested_host_ops, list):
        for op in requested_host_ops:
            if not isinstance(op, dict):
                continue
            sequence = op.get("sequence")
            action = op.get("action")
            justification = op.get("justification")
            inputs = op.get("inputs")
            if not isinstance(sequence, int) or not isinstance(action, str) or not isinstance(justification, str) or not isinstance(inputs, dict):
                continue
            broker_requests.append(
                {
                    "sequence": sequence,
                    "action": action,
                    "justification": justification,
                    "broker_request": {
                        "action": action,
                        "request_id": f"{request_data['request_id']}:op{sequence}",
                        "task_id": request_data["task_id"],
                        "requested_by": "main:intake",
                        "inputs": inputs,
                    },
                }
            )

    normalized_request = {
        "schema_version": "openclaw.main.broker-ready-request.v1alpha1",
        "intake_id": f"intake:{request_data.get('request_id', 'unknown')}",
        "task_id": request_data.get("task_id"),
        "run_id": summary_data.get("run_id"),
        "source_request_id": request_data.get("request_id"),
        "original_requested_by": request_data.get("requested_by"),
        "intake_status": intake_status,
        "dispatch_scope": dispatch_scope,
        "dispatch_status": dispatch_status,
        "requires_operator_approval": requires_operator_approval,
        "source_artifacts": source_artifacts,
        "summary_context": summary_context,
        "validation_status": validation_status,
        "forbidden_actions": forbidden_actions,
        "boundary_carry_forward": boundary_carry_forward,
        "evidence_refs": evidence_refs,
        "broker_requests": broker_requests,
        "refusal_reasons": refusal_reasons,
    }

    intake_report = {
        "schema_version": "openclaw.main.task-runner-intake-report.v1alpha1",
        "intake_id": normalized_request["intake_id"],
        "task_id": request_data.get("task_id"),
        "run_id": summary_data.get("run_id"),
        "source_request_id": request_data.get("request_id"),
        "status": intake_status,
        "dispatch_scope": dispatch_scope,
        "dispatch_status": dispatch_status,
        "requires_operator_approval": requires_operator_approval,
        "source_artifacts": source_artifacts,
        "validation_results": build_validation_results(summary_errors, request_errors, cross_errors),
        "refusal_reasons": refusal_reasons,
        "forbidden_actions": forbidden_actions,
        "boundary_carry_forward": boundary_carry_forward,
        "evidence_refs": evidence_refs,
    }

    (output_dir / "request.normalized.json").write_text(
        json.dumps(normalized_request, indent=2) + "\n",
        encoding="utf-8",
    )
    (output_dir / "intake-report.json").write_text(
        json.dumps(intake_report, indent=2) + "\n",
        encoding="utf-8",
    )

    return 0 if intake_status == "accepted" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
