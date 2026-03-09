# Routing Skill

## Skill identity
- **Name**: `routing`
- **Owner**: `main` agent
- **Purpose**: Route requests to appropriate execution contexts

## What this skill does
This skill determines where and how to execute user requests:
- Should this run in main agent context? (read/write/edit only)
- Should this be routed to task-runner? (exec required, Phase 1B+)
- Should this be routed to host-ops broker? (host mutation, Phase 1B+)
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
- **Engineering work** → Route to task-runner (Phase 1B+)
- **Host mutation** → Route to host-ops broker (Phase 1B+)
- **Development work in openclaw-dev** → Suggest Claude Code CLI
- **Uncertain** → Escalate to human

### Step 4: Verify routing target available
- task-runner: Check Phase 1B+ status (not yet available in Phase 1A)
- host-ops broker: Check Phase 1B+ status (not yet available in Phase 1A)
- Claude Code CLI: External tool, always suggest to user

### Step 5: Execute routing
- If target available → Route request
- If target not available → Explain limitation, suggest workaround or wait

## Phase 1A limitations
- task-runner not yet deployed → Cannot route engineering tasks
- host-ops broker not yet deployed → Cannot route host mutations
- Current workaround: Explain limitation, suggest manual execution or wait for Phase 1B

## Usage patterns

### Example 1: "What is the current OpenClaw config path?"
- **Analysis**: Control plane query
- **Route to**: main agent (current context)
- **Action**: Use host-sop skill to read control/SOP.md and answer

### Example 2: "Run tests in openclaw-dev repo"
- **Analysis**: Engineering task in development repo
- **Route to**: Claude Code CLI (external)
- **Action**: Suggest user run `claude` in /home/nick/projects/openclaw-dev

### Example 3: "Add a new plugin to OpenClaw"
- **Analysis**: Engineering task (code) + host mutation (config)
- **Route to**: task-runner for code (Phase 1B+), then host-ops broker for config (Phase 1B+)
- **Action**: Phase 1A → Explain limitation, suggest manual workflow with approval

### Example 4: "Update /etc/openclaw/openclaw.json"
- **Analysis**: Host mutation requiring approval
- **Route to**: Human escalation → host-ops broker (Phase 1B+)
- **Action**: Check approval-policy.md (Category 2), prepare plan, request approval, wait for Phase 1B

### Example 5: "Delete old snapshots"
- **Analysis**: Host mutation, destructive operation
- **Route to**: Human escalation → host-ops broker (Phase 1B+)
- **Action**: Check approval-policy.md (Category 1), request approval with rollback plan

### Example 6: "Update workspace-main control files"
- **Analysis**: Control plane operation, local to workspace-main
- **Route to**: main agent (current context)
- **Action**: Use write/edit tools, validate, update state

## Related skills
- `host-sop`: Provides host facts for routing decisions
- `approvals`: Determines approval requirements before routing
- `broker`: Execution target for host mutations (Phase 1B+)

## Safety notes
- Always check prohibited operations before routing
- Always check approval requirements before routing
- Never route to unavailable targets without explaining limitation
- When in doubt, escalate to human

## Phase 1B+ enhancements
When task-runner and host-ops broker are deployed:
- Routing becomes fully automated
- main agent can spawn task-runner for engineering work
- main agent can call broker for host mutations
- This skill definition remains authoritative for routing logic
