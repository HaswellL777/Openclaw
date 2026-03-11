# Broker Skill

## Skill identity
- **Name**: `broker`
- **Owner**: `main` agent
- **Purpose**: Interface with host-ops broker for host state mutations

## Status
**Phase 2**: This skill is planned but not yet implemented.
The host-ops broker is not yet deployed. Phase 2 has not started.

## What this skill does (planned)
This skill provides the interface for calling host-ops broker to execute:
- OpenClaw configuration changes
- Gateway restarts
- Snapshot creation
- Vault sync
- System rollback
- Other host mutations requiring elevated privileges

## Authority
The authoritative broker API contract is `control/host-ops-api.md`.

This skill should:
1. Reference `control/host-ops-api.md` for API contract
2. Check `control/approval-policy.md` for approval requirements
3. Verify approval exists in `control/state/pending-approvals.json`
4. Prepare structured host-change-request
5. Call broker API
6. Monitor execution
7. Update state files with results

## Broker API (planned)

### Endpoint
```
POST /host-ops/execute
```

### Request format
```json
{
  "request_id": "req-YYYYMMDD-HHMMSS-<random>",
  "timestamp": "YYYY-MM-DD HH:MM:SS UTC",
  "operation": "config-update | gateway-restart | snapshot-create | vault-sync | rollback",
  "approval_id": "approval-YYYYMMDD-HHMMSS-<random>",
  "parameters": { "operation-specific": "parameters" },
  "pre_snapshot_required": true | false,
  "post_snapshot_required": true | false,
  "vault_sync_required": true | false
}
```

### Response format
```json
{
  "request_id": "req-YYYYMMDD-HHMMSS-<random>",
  "status": "success | failed | partial",
  "timestamp": "YYYY-MM-DD HH:MM:SS UTC",
  "pre_snapshot": "snapshot-name or null",
  "post_snapshot": "snapshot-name or null",
  "vault_synced": true | false,
  "changes": [...],
  "validation_results": {...},
  "rollback_available": true | false,
  "rollback_procedure": "Step-by-step undo instructions",
  "logs": "/path/to/operation/logs"
}
```

## Supported operations (planned)

### config-update
Update `/etc/openclaw/openclaw.json`

### gateway-restart
Restart openclaw-gateway.service

### snapshot-create
Create btrfs snapshot

### vault-sync
Sync snapshot to vault

### rollback
Rollback to previous snapshot

See `control/host-ops-api.md` for detailed parameters and examples.

## Usage workflow (planned)

### Step 1: Check approval
Read `control/state/pending-approvals.json`.
Verify approval exists and status is "approved".

### Step 2: Prepare request
Read `control/host-ops-api.md` for API contract.
Prepare structured request with:
- Unique request_id
- Operation type
- Approval_id reference
- Operation-specific parameters
- Snapshot/vault requirements

### Step 3: Call broker
Send POST request to broker API.
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

## Phase 1 workaround (current)

Since broker is not yet implemented (Phase 2 not started):
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
- Broker handles snapshot → change → validate → snapshot → vault workflow automatically

## Notes
- Broker is a critical safety component
- Must be thoroughly tested before production use
- Must have comprehensive logging and audit trail
- Must handle errors gracefully with clear rollback guidance
- Must never bypass approval requirements
