# Allowed Workers

## Purpose
This file defines which subagents main is allowed to spawn.

## Allowed subagents

### task-runner (Phase 3+, updated 2026-03-25)
- **Purpose**: Execute engineering tasks in Docker sandbox
- **Status**: Deployed and operational
- **Image**: `openclaw-task-claude:2026-03-v3-full` (Ubuntu 24.04)
- **Network**: openclaw-task-net (outbound allowed)
- **Session scope**: **shared** (container persists across sessions, files visible between spawns)
- **Available in container**:
  - Python 3.12, Node.js 22, bash, git, ripgrep, jq, curl, pip, npm, build-essential
  - **Scrapling 0.4.2** — web scraping framework (`python3 -c "import scrapling"`)
  - `/workspace/knowledge/LabClaw/` — 240 biomedical research SKILL.md (read-only)
  - `/workspace/knowledge/autoresearch/` — ML experiment loop framework (read-only)
  - Skills: coding, testing, research, report, scrapling, autoresearch
- **Spawn conditions**:
  - User requests engineering work (code, tests, builds, research)
  - Task requires code execution, web scraping, or data analysis
  - Task needs Python/Node.js runtime
  - Task produces structured artifacts
- **Spawn syntax**: `sessions_spawn(runtime: "subagent", agentId: "task-runner", task: "...")`
- **Max spawn depth**: 2 (main → task-runner)

### ACP Claude Code (Phase 4, updated 2026-03-26)
- **Purpose**: Complex engineering tasks requiring full Claude Code capabilities on host
- **Status**: Deployed and verified (2026-03-26)
- **Runtime**: ACP (runs on host as `openclaw` user, NOT in Docker sandbox)
- **Capabilities**:
  - Full Claude Code toolset (Read, Write, Edit, Bash, Glob, Grep, Agent, etc.)
  - Can work on code repositories, refactor, analyze, generate complex artifacts
  - Access to `/var/lib/openclaw/task-workspaces/` as working directory
  - Uses MotChat proxy for Anthropic API
- **Spawn conditions**:
  - User explicitly requests Claude Code / ACP session
  - Task requires deep code analysis, complex refactoring, or multi-file engineering
  - Task requires Claude-level reasoning beyond what task-runner + deepseek-chat can do
  - Research tasks requiring advanced code understanding
- **Spawn syntax**: `sessions_spawn(runtime: "acp", agentId: "claude", task: "...")`
  - IMPORTANT: `agentId` must be `"claude"` (ACP harness ID), NOT `"claude-engineer"` (OpenClaw agent ID)
  - If `agentId` is omitted, `acp.defaultAgent: "claude"` is used
- **Security notes**:
  - ACP sessions run on host, not sandboxed
  - Permissions controlled via `/var/lib/openclaw/.claude/settings.json`
  - Only spawnable from main agent (sandboxed sessions cannot spawn ACP)

## Denied subagents

All other agent IDs are denied unless explicitly added to this whitelist.

## Spawn policy

- main MUST check this file before calling `sessions_spawn()`
- main MUST NOT spawn agents not in allowed list
- main MUST NOT spawn arbitrary new agents without human approval
- main MUST respect max spawn depth limit

## Current status

- task-runner: deployed and operational (2026-03-23)
- host-ops broker: deployed and operational (2026-03-17)
- Docker sandbox verified: container starts, tools work, results report back

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
