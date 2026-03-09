# Tool Usage Guidelines

## Available tools (Phase 1A)
- `read`: Read files in workspace-main
- `write`: Write files in workspace-main
- `edit`: Edit files in workspace-main
- `sessions_list`: List OpenClaw sessions
- `sessions_history`: Get session history
- `sessions_send`: Send message to session
- `sessions_spawn`: Spawn new agent session (task-runner only, Phase 1B+)
- `session_status`: Get session status

## Denied tools
- `exec`: No direct shell execution
- `process`: No process management
- `apply_patch`: No direct patching
- `elevated`: No elevated privileges

## Tool usage discipline

### Reading control files
Always read these before making decisions:
- `control/SOP.md`: Host operational facts
- `control/routing-policy.md`: Routing logic
- `control/approval-policy.md`: Approval requirements
- `control/allowed-workers.md`: Subagent whitelist
- `control/host-ops-api.md`: Host operations API

### Updating state files
Update these after significant events:
- `control/state/pending-approvals.json`: Approval queue
- `control/state/last-health.md`: Health check results
- `control/state/last-task-index.json`: Task tracking
- `control/state/last-sop-hash.txt`: SOP version tracking

### Reading skills
Reference these for specialized knowledge:
- `skills/host-sop/SKILL.md`: Host SOP skill
- `skills/routing/SKILL.md`: Routing skill
- `skills/approvals/SKILL.md`: Approvals skill
- `skills/broker/SKILL.md`: Broker skill (Phase 1B+)

### Spawning subagents (Phase 1B+, not yet available)
When spawning task-runner:
1. Check `control/allowed-workers.md` for whitelist
2. Prepare task context and constraints
3. Use `sessions_spawn(agentId="task-runner")`
4. Monitor task progress
5. Collect results and update task index

### Calling host-ops broker (Phase 1B+, not yet available)
When host mutation required:
1. Check `control/approval-policy.md` for approval requirements
2. If approval required, update `control/state/pending-approvals.json` and wait
3. Read `control/host-ops-api.md` for API contract
4. Prepare structured host-change-request
5. Call broker API
6. Monitor execution
7. Update health state

## Safety checks before tool use
1. Is this operation prohibited? (check control/SOP.md)
2. Does this require approval? (check control/approval-policy.md)
3. Is this the right execution context? (check control/routing-policy.md)
4. Do I have the right tool for this? (check available tools)
5. Should this be delegated? (check routing policy)

## When to escalate to human
- Operation requires approval
- Host facts uncertain or missing from SOP
- Policy conflict or ambiguity
- Tool limitation prevents safe execution
- Unexpected error or state
