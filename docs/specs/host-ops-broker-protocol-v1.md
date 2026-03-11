# Host-Ops Broker Protocol v1

> Status: **Dev-repo specification** — Phase 2 repo-only prep
> Created: 2026-03-11
> Authoritative design source: `docs/design-v3.md` §5.6
> This document is a repo-only protocol specification. It does NOT represent live deployment.

---

## 0. Scope and phase boundary

This protocol specification defines the wire format, semantics, validation rules, and error model for the host-ops broker. It exists as a **dev-repo artifact** within Phase 2 preparation work.

**What this document is:**
- Authoritative protocol specification for broker request/response envelopes
- Reference for schema authors, wrapper implementors, and plugin developers
- Basis for repo-only validation and contract testing

**What this document is NOT:**
- Evidence that the broker has been deployed
- Evidence that Phase 2 has started
- A deployment runbook (deployment procedures are separate)

Phase 1 is complete. Phase 2 has not started. The broker is not yet deployed.

---

## 1. Transport

- **Mechanism**: Unix socket or root-owned local IPC (exact path TBD at Phase 2 deployment)
- **Direction**: Plugin → Broker → Wrapper (unidirectional request/response)
- **Encoding**: JSON over socket, one request per connection
- **Authentication**: Implicit via Unix socket peer credentials (uid/gid)
- **No network transport**: The broker MUST NOT listen on TCP/IP

---

## 2. Request envelope

### 2.1 Schema

Defined in `broker/schemas/host-ops-request.schema.json`.

### 2.2 Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | string (enum) | Yes | One of 8 supported action identifiers |
| `request_id` | string | Yes | Unique request identifier, format: `req-YYYYMMDD-HHMMSS-<random>` |
| `task_id` | string | Yes | OpenClaw task identifier |
| `requested_by` | string | Yes | Identity of requester (e.g. `agent:main`, `cli:nick`) |
| `inputs` | object | Yes | Action-specific input object (schema varies per action) |

### 2.3 Action enum

The following 8 actions are the complete set. No other actions are accepted.

| Action | Purpose | Inputs schema |
|--------|---------|---------------|
| `gateway_health` | Check gateway service health | `actions/gateway-health.schema.json` |
| `gateway_restart` | Restart openclaw-gateway.service | `actions/gateway-restart.schema.json` |
| `validate_openclaw_json_candidate` | Validate candidate config file | `actions/validate-openclaw-json.schema.json` |
| `deploy_openclaw_json_candidate` | Deploy validated candidate config | `actions/deploy-openclaw-json.schema.json` |
| `snapshot_pre` | Create pre-change btrfs snapshot | `actions/snapshot-pre.schema.json` |
| `snapshot_post` | Create post-change btrfs snapshot | `actions/snapshot-post.schema.json` |
| `vault_sync` | Sync snapshot to offline vault | `actions/vault-sync.schema.json` |
| `rollback_prepare` | Prepare rollback to named snapshot | `actions/rollback-prepare.schema.json` |

### 2.4 Field semantics

**`action`**: Determines which wrapper script the broker invokes. Must be an exact match from the enum. The broker MUST reject any unrecognized action.

**`request_id`**: Globally unique identifier for audit trail. Must be preserved end-to-end from plugin through broker to wrapper and back. Format convention: `req-YYYYMMDD-HHMMSS-<random>` (random portion is at least 6 alphanumeric characters).

**`task_id`**: OpenClaw task identifier linking this broker request to the originating task context. Preserved end-to-end for traceability.

**`requested_by`**: Identity string identifying who/what initiated the request. Format convention: `agent:<agent_name>` for agent requests, `cli:<user>` for CLI requests. Used for audit logging, not for authorization (authorization is handled by the transport layer via Unix socket credentials).

**`inputs`**: Action-specific parameters as defined by the per-action schema. Each action defines its own required and optional fields. The broker MUST validate inputs against the per-action schema before invoking the wrapper.

---

## 3. Response envelope

### 3.1 Schema

Defined in `broker/schemas/host-ops-result.schema.json`.

### 3.2 Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ok` | boolean | Yes | `true` if action succeeded, `false` otherwise |
| `action` | string | Yes | Echo of requested action |
| `request_id` | string | Yes | Echo of request_id |
| `task_id` | string | Yes | Echo of task_id |
| `status` | string (enum) | Yes | One of: `ok`, `error`, `denied` |
| `message` | string | No | Human-readable description |
| `artifacts` | object | No | Action-specific output data |
| `rollback_hint` | string | No | Instructions for undoing the operation |

### 3.3 Status semantics

| Status | Meaning | `ok` value | When used |
|--------|---------|------------|-----------|
| `ok` | Action completed successfully | `true` | Normal completion |
| `error` | Action failed due to error | `false` | Validation failure, execution error, missing file, etc. |
| `denied` | Action denied by policy | `false` | Path not whitelisted, traversal detected, unauthorized |

**Invariant**: `ok` MUST be `true` if and only if `status` is `"ok"`. This is enforced by schema.

### 3.4 Echo fields

`action`, `request_id`, and `task_id` are always echoed back from the request. This enables:
- Request/response correlation in async scenarios
- Audit trail continuity
- Caller verification that the response matches the request

---

## 4. Error model

### 4.1 Fail-closed principle

The broker defaults to **deny** on any failure. Specifically:

1. **Unknown action** → `status: "error"`, exit non-zero
2. **Schema validation failure** → `status: "error"`, exit non-zero
3. **Missing required field** → `status: "error"`, exit non-zero
4. **Path outside whitelist** → `status: "denied"`, exit non-zero
5. **Path traversal detected** → `status: "denied"`, exit non-zero
6. **SHA256 format invalid** → `status: "error"`, exit non-zero
7. **Label format invalid** → `status: "error"`, exit non-zero
8. **Request file not found** → `status: "error"`, exit non-zero
9. **Wrapper execution failure** → `status: "error"`, exit non-zero
10. **Any unexpected error** → `status: "error"`, exit non-zero

### 4.2 Error output

On error, the wrapper:
1. Emits structured JSON to **stderr** (not stdout) containing `ok`, `status`, `message`
2. Exits with code **1** (non-zero)
3. Does NOT emit partial results to stdout

On success, the wrapper:
1. Emits structured JSON result to **stdout**
2. Emits STUB/log messages to **stderr** (in stub mode)
3. Exits with code **0**

### 4.3 No partial execution

If validation passes but execution fails midway, the wrapper MUST:
1. Report the failure state
2. Include rollback_hint in the error response
3. Not leave the system in an inconsistent state (or clearly document the inconsistency)

### 4.4 Error taxonomy

For formal error codes, denial reason definitions, and the error-vs-denied distinction, see `docs/specs/error-taxonomy-v1.md`. That document codifies the machine-readable error codes (`E_UNKNOWN_ACTION`, `D_PATH_TRAVERSAL`, etc.) and maps them to the result envelope fields.

### 4.5 Negative test fixtures

Each error category has a corresponding negative test fixture pair in `examples/broker/negative/`. These fixtures serve as the authoritative examples of expected error/denied response shapes.

---

## 5. Wrapper invocation contract

### 5.1 Invocation model

```
broker → wrapper <request-json-path>
```

- The broker writes the request JSON to a temp file
- The broker invokes the wrapper script with the file path as the sole argument
- The wrapper reads, validates, and acts on the request
- The wrapper returns structured JSON on stdout
- The broker reads the wrapper's stdout and exit code

### 5.2 Wrapper responsibilities

Each wrapper MUST:
1. Accept exactly one argument: path to request JSON file
2. Validate the file exists and is readable
3. Parse and validate common fields (action, request_id, task_id)
4. Validate the action matches the wrapper's expected action
5. Validate action-specific inputs against per-action schema rules
6. Perform the single operation (or echo in stub mode)
7. Return structured JSON result on stdout
8. Exit 0 on success, non-zero on failure

### 5.3 Wrapper constraints

Each wrapper MUST NOT:
1. Accept more than one argument
2. Execute any user-supplied command strings
3. Access paths outside its whitelisted set
4. Modify system state beyond its single declared purpose
5. Suppress errors or return exit 0 on failure

### 5.4 Shared validation library

Wrappers source `lib/common.sh` for common validation logic:
- `broker_validate_request_file` — argument and file existence check
- `broker_parse_common` — parse action, request_id, task_id from JSON
- `broker_validate_action` — verify action matches expected
- `broker_validate_required_fields` — verify request_id and task_id non-empty
- `broker_validate_sha256` — validate SHA256 hex format
- `broker_validate_path` — whitelist check + traversal detection
- `broker_validate_label` — alphanumeric format check
- `broker_error` — emit structured error to stderr and exit 1
- `broker_emit_result` — emit structured success result to stdout

This library is the single source of truth for validation rules shared across all wrappers. Action-specific validation remains in each wrapper.

---

## 6. Candidate file and hash verification

### 6.1 Applicable actions

`validate_openclaw_json_candidate` and `deploy_openclaw_json_candidate` involve candidate file operations.

### 6.2 Path whitelist

Candidate files MUST reside under: `/var/lib/openclaw/approvals/candidates/`

Any path not starting with this prefix is rejected with `status: "denied"`.

### 6.3 Path traversal prevention

Paths containing `..` are rejected with `status: "denied"`.

### 6.4 SHA256 verification

The `expected_sha256` field must be exactly 64 lowercase hexadecimal characters (`^[a-f0-9]{64}$`).

At execution time (not in stub mode), the wrapper:
1. Computes `sha256sum` of the candidate file
2. Compares with `expected_sha256`
3. Rejects on mismatch

### 6.5 Deployment procedure (deploy action)

1. Verify candidate file exists
2. Verify SHA256 matches expected
3. Backup current config: `cp /etc/openclaw/openclaw.json /etc/openclaw/openclaw.json.bak`
4. Copy candidate to target: `cp <candidate> /etc/openclaw/openclaw.json`
5. Set permissions: `chown root:openclaw`, `chmod 640`
6. Verify deployed file hash

---

## 7. Per-action input specifications

### 7.1 `gateway_health`

No required inputs. The `inputs` object may be empty (`{}`).

### 7.2 `gateway_restart`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `reason` | string | Yes | Human-readable reason for restart |

### 7.3 `validate_openclaw_json_candidate`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `candidate_path` | string | Yes | Absolute path under candidates prefix |
| `expected_sha256` | string | Yes | Expected SHA256 hash (64 hex chars) |

### 7.4 `deploy_openclaw_json_candidate`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `candidate_path` | string | Yes | Absolute path under candidates prefix |
| `expected_sha256` | string | Yes | Expected SHA256 hash (64 hex chars) |

### 7.5 `snapshot_pre`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `label` | string | Yes | Snapshot label (alphanumeric, dots, hyphens, underscores) |
| `reason` | string | Yes | Human-readable reason for snapshot |

Snapshot name generated as: `root-pre-<label>`

### 7.6 `snapshot_post`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `label` | string | Yes | Snapshot label (alphanumeric, dots, hyphens, underscores) |
| `reason` | string | Yes | Human-readable reason for snapshot |

Snapshot name generated as: `root-post-<label>`

### 7.7 `vault_sync`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `snapshot_name` | string | Yes | Name of snapshot to sync (alphanumeric format) |
| `incremental` | boolean | No | Whether to use incremental send (default: true) |

### 7.8 `rollback_prepare`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `target_snapshot` | string | Yes | Name of snapshot to rollback to (alphanumeric format) |
| `reason` | string | Yes | Human-readable reason for rollback |

---

## 8. Logging and audit

### 8.1 Requirements

- Every request MUST be logged with `request_id` and `task_id`
- Every wrapper invocation MUST log: action, requester, timestamp, outcome
- Logs MUST be written to a broker-specific log path (TBD at deployment)
- Logs MUST NOT contain sensitive data (no config file contents, no secrets)
- `request_id` MUST be traceable from plugin through broker to wrapper and back

### 8.2 Stub mode logging

In Phase 2 prep (stub mode), wrappers emit `[STUB]` markers to stderr indicating what would be executed. These markers serve as:
- Documentation of intended behavior
- Test verification points (tests check for `[STUB]` in stderr)

---

## 9. Schema file index

| Schema | Path | Purpose |
|--------|------|---------|
| Request envelope | `broker/schemas/host-ops-request.schema.json` | Top-level request validation |
| Result envelope | `broker/schemas/host-ops-result.schema.json` | Top-level result validation |
| gateway_health inputs | `broker/schemas/actions/gateway-health.schema.json` | Per-action inputs |
| gateway_restart inputs | `broker/schemas/actions/gateway-restart.schema.json` | Per-action inputs |
| validate_openclaw_json inputs | `broker/schemas/actions/validate-openclaw-json.schema.json` | Per-action inputs |
| deploy_openclaw_json inputs | `broker/schemas/actions/deploy-openclaw-json.schema.json` | Per-action inputs |
| snapshot_pre inputs | `broker/schemas/actions/snapshot-pre.schema.json` | Per-action inputs |
| snapshot_post inputs | `broker/schemas/actions/snapshot-post.schema.json` | Per-action inputs |
| vault_sync inputs | `broker/schemas/actions/vault-sync.schema.json` | Per-action inputs |
| rollback_prepare inputs | `broker/schemas/actions/rollback-prepare.schema.json` | Per-action inputs |

---

## 10. References

- `docs/design-v3.md` §5.6 — Authoritative broker design
- `workspace-main-template/control/host-ops-api.md` — API contract as seen by main agent
- `broker/README.md` — Broker directory overview
- `broker/wrappers/README.md` — Wrapper inventory and design rules
- `broker/wrappers/lib/common.sh` — Shared validation library
