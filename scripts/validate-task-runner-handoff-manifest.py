#!/usr/bin/env python3
"""Validate task-runner handoff manifest artifacts and cross-document consistency."""

from __future__ import annotations

from pathlib import Path
import importlib.util
import json
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import (  # noqa: E402
    ID_RE,
    ensure,
    ensure_type,
    is_non_empty_string,
    is_relative_path,
    load_json,
    reject_extra_keys,
    validate_schema_file,
)
from task_runner_handoff_contracts import (  # noqa: E402
    HANDOFF_MANIFEST_SCHEMA_VERSION,
    detect_reviewed_task_kind,
    non_empty_string,
)


SCHEMA_PATH = REPO_ROOT / "schemas" / "task-runner-handoff-manifest.schema.json"


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
validate_task_runner_workspace_layout = load_validator("validate-task-runner-workspace-layout")
validate_task_runner_exec_plan = load_validator("validate-task-runner-exec-plan")


def usage() -> int:
    print("Usage: scripts/validate-task-runner-handoff-manifest.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
    return 2


def base_root_for_manifest(path: Path) -> Path:
    if len(path.parents) < 3:
        raise ValueError("handoff manifest must live under <base>/tasks/<task-id>/")
    return path.parents[2]


def resolve_staged_path(base_root: Path, relpath: str) -> Path:
    return (base_root / relpath).resolve()


def resolve_source_path(path_value: str) -> Path:
    candidate = Path(path_value)
    if candidate.is_absolute():
        return candidate.resolve()
    return (REPO_ROOT / candidate).resolve()


def validate_boundary_flags(value: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(
        value,
        {
            "repo_side_only",
            "live_side_publish_performed",
            "broker_dispatch_performed",
            "real_docker_run_required",
            "openclaw_runtime_modified",
        },
        errors,
        where,
    )
    ensure(value.get("repo_side_only") is True, errors, f"{where}.repo_side_only must be true")
    ensure(value.get("live_side_publish_performed") is False, errors, f"{where}.live_side_publish_performed must be false")
    ensure(value.get("broker_dispatch_performed") is False, errors, f"{where}.broker_dispatch_performed must be false")
    ensure(value.get("real_docker_run_required") is False, errors, f"{where}.real_docker_run_required must be false")
    ensure(value.get("openclaw_runtime_modified") is False, errors, f"{where}.openclaw_runtime_modified must be false")


def validate_document(path: Path) -> list[str]:
    errors = validate_schema_file(
        SCHEMA_PATH,
        expected_title="TaskRunnerHandoffManifest",
        expected_const=HANDOFF_MANIFEST_SCHEMA_VERSION,
    )
    if errors:
        return errors

    try:
        data = load_json(path)
    except FileNotFoundError:
        return [f"{path}: file not found"]
    except json.JSONDecodeError as exc:
        return [f"{path}: could not parse JSON: {exc}"]

    if not isinstance(data, dict):
        return [f"{path}: root must be an object"]

    reject_extra_keys(
        data,
        {
            "schema_version",
            "manifest_id",
            "task_id",
            "run_id",
            "reviewed_task",
            "source_summary",
            "task_dir",
            "repo_seed",
            "staged_inputs",
            "execution_contract",
            "boundary_carry_forward",
        },
        errors,
        str(path),
    )

    ensure(data.get("schema_version") == HANDOFF_MANIFEST_SCHEMA_VERSION, errors, f"{path}: schema_version mismatch")
    ensure(ID_RE.match(str(data.get("manifest_id", ""))) is not None, errors, f"{path}: manifest_id must match contract id format")
    ensure(ID_RE.match(str(data.get("task_id", ""))) is not None, errors, f"{path}: task_id must match contract id format")
    ensure(ID_RE.match(str(data.get("run_id", ""))) is not None, errors, f"{path}: run_id must match contract id format")

    try:
        base_root = base_root_for_manifest(path.resolve())
    except ValueError as exc:
        errors.append(f"{path}: {exc}")
        return errors

    task_dir = data.get("task_dir")
    if ensure_type(task_dir, dict, errors, f"{path}: task_dir must be an object"):
        reject_extra_keys(task_dir, {"root_relpath", "repo_relpath", "inputs_relpath", "outputs_relpath"}, errors, f"{path}.task_dir")
        for key in ("root_relpath", "repo_relpath", "inputs_relpath", "outputs_relpath"):
            ensure(isinstance(task_dir.get(key), str) and str(task_dir.get(key)).startswith("tasks/"), errors, f"{path}.task_dir.{key} must stay under tasks/")

    reviewed_task = data.get("reviewed_task")
    reviewed_task_doc: dict[str, object] | None = None
    if ensure_type(reviewed_task, dict, errors, f"{path}: reviewed_task must be an object"):
        reject_extra_keys(
            reviewed_task,
            {
                "kind",
                "bundle_id",
                "bundle_type",
                "review_target",
                "review_status",
                "dispatch_scope",
                "dispatch_status",
                "requires_operator_approval",
                "broker_request_count",
                "source_path",
                "staged_relpath",
            },
            errors,
            f"{path}.reviewed_task",
        )
        ensure(reviewed_task.get("kind") in {"broker_review_bundle", "operator_review_bundle"}, errors, f"{path}.reviewed_task.kind must be supported")
        ensure(ID_RE.match(str(reviewed_task.get("bundle_id", ""))) is not None, errors, f"{path}.reviewed_task.bundle_id must match contract id format")
        ensure(reviewed_task.get("bundle_type") in {"BROKER_REVIEW_BUNDLE", "OPERATOR_REVIEW_BUNDLE"}, errors, f"{path}.reviewed_task.bundle_type must be supported")
        ensure(reviewed_task.get("review_target") in {"broker", "operator"}, errors, f"{path}.reviewed_task.review_target must be broker or operator")
        ensure(reviewed_task.get("review_status") in {"pending_broker_review", "pending_operator_review"}, errors, f"{path}.reviewed_task.review_status must be pending_*_review")
        ensure(reviewed_task.get("dispatch_scope") in {"readonly", "host_affecting"}, errors, f"{path}.reviewed_task.dispatch_scope must be supported")
        ensure(reviewed_task.get("dispatch_status") in {"broker_ready", "operator_approval_required"}, errors, f"{path}.reviewed_task.dispatch_status must be supported")
        ensure(isinstance(reviewed_task.get("requires_operator_approval"), bool), errors, f"{path}.reviewed_task.requires_operator_approval must be boolean")
        ensure(isinstance(reviewed_task.get("broker_request_count"), int) and int(reviewed_task.get("broker_request_count")) >= 1, errors, f"{path}.reviewed_task.broker_request_count must be >= 1")
        ensure(non_empty_string(reviewed_task.get("source_path")), errors, f"{path}.reviewed_task.source_path must be non-empty")
        ensure(isinstance(reviewed_task.get("staged_relpath"), str) and str(reviewed_task.get("staged_relpath")).startswith("tasks/"), errors, f"{path}.reviewed_task.staged_relpath must stay under tasks/")

        if is_non_empty_string(reviewed_task.get("staged_relpath")):
            reviewed_task_staged_path = resolve_staged_path(base_root, str(reviewed_task.get("staged_relpath")))
            ensure(reviewed_task_staged_path.is_file(), errors, f"{path}: staged reviewed task missing: {reviewed_task_staged_path}")
            if reviewed_task_staged_path.is_file():
                kind = reviewed_task.get("kind")
                reviewed_task_validation = (
                    validate_broker_review_bundle(reviewed_task_staged_path)
                    if kind == "broker_review_bundle"
                    else validate_operator_review_bundle(reviewed_task_staged_path)
                )
                errors.extend(reviewed_task_validation)
                if not reviewed_task_validation:
                    loaded_reviewed_task = load_json(reviewed_task_staged_path)
                    if isinstance(loaded_reviewed_task, dict):
                        reviewed_task_doc = loaded_reviewed_task
                        ensure(detect_reviewed_task_kind(loaded_reviewed_task) == kind, errors, f"{path}: reviewed_task.kind must match staged reviewed task schema")
                        ensure(loaded_reviewed_task.get("bundle_id") == reviewed_task.get("bundle_id"), errors, f"{path}: reviewed_task.bundle_id must match staged reviewed task")
                        ensure(loaded_reviewed_task.get("task_id") == data.get("task_id"), errors, f"{path}: reviewed_task.task_id must match staged reviewed task")
                        ensure(loaded_reviewed_task.get("run_id") == data.get("run_id"), errors, f"{path}: reviewed_task.run_id must match staged reviewed task")

        if is_non_empty_string(reviewed_task.get("source_path")):
            source_reviewed_task_path = resolve_source_path(str(reviewed_task.get("source_path")))
            ensure(source_reviewed_task_path.is_file(), errors, f"{path}: reviewed_task.source_path missing: {source_reviewed_task_path}")

    source_summary = data.get("source_summary")
    summary_doc: dict[str, object] | None = None
    if ensure_type(source_summary, dict, errors, f"{path}: source_summary must be an object"):
        reject_extra_keys(source_summary, {"source_path", "staged_relpath"}, errors, f"{path}.source_summary")
        ensure(non_empty_string(source_summary.get("source_path")), errors, f"{path}.source_summary.source_path must be non-empty")
        ensure(isinstance(source_summary.get("staged_relpath"), str) and str(source_summary.get("staged_relpath")).startswith("tasks/"), errors, f"{path}.source_summary.staged_relpath must stay under tasks/")

        if is_non_empty_string(source_summary.get("staged_relpath")):
            summary_staged_path = resolve_staged_path(base_root, str(source_summary.get("staged_relpath")))
            ensure(summary_staged_path.is_file(), errors, f"{path}: staged summary missing: {summary_staged_path}")
            if summary_staged_path.is_file():
                summary_validation = validate_task_runner_summary(summary_staged_path)
                errors.extend(summary_validation)
                if not summary_validation:
                    loaded_summary = load_json(summary_staged_path)
                    if isinstance(loaded_summary, dict):
                        summary_doc = loaded_summary
                        ensure(loaded_summary.get("task_id") == data.get("task_id"), errors, f"{path}: source_summary.task_id must match staged summary")
                        ensure(loaded_summary.get("run_id") == data.get("run_id"), errors, f"{path}: source_summary.run_id must match staged summary")

        if is_non_empty_string(source_summary.get("source_path")):
            source_summary_path = resolve_source_path(str(source_summary.get("source_path")))
            ensure(source_summary_path.is_file(), errors, f"{path}: source_summary.source_path missing: {source_summary_path}")

    repo_seed = data.get("repo_seed")
    if ensure_type(repo_seed, dict, errors, f"{path}: repo_seed must be an object"):
        reject_extra_keys(repo_seed, {"strategy", "changed_files"}, errors, f"{path}.repo_seed")
        ensure(repo_seed.get("strategy") == "changed_files_subset", errors, f"{path}.repo_seed.strategy must be changed_files_subset")
        changed_files = repo_seed.get("changed_files")
        changed_file_list: list[str] = []
        if ensure_type(changed_files, list, errors, f"{path}.repo_seed.changed_files must be an array"):
            ensure(len(changed_files) > 0, errors, f"{path}.repo_seed.changed_files must not be empty")
            for idx, changed_file in enumerate(changed_files):
                ensure(is_relative_path(changed_file), errors, f"{path}.repo_seed.changed_files[{idx}] must be a relative path")
                if isinstance(changed_file, str):
                    changed_file_list.append(changed_file)
                    repo_relpath = task_dir.get("repo_relpath") if isinstance(task_dir, dict) else None
                    if isinstance(repo_relpath, str):
                        staged_repo_file = resolve_staged_path(base_root, f"{repo_relpath}/{changed_file}")
                        ensure(staged_repo_file.is_file(), errors, f"{path}: staged repo file missing: {staged_repo_file}")
            if changed_file_list:
                ensure(len(changed_file_list) == len(set(changed_file_list)), errors, f"{path}.repo_seed.changed_files must be unique")
            if summary_doc is not None:
                summary_repo_changes = summary_doc.get("repo_changes")
                summary_changed_files = summary_repo_changes.get("changed_files") if isinstance(summary_repo_changes, dict) else None
                ensure(summary_changed_files == changed_file_list, errors, f"{path}: repo_seed.changed_files must match staged summary.repo_changes.changed_files")

    staged_inputs = data.get("staged_inputs")
    if ensure_type(staged_inputs, dict, errors, f"{path}: staged_inputs must be an object"):
        reject_extra_keys(staged_inputs, {"request_md", "context_json", "control_plane_dir", "control_plane_artifacts"}, errors, f"{path}.staged_inputs")
        for key in ("request_md", "context_json", "control_plane_dir"):
            ensure(isinstance(staged_inputs.get(key), str) and str(staged_inputs.get(key)).startswith("tasks/"), errors, f"{path}.staged_inputs.{key} must stay under tasks/")
        control_plane_artifacts = staged_inputs.get("control_plane_artifacts")
        artifact_names: list[str] = []
        if ensure_type(control_plane_artifacts, list, errors, f"{path}.staged_inputs.control_plane_artifacts must be an array"):
            ensure(len(control_plane_artifacts) >= 2, errors, f"{path}.staged_inputs.control_plane_artifacts must include reviewed task and summary")
            for idx, artifact in enumerate(control_plane_artifacts):
                item_where = f"{path}.staged_inputs.control_plane_artifacts[{idx}]"
                if not ensure_type(artifact, dict, errors, f"{item_where} must be an object"):
                    continue
                reject_extra_keys(artifact, {"name", "source_path", "staged_relpath"}, errors, item_where)
                ensure(ID_RE.match(str(artifact.get("name", ""))) is not None, errors, f"{item_where}.name must match contract id format")
                ensure(non_empty_string(artifact.get("source_path")), errors, f"{item_where}.source_path must be non-empty")
                ensure(isinstance(artifact.get("staged_relpath"), str) and str(artifact.get("staged_relpath")).startswith("tasks/"), errors, f"{item_where}.staged_relpath must stay under tasks/")
                if isinstance(artifact.get("name"), str):
                    artifact_names.append(str(artifact.get("name")))
                if is_non_empty_string(artifact.get("source_path")):
                    ensure(resolve_source_path(str(artifact.get("source_path"))).is_file(), errors, f"{item_where}.source_path must exist")
                if is_non_empty_string(artifact.get("staged_relpath")):
                    ensure(resolve_staged_path(base_root, str(artifact.get("staged_relpath"))).is_file(), errors, f"{item_where}.staged_relpath must exist")
            ensure("reviewed_task" in artifact_names, errors, f"{path}.staged_inputs.control_plane_artifacts must include reviewed_task")
            ensure("summary_json" in artifact_names, errors, f"{path}.staged_inputs.control_plane_artifacts must include summary_json")

        if isinstance(staged_inputs.get("request_md"), str):
            ensure(resolve_staged_path(base_root, str(staged_inputs.get("request_md"))).is_file(), errors, f"{path}.staged_inputs.request_md must exist")
        if isinstance(staged_inputs.get("context_json"), str):
            context_path = resolve_staged_path(base_root, str(staged_inputs.get("context_json")))
            ensure(context_path.is_file(), errors, f"{path}.staged_inputs.context_json must exist")
            if context_path.is_file():
                context_doc = load_json(context_path)
                if isinstance(context_doc, dict):
                    ensure(context_doc.get("task_id") == data.get("task_id"), errors, f"{path}: staged context task_id must match manifest")
                    ensure(context_doc.get("run_id") == data.get("run_id"), errors, f"{path}: staged context run_id must match manifest")
                    ensure(context_doc.get("workspace_mode") == data.get("execution_contract", {}).get("workspace_mode") if isinstance(data.get("execution_contract"), dict) else None, errors, f"{path}: staged context workspace_mode must match execution_contract")

    execution_contract = data.get("execution_contract")
    layout_doc: dict[str, object] | None = None
    exec_plan_doc: dict[str, object] | None = None
    if ensure_type(execution_contract, dict, errors, f"{path}: execution_contract must be an object"):
        reject_extra_keys(execution_contract, {"workspace_mode", "runner", "network_mode", "workspace_layout_path", "exec_plan_path"}, errors, f"{path}.execution_contract")
        ensure(execution_contract.get("workspace_mode") in {"readonly", "dev"}, errors, f"{path}.execution_contract.workspace_mode must be readonly or dev")
        ensure(execution_contract.get("runner") in {"codex", "claudecode"}, errors, f"{path}.execution_contract.runner must be supported")
        ensure(execution_contract.get("network_mode") in {"none", "restricted-egress"}, errors, f"{path}.execution_contract.network_mode must be supported")
        for key in ("workspace_layout_path", "exec_plan_path"):
            ensure(isinstance(execution_contract.get(key), str) and str(execution_contract.get(key)).startswith("tasks/"), errors, f"{path}.execution_contract.{key} must stay under tasks/")

        if is_non_empty_string(execution_contract.get("workspace_layout_path")):
            layout_path = resolve_staged_path(base_root, str(execution_contract.get("workspace_layout_path")))
            ensure(layout_path.is_file(), errors, f"{path}: workspace layout missing: {layout_path}")
            if layout_path.is_file():
                layout_validation = validate_task_runner_workspace_layout(layout_path)
                errors.extend(layout_validation)
                if not layout_validation:
                    loaded_layout = load_json(layout_path)
                    if isinstance(loaded_layout, dict):
                        layout_doc = loaded_layout

        if is_non_empty_string(execution_contract.get("exec_plan_path")):
            exec_plan_path = resolve_staged_path(base_root, str(execution_contract.get("exec_plan_path")))
            ensure(exec_plan_path.is_file(), errors, f"{path}: exec plan missing: {exec_plan_path}")
            if exec_plan_path.is_file():
                exec_plan_validation = validate_task_runner_exec_plan(exec_plan_path)
                errors.extend(exec_plan_validation)
                if not exec_plan_validation:
                    loaded_exec_plan = load_json(exec_plan_path)
                    if isinstance(loaded_exec_plan, dict):
                        exec_plan_doc = loaded_exec_plan

    validate_boundary_flags(data.get("boundary_carry_forward"), errors, f"{path}.boundary_carry_forward")

    if reviewed_task_doc is not None:
        ensure(reviewed_task_doc.get("task_id") == data.get("task_id"), errors, f"{path}: reviewed task staged copy task_id mismatch")
        ensure(reviewed_task_doc.get("run_id") == data.get("run_id"), errors, f"{path}: reviewed task staged copy run_id mismatch")
        ensure(reviewed_task_doc.get("requires_operator_approval") == reviewed_task.get("requires_operator_approval") if isinstance(reviewed_task, dict) else None, errors, f"{path}: reviewed task approval mismatch")
        expected_workspace_mode = "readonly" if reviewed_task_doc.get("dispatch_scope") == "readonly" else "dev"
        if isinstance(execution_contract, dict):
            ensure(execution_contract.get("workspace_mode") == expected_workspace_mode, errors, f"{path}: execution_contract.workspace_mode must match reviewed task dispatch_scope")

    if layout_doc is not None and exec_plan_doc is not None:
        ensure(layout_doc.get("task_id") == data.get("task_id"), errors, f"{path}: workspace-layout task_id mismatch")
        ensure(exec_plan_doc.get("task_id") == data.get("task_id"), errors, f"{path}: exec-plan task_id mismatch")
        if isinstance(execution_contract, dict):
            ensure(layout_doc.get("workspace_mode") == execution_contract.get("workspace_mode"), errors, f"{path}: workspace-layout.workspace_mode must match execution_contract")
            workspace = exec_plan_doc.get("workspace")
            network = exec_plan_doc.get("network")
            invocation = exec_plan_doc.get("invocation")
            if isinstance(workspace, dict):
                ensure(workspace.get("layout_mode") == execution_contract.get("workspace_mode"), errors, f"{path}: exec-plan workspace.layout_mode must match execution_contract.workspace_mode")
                ensure(workspace.get("layout_artifact") == execution_contract.get("workspace_layout_path"), errors, f"{path}: exec-plan workspace.layout_artifact must match execution_contract.workspace_layout_path")
            if isinstance(network, dict):
                ensure(network.get("mode") == execution_contract.get("network_mode"), errors, f"{path}: exec-plan network.mode must match execution_contract.network_mode")
            if isinstance(invocation, dict):
                ensure(invocation.get("runner") == execution_contract.get("runner"), errors, f"{path}: exec-plan invocation.runner must match execution_contract.runner")
            ensure(exec_plan_doc.get("boundary_carry_forward") == data.get("boundary_carry_forward"), errors, f"{path}: exec-plan boundary flags must match manifest")
        ensure(layout_doc.get("boundary_carry_forward") == data.get("boundary_carry_forward"), errors, f"{path}: workspace-layout boundary flags must match manifest")

        outputs_relpath = task_dir.get("outputs_relpath") if isinstance(task_dir, dict) else None
        if isinstance(outputs_relpath, str):
            outputs_dir = resolve_staged_path(base_root, outputs_relpath)
            ensure(outputs_dir.is_dir(), errors, f"{path}: outputs directory missing: {outputs_dir}")
            ensure((outputs_dir / "export").is_dir(), errors, f"{path}: outputs/export directory missing: {outputs_dir / 'export'}")

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
