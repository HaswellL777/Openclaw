# Broker Skill

## Skill identity
- **Name**: `broker`
- **Owner**: `main` agent
- **Purpose**: Interface with host-ops broker for host state mutations

## Status: Fully operational (2026-03-17)

| Layer | Status |
|-------|--------|
| Broker backend | **deployed** — daemon running, socket available, 8 wrappers installed |
| Plugin config registration | **complete** — gateway accepted, healthy |
| Plugin lifecycle activation | **complete** — `register(api)` export active on live gateway |
| Tool registration | **complete** — `api.registerTool(hostOpsTool)` active |
| Agent-facing `host_ops` tool | **8/8 actions live E2E verified** |

All 8 actions are operational and available via the `host_ops` tool.

## What this skill does
This skill provides the interface for calling host-ops broker to execute:
- OpenClaw configuration changes (validate + deploy candidate)
- Gateway health checks and restarts
- Snapshot creation (pre-change and post-change)
- Vault sync
- Rollback preparation

## Authority
The authoritative broker API contract is `control/host-ops-api.md`.
The authoritative protocol specification is `docs/specs/host-ops-broker-protocol-v1.md`.

This skill should:
1. Reference `control/host-ops-api.md` for API contract
2. Check `control/approval-policy.md` for approval requirements
3. Verify approval exists in `control/state/pending-approvals.json`
4. Call `host_ops` tool with structured request
5. Monitor execution
6. Update state files with results

## Supported actions (all operational)

| Action | Purpose | Type |
|--------|---------|------|
| `gateway_health` | Check gateway service health | read-only |
| `validate_openclaw_json_candidate` | Validate candidate config file | read-only |
| `deploy_openclaw_json_candidate` | Deploy validated candidate to /etc/openclaw | write (Route C) |
| `snapshot_pre` | Create pre-change btrfs snapshot | write |
| `snapshot_post` | Create post-change btrfs snapshot | write |
| `rollback_prepare` | Prepare rollback to previous snapshot | read-only (prepare-only) |
| `gateway_restart` | Restart openclaw-gateway.service | write (two-phase) |
| `vault_sync` | Sync snapshot to vault | write (incremental send) |

See `control/host-ops-api.md` for detailed parameters and examples.

## Request format
Per `docs/specs/host-ops-broker-protocol-v1.md`:

```json
{
  "action": "deploy_openclaw_json_candidate",
  "request_id": "req-20260311-143000-a1b2c3",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/openclaw.json",
    "expected_sha256": "..."
  }
}
```

## Usage workflow

### Step 1: Check approval
Read `control/state/pending-approvals.json`.
Verify approval exists and status is "approved" (for Category 1/2 operations).

### Step 2: Call host_ops
Use the `host_ops` tool directly. The tool handles broker communication.

### Step 3: Update state
When complete:
- Update `control/state/pending-approvals.json` (mark completed/failed)
- Update `control/state/last-health.md` with results
- Report results to human

## Standard host mutation workflow
For operations that change host state:
1. `snapshot_pre` — create pre-change snapshot
2. `vault_sync` — sync pre-state to vault
3. Execute the change (e.g. `deploy_openclaw_json_candidate`)
4. `gateway_restart` — if config changed
5. `gateway_health` — verify health
6. `snapshot_post` — create post-change snapshot
7. `vault_sync` — sync post-state to vault

## Safety guarantees
The broker:
- Validates all request parameters via schema
- Uses root-owned wrappers with no shell injection
- Logs all operations with request-id tracking
- Returns structured results with rollback hints
- Fails closed on invalid input

## Related skills
- `approvals`: Determines approval requirements before calling broker
- `routing`: Routes host mutations to broker
- `host-sop`: Provides host facts for broker operations

## Related runbooks
- `control/runbooks/openclaw-config-change.md`: Config update procedure
- `control/runbooks/gateway-restart.md`: Gateway restart procedure
- `control/runbooks/rollback.md`: System rollback procedure
