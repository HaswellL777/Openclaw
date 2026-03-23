#!/usr/bin/env python3
"""Validate the assembled first-live-pilot candidate pack."""

from __future__ import annotations

from pathlib import Path
import argparse
import importlib.util
import json
import subprocess
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from first_live_pilot_candidate_contracts import (  # noqa: E402
    AUTHORITY_DOCS,
    CANDIDATE_ID,
    CONTROL_PLANE_CASES,
    EXECUTION_PLANE_COMPONENTS,
    HANDOFF_ANCHORS,
    PACK_FILE_NAMES,
    PACK_ROOT_RELATIVE,
    READY_STATE,
    REMAINING_BLOCKER,
    VALIDATION_ENTRYPOINTS,
    bytes_for_file,
    sha256_file,
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


VALIDATORS = {
    "control_plane_manifest": load_validator("validate-control-plane-artifact-manifest"),
    "handoff_manifest": load_validator("validate-task-runner-handoff-manifest"),
    "exec_plan": load_validator("validate-task-runner-exec-plan"),
    "workspace_layout": load_validator("validate-task-runner-workspace-layout"),
}

INDEX_FILE_BY_PLANE = {
    "control_plane": "control-plane-asset-index.json",
    "execution_plane": "execution-plane-asset-index.json",
    "handoff_pack": "handoff-pack-asset-index.json",
}

PROHIBITED_PREFIXES = (
    ".tmp/",
    "docs/checklists/hello-world-image-prerequisite-window-preflight-2026-03-21.md",
    "docs/execution-pack-hello-world-image-prerequisite-window-2026-03-21.md",
)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate the repo-side first-live-pilot candidate pack.",
    )
    parser.add_argument(
        "--pack-dir",
        default=str(REPO_ROOT / PACK_ROOT_RELATIVE / CANDIDATE_ID),
        help="Candidate pack directory to validate",
    )
    parser.add_argument("--expect-valid", action="store_true", help="Exit non-zero when validation fails (default)")
    parser.add_argument("--expect-invalid", action="store_true", help="Exit non-zero when validation unexpectedly succeeds")
    return parser.parse_args(argv)


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def ensure(condition: bool, errors: list[str], message: str) -> None:
    if not condition:
        errors.append(message)


def is_git_tracked(relpath: str) -> bool:
    result = subprocess.run(
        ["git", "ls-files", "--error-unmatch", relpath],
        cwd=REPO_ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def candidate_relpath(path: Path) -> str:
    return path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()


def validate_asset_entry(asset: object, plane: str, errors: list[str], where: str) -> str | None:
    if not isinstance(asset, dict):
        errors.append(f"{where} must be an object")
        return None

    required_keys = {"asset_id", "group", "category", "role", "path", "sha256", "bytes"}
    ensure(set(asset.keys()) == required_keys, errors, f"{where} must contain exactly {sorted(required_keys)}")

    relpath = asset.get("path")
    ensure(isinstance(relpath, str) and relpath.strip() != "", errors, f"{where}.path must be a non-empty string")
    if not isinstance(relpath, str) or relpath.strip() == "":
        return None
    ensure(not relpath.startswith("/"), errors, f"{where}.path must be repo-relative")
    ensure(not any(relpath == prefix or relpath.startswith(prefix) for prefix in PROHIBITED_PREFIXES), errors, f"{where}.path must stay out of excluded temporary paths")

    source = REPO_ROOT / relpath
    ensure(source.is_file(), errors, f"{where}.path missing from repo: {source}")
    ensure(is_git_tracked(relpath), errors, f"{where}.path must be git-tracked: {relpath}")
    if source.is_file():
        ensure(asset.get("sha256") == sha256_file(source), errors, f"{where}.sha256 mismatch for {relpath}")
        ensure(asset.get("bytes") == bytes_for_file(source), errors, f"{where}.bytes mismatch for {relpath}")

    if relpath.endswith("/artifact-manifest.json"):
        errors.extend(VALIDATORS["control_plane_manifest"](source))
    elif relpath.endswith("/handoff-manifest.json"):
        errors.extend(VALIDATORS["handoff_manifest"](source))
    elif relpath.endswith("/exec-plan.json") or relpath.startswith("fixtures/task-runner-exec-plan/"):
        errors.extend(VALIDATORS["exec_plan"](source))
    elif relpath.endswith("/workspace-layout.json") or relpath.startswith("fixtures/task-runner-workspace-layout/"):
        errors.extend(VALIDATORS["workspace_layout"](source))

    return relpath


def validate_index(index: object, plane: str, errors: list[str], where: str) -> dict[str, object] | None:
    if not isinstance(index, dict):
        errors.append(f"{where} must be an object")
        return None

    ensure(index.get("schema_version") == "openclaw.phase3.first-live-pilot.asset-index.v1alpha1", errors, f"{where}.schema_version mismatch")
    ensure(index.get("candidate_id") == CANDIDATE_ID, errors, f"{where}.candidate_id mismatch")
    ensure(index.get("plane") == plane, errors, f"{where}.plane mismatch")

    assets = index.get("assets")
    ensure(isinstance(assets, list) and len(assets) > 0, errors, f"{where}.assets must be a non-empty array")
    if not isinstance(assets, list) or not assets:
        return None

    asset_paths: list[str] = []
    for idx, asset in enumerate(assets):
        relpath = validate_asset_entry(asset, plane, errors, f"{where}.assets[{idx}]")
        if relpath is not None:
            asset_paths.append(relpath)

    ensure(len(asset_paths) == len(set(asset_paths)), errors, f"{where}.assets paths must be unique")
    ensure(index.get("asset_count") == len(assets), errors, f"{where}.asset_count must match assets length")

    asset_groups = index.get("asset_groups")
    ensure(isinstance(asset_groups, list) and len(asset_groups) > 0, errors, f"{where}.asset_groups must be a non-empty array")
    if isinstance(asset_groups, list):
        grouped = {}
        for relpath in asset_paths:
            for asset in assets:
                if isinstance(asset, dict) and asset.get("path") == relpath:
                    grouped.setdefault(asset.get("group"), []).append(relpath)
        for idx, group in enumerate(asset_groups):
            if not isinstance(group, dict):
                errors.append(f"{where}.asset_groups[{idx}] must be an object")
                continue
            group_name = group.get("group")
            paths = group.get("paths")
            ensure(isinstance(group_name, str) and group_name.strip() != "", errors, f"{where}.asset_groups[{idx}].group must be non-empty")
            ensure(isinstance(paths, list), errors, f"{where}.asset_groups[{idx}].paths must be an array")
            if isinstance(group_name, str) and isinstance(paths, list):
                expected = grouped.get(group_name, [])
                ensure(paths == expected, errors, f"{where}.asset_groups[{idx}].paths must match grouped asset paths")
                ensure(group.get("asset_count") == len(expected), errors, f"{where}.asset_groups[{idx}].asset_count mismatch")

    if plane == "control_plane":
        ensure(index.get("case_ids") == CONTROL_PLANE_CASES, errors, f"{where}.case_ids mismatch")
    if plane == "execution_plane":
        ensure(index.get("components") == EXECUTION_PLANE_COMPONENTS, errors, f"{where}.components mismatch")
    if plane == "handoff_pack":
        anchors = index.get("anchors")
        ensure(anchors == HANDOFF_ANCHORS, errors, f"{where}.anchors mismatch")

    return index


def validate_summary(summary: object, pack_relpath: str, indexes: dict[str, dict[str, object]], errors: list[str]) -> None:
    if not isinstance(summary, dict):
        errors.append("candidate-summary.json must be an object")
        return
    ensure(summary.get("schema_version") == "openclaw.phase3.first-live-pilot.candidate-summary.v1alpha1", errors, "candidate-summary schema_version mismatch")
    ensure(summary.get("candidate_id") == CANDIDATE_ID, errors, "candidate-summary candidate_id mismatch")
    ensure(summary.get("candidate_pack_relpath") == pack_relpath, errors, "candidate-summary candidate_pack_relpath mismatch")
    ensure(summary.get("readiness_state") == READY_STATE, errors, "candidate-summary readiness_state mismatch")
    ensure(summary.get("repo_side_gap_closed") is True, errors, "candidate-summary repo_side_gap_closed must be true")
    ensure(summary.get("remaining_blocker") == REMAINING_BLOCKER, errors, "candidate-summary remaining_blocker mismatch")

    authority_docs = summary.get("authority_docs")
    ensure(isinstance(authority_docs, list) and len(authority_docs) == len(AUTHORITY_DOCS), errors, "candidate-summary authority_docs mismatch")
    if isinstance(authority_docs, list):
        for idx, item in enumerate(authority_docs):
            if not isinstance(item, dict):
                errors.append(f"candidate-summary authority_docs[{idx}] must be an object")
                continue
            relpath = item.get("path")
            ensure(relpath == AUTHORITY_DOCS[idx], errors, f"candidate-summary authority_docs[{idx}].path mismatch")
            if isinstance(relpath, str):
                source = REPO_ROOT / relpath
                ensure(item.get("sha256") == sha256_file(source), errors, f"candidate-summary authority_docs[{idx}].sha256 mismatch")

    planes = summary.get("planes")
    ensure(isinstance(planes, dict), errors, "candidate-summary planes must be an object")
    if isinstance(planes, dict):
        for plane, index_name in INDEX_FILE_BY_PLANE.items():
            plane_summary = planes.get(plane)
            ensure(isinstance(plane_summary, dict), errors, f"candidate-summary planes.{plane} must be an object")
            if not isinstance(plane_summary, dict):
                continue
            ensure(plane_summary.get("index_path") == index_name, errors, f"candidate-summary planes.{plane}.index_path mismatch")
            ensure(plane_summary.get("asset_count") == indexes[plane]["asset_count"], errors, f"candidate-summary planes.{plane}.asset_count mismatch")
        control = planes.get("control_plane")
        if isinstance(control, dict):
            ensure(control.get("case_ids") == CONTROL_PLANE_CASES, errors, "candidate-summary control_plane.case_ids mismatch")
        execution = planes.get("execution_plane")
        if isinstance(execution, dict):
            ensure(execution.get("components") == EXECUTION_PLANE_COMPONENTS, errors, "candidate-summary execution_plane.components mismatch")
        handoff = planes.get("handoff_pack")
        if isinstance(handoff, dict):
            ensure(handoff.get("anchor_count") == len(HANDOFF_ANCHORS), errors, "candidate-summary handoff_pack.anchor_count mismatch")

    anchors = summary.get("reviewed_task_handoff_anchors")
    ensure(isinstance(anchors, list) and len(anchors) == len(HANDOFF_ANCHORS), errors, "candidate-summary reviewed_task_handoff_anchors mismatch")
    if isinstance(anchors, list):
        for idx, anchor in enumerate(anchors):
            spec = HANDOFF_ANCHORS[idx]
            if not isinstance(anchor, dict):
                errors.append(f"candidate-summary reviewed_task_handoff_anchors[{idx}] must be an object")
                continue
            ensure(anchor.get("task_id") == spec["task_id"], errors, f"candidate-summary anchor[{idx}].task_id mismatch")
            ensure(anchor.get("reviewed_task_path") == spec["reviewed_task_path"], errors, f"candidate-summary anchor[{idx}].reviewed_task_path mismatch")
            ensure(anchor.get("handoff_manifest_path") == spec["handoff_manifest_path"], errors, f"candidate-summary anchor[{idx}].handoff_manifest_path mismatch")
            ensure(anchor.get("workspace_mode") == spec["workspace_mode"], errors, f"candidate-summary anchor[{idx}].workspace_mode mismatch")


def validate_manifest(manifest: object, pack_relpath: str, indexes: dict[str, dict[str, object]], frozen_refs: dict[str, object], errors: list[str]) -> None:
    if not isinstance(manifest, dict):
        errors.append("candidate-manifest.json must be an object")
        return
    ensure(manifest.get("schema_version") == "openclaw.phase3.first-live-pilot.candidate-manifest.v1alpha1", errors, "candidate-manifest schema_version mismatch")
    ensure(manifest.get("candidate_id") == CANDIDATE_ID, errors, "candidate-manifest candidate_id mismatch")
    ensure(manifest.get("candidate_pack_relpath") == pack_relpath, errors, "candidate-manifest candidate_pack_relpath mismatch")
    ensure(manifest.get("ready_state") == READY_STATE, errors, "candidate-manifest ready_state mismatch")
    ensure(manifest.get("required_pack_files") == PACK_FILE_NAMES, errors, "candidate-manifest required_pack_files mismatch")
    ensure(manifest.get("authority_docs") == AUTHORITY_DOCS, errors, "candidate-manifest authority_docs mismatch")
    ensure(manifest.get("validation_entrypoints") == VALIDATION_ENTRYPOINTS, errors, "candidate-manifest validation_entrypoints mismatch")

    index_files = manifest.get("index_files")
    ensure(index_files == INDEX_FILE_BY_PLANE, errors, "candidate-manifest index_files mismatch")

    support_files = manifest.get("support_files")
    expected_support = {
        "candidate_summary": "candidate-summary.json",
        "readiness_assertions": "readiness-assertions.json",
        "frozen_input_refs": "frozen-input-refs.json",
    }
    ensure(support_files == expected_support, errors, "candidate-manifest support_files mismatch")

    asset_counts = manifest.get("asset_counts")
    ensure(isinstance(asset_counts, dict), errors, "candidate-manifest asset_counts must be an object")
    if isinstance(asset_counts, dict):
        ensure(asset_counts.get("control_plane") == indexes["control_plane"]["asset_count"], errors, "candidate-manifest control_plane asset count mismatch")
        ensure(asset_counts.get("execution_plane") == indexes["execution_plane"]["asset_count"], errors, "candidate-manifest execution_plane asset count mismatch")
        ensure(asset_counts.get("handoff_pack") == indexes["handoff_pack"]["asset_count"], errors, "candidate-manifest handoff_pack asset count mismatch")
        ensure(asset_counts.get("frozen_input_refs") == frozen_refs.get("ref_count"), errors, "candidate-manifest frozen_input_refs count mismatch")

    for relpath in VALIDATION_ENTRYPOINTS:
        ensure((REPO_ROOT / relpath).is_file(), errors, f"candidate-manifest validation entrypoint missing: {relpath}")


def validate_readiness(readiness: object, errors: list[str]) -> None:
    if not isinstance(readiness, dict):
        errors.append("readiness-assertions.json must be an object")
        return
    ensure(readiness.get("schema_version") == "openclaw.phase3.first-live-pilot.readiness-assertions.v1alpha1", errors, "readiness-assertions schema_version mismatch")
    ensure(readiness.get("candidate_id") == CANDIDATE_ID, errors, "readiness-assertions candidate_id mismatch")
    ensure(readiness.get("readiness_state") == READY_STATE, errors, "readiness-assertions readiness_state mismatch")
    boundary = readiness.get("boundary_assertions")
    ensure(isinstance(boundary, dict), errors, "readiness-assertions boundary_assertions must be an object")
    if isinstance(boundary, dict):
        expected_boundary = {
            "no_live_side_publish": True,
            "no_real_docker_run": True,
            "no_broker_dispatch": True,
            "no_runtime_change": True,
            "no_operator_exact_command_block": True,
        }
        ensure(boundary == expected_boundary, errors, "readiness-assertions boundary_assertions mismatch")

    blocker = readiness.get("remaining_blocker")
    ensure(isinstance(blocker, dict), errors, "readiness-assertions remaining_blocker must be an object")
    if isinstance(blocker, dict):
        ensure(blocker.get("repo_side_asset_gap_closed") is True, errors, "readiness-assertions remaining_blocker.repo_side_asset_gap_closed must be true")
        ensure(blocker.get("remaining_blocker") == REMAINING_BLOCKER, errors, "readiness-assertions remaining_blocker.remaining_blocker mismatch")
        ensure(blocker.get("remaining_blocker_is_future_execution_seam_or_operator_input") is True, errors, "readiness-assertions remaining_blocker future execution seam flag must be true")

    anchors = readiness.get("reviewed_task_handoff_anchors")
    ensure(isinstance(anchors, list) and len(anchors) == len(HANDOFF_ANCHORS), errors, "readiness-assertions reviewed_task_handoff_anchors mismatch")
    if isinstance(anchors, list):
        for idx, anchor in enumerate(anchors):
            spec = HANDOFF_ANCHORS[idx]
            if not isinstance(anchor, dict):
                errors.append(f"readiness-assertions reviewed_task_handoff_anchors[{idx}] must be an object")
                continue
            ensure(anchor.get("anchor_id") == spec["anchor_id"], errors, f"readiness anchor[{idx}].anchor_id mismatch")
            ensure(anchor.get("task_id") == spec["task_id"], errors, f"readiness anchor[{idx}].task_id mismatch")
            ensure(anchor.get("reviewed_task_path") == spec["reviewed_task_path"], errors, f"readiness anchor[{idx}].reviewed_task_path mismatch")
            ensure(anchor.get("handoff_manifest_path") == spec["handoff_manifest_path"], errors, f"readiness anchor[{idx}].handoff_manifest_path mismatch")
            ensure(anchor.get("exec_plan_path") == spec["exec_plan_path"], errors, f"readiness anchor[{idx}].exec_plan_path mismatch")
            ensure(anchor.get("workspace_layout_path") == spec["workspace_layout_path"], errors, f"readiness anchor[{idx}].workspace_layout_path mismatch")
            ensure(anchor.get("dispatch_scope") == spec["dispatch_scope"], errors, f"readiness anchor[{idx}].dispatch_scope mismatch")
            ensure(anchor.get("workspace_mode") == spec["workspace_mode"], errors, f"readiness anchor[{idx}].workspace_mode mismatch")
            ensure(anchor.get("status") == "present", errors, f"readiness anchor[{idx}].status must be present")


def validate_frozen_refs(frozen_refs: object, indexes: dict[str, dict[str, object]], errors: list[str]) -> None:
    if not isinstance(frozen_refs, dict):
        errors.append("frozen-input-refs.json must be an object")
        return
    ensure(frozen_refs.get("schema_version") == "openclaw.phase3.first-live-pilot.frozen-input-refs.v1alpha1", errors, "frozen-input-refs schema_version mismatch")
    ensure(frozen_refs.get("candidate_id") == CANDIDATE_ID, errors, "frozen-input-refs candidate_id mismatch")

    refs = frozen_refs.get("refs")
    ensure(isinstance(refs, list) and len(refs) > 0, errors, "frozen-input-refs refs must be a non-empty array")
    if not isinstance(refs, list) or not refs:
        return

    expected_paths = set(AUTHORITY_DOCS)
    for plane in ("control_plane", "execution_plane", "handoff_pack"):
        for asset in indexes[plane]["assets"]:
            if isinstance(asset, dict):
                expected_paths.add(str(asset["path"]))

    seen_paths: set[str] = set()
    for idx, ref in enumerate(refs):
        if not isinstance(ref, dict):
            errors.append(f"frozen-input-refs refs[{idx}] must be an object")
            continue
        relpath = ref.get("path")
        ensure(isinstance(relpath, str) and relpath.strip() != "", errors, f"frozen-input-refs refs[{idx}].path must be a non-empty string")
        if not isinstance(relpath, str) or relpath.strip() == "":
            continue
        ensure(relpath not in seen_paths, errors, f"frozen-input-refs refs[{idx}].path must be unique")
        seen_paths.add(relpath)
        ensure(relpath in expected_paths, errors, f"frozen-input-refs refs[{idx}].path must belong to the candidate input set")
        source = REPO_ROOT / relpath
        ensure(source.is_file(), errors, f"frozen-input-refs refs[{idx}].path missing: {relpath}")
        if source.is_file():
            ensure(ref.get("sha256") == sha256_file(source), errors, f"frozen-input-refs refs[{idx}].sha256 mismatch for {relpath}")
            ensure(ref.get("bytes") == bytes_for_file(source), errors, f"frozen-input-refs refs[{idx}].bytes mismatch for {relpath}")
        ensure(is_git_tracked(relpath), errors, f"frozen-input-refs refs[{idx}].path must be git-tracked: {relpath}")
        if relpath in AUTHORITY_DOCS:
            ensure(ref.get("plane") == "authority", errors, f"frozen-input-refs refs[{idx}].plane must be authority for {relpath}")
            ensure(ref.get("kind") == "authority_doc", errors, f"frozen-input-refs refs[{idx}].kind must be authority_doc for {relpath}")
        else:
            ensure(ref.get("kind") == "asset", errors, f"frozen-input-refs refs[{idx}].kind must be asset for {relpath}")

    ensure(seen_paths == expected_paths, errors, "frozen-input-refs path set must match authority docs plus indexed assets exactly")
    ensure(frozen_refs.get("ref_count") == len(refs), errors, "frozen-input-refs ref_count must match refs length")


def validate_pack(pack_dir: Path) -> list[str]:
    errors: list[str] = []
    ensure(pack_dir.is_dir(), errors, f"pack directory missing: {pack_dir}")
    if errors:
        return errors

    pack_relpath = candidate_relpath(pack_dir)
    expected_relpath = f"{PACK_ROOT_RELATIVE}/{CANDIDATE_ID}"
    ensure(pack_relpath == expected_relpath, errors, f"candidate pack must live at {expected_relpath}")

    actual_files = sorted(path.name for path in pack_dir.iterdir() if path.is_file())
    ensure(actual_files == sorted(PACK_FILE_NAMES), errors, "candidate pack file set must match the required file list exactly")
    for filename in PACK_FILE_NAMES:
        ensure((pack_dir / filename).is_file(), errors, f"missing candidate pack file: {filename}")
    if errors:
        return errors

    indexes: dict[str, dict[str, object]] = {}
    for plane, filename in INDEX_FILE_BY_PLANE.items():
        loaded = load_json(pack_dir / filename)
        validated = validate_index(loaded, plane, errors, filename)
        if isinstance(validated, dict):
            indexes[plane] = validated

    summary = load_json(pack_dir / "candidate-summary.json")
    readiness = load_json(pack_dir / "readiness-assertions.json")
    frozen_refs = load_json(pack_dir / "frozen-input-refs.json")
    manifest = load_json(pack_dir / "candidate-manifest.json")

    if len(indexes) == 3:
        validate_summary(summary, pack_relpath, indexes, errors)
        validate_readiness(readiness, errors)
        validate_frozen_refs(frozen_refs, indexes, errors)
        validate_manifest(manifest, pack_relpath, indexes, frozen_refs if isinstance(frozen_refs, dict) else {}, errors)

    return errors


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.expect_valid and args.expect_invalid:
        raise SystemExit("choose only one of --expect-valid or --expect-invalid")

    errors = validate_pack(Path(args.pack_dir).resolve())
    expect_invalid = args.expect_invalid
    if errors:
        if expect_invalid:
            return 0
        detail = "\n".join(f"  - {item}" for item in errors)
        print(f"first-live-pilot candidate pack validation failed:\n{detail}", file=sys.stderr)
        return 1

    if expect_invalid:
        print("validation unexpectedly succeeded", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
