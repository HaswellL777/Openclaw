#!/usr/bin/env python3
"""Assemble a reviewed-task handoff pack under tasks/<task-id>/."""

from __future__ import annotations

from pathlib import Path
import argparse
import importlib.util
import json
import shutil
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_handoff_contracts import (  # noqa: E402
    BOUNDARY_CARRY_FORWARD,
    IMAGE_REFERENCE,
    POLICY_FILES,
    REPO_SEED_STRATEGY,
    RUNNER_BOOTSTRAP_PATH,
    RUNNER_NAME,
    TASK_CONTEXT_JSON,
    TASK_CONTROL_PLANE_DIR,
    TASK_EXEC_PLAN,
    TASK_HANDOFF_MANIFEST,
    TASK_REQUEST_MD,
    TASK_STAGED_SUMMARY_JSON,
    TASK_WORKSPACE_LAYOUT,
    detect_reviewed_task_kind,
    ensure_reviewed_task_document,
    ensure_summary_document,
    load_document,
    resolve_input_path,
    to_repo_relpath,
    validate_cross_document_basics,
    workspace_mode_from_reviewed_task,
)


def load_validator(script_name: str):
    module_name = script_name.replace("-", "_")
    script_path = SCRIPT_DIR / f"{script_name}.py"
    spec = importlib.util.spec_from_file_location(module_name, script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load validator module: {script_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.validate_document


validate_task_runner_summary = load_validator("validate-task-runner-summary")
validate_broker_review_bundle = load_validator("validate-broker-review-bundle")
validate_operator_review_bundle = load_validator("validate-operator-review-bundle")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a repo-side reviewed-task handoff pack anchored under tasks/<task-id>/.",
    )
    parser.add_argument("--reviewed-task", required=True, help="Path to broker-review-bundle.json or operator-review-bundle.json")
    parser.add_argument("--summary", required=True, help="Path to the reviewed task-runner summary.json")
    parser.add_argument(
        "--output-root",
        default=str(REPO_ROOT),
        help="Root directory that will receive tasks/<task-id>/ (default: repo root)",
    )
    parser.add_argument(
        "--repo-root",
        default=str(REPO_ROOT),
        help="Repository root used to resolve changed files for repo/ staging",
    )
    parser.add_argument("--force", action="store_true", help="Replace an existing tasks/<task-id>/ directory")
    parser.add_argument("--print-task-dir", action="store_true", help="Print the final task directory path")
    return parser.parse_args(argv)


def validate_reviewed_task(path: Path, reviewed_task: dict[str, object]) -> list[str]:
    kind = detect_reviewed_task_kind(reviewed_task)
    if kind == "broker_review_bundle":
        return validate_broker_review_bundle(path)
    if kind == "operator_review_bundle":
        return validate_operator_review_bundle(path)
    return [f"{path}: unsupported reviewed task schema"]


def mkdir_clean(path: Path, force: bool) -> None:
    if path.exists():
        if not force:
            raise SystemExit(f"output already exists: {path} (use --force to replace)")
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def write_json(path: Path, data: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def repo_changed_files(summary: dict[str, object]) -> list[str]:
    repo_changes = summary.get("repo_changes")
    changed_files = repo_changes.get("changed_files") if isinstance(repo_changes, dict) else None
    if not isinstance(changed_files, list):
        raise SystemExit("summary.repo_changes.changed_files must be an array")
    output: list[str] = []
    for item in changed_files:
        if isinstance(item, str) and item not in output:
            output.append(item)
    if not output:
        raise SystemExit("summary.repo_changes.changed_files must not be empty")
    return output


def stage_repo_subset(task_repo_dir: Path, repo_root: Path, changed_files: list[str]) -> None:
    for relpath in changed_files:
        source = (repo_root / relpath).resolve()
        if not source.is_file():
            raise SystemExit(f"changed file missing from repo root: {source}")
        destination = task_repo_dir / relpath
        copy_file(source, destination)


def write_placeholder(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("", encoding="utf-8")


def stage_control_plane_inputs(
    *,
    task_inputs_dir: Path,
    reviewed_task_path: Path,
    reviewed_task: dict[str, object],
    summary_path: Path,
    repo_root: Path,
) -> list[dict[str, str]]:
    control_plane_dir = task_inputs_dir / "control-plane"
    staged: list[dict[str, str]] = []

    reviewed_task_dest = control_plane_dir / reviewed_task_path.name
    copy_file(reviewed_task_path, reviewed_task_dest)
    staged.append(
        {
            "name": "reviewed_task",
            "source_path": to_repo_relpath(reviewed_task_path, repo_root),
            "staged_relpath": f"{TASK_CONTROL_PLANE_DIR}/{reviewed_task_path.name}",
        }
    )

    summary_dest = control_plane_dir / "task-runner-summary.json"
    copy_file(summary_path, summary_dest)
    staged.append(
        {
            "name": "summary_json",
            "source_path": to_repo_relpath(summary_path, repo_root),
            "staged_relpath": TASK_STAGED_SUMMARY_JSON,
        }
    )

    source_artifacts = reviewed_task.get("source_artifacts")
    if isinstance(source_artifacts, dict):
        for name, raw_path in source_artifacts.items():
            if not isinstance(raw_path, str) or raw_path.strip() == "":
                continue
            resolved = resolve_input_path(raw_path, preferred_base=reviewed_task_path.parent, repo_root=repo_root)
            destination = control_plane_dir / resolved.name
            copy_file(resolved, destination)
            staged.append(
                {
                    "name": name,
                    "source_path": to_repo_relpath(resolved, repo_root),
                    "staged_relpath": f"{TASK_CONTROL_PLANE_DIR}/{resolved.name}",
                }
            )

    return staged


def build_request_markdown(
    *,
    reviewed_task: dict[str, object],
    summary: dict[str, object],
    workspace_mode: str,
) -> str:
    summary_context = reviewed_task.get("summary_context", {})
    request_title = summary_context.get("request_title", "")
    request_scope = summary_context.get("request_scope", "")
    goal = summary_context.get("goal", "")
    outcome = summary_context.get("outcome", "")

    return "\n".join(
        [
            f"# Reviewed Task Handoff: {reviewed_task.get('task_id')}",
            "",
            f"- Run ID: {reviewed_task.get('run_id')}",
            f"- Review Artifact: {reviewed_task.get('bundle_type')}",
            f"- Review Status: {reviewed_task.get('review_status')}",
            f"- Dispatch Scope: {reviewed_task.get('dispatch_scope')}",
            f"- Workspace Mode: {workspace_mode}",
            f"- Requires Operator Approval: {reviewed_task.get('requires_operator_approval')}",
            "",
            "## Goal",
            str(goal),
            "",
            "## Reviewed Request",
            str(request_title),
            "",
            "## Scope",
            str(request_scope),
            "",
            "## Outcome Anchor",
            str(outcome),
            "",
            "## Repo-Side Boundary",
            "- Stay inside the staged repo subset under /workspace/repo.",
            "- Use /workspace/inputs/control-plane for reviewed-task context.",
            "- Do not perform live-side publish, broker dispatch, or real Docker execution.",
            "- Write artifacts only under /workspace/outputs.",
            "",
            "## Existing Summary Status",
            str(summary.get("status")),
            "",
        ]
    ) + "\n"


def build_context_json(
    *,
    reviewed_task: dict[str, object],
    summary: dict[str, object],
    changed_files: list[str],
    workspace_mode: str,
    staged_control_plane_artifacts: list[dict[str, str]],
) -> dict[str, object]:
    return {
        "task_id": reviewed_task.get("task_id"),
        "run_id": reviewed_task.get("run_id"),
        "workspace_mode": workspace_mode,
        "reviewed_task": {
            "bundle_id": reviewed_task.get("bundle_id"),
            "bundle_type": reviewed_task.get("bundle_type"),
            "review_target": reviewed_task.get("review_target"),
            "review_status": reviewed_task.get("review_status"),
            "dispatch_scope": reviewed_task.get("dispatch_scope"),
            "dispatch_status": reviewed_task.get("dispatch_status"),
            "requires_operator_approval": reviewed_task.get("requires_operator_approval"),
            "broker_requests": reviewed_task.get("broker_requests"),
        },
        "summary": {
            "status": summary.get("status"),
            "goal": summary.get("summary", {}).get("goal") if isinstance(summary.get("summary"), dict) else None,
            "outcome": summary.get("summary", {}).get("outcome") if isinstance(summary.get("summary"), dict) else None,
            "changed_files": changed_files,
        },
        "staged_control_plane_artifacts": staged_control_plane_artifacts,
        "boundary_carry_forward": BOUNDARY_CARRY_FORWARD,
    }


def build_workspace_layout(
    *,
    task_id: str,
    workspace_mode: str,
) -> dict[str, object]:
    writable_paths = [
        "/workspace/outputs",
        "/workspace/outputs/export",
        "/tmp",
        "/var/tmp",
        "/run",
    ]
    if workspace_mode == "dev":
        writable_paths.insert(0, "/workspace/repo")

    return {
        "schema_version": "openclaw.task-runner.workspace-layout.v1alpha1",
        "layout_id": f"tr-layout:{task_id}",
        "task_id": task_id,
        "workspace_mode": workspace_mode,
        "container_root": "/workspace",
        "control_surface": {
            "policy_files": POLICY_FILES,
        },
        "mounts": [
            {
                "name": "repo",
                "source_relpath": f"tasks/{task_id}/repo",
                "container_path": "/workspace/repo",
                "access": "ro" if workspace_mode == "readonly" else "rw",
                "required": True,
            },
            {
                "name": "inputs",
                "source_relpath": f"tasks/{task_id}/inputs",
                "container_path": "/workspace/inputs",
                "access": "ro",
                "required": True,
            },
            {
                "name": "outputs",
                "source_relpath": f"tasks/{task_id}/outputs",
                "container_path": "/workspace/outputs",
                "access": "rw",
                "required": True,
            },
        ],
        "writable_paths": writable_paths,
        "tmpfs_paths": ["/tmp", "/var/tmp", "/run"],
        "artifact_export": {
            "container_path": "/workspace/outputs/export",
            "source_relpath": f"tasks/{task_id}/outputs/export",
            "access": "rw",
            "required": True,
        },
        "retained_artifacts": [
            "summary.md",
            "summary.json",
            "diff.patch",
            "host-change-request.json",
        ],
        "boundary_carry_forward": BOUNDARY_CARRY_FORWARD,
    }


def build_exec_plan(
    *,
    task_id: str,
    workspace_mode: str,
) -> dict[str, object]:
    return {
        "schema_version": "openclaw.task-runner.exec-plan.v1alpha1",
        "plan_id": f"tr-exec-plan:{task_id}",
        "task_id": task_id,
        "image": {
            "reference": IMAGE_REFERENCE,
            "pull_policy": "never",
            "run_as_user": "runner",
            "workdir": "/workspace/repo",
            "entrypoint": "/usr/local/bin/task-runner-entrypoint",
        },
        "workspace": {
            "layout_mode": workspace_mode,
            "layout_artifact": f"tasks/{task_id}/{TASK_WORKSPACE_LAYOUT}",
            "root_path": "/workspace",
            "repo_path": "/workspace/repo",
            "inputs_path": "/workspace/inputs",
            "outputs_path": "/workspace/outputs",
            "artifact_export_path": "/workspace/outputs/export",
        },
        "inputs": {
            "required_inputs": [
                "/workspace/inputs/request.md",
                "/workspace/inputs/context.json",
                "/workspace/inputs/control-plane/task-runner-summary.json",
                f"/workspace/inputs/control-plane/{'broker-review-bundle.json' if workspace_mode == 'readonly' else 'operator-review-bundle.json'}",
            ],
        },
        "outputs": {
            "required_artifacts": [
                "/workspace/outputs/summary.md",
                "/workspace/outputs/summary.json",
                "/workspace/outputs/diff.patch",
                "/workspace/outputs/host-change-request.json",
                "/workspace/outputs/export",
            ],
            "artifact_export_path": "/workspace/outputs/export",
            "preserve_failed_run_logs": True,
        },
        "environment": {
            "allowed": [
                "TASK_ID",
                "RUN_ID",
                "RUNNER_TOOL",
                "RUNNER_MODE",
                "WORKSPACE_MODE",
                "TASK_REPO_PATH",
                "TASK_INPUTS_PATH",
                "TASK_OUTPUTS_PATH",
                "ARTIFACT_EXPORT_PATH",
                "TASK_PROMPT_PATH",
            ],
            "required": [
                "TASK_ID",
                "RUN_ID",
                "RUNNER_TOOL",
                "RUNNER_MODE",
                "WORKSPACE_MODE",
                "TASK_REPO_PATH",
                "TASK_INPUTS_PATH",
                "TASK_OUTPUTS_PATH",
                "ARTIFACT_EXPORT_PATH",
            ],
            "forbidden": [
                "OPENCLAW_CONFIG_PATH",
                "OPENCLAW_STATE_DIR",
                "DOCKER_HOST",
                "OPENAI_API_KEY",
                "ANTHROPIC_AUTH_TOKEN",
                "OPENCLAW_BROKER_SOCKET",
            ],
        },
        "tool_contract": {
            "agent_tools": {
                "allow": [
                    "read",
                    "write",
                    "edit",
                    "apply_patch",
                    "exec",
                    "process",
                ],
                "deny": [
                    "sessions_spawn",
                    "elevated",
                ],
            },
            "container_binaries": {
                "expected_available": [
                    "bash",
                    "git",
                    "jq",
                    "python3",
                    "rg",
                ],
                "expected_unavailable": [
                    "docker",
                    "sudo",
                    "systemctl",
                    "mount",
                    "umount",
                ],
            },
        },
        "invocation": {
            "runner": RUNNER_NAME,
            "mode": "non_interactive",
            "bootstrap_path": RUNNER_BOOTSTRAP_PATH,
            "prompt_source": "file",
        },
        "network": {
            "mode": "none",
            "allow_host_network": False,
            "allowed_endpoints": [],
        },
        "privilege": {
            "run_as_non_root": True,
            "user": "runner",
            "allow_privilege_escalation": False,
            "read_only_rootfs": True,
            "no_new_privileges": True,
        },
        "boundary_carry_forward": BOUNDARY_CARRY_FORWARD,
    }


def build_handoff_manifest(
    *,
    task_id: str,
    run_id: str,
    workspace_mode: str,
    reviewed_task: dict[str, object],
    reviewed_task_path: Path,
    summary_path: Path,
    changed_files: list[str],
    staged_control_plane_artifacts: list[dict[str, str]],
    repo_root: Path,
) -> dict[str, object]:
    reviewed_task_staged = next(item for item in staged_control_plane_artifacts if item["name"] == "reviewed_task")
    summary_staged = next(item for item in staged_control_plane_artifacts if item["name"] == "summary_json")
    staged_artifacts = [
        {
            **item,
            "staged_relpath": f"tasks/{task_id}/{item['staged_relpath']}",
        }
        for item in staged_control_plane_artifacts
    ]

    return {
        "schema_version": "openclaw.task-runner.handoff-manifest.v1alpha1",
        "manifest_id": f"handoff:{task_id}",
        "task_id": task_id,
        "run_id": run_id,
        "reviewed_task": {
            "kind": detect_reviewed_task_kind(reviewed_task),
            "bundle_id": reviewed_task.get("bundle_id"),
            "bundle_type": reviewed_task.get("bundle_type"),
            "review_target": reviewed_task.get("review_target"),
            "review_status": reviewed_task.get("review_status"),
            "dispatch_scope": reviewed_task.get("dispatch_scope"),
            "dispatch_status": reviewed_task.get("dispatch_status"),
            "requires_operator_approval": reviewed_task.get("requires_operator_approval"),
            "broker_request_count": len(reviewed_task.get("broker_requests", [])) if isinstance(reviewed_task.get("broker_requests"), list) else 0,
            "source_path": to_repo_relpath(reviewed_task_path, repo_root),
            "staged_relpath": f"tasks/{task_id}/{reviewed_task_staged['staged_relpath']}",
        },
        "source_summary": {
            "source_path": to_repo_relpath(summary_path, repo_root),
            "staged_relpath": f"tasks/{task_id}/{summary_staged['staged_relpath']}",
        },
        "task_dir": {
            "root_relpath": f"tasks/{task_id}",
            "repo_relpath": f"tasks/{task_id}/repo",
            "inputs_relpath": f"tasks/{task_id}/inputs",
            "outputs_relpath": f"tasks/{task_id}/outputs",
        },
        "repo_seed": {
            "strategy": REPO_SEED_STRATEGY,
            "changed_files": changed_files,
        },
        "staged_inputs": {
            "request_md": f"tasks/{task_id}/{TASK_REQUEST_MD}",
            "context_json": f"tasks/{task_id}/{TASK_CONTEXT_JSON}",
            "control_plane_dir": f"tasks/{task_id}/{TASK_CONTROL_PLANE_DIR}",
            "control_plane_artifacts": staged_artifacts,
        },
        "execution_contract": {
            "workspace_mode": workspace_mode,
            "runner": RUNNER_NAME,
            "network_mode": "none",
            "workspace_layout_path": f"tasks/{task_id}/{TASK_WORKSPACE_LAYOUT}",
            "exec_plan_path": f"tasks/{task_id}/{TASK_EXEC_PLAN}",
        },
        "boundary_carry_forward": BOUNDARY_CARRY_FORWARD,
    }


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    repo_root = Path(args.repo_root).resolve()
    reviewed_task_path = Path(args.reviewed_task).resolve()
    summary_path = Path(args.summary).resolve()
    output_root = Path(args.output_root).resolve()

    summary_errors = validate_task_runner_summary(summary_path)
    if summary_errors:
        detail = "\n".join(f"  - {item}" for item in summary_errors)
        raise SystemExit(f"summary validation failed:\n{detail}")

    reviewed_task_data = ensure_reviewed_task_document(load_document(reviewed_task_path))
    summary_data = ensure_summary_document(load_document(summary_path))
    reviewed_task_errors = validate_reviewed_task(reviewed_task_path, reviewed_task_data)
    if reviewed_task_errors:
        detail = "\n".join(f"  - {item}" for item in reviewed_task_errors)
        raise SystemExit(f"reviewed task validation failed:\n{detail}")

    cross_errors = validate_cross_document_basics(
        reviewed_task=reviewed_task_data,
        summary=summary_data,
        reviewed_task_path=reviewed_task_path,
        summary_path=summary_path,
    )
    if cross_errors:
        detail = "\n".join(f"  - {item}" for item in cross_errors)
        raise SystemExit(f"cross-document validation failed:\n{detail}")

    task_id = str(reviewed_task_data["task_id"])
    run_id = str(reviewed_task_data["run_id"])
    workspace_mode = workspace_mode_from_reviewed_task(reviewed_task_data)
    if workspace_mode is None:
        raise SystemExit(f"unsupported dispatch_scope for reviewed task: {reviewed_task_data.get('dispatch_scope')}")

    task_dir = output_root / "tasks" / task_id
    task_repo_dir = task_dir / "repo"
    task_inputs_dir = task_dir / "inputs"
    task_outputs_dir = task_dir / "outputs"

    mkdir_clean(task_dir, args.force)
    task_repo_dir.mkdir(parents=True, exist_ok=True)
    (task_outputs_dir / "export").mkdir(parents=True, exist_ok=True)
    write_placeholder(task_outputs_dir / ".gitkeep")
    write_placeholder(task_outputs_dir / "export" / ".gitkeep")

    changed_files = repo_changed_files(summary_data)
    stage_repo_subset(task_repo_dir, repo_root, changed_files)
    staged_control_plane_artifacts = stage_control_plane_inputs(
        task_inputs_dir=task_inputs_dir,
        reviewed_task_path=reviewed_task_path,
        reviewed_task=reviewed_task_data,
        summary_path=summary_path,
        repo_root=repo_root,
    )

    request_md_path = task_dir / TASK_REQUEST_MD
    request_md_path.parent.mkdir(parents=True, exist_ok=True)
    request_md_path.write_text(
        build_request_markdown(
            reviewed_task=reviewed_task_data,
            summary=summary_data,
            workspace_mode=workspace_mode,
        ),
        encoding="utf-8",
    )

    context_json_path = task_dir / TASK_CONTEXT_JSON
    write_json(
        context_json_path,
        build_context_json(
            reviewed_task=reviewed_task_data,
            summary=summary_data,
            changed_files=changed_files,
            workspace_mode=workspace_mode,
            staged_control_plane_artifacts=staged_control_plane_artifacts,
        ),
    )

    write_json(task_dir / TASK_WORKSPACE_LAYOUT, build_workspace_layout(task_id=task_id, workspace_mode=workspace_mode))
    write_json(task_dir / TASK_EXEC_PLAN, build_exec_plan(task_id=task_id, workspace_mode=workspace_mode))
    write_json(
        task_dir / TASK_HANDOFF_MANIFEST,
        build_handoff_manifest(
            task_id=task_id,
            run_id=run_id,
            workspace_mode=workspace_mode,
            reviewed_task=reviewed_task_data,
            reviewed_task_path=reviewed_task_path,
            summary_path=summary_path,
            changed_files=changed_files,
            staged_control_plane_artifacts=staged_control_plane_artifacts,
            repo_root=repo_root,
        ),
    )

    if args.print_task_dir:
        print(task_dir)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
