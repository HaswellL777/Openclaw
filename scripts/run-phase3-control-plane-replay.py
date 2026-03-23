#!/usr/bin/env python3
"""Replay the repo-side phase3 control-plane dry-run into a stable artifact layout."""

from __future__ import annotations

from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import shutil
import sys


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import load_json  # noqa: E402


CANONICAL_ARTIFACTS = [
    ("summary", "summary.json", "validate-task-runner-summary"),
    ("request_normalized", "request.normalized.json", "validate-broker-ready-request"),
    ("intake_report", "intake-report.json", "validate-task-runner-intake-report"),
    ("routing_decision", "routing-decision.json", "validate-main-routing-decision"),
    ("broker_submission_envelope", "broker-submission-envelope.json", "validate-broker-submission-envelope"),
    ("operator_approval_envelope", "operator-approval-envelope.json", "validate-operator-approval-envelope"),
    ("broker_review_bundle", "broker-review-bundle.json", "validate-broker-review-bundle"),
    ("operator_review_bundle", "operator-review-bundle.json", "validate-operator-review-bundle"),
    ("dispatch_intent_ledger", "dispatch-intent-ledger.json", "validate-dispatch-intent-ledger"),
]


def load_module(script_name: str):
    module_name = script_name.replace("-", "_")
    script_path = SCRIPT_DIR / f"{script_name}.py"
    spec = importlib.util.spec_from_file_location(module_name, script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load script module: {script_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BUILD_BROKER_READY_REQUEST = load_module("build-broker-ready-request")
BUILD_MAIN_ROUTING_DECISION = load_module("build-main-routing-decision")
BUILD_SUBMISSION_ENVELOPES = load_module("build-submission-envelopes")
BUILD_REVIEW_BUNDLES = load_module("build-review-bundles")
BUILD_DISPATCH_INTENT_LEDGER = load_module("build-dispatch-intent-ledger")

VALIDATORS = {
    script_name: load_module(script_name).validate_document
    for script_name in {
        "validate-broker-ready-request",
        "validate-task-runner-summary",
        "validate-task-runner-intake-report",
        "validate-main-routing-decision",
        "validate-broker-submission-envelope",
        "validate-operator-approval-envelope",
        "validate-broker-review-bundle",
        "validate-operator-review-bundle",
        "validate-dispatch-intent-ledger",
    }
}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Replay task-runner outputs through the repo-side phase3 control-plane dry-run and emit a stable artifact layout.",
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--fixture-case", help="Fixture case under fixtures/task-runner-intake/")
    source.add_argument("--task-runner-output-dir", help="Directory containing summary.json and host-change-request.json")
    parser.add_argument(
        "--output-root",
        default=str(REPO_ROOT / "artifacts" / "phase3" / "control-plane-dry-run"),
        help="Root directory that will contain <run-id>/",
    )
    parser.add_argument("--run-id", help="Override the output run-id; defaults to summary.run_id")
    parser.add_argument("--force", action="store_true", help="Replace an existing output directory")
    parser.add_argument("--print-run-dir", action="store_true", help="Print the final run directory path")
    return parser.parse_args(argv)


def to_repo_relpath(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT.resolve()))
    except ValueError:
        return path.resolve().as_posix()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_builder(module, argv: list[str], allowed_exit_codes: set[int]) -> int:
    status = int(module.main(argv))
    if status not in allowed_exit_codes:
        raise SystemExit(f"{module.__name__} returned unsupported exit code {status}")
    return status


def validate_artifact(path: Path, validator_name: str) -> None:
    errors = VALIDATORS[validator_name](path)
    if errors:
        detail = "\n".join(f"  - {item}" for item in errors)
        raise SystemExit(f"{path} failed {validator_name}:\n{detail}")


def rewrite_internal_source_artifacts(path: Path, run_dir: Path) -> None:
    data = load_json(path)
    if not isinstance(data, dict):
        return
    source_artifacts = data.get("source_artifacts")
    if not isinstance(source_artifacts, dict):
        return

    changed = False
    for key, value in list(source_artifacts.items()):
        if not isinstance(value, str) or value.strip() == "":
            continue
        candidate = Path(value)
        if candidate.is_absolute():
            resolved = candidate.resolve()
        else:
            resolved = (REPO_ROOT / candidate).resolve()
        try:
            rel = resolved.relative_to(run_dir.resolve())
        except ValueError:
            continue
        source_artifacts[key] = rel.as_posix()
        changed = True

    if changed:
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def determine_layout(decision: str) -> tuple[list[str], list[str]]:
    always_required = [
        "summary.json",
        "request.normalized.json",
        "intake-report.json",
        "routing-decision.json",
        "dispatch-intent-ledger.json",
    ]
    if decision == "BROKER_SUBMISSION_CANDIDATE":
        return (
            [*always_required, "broker-submission-envelope.json", "broker-review-bundle.json"],
            ["operator-approval-envelope.json", "operator-review-bundle.json"],
        )
    if decision == "REQUIRES_OPERATOR_APPROVAL":
        return (
            [*always_required, "operator-approval-envelope.json", "operator-review-bundle.json"],
            ["broker-submission-envelope.json", "broker-review-bundle.json"],
        )
    return (
        always_required,
        [
            "broker-submission-envelope.json",
            "operator-approval-envelope.json",
            "broker-review-bundle.json",
            "operator-review-bundle.json",
        ],
    )


def build_manifest(
    *,
    run_id: str,
    source_kind: str,
    case_name: str | None,
    source_dir: Path,
    summary_source_path: Path,
    request_source_path: Path,
    output_dir: Path,
    intake_exit_code: int,
    routing_exit_code: int,
) -> dict[str, object]:
    routing = load_json(output_dir / "routing-decision.json")
    ledger = load_json(output_dir / "dispatch-intent-ledger.json")
    if not isinstance(routing, dict) or not isinstance(ledger, dict):
        raise SystemExit("routing decision and dispatch intent ledger must both be JSON objects")

    decision = str(routing.get("decision", ""))
    required_artifacts, forbidden_artifacts = determine_layout(decision)

    artifacts: list[dict[str, object]] = []
    for logical_name, file_name, validator_name in CANONICAL_ARTIFACTS:
        artifact_path = output_dir / file_name
        present = artifact_path.is_file()
        entry: dict[str, object] = {
            "name": logical_name,
            "path": file_name,
            "required": file_name in required_artifacts,
            "present": present,
            "validator": f"scripts/{validator_name}.py",
        }
        if present:
            entry["sha256"] = sha256_file(artifact_path)
        artifacts.append(entry)

    manifest = {
        "schema_version": "openclaw.main.control-plane-artifact-manifest.v1alpha1",
        "manifest_id": f"manifest:{run_id}",
        "run_id": run_id,
        "replay_mode": "repo_side_control_plane_dry_run",
        "source": {
            "kind": source_kind,
            "case_name": case_name,
            "input_dir": to_repo_relpath(source_dir),
            "summary_path": to_repo_relpath(summary_source_path),
            "host_change_request_path": to_repo_relpath(request_source_path),
        },
        "builder_exit_codes": {
            "intake": intake_exit_code,
            "routing": routing_exit_code,
            "submission": 0,
            "review": 0,
            "dispatch_intent": 0,
        },
        "route_summary": {
            "decision": routing.get("decision"),
            "dispatch_scope": routing.get("dispatch_scope"),
            "dispatch_status": routing.get("dispatch_status"),
            "requires_operator_approval": routing.get("requires_operator_approval"),
        },
        "boundary_assertions": ledger.get("boundary_carry_forward"),
        "expected_layout": {
            "required_artifacts": required_artifacts,
            "forbidden_artifacts": forbidden_artifacts,
        },
        "artifacts": artifacts,
    }
    return manifest


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.fixture_case:
        source_dir = REPO_ROOT / "fixtures" / "task-runner-intake" / args.fixture_case
        source_kind = "fixture_case"
        case_name = args.fixture_case
    else:
        source_dir = Path(args.task_runner_output_dir).resolve()
        source_kind = "task_runner_output_dir"
        case_name = None

    summary_source_path = source_dir / "summary.json"
    request_source_path = source_dir / "host-change-request.json"
    if not summary_source_path.is_file():
        raise SystemExit(f"summary.json not found: {summary_source_path}")
    if not request_source_path.is_file():
        raise SystemExit(f"host-change-request.json not found: {request_source_path}")

    summary_data = load_json(summary_source_path)
    if not isinstance(summary_data, dict):
        raise SystemExit("summary.json root must be an object")

    run_id = args.run_id or str(summary_data.get("run_id", "")).strip()
    if not run_id:
        raise SystemExit("summary.json must provide run_id or --run-id must be supplied")

    output_root = Path(args.output_root).resolve()
    run_dir = output_root / run_id
    if run_dir.exists():
        if not args.force:
            raise SystemExit(f"output directory already exists: {run_dir}")
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)

    shutil.copy2(summary_source_path, run_dir / "summary.json")
    validate_artifact(run_dir / "summary.json", "validate-task-runner-summary")

    intake_exit_code = run_builder(
        BUILD_BROKER_READY_REQUEST,
        [
            "--summary",
            str(summary_source_path),
            "--host-change-request",
            str(request_source_path),
            "--output-dir",
            str(run_dir),
        ],
        {0, 1},
    )
    validate_artifact(run_dir / "request.normalized.json", "validate-broker-ready-request")
    validate_artifact(run_dir / "intake-report.json", "validate-task-runner-intake-report")

    routing_exit_code = run_builder(
        BUILD_MAIN_ROUTING_DECISION,
        [
            "--normalized-request",
            str(run_dir / "request.normalized.json"),
            "--intake-report",
            str(run_dir / "intake-report.json"),
            "--output",
            str(run_dir / "routing-decision.json"),
        ],
        {0, 1},
    )
    rewrite_internal_source_artifacts(run_dir / "routing-decision.json", run_dir)
    validate_artifact(run_dir / "routing-decision.json", "validate-main-routing-decision")

    run_builder(
        BUILD_SUBMISSION_ENVELOPES,
        [
            "--normalized-request",
            str(run_dir / "request.normalized.json"),
            "--intake-report",
            str(run_dir / "intake-report.json"),
            "--routing-decision",
            str(run_dir / "routing-decision.json"),
            "--output-dir",
            str(run_dir),
        ],
        {0},
    )
    for file_name, validator_name in (
        ("broker-submission-envelope.json", "validate-broker-submission-envelope"),
        ("operator-approval-envelope.json", "validate-operator-approval-envelope"),
    ):
        path = run_dir / file_name
        if path.is_file():
            rewrite_internal_source_artifacts(path, run_dir)
            validate_artifact(path, validator_name)

    run_builder(
        BUILD_REVIEW_BUNDLES,
        [
            "--normalized-request",
            str(run_dir / "request.normalized.json"),
            "--intake-report",
            str(run_dir / "intake-report.json"),
            "--routing-decision",
            str(run_dir / "routing-decision.json"),
            "--submission-dir",
            str(run_dir),
            "--output-dir",
            str(run_dir),
        ],
        {0},
    )
    for file_name, validator_name in (
        ("broker-review-bundle.json", "validate-broker-review-bundle"),
        ("operator-review-bundle.json", "validate-operator-review-bundle"),
    ):
        path = run_dir / file_name
        if path.is_file():
            rewrite_internal_source_artifacts(path, run_dir)
            validate_artifact(path, validator_name)

    run_builder(
        BUILD_DISPATCH_INTENT_LEDGER,
        [
            "--normalized-request",
            str(run_dir / "request.normalized.json"),
            "--intake-report",
            str(run_dir / "intake-report.json"),
            "--routing-decision",
            str(run_dir / "routing-decision.json"),
            "--submission-dir",
            str(run_dir),
            "--review-dir",
            str(run_dir),
            "--output",
            str(run_dir / "dispatch-intent-ledger.json"),
        ],
        {0},
    )
    rewrite_internal_source_artifacts(run_dir / "dispatch-intent-ledger.json", run_dir)
    validate_artifact(run_dir / "dispatch-intent-ledger.json", "validate-dispatch-intent-ledger")

    manifest = build_manifest(
        run_id=run_id,
        source_kind=source_kind,
        case_name=case_name,
        source_dir=source_dir,
        summary_source_path=summary_source_path,
        request_source_path=request_source_path,
        output_dir=run_dir,
        intake_exit_code=intake_exit_code,
        routing_exit_code=routing_exit_code,
    )
    manifest_path = run_dir / "artifact-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    if args.print_run_dir:
        print(run_dir)
    else:
        print(f"Replay artifacts written to {run_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
