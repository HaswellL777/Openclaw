# Host Operations API

## Purpose
This document defines the API contract for host-ops broker (Phase 1B+, not yet implemented).

## Status
**Phase 1B+**: This API is planned but not yet implemented.

## Overview

The host-ops broker provides a controlled interface for host state mutations that:
- Require elevated privileges
- Affect shared system state
- Must follow snapshot → change → validate → snapshot → vault workflow
- Are too risky for direct execution

## API endpoint (planned)

```
POST /host-ops/execute
```

## Request format

```json
{
  "request_id": "req-YYYYMMDD-HHMMSS-<random>",
  "timestamp": "YYYY-MM-DD HH:MM:SS UTC",
  "operation": "config-update | gateway-restart | snapshot-create | vault-sync | rollback",
  "approval_id": "approval-YYYYMMDD-HHMMSS-<random>",
  "parameters": {
    "operation-specific": "parameters"
  },
  "pre_snapshot_required": true | false,
  "post_snapshot_required": true | false,
  "vault_sync_required": true | false
}
```

## Response format

```json
{
  "request_id": "req-YYYYMMDD-HHMMSS-<random>",
  "status": "success | failed | partial",
  "timestamp": "YYYY-MM-DD HH:MM:SS UTC",
  "pre_snapshot": "snapshot-name or null",
  "post_snapshot": "snapshot-name or null",
  "vault_synced": true | false,
  "changes": [
    {
      "path": "/etc/openclaw/openclaw.json",
      "action": "modified",
      "backup": "/path/to/backup"
    }
  ],
  "validation_results": {
    "gateway_healthy": true | false,
    "config_valid": true | false,
    "services_running": true | false
  },
  "rollback_available": true | false,
  "rollback_procedure": "Step-by-step undo instructions",
  "logs": "/path/to/operation/logs"
}
```

## Supported operations (planned)

### config-update
Update `/etc/openclaw/openclaw.json`

**Parameters**:
```json
{
  "operation": "config-update",
  "parameters": {
    "patch": { "json": "patch" },
    "validate_before": true,
    "restart_gateway": true
  }
}
```

### gateway-restart
Restart openclaw-gateway.service

**Parameters**:
```json
{
  "operation": "gateway-restart",
  "parameters": {
    "graceful": true,
    "timeout_seconds": 30
  }
}
```

### snapshot-create
Create btrfs snapshot

**Parameters**:
```json
{
  "operation": "snapshot-create",
  "parameters": {
    "name": "snapshot-name",
    "description": "Snapshot description"
  }
}
```

### vault-sync
Sync snapshot to vault

**Parameters**:
```json
{
  "operation": "vault-sync",
  "parameters": {
    "snapshot": "snapshot-name",
    "incremental": true
  }
}
```

### rollback
Rollback to previous snapshot

**Parameters**:
```json
{
  "operation": "rollback",
  "parameters": {
    "snapshot": "snapshot-name",
    "confirm": true
  }
}
```

## Safety guarantees

The broker MUST:
1. Verify approval_id exists and is approved
2. Create pre-change snapshot if required
3. Validate operation parameters
4. Execute operation with proper error handling
5. Validate results
6. Create post-change snapshot if required
7. Sync to vault if required
8. Return structured results with rollback info

The broker MUST NOT:
1. Execute without valid approval
2. Skip snapshot steps if required
3. Proceed if validation fails
4. Leave system in inconsistent state

## Error handling

If operation fails:
1. Attempt automatic rollback if safe
2. If rollback not safe, freeze and alert human
3. Preserve all logs and state
4. Provide clear rollback instructions
5. Update approval status to "failed"

## Phase 1A workaround

Since broker is not yet implemented:
1. main prepares operation plan
2. main requests approval
3. Human executes manually following runbooks
4. Human reports results
5. main updates state files

## Implementation notes

The broker should be implemented as:
- Separate service or command-line tool
- Root-owned, minimal attack surface
- Comprehensive logging and audit trail
- Idempotent operations where possible
- Clear error messages and rollback guidance
