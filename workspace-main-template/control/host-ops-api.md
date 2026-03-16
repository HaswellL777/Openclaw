# Host Operations API

## Purpose
This document defines the API contract for the host-ops broker.
The authoritative protocol definition is `docs/design-v3.md` §5.6.

## Status

### Deployment state (2026-03-16)

| Layer | Status |
|-------|--------|
| Broker backend | **deployed** — `openclaw-broker.service` active + enabled, socket at `/run/openclaw/broker.sock` (`root:openclaw 660`), 8 wrappers installed (production, `BROKER_DRY_RUN=false`) |
| Plugin config registration | **complete** — `host-ops-tool` in `plugins.allow`, `plugins.entries["host-ops-tool"].enabled = true`, gateway accepted + healthy |
| Plugin lifecycle activation | **complete** — `register(api)` export active on live gateway, no lifecycle warnings |
| Tool registration (repo) | **complete** — `register(api)` calls `api.registerTool(hostOpsTool, {optional:true})`, fail-closed via ENABLED_ACTIONS (currently: gateway_health, gateway_restart, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, rollback_prepare) |
| Agent-facing `host_ops` tool | **逐项切片推进中（2026-03-16）** — `host_ops` 已加入 `main.tools.allow`；`gateway_health` agent-facing E2E 成功；`validate_openclaw_json_candidate` agent-facing E2E 成功（含正例 + 负例，live verified）；`deploy_openclaw_json_candidate` live E2E verified（Route C，正例 + 负例含 wrapper 侧 + 回归通过）；`snapshot_pre` live E2E verified（2026-03-16，正例 + 负例 + 回归通过）；`snapshot_post` live E2E verified（2026-03-16，正例 + 负例 + 回归通过）；`rollback_prepare` live E2E verified（2026-03-16，正例 + 负例含 wrapper 侧 E_FILE_NOT_FOUND + 回归通过，纯只读 prepare-only metadata 契约）；`gateway_restart` repo-side ready（契约稳定化完成：`--no-block` 两段式语义，待 live activation + E2E 验收）；其余 1 个 action（`vault_sync`）仍需逐项启用和验收 |

### Activation sequence

1. **Step 1 — Plugin lifecycle activation**: Complete (2026-03-15). `register(api)` export deployed and accepted by gateway.
2. **Step 2 — Tool registration implementation**: Complete (2026-03-15). `register(api)` now calls `api.registerTool()` with the `host_ops` tool object (`optional: true`, fail-closed via ENABLED_ACTIONS).
3. **Step 3 — Deploy registerTool version**: Complete (2026-03-15). Updated `index.js` deployed to live, gateway restarted, no registration errors.
4. **Step 4 — Agent-facing enablement (gateway_health)**: Complete (2026-03-15). `host_ops` added to `main.tools.allow` via candidate workflow. Agent successfully invoked `host_ops(action: "gateway_health")`, broker returned `ok: true`.

### Current operational path

`gateway_health`、`validate_openclaw_json_candidate`、`deploy_openclaw_json_candidate`、`snapshot_pre`、`snapshot_post` 和 `rollback_prepare` 六个 action 均已通过 agent-facing E2E 验证（live verified），可由 agent 直接调用。前两者为只读操作，`deploy_openclaw_json_candidate` 是写操作（Route C，deploy 后的 restart / snapshot 仍由 operator-mediated checklist 承担，见 `docs/checklists/deploy-candidate-route-c-checklist.md`），`snapshot_pre` 和 `snapshot_post` 是写操作（创建只读 btrfs 快照），`rollback_prepare` 是纯只读操作（验证 snapshot 存在性并返回 prepare-only metadata，不执行实际 rollback）。`gateway_restart` repo-side ready（契约稳定化完成：`--no-block` 两段式语义，待 live activation + E2E 验收）。其余 1 个 action（`vault_sync`）尚未逐项 agent-facing 验收，仍使用 Phase 1 workaround（Section "Phase 1 workaround"）。

## Overview

The host-ops broker provides a controlled interface for host state mutations that:
- Require elevated privileges
- Affect shared system state
- Must follow snapshot → change → validate → snapshot → vault workflow
- Are too risky for direct execution

The broker is the **sole host mutation entry point**. It accepts only structured JSON requests, delegates to root-owned wrapper scripts, and never executes free-form shell commands.

## Transport

Unix domain socket at `/run/openclaw/broker.sock`.

## Actions

The broker supports exactly 8 actions:

| Action | Wrapper | Purpose |
|--------|---------|---------|
| `gateway_health` | `ocw-gateway-health.sh` | Check gateway service health |
| `gateway_restart` | `ocw-gateway-restart.sh` | Restart openclaw-gateway.service |
| `validate_openclaw_json_candidate` | `ocw-validate-openclaw-json.sh` | Validate a candidate config file |
| `deploy_openclaw_json_candidate` | `ocw-deploy-openclaw-json.sh` | Deploy validated candidate to /etc/openclaw |
| `snapshot_pre` | `ocw-snapshot-pre.sh` | Create pre-change btrfs snapshot |
| `snapshot_post` | `ocw-snapshot-post.sh` | Create post-change btrfs snapshot |
| `vault_sync` | `ocw-vault-sync.sh` | Sync snapshot to vault |
| `rollback_prepare` | `ocw-rollback-prepare.sh` | Prepare rollback to previous snapshot |

## Request format

Per `docs/design-v3.md` §5.6.2:

```json
{
  "action": "deploy_openclaw_json_candidate",
  "request_id": "req-20260311-143000-a1b2c3",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/openclaw.json",
    "expected_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
```

Required fields:
- `action` — One of the 8 supported action strings
- `request_id` — Unique request identifier (format: `req-YYYYMMDD-HHMMSS-<random>`)
- `task_id` — OpenClaw task identifier
- `requested_by` — Identity of requester (e.g. `agent:main`)
- `inputs` — Action-specific input object (schema varies per action)

Schema: `broker/schemas/host-ops-request.schema.json`
Per-action input schemas: `broker/schemas/actions/<action>.schema.json`

## Result format

```json
{
  "ok": true,
  "action": "deploy_openclaw_json_candidate",
  "request_id": "req-20260311-143000-a1b2c3",
  "task_id": "task-...",
  "status": "ok",
  "message": "Config deployed successfully",
  "artifacts": {
    "deployed_path": "/etc/openclaw/openclaw.json",
    "deployed_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  },
  "rollback_hint": "Restore from pre-change snapshot: root-pre-20260311-1430"
}
```

Required fields:
- `ok` — Boolean success indicator
- `action` — Echo of requested action
- `request_id` — Echo of request_id
- `task_id` — Echo of task_id
- `status` — One of: `ok`, `error`, `denied`

Optional fields:
- `message` — Human-readable description
- `artifacts` — Action-specific output data
- `rollback_hint` — Instructions for undoing the operation
- `error_code` — Machine-readable error code (reserved; see `docs/specs/error-taxonomy-v1.md`)

Schema: `broker/schemas/host-ops-result.schema.json`

## Per-action input specifications

### gateway_health

No required inputs. Returns gateway service status.

```json
{
  "action": "gateway_health",
  "request_id": "req-...",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {}
}
```

### gateway_restart

> **Status: repo-side ready (2026-03-16, revised) — 待 live activation + E2E 验收**
> Contract revised: uses `systemd-run --on-active=2s` transient timer to schedule restart.
> The previous `--no-block` approach failed in live testing (E_BROKER_INTERNAL / -15)
> because systemd's After= reverse stop order SIGTERMs the broker before the wrapper
> can return its response.
>
> Returns `restart_scheduled: true` immediately. Does NOT verify post-restart status in the same request.
> Caller MUST invoke `gateway_health` afterward to verify that the gateway is healthy after the restart completes.
> Operator MUST independently confirm `systemctl is-active` for both gateway and broker services.
>
> **IMPORTANT**: `systemd-run` returning success (exit code 0) means only that the transient
> timer/unit was successfully created and registered with systemd. It does NOT mean the
> gateway restart has completed. It does NOT mean the gateway restart will succeed.
> Completion criteria: subsequent operator `systemctl is-active` check + agent `gateway_health` call.

```json
{
  "action": "gateway_restart",
  "request_id": "req-...",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "reason": "Post config-deploy restart"
  }
}
```

**Return value contract (deferred dispatch via systemd-run):**

On success (`ok: true`), `artifacts` contains:
- `reason` — Echo of requested reason
- `restart_scheduled` — `true` (transient timer unit created, restart will execute ~2s later)
- `delay_seconds` — `2` (delay before restart executes)
- `dispatch_method` — `"systemd-run-transient-timer"` (mechanism used)
- `verification_required` — `true` (post-restart status NOT verified in this request)
- `service_active_after` — `null` (not checked — caller must use gateway_health)
- `mode` — `"live"` or `"dry-run"`

**Three-stage usage pattern:**
1. Call `gateway_restart` → receive `restart_scheduled: true` (timer unit created — gateway has NOT restarted yet, restart will execute ~2s later)
2. Wait 5-10 seconds for gateway + broker to complete restart cycle
3. Operator independently confirms: `systemctl is-active openclaw-gateway.service` + `systemctl is-active openclaw-broker.service`
4. Call `gateway_health` → verify `service_active: "active"` (also implicitly confirms broker is healthy via successful socket roundtrip)

### validate_openclaw_json_candidate

```json
{
  "action": "validate_openclaw_json_candidate",
  "request_id": "req-...",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/openclaw.json",
    "expected_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
```

### deploy_openclaw_json_candidate

```json
{
  "action": "deploy_openclaw_json_candidate",
  "request_id": "req-...",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/openclaw.json",
    "expected_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
```

### snapshot_pre

```json
{
  "action": "snapshot_pre",
  "request_id": "req-...",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "label": "pre-config-deploy-20260311",
    "reason": "Pre-change snapshot before config deploy"
  }
}
```

### snapshot_post

```json
{
  "action": "snapshot_post",
  "request_id": "req-...",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "label": "post-config-deploy-20260311",
    "reason": "Post-change snapshot after config deploy"
  }
}
```

### vault_sync

```json
{
  "action": "vault_sync",
  "request_id": "req-...",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "snapshot_name": "root-pre-20260311-1430",
    "incremental": true
  }
}
```

### rollback_prepare

> **Status: live E2E verified (2026-03-16)**
> Pure read-only action: verifies snapshot existence via `btrfs subvolume show`, returns prepare-only metadata. Does NOT execute actual rollback. Actual rollback requires LiveUSB/rescue environment.

```json
{
  "action": "rollback_prepare",
  "request_id": "req-...",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "target_snapshot": "root-pre-20260311-1430",
    "reason": "Config deploy caused gateway failure"
  }
}
```

**Return value contract (prepare-only metadata):**

On success (`ok: true`), `artifacts` contains:
- `target_snapshot` — Echo of requested snapshot name
- `reason` — Echo of requested reason
- `snapshot_path` — Full path to verified snapshot (`/.snapshots/{target_snapshot}`)
- `snapshot_verified` — `true` (snapshot exists and is valid btrfs subvolume)
- `prepare_only` — `true` (this is a prepare-only operation, no rollback executed)
- `rollback_executed` — `false` (actual rollback was NOT executed)
- `scope` — `"root-filesystem-only"` (rollback scope covers root filesystem only)
- `excluded_paths` — `["/var/lib/openclaw"]` (independent btrfs subvolume, NOT included in root rollback)
- `operator_action_required` — `true` (actual rollback requires operator in LiveUSB/rescue environment)
- `mode` — `"live"`

**The `rollback_steps` field is NOT returned.** The previous `rollback_steps` contract was removed because it implied a verified, executable recovery plan, which exceeded the actual system boundary (root snapshot does not restore `/var/lib/openclaw` independent subvolume).

## Safety guarantees

The broker MUST (per design-v3.md §5.6.3):
1. Use Unix socket or root-owned local IPC
2. Apply strict schema validation on every request
3. Enforce parameter whitelisting per action
4. Enforce path whitelisting (no arbitrary paths)
5. Only call root-owned wrapper scripts
6. Never execute free-form shell commands
7. Maintain complete logging with request-id tracing
8. Default to deny on any failure

The broker MUST NOT:
1. Execute without schema-valid request
2. Accept free-form shell or user-supplied commands
3. Allow path traversal outside whitelisted directories
4. Proceed if wrapper validation fails
5. Leave system in inconsistent state

## Relationship to main agent

Per design-v3.md §5.6.5:
- `main` does not have `exec` capability
- `main` calls the `host_ops(...)` plugin tool
- The plugin tool submits structured requests to the broker
- The broker delegates to root-owned wrappers
- This ensures the control plane can invoke host mutations without having arbitrary command execution

## Error handling

If an operation fails:
1. Wrapper returns structured error JSON with `ok: false, status: "error"` or `status: "denied"`
2. Broker preserves all logs with request-id
3. Result includes `rollback_hint` when applicable
4. Caller (main agent) can present rollback options to human

### Error vs denied

- **`error`**: Request was malformed, incomplete, or execution failed. May be retryable after correction.
- **`denied`**: Request was understood but rejected by security policy (path whitelist, traversal). Do NOT retry with same inputs.

### Error example

```json
{
  "ok": false,
  "action": "deploy_openclaw_json_candidate",
  "request_id": "req-20260311-160300-neg004",
  "task_id": "task-neg-traversal",
  "status": "denied",
  "message": "Path traversal detected"
}
```

See `docs/specs/error-taxonomy-v1.md` for the full error code taxonomy.

## Phase 1 workaround (for remaining non-enabled actions)

For the 1 action not yet in ENABLED_ACTIONS (`vault_sync`):
1. main agent prepares operation plan
2. main agent requests approval via approval-policy.md workflow
3. Human executes manually following runbooks in `control/runbooks/`
4. Human reports results
5. main agent updates state files

## References
- `docs/design-v3.md` §5.6 — Authoritative broker protocol definition
- `docs/specs/host-ops-broker-protocol-v1.md` — Full protocol specification
- `docs/specs/error-taxonomy-v1.md` — Error taxonomy and result codes
- `broker/schemas/host-ops-request.schema.json` — Request JSON Schema
- `broker/schemas/host-ops-result.schema.json` — Result JSON Schema
- `broker/schemas/actions/*.schema.json` — Per-action input schemas
- `broker/wrappers/` — Wrapper scripts (dual-mode: dry-run + live)
- `control/approval-policy.md` — When approval is required
