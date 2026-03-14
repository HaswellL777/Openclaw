# Broker Skill

## Skill identity
- **Name**: `broker`
- **Owner**: `main` agent
- **Purpose**: Interface with host-ops broker for host state mutations

## Status
**Phase 2 — broker backend deployed (2026-03-14)**:
- Broker daemon running (`openclaw-broker.service`, active + enabled)
- Unix socket available (`/run/openclaw/broker.sock`)
- 8 wrappers installed with production logic
- Plugin registered in `openclaw.json` (gateway accepted, healthy)
- **Pending**: `index.js` register/activate export (gateway logs `missing register/activate export` — non-blocking)
- **Pending**: agent-facing `host_ops` tool access (`tools.allow` update)

This skill is not yet operational. Until plugin activation is complete, use the Phase 1 workaround below.

## What this skill does (planned)
This skill provides the interface for calling host-ops broker to execute:
- OpenClaw configuration changes (validate + deploy candidate)
- Gateway health checks and restarts
- Snapshot creation (pre-change and post-change)
- Vault sync
- Rollback preparation
- Other host mutations requiring elevated privileges

## Authority
The authoritative broker API contract is `control/host-ops-api.md`.
The authoritative protocol specification is `docs/specs/host-ops-broker-protocol-v1.md`.

This skill should:
1. Reference `control/host-ops-api.md` for API contract
2. Check `control/approval-policy.md` for approval requirements
3. Verify approval exists in `control/state/pending-approvals.json`
4. Prepare structured host-ops request
5. Call broker API
6. Monitor execution
7. Update state files with results

## Broker API (planned)

### Transport
Unix domain socket at `/run/openclaw/broker.sock`.

### Request format
Per `docs/specs/host-ops-broker-protocol-v1.md` §2 and `broker/schemas/host-ops-request.schema.json`:

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
- `action` — One of 8 supported action strings
- `request_id` — Unique request identifier
- `task_id` — OpenClaw task identifier
- `requested_by` — Identity of requester
- `inputs` — Action-specific input object

### Response format
Per `broker/schemas/host-ops-result.schema.json`:

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
    "deployed_sha256": "abc123..."
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

## Supported actions (planned)

| Action | Purpose |
|--------|---------|
| `gateway_health` | Check gateway service health |
| `gateway_restart` | Restart openclaw-gateway.service |
| `validate_openclaw_json_candidate` | Validate candidate config file |
| `deploy_openclaw_json_candidate` | Deploy validated candidate to /etc/openclaw |
| `snapshot_pre` | Create pre-change btrfs snapshot |
| `snapshot_post` | Create post-change btrfs snapshot |
| `vault_sync` | Sync snapshot to vault |
| `rollback_prepare` | Prepare rollback to previous snapshot |

See `control/host-ops-api.md` for detailed parameters and examples.

## Usage workflow (planned)

### Step 1: Check approval
Read `control/state/pending-approvals.json`.
Verify approval exists and status is "approved".

### Step 2: Prepare request
Read `control/host-ops-api.md` for API contract.
Prepare structured request with:
- Unique request_id (format: `req-YYYYMMDD-HHMMSS-<random>`)
- Action type
- requested_by identity
- Action-specific inputs

### Step 3: Call broker
Send request to broker via Unix socket.
(Implementation details TBD in Phase 2)

### Step 4: Monitor execution
Poll for status or wait for callback.
Track progress and intermediate results.

### Step 5: Update state
When complete:
- Update `control/state/pending-approvals.json` (mark completed/failed)
- Update `control/state/last-health.md` with results
- Update `control/state/last-sop-hash.txt` if SOP changed
- Report results to human

## Phase 1 workaround (current — until plugin activation is complete)

Since broker backend is deployed but agent-facing tool is not yet active:
1. main agent prepares operation plan
2. main agent requests approval
3. Human executes manually following runbooks in `control/runbooks/`
4. Human reports results
5. main agent updates state files

## Safety guarantees (planned)

The broker MUST:
- Verify approval exists and is approved
- Create pre-change snapshot if required
- Validate operation parameters
- Execute with proper error handling
- Validate results
- Create post-change snapshot if required
- Sync to vault if required
- Return structured results with rollback info

The broker MUST NOT:
- Execute without valid approval
- Skip snapshot steps if required
- Proceed if validation fails
- Leave system in inconsistent state

## Related skills
- `approvals`: Determines approval requirements before calling broker
- `routing`: Routes host mutations to broker
- `host-sop`: Provides host facts for broker operations

## Related runbooks
- `control/runbooks/openclaw-config-change.md`: Manual procedure for config updates
- `control/runbooks/gateway-restart.md`: Manual procedure for gateway restart
- `control/runbooks/rollback.md`: Manual procedure for system rollback

## Phase 2 implementation

When broker is deployed:
- This skill becomes operational
- main agent can call broker API directly
- Manual runbook execution is replaced by automated broker calls
- Human approval still required for Category 1/2 operations
- Broker handles snapshot -> change -> validate -> snapshot -> vault workflow automatically

## Notes
- Broker is a critical safety component
- Must be thoroughly tested before production use
- Must have comprehensive logging and audit trail
- Must handle errors gracefully with clear rollback guidance
- Must never bypass approval requirements
