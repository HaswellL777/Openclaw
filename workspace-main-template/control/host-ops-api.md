# Host Operations API

## Purpose
This document defines the API contract for the host-ops broker.
The authoritative protocol definition is `docs/design-v3.md` §5.6.

## Status
**Phase 2**: This API is designed and schemas exist in the dev repo, but broker is not yet deployed.

## Overview

The host-ops broker provides a controlled interface for host state mutations that:
- Require elevated privileges
- Affect shared system state
- Must follow snapshot → change → validate → snapshot → vault workflow
- Are too risky for direct execution

The broker is the **sole host mutation entry point**. It accepts only structured JSON requests, delegates to root-owned wrapper scripts, and never executes free-form shell commands.

## Transport

Unix socket or root-owned local IPC (exact path TBD at Phase 2 deployment).

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

## Phase 1 workaround (current)

Since broker is not yet deployed:
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
- `broker/wrappers/` — Wrapper script stubs
- `control/approval-policy.md` — When approval is required
