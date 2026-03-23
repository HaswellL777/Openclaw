#!/usr/bin/env python3
"""Assemble the repo-side first-live-pilot candidate pack."""

from __future__ import annotations

from pathlib import Path
import argparse
import json
import shutil
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
    PLANE_SPECS,
    READY_STATE,
    REMAINING_BLOCKER,
    VALIDATION_ENTRYPOINTS,
    bytes_for_file,
    expand_relative_paths,
    sha256_file,
)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the first-live-pilot candidate pack from current repo-side assets.",
    )
    parser.add_argument(
        "--output-root",
        default=str(REPO_ROOT / PACK_ROOT_RELATIVE),
        help="Root directory that will contain <candidate-id>/",
    )
    parser.add_argument("--candidate-id", default=CANDIDATE_ID, help="Candidate identifier for the pack directory")
    parser.add_argument("--force", action="store_true", help="Replace an existing candidate directory")
    parser.add_argument("--print-pack-dir", action="store_true", help="Print the final candidate directory path")
    return parser.parse_args(argv)


def mkdir_clean(path: Path, force: bool) -> None:
    if path.exists():
        if not force:
            raise SystemExit(f"output already exists: {path} (use --force to replace)")
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def write_json(path: Path, data: dict[str, object]) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def build_asset_entries(plane: str) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    assets: list[dict[str, object]] = []
    group_summaries: list[dict[str, object]] = []
    seen_paths: set[str] = set()

    for spec in PLANE_SPECS[plane]:
        relpaths = expand_relative_paths(REPO_ROOT, spec.get("files"), spec.get("dirs"))
        group_assets: list[str] = []
        for relpath in relpaths:
            if relpath in seen_paths:
                raise SystemExit(f"duplicate asset path in {plane}: {relpath}")
            source = REPO_ROOT / relpath
            if not source.is_file():
                raise SystemExit(f"missing asset for {plane}: {source}")
            seen_paths.add(relpath)
            group_assets.append(relpath)
            asset_id = f"{plane}:{spec['group']}:{relpath.replace('/', ':')}"
            assets.append(
                {
                    "asset_id": asset_id,
                    "group": spec["group"],
                    "category": spec["category"],
                    "role": spec["role"],
                    "path": relpath,
                    "sha256": sha256_file(source),
                    "bytes": bytes_for_file(source),
                }
            )
        group_summaries.append(
            {
                "group": spec["group"],
                "category": spec["category"],
                "role": spec["role"],
                "asset_count": len(group_assets),
                "paths": group_assets,
            }
        )

    return assets, group_summaries


def build_index(plane: str, candidate_id: str) -> dict[str, object]:
    assets, group_summaries = build_asset_entries(plane)
    index: dict[str, object] = {
        "schema_version": "openclaw.phase3.first-live-pilot.asset-index.v1alpha1",
        "candidate_id": candidate_id,
        "plane": plane,
        "asset_count": len(assets),
        "asset_groups": group_summaries,
        "assets": assets,
    }
    if plane == "control_plane":
        index["case_ids"] = CONTROL_PLANE_CASES
    if plane == "execution_plane":
        index["components"] = EXECUTION_PLANE_COMPONENTS
    if plane == "handoff_pack":
        index["anchors"] = HANDOFF_ANCHORS
    return index


def build_frozen_refs(
    candidate_id: str,
    indexes: dict[str, dict[str, object]],
) -> dict[str, object]:
    refs: list[dict[str, object]] = []
    seen_paths: set[str] = set()

    for relpath in AUTHORITY_DOCS:
        source = REPO_ROOT / relpath
        refs.append(
            {
                "ref_id": f"authority:{relpath.replace('/', ':')}",
                "plane": "authority",
                "kind": "authority_doc",
                "path": relpath,
                "sha256": sha256_file(source),
                "bytes": bytes_for_file(source),
            }
        )
        seen_paths.add(relpath)

    for plane, index in indexes.items():
        for asset in index["assets"]:
            relpath = str(asset["path"])
            if relpath in seen_paths:
                continue
            refs.append(
                {
                    "ref_id": f"{plane}:{relpath.replace('/', ':')}",
                    "plane": plane,
                    "kind": "asset",
                    "path": relpath,
                    "sha256": asset["sha256"],
                    "bytes": asset["bytes"],
                }
            )
            seen_paths.add(relpath)

    return {
        "schema_version": "openclaw.phase3.first-live-pilot.frozen-input-refs.v1alpha1",
        "candidate_id": candidate_id,
        "ref_count": len(refs),
        "refs": refs,
    }


def build_readiness_assertions(candidate_id: str) -> dict[str, object]:
    return {
        "schema_version": "openclaw.phase3.first-live-pilot.readiness-assertions.v1alpha1",
        "candidate_id": candidate_id,
        "readiness_state": READY_STATE,
        "boundary_assertions": {
            "no_live_side_publish": True,
            "no_real_docker_run": True,
            "no_broker_dispatch": True,
            "no_runtime_change": True,
            "no_operator_exact_command_block": True,
        },
        "remaining_blocker": {
            "repo_side_asset_gap_closed": True,
            "remaining_blocker": REMAINING_BLOCKER,
            "remaining_blocker_is_future_execution_seam_or_operator_input": True,
            "summary": "Current repo-side assets are assembled; the remaining blocker is future execution seam / operator input, not a repo-side asset gap.",
        },
        "reviewed_task_handoff_anchors": [
            {
                "anchor_id": anchor["anchor_id"],
                "task_id": anchor["task_id"],
                "reviewed_task_path": anchor["reviewed_task_path"],
                "handoff_manifest_path": anchor["handoff_manifest_path"],
                "exec_plan_path": anchor["exec_plan_path"],
                "workspace_layout_path": anchor["workspace_layout_path"],
                "dispatch_scope": anchor["dispatch_scope"],
                "workspace_mode": anchor["workspace_mode"],
                "status": "present",
            }
            for anchor in HANDOFF_ANCHORS
        ],
    }


def build_candidate_summary(
    candidate_id: str,
    candidate_relpath: str,
    indexes: dict[str, dict[str, object]],
) -> dict[str, object]:
    authority_refs = []
    for relpath in AUTHORITY_DOCS:
        source = REPO_ROOT / relpath
        authority_refs.append(
            {
                "path": relpath,
                "sha256": sha256_file(source),
            }
        )

    return {
        "schema_version": "openclaw.phase3.first-live-pilot.candidate-summary.v1alpha1",
        "candidate_id": candidate_id,
        "candidate_pack_relpath": candidate_relpath,
        "readiness_state": READY_STATE,
        "repo_side_gap_closed": True,
        "remaining_blocker": REMAINING_BLOCKER,
        "authority_docs": authority_refs,
        "planes": {
            "control_plane": {
                "index_path": "control-plane-asset-index.json",
                "asset_count": indexes["control_plane"]["asset_count"],
                "case_ids": CONTROL_PLANE_CASES,
            },
            "execution_plane": {
                "index_path": "execution-plane-asset-index.json",
                "asset_count": indexes["execution_plane"]["asset_count"],
                "components": EXECUTION_PLANE_COMPONENTS,
            },
            "handoff_pack": {
                "index_path": "handoff-pack-asset-index.json",
                "asset_count": indexes["handoff_pack"]["asset_count"],
                "anchor_count": len(HANDOFF_ANCHORS),
            },
        },
        "reviewed_task_handoff_anchors": [
            {
                "task_id": anchor["task_id"],
                "reviewed_task_path": anchor["reviewed_task_path"],
                "handoff_manifest_path": anchor["handoff_manifest_path"],
                "workspace_mode": anchor["workspace_mode"],
            }
            for anchor in HANDOFF_ANCHORS
        ],
    }


def build_candidate_manifest(
    candidate_id: str,
    candidate_relpath: str,
    indexes: dict[str, dict[str, object]],
    frozen_ref_count: int,
) -> dict[str, object]:
    return {
        "schema_version": "openclaw.phase3.first-live-pilot.candidate-manifest.v1alpha1",
        "candidate_id": candidate_id,
        "candidate_pack_relpath": candidate_relpath,
        "ready_state": READY_STATE,
        "required_pack_files": PACK_FILE_NAMES,
        "index_files": {
            "control_plane": "control-plane-asset-index.json",
            "execution_plane": "execution-plane-asset-index.json",
            "handoff_pack": "handoff-pack-asset-index.json",
        },
        "support_files": {
            "candidate_summary": "candidate-summary.json",
            "readiness_assertions": "readiness-assertions.json",
            "frozen_input_refs": "frozen-input-refs.json",
        },
        "authority_docs": AUTHORITY_DOCS,
        "validation_entrypoints": VALIDATION_ENTRYPOINTS,
        "asset_counts": {
            "control_plane": indexes["control_plane"]["asset_count"],
            "execution_plane": indexes["execution_plane"]["asset_count"],
            "handoff_pack": indexes["handoff_pack"]["asset_count"],
            "frozen_input_refs": frozen_ref_count,
        },
    }


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    output_root = Path(args.output_root).resolve()
    candidate_dir = output_root / args.candidate_id
    candidate_relpath = candidate_dir.relative_to(REPO_ROOT).as_posix()
    mkdir_clean(candidate_dir, args.force)

    indexes = {
        "control_plane": build_index("control_plane", args.candidate_id),
        "execution_plane": build_index("execution_plane", args.candidate_id),
        "handoff_pack": build_index("handoff_pack", args.candidate_id),
    }
    frozen_refs = build_frozen_refs(args.candidate_id, indexes)
    readiness = build_readiness_assertions(args.candidate_id)
    summary = build_candidate_summary(args.candidate_id, candidate_relpath, indexes)
    manifest = build_candidate_manifest(
        args.candidate_id,
        candidate_relpath,
        indexes,
        frozen_ref_count=int(frozen_refs["ref_count"]),
    )

    write_json(candidate_dir / "control-plane-asset-index.json", indexes["control_plane"])
    write_json(candidate_dir / "execution-plane-asset-index.json", indexes["execution_plane"])
    write_json(candidate_dir / "handoff-pack-asset-index.json", indexes["handoff_pack"])
    write_json(candidate_dir / "readiness-assertions.json", readiness)
    write_json(candidate_dir / "frozen-input-refs.json", frozen_refs)
    write_json(candidate_dir / "candidate-summary.json", summary)
    write_json(candidate_dir / "candidate-manifest.json", manifest)

    if args.print_pack_dir:
        print(candidate_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
