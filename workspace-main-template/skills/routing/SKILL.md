# Routing Skill

## Skill identity
- **Name**: `routing`
- **Owner**: `main` agent
- **Purpose**: Route requests to appropriate execution contexts

## What this skill does
This skill determines where and how to execute user requests:
- Should this run in main agent context? (read/write/edit only)
- Should this be routed to task-runner? (engineering work requiring exec)
- Should this be routed to host-ops broker? (host mutation)
- Should this be routed to Claude Code CLI? (development work)
- Should this be escalated to human? (risky operations, approval required)

## Authority
The authoritative routing policy is `control/routing-policy.md`.

This skill should:
1. Reference `control/routing-policy.md` for routing decisions
2. Check `control/allowed-workers.md` before spawning subagents
3. Check `control/approval-policy.md` for approval requirements
4. Never route prohibited operations (see control/SOP.md)

## Routing decision process

### Step 1: Check if prohibited
Read `control/SOP.md` prohibited operations list.
If operation is prohibited → Explain prohibition, suggest alternatives, do NOT route anywhere.

### Step 2: Check if approval required
Read `control/approval-policy.md`.
If operation requires approval → Escalate to human first, then route after approval.

### Step 3: Determine execution context
Read `control/routing-policy.md` and apply decision tree:

- **Control plane query** → Handle in main agent
- **Engineering work** → Route to task-runner via `sessions_spawn`
- **Host mutation** → Route to host-ops broker via `host_ops` tool
- **Development work in openclaw-dev** → Suggest Claude Code CLI
- **Uncertain** → Escalate to human

### Step 4: Execute routing
- task-runner: `sessions_spawn(agentId="task-runner")` — **operational** (deployed 2026-03-23)
- host-ops broker: `host_ops` tool — **operational** (8/8 actions live E2E verified 2026-03-17)
- Claude Code CLI: External tool, suggest to user

## Current capabilities (Phase 3)

| Target | Status | Since |
|--------|--------|-------|
| task-runner | **operational** — Docker sandbox, exec/read/write/edit in container | 2026-03-23 |
| host-ops broker | **operational** — 8/8 actions live E2E verified | 2026-03-17 |
| Claude Code CLI | external — always available to nick user | — |

## Usage patterns

### Example 1: "What is the current OpenClaw config path?"
- **Analysis**: Control plane query
- **Route to**: main agent (current context)
- **Action**: Use host-sop skill to read control/SOP.md and answer

### Example 2: "Clone this repo and run its tests"
- **Analysis**: Engineering task requiring exec
- **Route to**: task-runner via `sessions_spawn(agentId="task-runner")`
- **Action**: Spawn task-runner, provide repo URL and task description

### Example 3: "Add a new plugin to OpenClaw"
- **Analysis**: Engineering task (code) + host mutation (config)
- **Route to**: task-runner for code, then host-ops broker for config deployment
- **Action**: Spawn task-runner for code work, then use broker for config change

### Example 4: "Update /etc/openclaw/openclaw.json"
- **Analysis**: Host mutation requiring approval
- **Route to**: Human escalation → host-ops broker
- **Action**: Check approval-policy.md (Category 2), prepare plan, request approval, then call broker

### Example 5: "Delete old snapshots"
- **Analysis**: Host mutation, destructive operation
- **Route to**: Human escalation → host-ops broker
- **Action**: Check approval-policy.md (Category 1), request approval with rollback plan

### Example 6: "Update workspace-main control files"
- **Analysis**: Control plane operation, local to workspace-main
- **Route to**: main agent (current context)
- **Action**: Use write/edit tools, validate, update state

## Related skills
- `host-sop`: Provides host facts for routing decisions
- `approvals`: Determines approval requirements before routing
- `broker`: Execution target for host mutations

## Safety notes
- Always check prohibited operations before routing
- Always check approval requirements before routing
- Never route to unavailable targets without explaining limitation
- When in doubt, escalate to human
