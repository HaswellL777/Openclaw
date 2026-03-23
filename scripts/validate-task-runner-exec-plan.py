#!/usr/bin/env python3
"""Validate task-runner execution plan artifacts."""

from __future__ import annotations

from pathlib import Path
import sys

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))

from task_runner_container_contracts import (  # noqa: E402
    ID_RE,
    NETWORK_MODES,
    REQUIRED_AGENT_ALLOW,
    REQUIRED_AGENT_DENY,
    REQUIRED_ALLOWED_ENV,
    REQUIRED_AVAILABLE_BINARIES,
    REQUIRED_FORBIDDEN_ENV,
    REQUIRED_OUTPUT_ARTIFACTS,
    REQUIRED_UNAVAILABLE_BINARIES,
    RUNNER_BOOTSTRAP_PATH,
    RUNNER_TOOLS,
    WORKSPACE_MODES,
    ensure,
    ensure_type,
    is_non_empty_string,
    is_relative_path,
    load_document,
    reject_extra_keys,
    validate_boundary_flags,
    validate_container_path,
    validate_env_name_list,
    validate_schema_file,
)


REPO_ROOT = SCRIPT_DIR.parent
SCHEMA_PATH = REPO_ROOT / "schemas" / "task-runner-exec-plan.schema.json"


def usage() -> int:
    print("Usage: scripts/validate-task-runner-exec-plan.py [--expect-valid|--expect-invalid] FILE [FILE ...]")
    return 2


def validate_document(path: Path) -> list[str]:
    errors = validate_schema_file(
        SCHEMA_PATH,
        expected_title="TaskRunnerExecPlan",
        expected_const="openclaw.task-runner.exec-plan.v1alpha1",
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
            "plan_id",
            "task_id",
            "image",
            "workspace",
            "inputs",
            "outputs",
            "environment",
            "tool_contract",
            "invocation",
            "network",
            "privilege",
            "boundary_carry_forward",
        },
        errors,
        str(path),
    )

    ensure(data.get("schema_version") == "openclaw.task-runner.exec-plan.v1alpha1", errors, f"{path}: schema_version mismatch")
    ensure(ID_RE.match(str(data.get("plan_id", ""))) is not None, errors, f"{path}: plan_id must match contract id format")
    ensure(ID_RE.match(str(data.get("task_id", ""))) is not None, errors, f"{path}: task_id must match contract id format")

    image = data.get("image")
    if ensure_type(image, dict, errors, f"{path}: image must be an object"):
        reject_extra_keys(image, {"reference", "pull_policy", "run_as_user", "workdir", "entrypoint"}, errors, f"{path}.image")
        ensure(is_non_empty_string(image.get("reference")), errors, f"{path}.image.reference must be non-empty")
        ensure(image.get("pull_policy") in {"never", "if_not_present"}, errors, f"{path}.image.pull_policy must be supported")
        ensure(image.get("run_as_user") == "runner", errors, f"{path}.image.run_as_user must be runner")
        ensure(image.get("workdir") == "/workspace/repo", errors, f"{path}.image.workdir must be /workspace/repo")
        ensure(image.get("entrypoint") == "/usr/local/bin/task-runner-entrypoint", errors, f"{path}.image.entrypoint must be /usr/local/bin/task-runner-entrypoint")

    workspace = data.get("workspace")
    workspace_mode = None
    if ensure_type(workspace, dict, errors, f"{path}: workspace must be an object"):
        reject_extra_keys(
            workspace,
            {
                "layout_mode",
                "layout_artifact",
                "root_path",
                "repo_path",
                "inputs_path",
                "outputs_path",
                "artifact_export_path",
            },
            errors,
            f"{path}.workspace",
        )
        workspace_mode = workspace.get("layout_mode")
        ensure(workspace_mode in WORKSPACE_MODES, errors, f"{path}.workspace.layout_mode must be readonly or dev")
        ensure(is_relative_path(workspace.get("layout_artifact")), errors, f"{path}.workspace.layout_artifact must be a relative path")
        ensure(workspace.get("root_path") == "/workspace", errors, f"{path}.workspace.root_path must be /workspace")
        ensure(workspace.get("repo_path") == "/workspace/repo", errors, f"{path}.workspace.repo_path must be /workspace/repo")
        ensure(workspace.get("inputs_path") == "/workspace/inputs", errors, f"{path}.workspace.inputs_path must be /workspace/inputs")
        ensure(workspace.get("outputs_path") == "/workspace/outputs", errors, f"{path}.workspace.outputs_path must be /workspace/outputs")
        ensure(workspace.get("artifact_export_path") == "/workspace/outputs/export", errors, f"{path}.workspace.artifact_export_path must be /workspace/outputs/export")

    inputs = data.get("inputs")
    if ensure_type(inputs, dict, errors, f"{path}: inputs must be an object"):
        reject_extra_keys(inputs, {"required_inputs"}, errors, f"{path}.inputs")
        required_inputs = inputs.get("required_inputs")
        if ensure_type(required_inputs, list, errors, f"{path}.inputs.required_inputs must be an array"):
            ensure(len(required_inputs) > 0, errors, f"{path}.inputs.required_inputs must not be empty")
            for idx, input_path in enumerate(required_inputs):
                validate_container_path(input_path, errors, f"{path}.inputs.required_inputs[{idx}]", prefix="/workspace/inputs")

    outputs = data.get("outputs")
    if ensure_type(outputs, dict, errors, f"{path}: outputs must be an object"):
        reject_extra_keys(outputs, {"required_artifacts", "artifact_export_path", "preserve_failed_run_logs"}, errors, f"{path}.outputs")
        required_artifacts = outputs.get("required_artifacts")
        artifact_set: set[str] = set()
        if ensure_type(required_artifacts, list, errors, f"{path}.outputs.required_artifacts must be an array"):
            ensure(len(required_artifacts) >= 3, errors, f"{path}.outputs.required_artifacts must contain the minimum export surface")
            for idx, output_path in enumerate(required_artifacts):
                validate_container_path(output_path, errors, f"{path}.outputs.required_artifacts[{idx}]", prefix="/workspace/outputs")
                if isinstance(output_path, str):
                    artifact_set.add(output_path)
            ensure(REQUIRED_OUTPUT_ARTIFACTS.issubset(artifact_set), errors, f"{path}.outputs.required_artifacts must include summary.md, summary.json, and diff.patch")
        ensure(outputs.get("artifact_export_path") == "/workspace/outputs/export", errors, f"{path}.outputs.artifact_export_path must be /workspace/outputs/export")
        ensure(isinstance(outputs.get("preserve_failed_run_logs"), bool), errors, f"{path}.outputs.preserve_failed_run_logs must be boolean")

    environment = data.get("environment")
    if ensure_type(environment, dict, errors, f"{path}: environment must be an object"):
        reject_extra_keys(environment, {"allowed", "required", "forbidden"}, errors, f"{path}.environment")
        allowed = validate_env_name_list(environment.get("allowed"), errors, f"{path}.environment.allowed")
        required = validate_env_name_list(environment.get("required"), errors, f"{path}.environment.required")
        forbidden = validate_env_name_list(environment.get("forbidden"), errors, f"{path}.environment.forbidden")
        ensure(REQUIRED_ALLOWED_ENV.issubset(allowed), errors, f"{path}.environment.allowed must include the required task-runner env surface")
        ensure(required.issubset(allowed), errors, f"{path}.environment.required must be a subset of environment.allowed")
        ensure(REQUIRED_ALLOWED_ENV.issubset(required), errors, f"{path}.environment.required must include the core runner env names")
        ensure(REQUIRED_FORBIDDEN_ENV.issubset(forbidden), errors, f"{path}.environment.forbidden must preserve the required forbidden env names")
        ensure(allowed.isdisjoint(forbidden), errors, f"{path}.environment.allowed and environment.forbidden must be disjoint")

    tool_contract = data.get("tool_contract")
    if ensure_type(tool_contract, dict, errors, f"{path}: tool_contract must be an object"):
        reject_extra_keys(tool_contract, {"agent_tools", "container_binaries"}, errors, f"{path}.tool_contract")
        agent_tools = tool_contract.get("agent_tools")
        if ensure_type(agent_tools, dict, errors, f"{path}.tool_contract.agent_tools must be an object"):
            reject_extra_keys(agent_tools, {"allow", "deny"}, errors, f"{path}.tool_contract.agent_tools")
            allow = set(agent_tools.get("allow", [])) if isinstance(agent_tools.get("allow"), list) else set()
            deny = set(agent_tools.get("deny", [])) if isinstance(agent_tools.get("deny"), list) else set()
            ensure(REQUIRED_AGENT_ALLOW.issubset(allow), errors, f"{path}.tool_contract.agent_tools.allow must include the required OpenClaw task-runner tools")
            ensure(REQUIRED_AGENT_DENY.issubset(deny), errors, f"{path}.tool_contract.agent_tools.deny must include sessions_spawn and elevated")
            ensure(allow.isdisjoint(deny), errors, f"{path}.tool_contract.agent_tools allow and deny sets must be disjoint")
        container_binaries = tool_contract.get("container_binaries")
        if ensure_type(container_binaries, dict, errors, f"{path}.tool_contract.container_binaries must be an object"):
            reject_extra_keys(container_binaries, {"expected_available", "expected_unavailable"}, errors, f"{path}.tool_contract.container_binaries")
            expected_available = set(container_binaries.get("expected_available", [])) if isinstance(container_binaries.get("expected_available"), list) else set()
            expected_unavailable = set(container_binaries.get("expected_unavailable", [])) if isinstance(container_binaries.get("expected_unavailable"), list) else set()
            ensure(REQUIRED_AVAILABLE_BINARIES.issubset(expected_available), errors, f"{path}.tool_contract.container_binaries.expected_available must include the minimum toolchain")
            ensure(REQUIRED_UNAVAILABLE_BINARIES.issubset(expected_unavailable), errors, f"{path}.tool_contract.container_binaries.expected_unavailable must include docker/sudo/systemctl/mount/umount")
            ensure(expected_available.isdisjoint(REQUIRED_UNAVAILABLE_BINARIES), errors, f"{path}.tool_contract.container_binaries.expected_available must not expose docker/sudo/systemctl/mount/umount")

    invocation = data.get("invocation")
    if ensure_type(invocation, dict, errors, f"{path}: invocation must be an object"):
        reject_extra_keys(invocation, {"runner", "mode", "bootstrap_path", "prompt_source"}, errors, f"{path}.invocation")
        runner = invocation.get("runner")
        ensure(runner in RUNNER_TOOLS, errors, f"{path}.invocation.runner must be codex or claudecode")
        ensure(invocation.get("mode") == "non_interactive", errors, f"{path}.invocation.mode must be non_interactive")
        if runner in RUNNER_BOOTSTRAP_PATH:
            ensure(invocation.get("bootstrap_path") == RUNNER_BOOTSTRAP_PATH[runner], errors, f"{path}.invocation.bootstrap_path must match the selected runner")
        ensure(invocation.get("prompt_source") in {"file", "stdin"}, errors, f"{path}.invocation.prompt_source must be file or stdin")

    network = data.get("network")
    if ensure_type(network, dict, errors, f"{path}: network must be an object"):
        reject_extra_keys(network, {"mode", "allow_host_network", "allowed_endpoints"}, errors, f"{path}.network")
        mode = network.get("mode")
        ensure(mode in NETWORK_MODES, errors, f"{path}.network.mode must be supported")
        ensure(network.get("allow_host_network") is False, errors, f"{path}.network.allow_host_network must be false")
        allowed_endpoints = network.get("allowed_endpoints")
        if ensure_type(allowed_endpoints, list, errors, f"{path}.network.allowed_endpoints must be an array"):
            for idx, endpoint in enumerate(allowed_endpoints):
                ensure(is_non_empty_string(endpoint), errors, f"{path}.network.allowed_endpoints[{idx}] must be non-empty")
            if mode == "none":
                ensure(len(allowed_endpoints) == 0, errors, f"{path}.network.mode=none requires allowed_endpoints to be empty")
            elif mode == "restricted-egress":
                ensure(len(allowed_endpoints) > 0, errors, f"{path}.network.mode=restricted-egress requires explicit allowed_endpoints")

    privilege = data.get("privilege")
    if ensure_type(privilege, dict, errors, f"{path}: privilege must be an object"):
        reject_extra_keys(
            privilege,
            {"run_as_non_root", "user", "allow_privilege_escalation", "read_only_rootfs", "no_new_privileges"},
            errors,
            f"{path}.privilege",
        )
        ensure(privilege.get("run_as_non_root") is True, errors, f"{path}.privilege.run_as_non_root must be true")
        ensure(privilege.get("user") == "runner", errors, f"{path}.privilege.user must be runner")
        ensure(privilege.get("allow_privilege_escalation") is False, errors, f"{path}.privilege.allow_privilege_escalation must be false")
        ensure(privilege.get("read_only_rootfs") is True, errors, f"{path}.privilege.read_only_rootfs must be true")
        ensure(privilege.get("no_new_privileges") is True, errors, f"{path}.privilege.no_new_privileges must be true")

    validate_boundary_flags(data.get("boundary_carry_forward"), errors, f"{path}.boundary_carry_forward")

    if workspace_mode == "readonly":
        ensure(data.get("invocation", {}).get("runner") in RUNNER_TOOLS if isinstance(data.get("invocation"), dict) else False, errors, f"{path}: readonly plan must still select a supported runner")

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
