#!/usr/bin/env python3
"""Validate stable phase3 control-plane replay artifact manifests."""

from __future__ import annotations

from pathlib import Path
import hashlib
import importlib.util
import json
import sys


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_contracts import (  # noqa: E402
    ID_RE,
    SHA256_RE,
    ensure,
    ensure_type,
    load_json,
    reject_extra_keys,
)


MANIFEST_VERSION = "openclaw.main.control-plane-artifact-manifest.v1alpha1"
REPLAY_MODE = "repo_side_control_plane_dry_run"
CANONICAL_ARTIFACTS = {
    "summary.json": "validate-task-runner-summary",
    "request.normalized.json": "validate-broker-ready-request",
    "intake-report.json": "validate-task-runner-intake-report",
    "routing-decision.json": "validate-main-routing-decision",
    "broker-submission-envelope.json": "validate-broker-submission-envelope",
    "operator-approval-envelope.json": "validate-operator-approval-envelope",
    "broker-review-bundle.json": "validate-broker-review-bundle",
    "operator-review-bundle.json": "validate-operator-review-bundle",
    "dispatch-intent-ledger.json": "validate-dispatch-intent-ledger",
}


def load_validator(script_name: str):
    module_name = script_name.replace("-", "_")
    script_path = SCRIPT_DIR / f"{script_name}.py"
    spec = importlib.util.spec_from_file_location(module_name, script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load validator module: {script_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.validate_document


VALIDATORS = {name: load_validator(name) for name in set(CANONICAL_ARTIFACTS.values())}


def usage() -> int:
    print(
        "Usage: scripts/validate-control-plane-artifact-manifest.py "
        "[--expect-valid|--expect-invalid] FILE [FILE ...]"
    )
    return 2


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_boundary_assertions(value: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(
        value,
        {
            "repo_side_only",
            "live_side_publish_performed",
            "broker_dispatch_performed",
            "openclaw_runtime_modified",
            "operator_command_blocks_present",
        },
        errors,
        where,
    )
    ensure(value.get("repo_side_only") is True, errors, f"{where}.repo_side_only must be true")
    ensure(value.get("live_side_publish_performed") is False, errors, f"{where}.live_side_publish_performed must be false")
    ensure(value.get("broker_dispatch_performed") is False, errors, f"{where}.broker_dispatch_performed must be false")
    ensure(value.get("openclaw_runtime_modified") is False, errors, f"{where}.openclaw_runtime_modified must be false")
    ensure(value.get("operator_command_blocks_present") is False, errors, f"{where}.operator_command_blocks_present must be false")


def validate_source(value: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(value, {"kind", "case_name", "input_dir", "summary_path", "host_change_request_path"}, errors, where)
    ensure(value.get("kind") in {"fixture_case", "task_runner_output_dir"}, errors, f"{where}.kind must be fixture_case or task_runner_output_dir")
    case_name = value.get("case_name")
    ensure(case_name is None or isinstance(case_name, str), errors, f"{where}.case_name must be null or string")
    for key in ("input_dir", "summary_path", "host_change_request_path"):
        ensure(isinstance(value.get(key), str) and str(value.get(key)).strip() != "", errors, f"{where}.{key} must be a non-empty path string")


def validate_builder_exit_codes(value: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(value, {"intake", "routing", "submission", "review", "dispatch_intent"}, errors, where)
    for key in ("intake", "routing", "submission", "review", "dispatch_intent"):
        ensure(isinstance(value.get(key), int), errors, f"{where}.{key} must be an integer")
    if isinstance(value.get("intake"), int):
        ensure(value["intake"] in {0, 1}, errors, f"{where}.intake must be 0 or 1")
    if isinstance(value.get("routing"), int):
        ensure(value["routing"] in {0, 1}, errors, f"{where}.routing must be 0 or 1")
    for key in ("submission", "review", "dispatch_intent"):
        if isinstance(value.get(key), int):
            ensure(value[key] == 0, errors, f"{where}.{key} must be 0")


def validate_route_summary(value: object, errors: list[str], where: str) -> None:
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return
    reject_extra_keys(value, {"decision", "dispatch_scope", "dispatch_status", "requires_operator_approval"}, errors, where)
    ensure(value.get("decision") in {"LOCAL_REFUSE", "REQUIRES_OPERATOR_APPROVAL", "BROKER_SUBMISSION_CANDIDATE"}, errors, f"{where}.decision invalid")
    ensure(value.get("dispatch_scope") in {"readonly", "host_affecting", "unclassified"}, errors, f"{where}.dispatch_scope invalid")
    ensure(value.get("dispatch_status") in {"broker_ready", "operator_approval_required", "refused"}, errors, f"{where}.dispatch_status invalid")
    ensure(isinstance(value.get("requires_operator_approval"), bool), errors, f"{where}.requires_operator_approval must be boolean")


def validate_expected_layout(value: object, errors: list[str], where: str) -> tuple[set[str], set[str]]:
    required: set[str] = set()
    forbidden: set[str] = set()
    if not ensure_type(value, dict, errors, f"{where} must be an object"):
        return required, forbidden
    reject_extra_keys(value, {"required_artifacts", "forbidden_artifacts"}, errors, where)
    required_list = value.get("required_artifacts")
    forbidden_list = value.get("forbidden_artifacts")
    for label, target, bucket in (
        ("required_artifacts", required_list, required),
        ("forbidden_artifacts", forbidden_list, forbidden),
    ):
        if not ensure_type(target, list, errors, f"{where}.{label} must be an array"):
            continue
        for idx, item in enumerate(target):
            item_where = f"{where}.{label}[{idx}]"
            ensure(item in CANONICAL_ARTIFACTS, errors, f"{item_where} must be a canonical artifact path")
            if isinstance(item, str):
                bucket.add(item)
    ensure(required.isdisjoint(forbidden), errors, f"{where} required_artifacts and forbidden_artifacts must not overlap")
    return required, forbidden


def validate_artifacts(
    value: object,
    run_dir: Path,
    required_artifacts: set[str],
    forbidden_artifacts: set[str],
    errors: list[str],
    where: str,
) -> None:
    if not ensure_type(value, list, errors, f"{where} must be an array"):
        return

    seen_names: set[str] = set()
    seen_paths: set[str] = set()
    declared_paths: set[str] = set()
    present_paths: set[str] = set()

    for idx, item in enumerate(value):
        item_where = f"{where}[{idx}]"
        if not ensure_type(item, dict, errors, f"{item_where} must be an object"):
            continue
        reject_extra_keys(item, {"name", "path", "required", "present", "sha256", "validator"}, errors, item_where)
        name = item.get("name")
        path = item.get("path")
        required = item.get("required")
        present = item.get("present")
        validator = item.get("validator")
        sha256 = item.get("sha256")

        ensure(isinstance(name, str) and name not in seen_names, errors, f"{item_where}.name must be unique")
        ensure(isinstance(path, str) and path not in seen_paths, errors, f"{item_where}.path must be unique")
        if isinstance(name, str):
            seen_names.add(name)
        if isinstance(path, str):
            seen_paths.add(path)
            declared_paths.add(path)
            ensure(path in CANONICAL_ARTIFACTS, errors, f"{item_where}.path must be canonical")

        ensure(isinstance(required, bool), errors, f"{item_where}.required must be boolean")
        ensure(isinstance(present, bool), errors, f"{item_where}.present must be boolean")
        if isinstance(validator, str):
            ensure(validator == f"scripts/{CANONICAL_ARTIFACTS.get(path, '')}.py", errors, f"{item_where}.validator must match the canonical validator")
        else:
            errors.append(f"{item_where}.validator must be a string")

        if isinstance(path, str) and isinstance(required, bool):
            if path in required_artifacts:
                ensure(required is True, errors, f"{item_where}.required must be true because expected_layout requires {path}")
            if path in forbidden_artifacts:
                ensure(required is False, errors, f"{item_where}.required must be false because expected_layout forbids {path}")

        artifact_path = run_dir / str(path)
        if present is True:
            ensure(required is True or path not in forbidden_artifacts, errors, f"{item_where} present artifact must not be forbidden")
            ensure(artifact_path.is_file(), errors, f"{item_where} declares present=true but file is missing")
            ensure(isinstance(sha256, str) and SHA256_RE.match(sha256) is not None, errors, f"{item_where}.sha256 must be 64 lowercase hex")
            if artifact_path.is_file() and isinstance(sha256, str) and SHA256_RE.match(sha256) is not None:
                ensure(sha256_file(artifact_path) == sha256, errors, f"{item_where}.sha256 does not match file contents")
                present_paths.add(str(path))
                validator_name = CANONICAL_ARTIFACTS.get(str(path))
                if validator_name is not None:
                    validator_errors = VALIDATORS[validator_name](artifact_path)
                    for validator_error in validator_errors:
                        errors.append(f"{item_where} validation failed: {validator_error}")
        elif present is False:
            ensure(not artifact_path.exists(), errors, f"{item_where} declares present=false but file exists")
            ensure("sha256" not in item, errors, f"{item_where}.sha256 must be omitted when present=false")

        if required is True:
            ensure(present is True, errors, f"{item_where} required artifacts must be present")

    ensure(declared_paths == set(CANONICAL_ARTIFACTS.keys()), errors, f"{where} must declare every canonical artifact exactly once")

    actual_files = sorted(path.name for path in run_dir.iterdir() if path.is_file() and path.name != "artifact-manifest.json")
    ensure(set(actual_files) == present_paths, errors, f"{where} present artifact set must match actual files in run dir")


def validate_route_consistency(
    route_summary: object,
    expected_layout: object,
    errors: list[str],
    where: str,
) -> None:
    if not isinstance(route_summary, dict) or not isinstance(expected_layout, dict):
        return
    decision = route_summary.get("decision")
    required = set(expected_layout.get("required_artifacts", [])) if isinstance(expected_layout.get("required_artifacts"), list) else set()
    forbidden = set(expected_layout.get("forbidden_artifacts", [])) if isinstance(expected_layout.get("forbidden_artifacts"), list) else set()

    if decision == "BROKER_SUBMISSION_CANDIDATE":
        ensure(
            {"broker-submission-envelope.json", "broker-review-bundle.json"} <= required,
            errors,
            f"{where}: broker candidate must require broker submission and review artifacts",
        )
        ensure(
            {"operator-approval-envelope.json", "operator-review-bundle.json"} <= forbidden,
            errors,
            f"{where}: broker candidate must forbid operator approval artifacts",
        )
    elif decision == "REQUIRES_OPERATOR_APPROVAL":
        ensure(
            {"operator-approval-envelope.json", "operator-review-bundle.json"} <= required,
            errors,
            f"{where}: approval route must require operator approval artifacts",
        )
        ensure(
            {"broker-submission-envelope.json", "broker-review-bundle.json"} <= forbidden,
            errors,
            f"{where}: approval route must forbid broker submission artifacts",
        )
    elif decision == "LOCAL_REFUSE":
        ensure(
            {
                "broker-submission-envelope.json",
                "operator-approval-envelope.json",
                "broker-review-bundle.json",
                "operator-review-bundle.json",
            }
            <= forbidden,
            errors,
            f"{where}: local refusal must forbid all submission and review artifacts",
        )


def validate_document(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        data = load_json(path)
    except FileNotFoundError:
        return [f"{path}: file not found"]
    except Exception as exc:  # pragma: no cover
        return [f"{path}: could not parse JSON: {exc}"]

    if not isinstance(data, dict):
        return [f"{path}: root must be an object"]

    run_dir = path.parent
    reject_extra_keys(
        data,
        {
            "schema_version",
            "manifest_id",
            "run_id",
            "replay_mode",
            "source",
            "builder_exit_codes",
            "route_summary",
            "boundary_assertions",
            "expected_layout",
            "artifacts",
        },
        errors,
        str(path),
    )

    ensure(data.get("schema_version") == MANIFEST_VERSION, errors, f"{path}: schema_version mismatch")
    for key in ("manifest_id", "run_id"):
        ensure(ID_RE.match(str(data.get(key, ""))) is not None, errors, f"{path}: {key} must match contract id format")
    ensure(data.get("replay_mode") == REPLAY_MODE, errors, f"{path}: replay_mode mismatch")
    validate_source(data.get("source"), errors, f"{path}.source")
    validate_builder_exit_codes(data.get("builder_exit_codes"), errors, f"{path}.builder_exit_codes")
    validate_route_summary(data.get("route_summary"), errors, f"{path}.route_summary")
    validate_boundary_assertions(data.get("boundary_assertions"), errors, f"{path}.boundary_assertions")
    required_artifacts, forbidden_artifacts = validate_expected_layout(data.get("expected_layout"), errors, f"{path}.expected_layout")
    validate_route_consistency(data.get("route_summary"), data.get("expected_layout"), errors, f"{path}.route_consistency")
    validate_artifacts(data.get("artifacts"), run_dir, required_artifacts, forbidden_artifacts, errors, f"{path}.artifacts")
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
