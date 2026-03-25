# Task Delegation Skill

## Skill identity
- **Name**: `task-delegation`
- **Owner**: `main` agent
- **Purpose**: Delegate engineering tasks to task-runner or claude-engineer agents
- **Status**: operational (task-runner); pending (claude-engineer, awaiting ACP spike)

## Prerequisites
- Phase 3 operational (task-runner available)
- `sessions_spawn` tool available
- task-runner agent configured in openclaw.json

## What this skill does
Routes engineering tasks from human requests to the appropriate execution agent.
Selects between task-runner (Docker sandbox, tool execution) and claude-engineer
(ACP, code analysis/generation) based on task requirements.

## When to use this skill
- Human requests an engineering task (code, research, testing)
- Task requires execution in a sandbox environment
- Task requires Claude Code capabilities (ACP)

## Workflow
1. Analyze the task request
2. Determine routing:
   - **task-runner**: tasks needing Docker sandbox (build, test, data processing, web scraping)
   - **claude-engineer**: tasks needing Claude Code (complex code analysis, multi-file refactoring) — *available after ACP spike*
3. Prepare task inputs (structured prompt, reference files)
4. Call `sessions_spawn` with appropriate runtime and agent
5. Monitor task progress
6. Collect and present results

## Routing decision matrix

| Task type | Agent | Runtime | Reason |
|-----------|-------|---------|--------|
| Code execution | task-runner | subagent | Sandbox isolation |
| Build & test | task-runner | subagent | Sandbox isolation |
| Web scraping | task-runner | subagent | Network access in container |
| Data analysis | task-runner | subagent | Sandbox + Python |
| Code review | claude-engineer | acp | Claude Code capabilities |
| Complex refactor | claude-engineer | acp | Multi-file awareness |
| Research + code | task-runner | subagent | Network + execution |

## Safety rules
- Never delegate host-ops actions to task-runner (use broker skill)
- Verify task doesn't require elevated privileges before delegation
- Set appropriate timeout for long-running tasks
- Review task outputs before presenting to human

## Related skills
- `broker`: For host state mutations (not task delegation)
- `routing`: For general message routing policy
