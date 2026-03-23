#!/usr/bin/env python3
"""Shared contracts for the first-live-pilot candidate pack."""

from __future__ import annotations

from pathlib import Path
import hashlib


CANDIDATE_ID = "first-live-pilot-candidate-20260323-v1"
PACK_ROOT_RELATIVE = "candidates/phase3/first-live-pilot-candidate"
PACK_FILE_NAMES = [
    "candidate-summary.json",
    "candidate-manifest.json",
    "control-plane-asset-index.json",
    "execution-plane-asset-index.json",
    "handoff-pack-asset-index.json",
    "readiness-assertions.json",
    "frozen-input-refs.json",
]

READY_STATE = "READY_TO_PREPARE_FIRST_LIVE_PILOT_CANDIDATE"
REMAINING_BLOCKER = "future_execution_seam_or_operator_input"

AUTHORITY_DOCS = [
    "docs/design-v3.md",
    "docs/host-sop.md",
    "docs/current-boundary.md",
    "docs/map.md",
]

PLANE_SPECS = {
    "control_plane": [
        {
            "group": "pipeline_scripts",
            "category": "script",
            "role": "builder",
            "files": [
                "scripts/build-broker-ready-request.py",
                "scripts/build-main-routing-decision.py",
                "scripts/build-submission-envelopes.py",
                "scripts/build-review-bundles.py",
                "scripts/build-dispatch-intent-ledger.py",
                "scripts/run-dispatch-adapter.py",
                "scripts/run-phase3-control-plane-replay.py",
                "scripts/run-phase3-control-plane-replay.sh",
            ],
        },
        {
            "group": "contract_validators",
            "category": "validator",
            "role": "validation",
            "files": [
                "scripts/validate-broker-ready-request.py",
                "scripts/validate-task-runner-intake-report.py",
                "scripts/validate-main-routing-decision.py",
                "scripts/validate-broker-submission-envelope.py",
                "scripts/validate-operator-approval-envelope.py",
                "scripts/validate-broker-review-bundle.py",
                "scripts/validate-operator-review-bundle.py",
                "scripts/validate-dispatch-intent-ledger.py",
                "scripts/validate-dispatch-adapter-result.py",
                "scripts/validate-control-plane-artifact-manifest.py",
            ],
        },
        {
            "group": "checks",
            "category": "check",
            "role": "verification",
            "files": [
                "scripts/check-main-routing-flow.sh",
                "scripts/check-phase3-control-plane-artifact-layout.sh",
                "scripts/check-phase3-control-plane-dry-run.sh",
                "tests/test_phase3_control_plane_artifact_layout.sh",
                "tests/test_phase3_control_plane_dry_run.sh",
                "tests/test_phase3_dispatch_adapter_flow.sh",
            ],
        },
        {
            "group": "golden_case_valid_readonly",
            "category": "fixture",
            "role": "golden_case",
            "dirs": ["fixtures/control-plane-replay/valid-readonly"],
        },
        {
            "group": "golden_case_valid_host_affecting",
            "category": "fixture",
            "role": "golden_case",
            "dirs": ["fixtures/control-plane-replay/valid-host-affecting"],
        },
        {
            "group": "golden_case_valid_broker_submission_candidate",
            "category": "fixture",
            "role": "golden_case",
            "dirs": ["fixtures/control-plane-replay/valid-broker-submission-candidate"],
        },
    ],
    "execution_plane": [
        {
            "group": "container_scaffold",
            "category": "container_scaffold",
            "role": "execution_plane",
            "dirs": ["task-runner-container"],
        },
        {
            "group": "workspace_template",
            "category": "workspace_template",
            "role": "execution_plane",
            "dirs": ["workspace-task-runner-template"],
        },
        {
            "group": "contracts_and_checks",
            "category": "contract",
            "role": "verification",
            "files": [
                "scripts/check-task-runner-container-spec.sh",
                "scripts/check-workspace-task-runner-template.sh",
                "scripts/validate-task-runner-exec-plan.py",
                "scripts/validate-task-runner-workspace-layout.py",
                "scripts/lib/task_runner_container_contracts.py",
            ],
        },
        {
            "group": "exec_plan_fixtures",
            "category": "fixture",
            "role": "execution_contract_fixture",
            "files": [
                "fixtures/task-runner-exec-plan/valid-dev-workspace.json",
                "fixtures/task-runner-exec-plan/valid-readonly-workspace.json",
            ],
        },
        {
            "group": "workspace_layout_fixtures",
            "category": "fixture",
            "role": "execution_contract_fixture",
            "files": [
                "fixtures/task-runner-workspace-layout/valid-dev-workspace.json",
                "fixtures/task-runner-workspace-layout/valid-readonly-workspace.json",
            ],
        },
    ],
    "handoff_pack": [
        {
            "group": "handoff_scripts",
            "category": "script",
            "role": "builder",
            "files": [
                "scripts/build-task-runner-handoff-pack.py",
                "scripts/validate-task-runner-handoff-manifest.py",
                "scripts/check-task-runner-handoff-pack.sh",
                "scripts/lib/task_runner_handoff_contracts.py",
                "tests/test_task_runner_handoff_pack.sh",
            ],
        },
        {
            "group": "handoff_fixture_valid_readonly",
            "category": "fixture",
            "role": "handoff_fixture",
            "dirs": ["fixtures/task-runner-handoff-pack/valid-readonly"],
        },
        {
            "group": "handoff_fixture_valid_requires_approval",
            "category": "fixture",
            "role": "handoff_fixture",
            "dirs": ["fixtures/task-runner-handoff-pack/valid-requires-approval"],
        },
    ],
}

HANDOFF_ANCHORS = [
    {
        "anchor_id": "anchor:task-intake-readonly",
        "task_id": "task-intake-readonly",
        "dispatch_scope": "readonly",
        "workspace_mode": "readonly",
        "review_target": "broker",
        "reviewed_task_path": "fixtures/control-plane-replay/valid-readonly/broker-review-bundle.json",
        "summary_path": "fixtures/control-plane-replay/valid-readonly/summary.json",
        "handoff_manifest_path": "fixtures/task-runner-handoff-pack/valid-readonly/tasks/task-intake-readonly/handoff-manifest.json",
        "exec_plan_path": "fixtures/task-runner-handoff-pack/valid-readonly/tasks/task-intake-readonly/exec-plan.json",
        "workspace_layout_path": "fixtures/task-runner-handoff-pack/valid-readonly/tasks/task-intake-readonly/workspace-layout.json",
    },
    {
        "anchor_id": "anchor:task-intake-host-affecting",
        "task_id": "task-intake-host-affecting",
        "dispatch_scope": "host_affecting",
        "workspace_mode": "dev",
        "review_target": "operator",
        "reviewed_task_path": "fixtures/control-plane-replay/valid-host-affecting/operator-review-bundle.json",
        "summary_path": "fixtures/control-plane-replay/valid-host-affecting/summary.json",
        "handoff_manifest_path": "fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/handoff-manifest.json",
        "exec_plan_path": "fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/exec-plan.json",
        "workspace_layout_path": "fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/workspace-layout.json",
    },
]

CONTROL_PLANE_CASES = [
    "valid-readonly",
    "valid-host-affecting",
    "valid-broker-submission-candidate",
]

EXECUTION_PLANE_COMPONENTS = [
    "task-runner-container",
    "workspace-task-runner-template",
]

VALIDATION_ENTRYPOINTS = [
    "scripts/check-phase3-control-plane-dry-run.sh",
    "scripts/check-task-runner-container-spec.sh",
    "scripts/check-workspace-task-runner-template.sh",
    "scripts/check-task-runner-handoff-pack.sh",
    "scripts/check-first-live-pilot-candidate-pack.sh",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bytes_for_file(path: Path) -> int:
    return path.stat().st_size


def expand_relative_paths(repo_root: Path, files: list[str] | None = None, dirs: list[str] | None = None) -> list[str]:
    expanded: list[str] = []
    for relpath in files or []:
        expanded.append(relpath)
    for rel_dir in dirs or []:
        root = repo_root / rel_dir
        for path in sorted(root.rglob("*")):
            if path.is_file():
                expanded.append(path.relative_to(repo_root).as_posix())
    return expanded
