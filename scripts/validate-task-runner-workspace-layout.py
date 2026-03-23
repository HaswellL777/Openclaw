#!/usr/bin/env python3
"""Validate task-runner workspace layout artifacts."""

from __future__ import annotations

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_container_contracts import (  # noqa: E402
    EXPECTED_MOUNT_PATHS,
    ID_RE,
    REQUIRED_POLICY_FILES,
    REQUIRED_RETAINED_ARTIFACTS,
    REQUIRED_TMPFS_PATHS,
    VALID_MOUNT_NAMES,
    WORKSPACE_MODES,
    ensure,
    ensure_type,
    load_document,
    reject_extra_keys,
    validate_boundary_flags,
    validate_container_path,
    validate_mount_source_relpath,
    validate_schema_file,
)


REPO_ROOT = SCRIPT_DIR.parent
SCHEMA_PATH = REPO_ROOT / "schemas" / "task-runner-workspace-layout.schema.json"


def usage() -> int:
    print("Usage: scripts/validate-task-runner-workspace-layout.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
    return 2


def validate_document(path: Path) -> list[str]:
    errors = validate_schema_file(
        SCHEMA_PATH,
        expected_title="TaskRunnerWorkspaceLayout",
        expected_const="openclaw.task-runner.workspace-layout.v1alpha1",
    )
    if errors:
        return errors

    try:
        data = load_document(path)
    except FileNotFoundError:
        return [f"{path}: file not found"]
    except Exception as exc:
        return [f"{path}: could not parse JSON: {exc}"]

    reject_extra_keys(
        data,
        {
            "schema_version",
            "layout_id",
            "task_id",
            "workspace_mode",
            "container_root",
            "control_surface",
            "mounts",
            "writable_paths",
            "tmpfs_paths",
            "artifact_export",
            "retained_artifacts",
            "boundary_carry_forward",
        },
        errors,
        str(path),
    )

    ensure(data.get("schema_version") == "openclaw.task-runner.workspace-layout.v1alpha1", errors, f"{path}: schema_version mismatch")
    ensure(ID_RE.match(str(data.get("layout_id", ""))) is not None, errors, f"{path}: layout_id must match contract id format")
    ensure(ID_RE.match(str(data.get("task_id", ""))) is not None, errors, f"{path}: task_id must match contract id format")
    workspace_mode = data.get("workspace_mode")
    ensure(workspace_mode in WORKSPACE_MODES, errors, f"{path}: workspace_mode must be readonly or dev")
    ensure(data.get("container_root") == "/workspace", errors, f"{path}: container_root must be /workspace")

    control_surface = data.get("control_surface")
    if ensure_type(control_surface, dict, errors, f"{path}: control_surface must be an object"):
        reject_extra_keys(control_surface, {"policy_files"}, errors, f"{path}.control_surface")
        policy_files = control_surface.get("policy_files")
        policy_set: set[str] = set()
        if ensure_type(policy_files, list, errors, f"{path}.control_surface.policy_files must be an array"):
            for idx, policy_file in enumerate(policy_files):
                ensure(isinstance(policy_file, str) and policy_file != "", errors, f"{path}.control_surface.policy_files[{idx}] must be a non-empty string")
                if isinstance(policy_file, str):
                    policy_set.add(policy_file)
            ensure(REQUIRED_POLICY_FILES.issubset(policy_set), errors, f"{path}.control_surface.policy_files must include AGENTS.md, TOOLS.md, control/runner-policy.md, and control/artifact-contract.md")

    mounts = data.get("mounts")
    mount_by_name: dict[str, dict[str, object]] = {}
    if ensure_type(mounts, list, errors, f"{path}: mounts must be an array"):
        for idx, mount in enumerate(mounts):
            item_where = f"{path}.mounts[{idx}]"
            if not ensure_type(mount, dict, errors, f"{item_where} must be an object"):
                continue
            reject_extra_keys(mount, {"name", "source_relpath", "container_path", "access", "required"}, errors, item_where)
            name = mount.get("name")
            ensure(name in VALID_MOUNT_NAMES, errors, f"{item_where}.name must be repo, inputs, or outputs")
            if isinstance(name, str):
                if name in mount_by_name:
                    errors.append(f"{item_where}.name duplicates a previous mount")
                else:
                    mount_by_name[name] = mount
            validate_mount_source_relpath(mount.get("source_relpath"), errors, f"{item_where}.source_relpath")
            if isinstance(name, str):
                ensure(mount.get("container_path") == EXPECTED_MOUNT_PATHS[name], errors, f"{item_where}.container_path must match the {name} mount")
            ensure(mount.get("access") in {"ro", "rw"}, errors, f"{item_where}.access must be ro or rw")
            ensure(mount.get("required") is True, errors, f"{item_where}.required must be true")

        ensure(set(mount_by_name.keys()) == VALID_MOUNT_NAMES, errors, f"{path}: mounts must contain exactly repo, inputs, and outputs")
        repo_mount = mount_by_name.get("repo")
        inputs_mount = mount_by_name.get("inputs")
        outputs_mount = mount_by_name.get("outputs")
        if isinstance(repo_mount, dict):
            expected_repo_access = "ro" if workspace_mode == "readonly" else "rw"
            ensure(repo_mount.get("access") == expected_repo_access, errors, f"{path}: repo mount access must be {expected_repo_access} for workspace_mode={workspace_mode}")
        if isinstance(inputs_mount, dict):
            ensure(inputs_mount.get("access") == "ro", errors, f"{path}: inputs mount must be ro")
        if isinstance(outputs_mount, dict):
            ensure(outputs_mount.get("access") == "rw", errors, f"{path}: outputs mount must be rw")

    writable_paths = data.get("writable_paths")
    writable_set: set[str] = set()
    if ensure_type(writable_paths, list, errors, f"{path}: writable_paths must be an array"):
        for idx, writable_path in enumerate(writable_paths):
            validate_container_path(writable_path, errors, f"{path}.writable_paths[{idx}]", prefix="/")
            if isinstance(writable_path, str):
                writable_set.add(writable_path)
        ensure("/workspace/outputs" in writable_set, errors, f"{path}: writable_paths must include /workspace/outputs")
        ensure("/workspace/outputs/export" in writable_set, errors, f"{path}: writable_paths must include /workspace/outputs/export")
        ensure(REQUIRED_TMPFS_PATHS.issubset(writable_set), errors, f"{path}: writable_paths must include /tmp, /var/tmp, and /run")
        if workspace_mode == "dev":
            ensure("/workspace/repo" in writable_set, errors, f"{path}: dev workspace must make /workspace/repo writable")
        if workspace_mode == "readonly":
            ensure("/workspace/repo" not in writable_set, errors, f"{path}: readonly workspace must not make /workspace/repo writable")
        ensure("/etc/openclaw" not in writable_set, errors, f"{path}: writable_paths must not include /etc/openclaw")

    tmpfs_paths = data.get("tmpfs_paths")
    tmpfs_set: set[str] = set()
    if ensure_type(tmpfs_paths, list, errors, f"{path}: tmpfs_paths must be an array"):
        for idx, tmpfs_path in enumerate(tmpfs_paths):
            validate_container_path(tmpfs_path, errors, f"{path}.tmpfs_paths[{idx}]", prefix="/")
            if isinstance(tmpfs_path, str):
                tmpfs_set.add(tmpfs_path)
        ensure(tmpfs_set == REQUIRED_TMPFS_PATHS, errors, f"{path}: tmpfs_paths must be exactly /tmp, /var/tmp, and /run")

    artifact_export = data.get("artifact_export")
    if ensure_type(artifact_export, dict, errors, f"{path}: artifact_export must be an object"):
        reject_extra_keys(artifact_export, {"container_path", "source_relpath", "access", "required"}, errors, f"{path}.artifact_export")
        ensure(artifact_export.get("container_path") == "/workspace/outputs/export", errors, f"{path}.artifact_export.container_path must be /workspace/outputs/export")
        validate_mount_source_relpath(artifact_export.get("source_relpath"), errors, f"{path}.artifact_export.source_relpath")
        if isinstance(artifact_export.get("source_relpath"), str):
            ensure(str(artifact_export.get("source_relpath")).endswith("/outputs/export"), errors, f"{path}.artifact_export.source_relpath must point to tasks/<task-id>/outputs/export")
        ensure(artifact_export.get("access") == "rw", errors, f"{path}.artifact_export.access must be rw")
        ensure(artifact_export.get("required") is True, errors, f"{path}.artifact_export.required must be true")

    retained_artifacts = data.get("retained_artifacts")
    retained_set: set[str] = set()
    if ensure_type(retained_artifacts, list, errors, f"{path}: retained_artifacts must be an array"):
        for idx, artifact in enumerate(retained_artifacts):
            ensure(isinstance(artifact, str) and artifact != "", errors, f"{path}.retained_artifacts[{idx}] must be a non-empty string")
            if isinstance(artifact, str):
                retained_set.add(artifact)
        ensure(REQUIRED_RETAINED_ARTIFACTS.issubset(retained_set), errors, f"{path}: retained_artifacts must include summary.md, summary.json, and diff.patch")

    validate_boundary_flags(data.get("boundary_carry_forward"), errors, f"{path}.boundary_carry_forward")

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
