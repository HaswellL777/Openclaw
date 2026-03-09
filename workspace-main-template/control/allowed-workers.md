# Allowed Workers

## Purpose
This file defines which subagents main is allowed to spawn.

## Allowed subagents

### task-runner (Phase 1B+, not yet deployed)
- **Purpose**: Execute engineering tasks in Docker sandbox
- **Spawn conditions**:
  - User requests engineering work (code, tests, builds)
  - Task requires exec/process tools
  - Task is scoped to specific repository
  - Task produces structured artifacts
- **Max spawn depth**: 2 (main → task-runner)
- **Session scope**: Per-task (one container per task)

## Denied subagents

All other agent IDs are denied unless explicitly added to this whitelist.

## Spawn policy

- main MUST check this file before calling `sessions_spawn()`
- main MUST NOT spawn agents not in allowed list
- main MUST NOT spawn arbitrary new agents without human approval
- main MUST respect max spawn depth limit

## Phase 1A status

- task-runner not yet deployed
- Spawn attempts will fail gracefully
- main should explain limitation and suggest alternatives

## Adding new allowed workers

To add a new allowed worker:
1. Prepare justification (why needed, what it does, safety boundaries)
2. Define spawn conditions and constraints
3. Update this file
4. Get human approval (Category 2)
5. Test spawn workflow
6. Update routing-policy.md if needed

## Subagent coordination

When spawning task-runner:
1. Prepare task context (repo, branch, task description)
2. Define task constraints (time limit, resource limits)
3. Specify expected artifacts (outputs/, reports/)
4. Call `sessions_spawn(agentId="task-runner", context={...})`
5. Monitor task progress via `session_status()`
6. Collect results when complete
7. Update control/state/last-task-index.json

## Safety notes

- Subagents inherit OpenClaw security boundaries
- task-runner runs in Docker sandbox with limited tools
- task-runner cannot spawn further subagents
- task-runner cannot access workspace-main
- task-runner cannot directly mutate host state
