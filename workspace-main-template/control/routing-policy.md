# Routing Policy

## Purpose
This policy defines how main agent routes requests to appropriate execution contexts.

## Execution contexts

### 1. main agent (current context)
**Capabilities**:
- Read/write/edit files in workspace-main
- Query control files
- Update state files
- Spawn subagents (task-runner: operational)
- Call host-ops broker (operational)

**Use for**:
- Control plane queries
- Policy lookups
- State updates
- Approval workflow management
- Orchestration and routing decisions

**Do NOT use for**:
- Engineering tasks (code, tests, builds)
- Shell command execution
- Direct host mutations
- File operations outside workspace-main

### 2. task-runner (Phase 3, deployed 2026-03-23)
**Capabilities**:
- Read/write/edit files in task workspace
- Execute shell commands in sandbox
- Run tests and builds
- Apply patches
- Produce structured artifacts

**Use for**:
- Engineering work (code, tests, docs)
- Repository operations
- Build and test execution
- Artifact generation
- Any task requiring exec/process tools

**Do NOT use for**:
- Direct host mutations
- Operations outside task sandbox
- Long-lived state management
- Control plane decisions

### 3. host-ops broker (Phase 2, deployed 2026-03-17)
**Capabilities**:
- Execute pre-approved host mutations
- Follow snapshot → change → validate → snapshot → vault workflow
- Modify /etc/openclaw, systemd units, Docker config
- Manage snapshots and backups

**Use for**:
- OpenClaw configuration changes
- Systemd unit modifications
- Docker privilege boundary changes
- Snapshot and backup operations
- Any operation in prohibited list that has approval

**Do NOT use for**:
- Routine engineering tasks
- Control plane queries
- Operations that don't require host mutation

### 4. ACP Claude Code (Phase 4, deployed 2026-03-26)
**Capabilities**:
- Full Claude Code toolset on host (Read, Write, Edit, Bash, Glob, Grep, etc.)
- Advanced code analysis, refactoring, and generation
- Multi-file engineering tasks with Claude-level reasoning
- Access to /var/lib/openclaw/task-workspaces/

**Use for**:
- Complex engineering tasks requiring deep reasoning
- Tasks user explicitly requests Claude Code / ACP for
- Research tasks requiring advanced code understanding
- Multi-file refactoring or analysis beyond task-runner capabilities

**Spawn syntax**: `sessions_spawn(runtime: "acp", agentId: "claude", task: "...")`
- IMPORTANT: agentId must be "claude" (ACP harness), NOT "claude-engineer"

**Do NOT use for**:
- Simple tasks that task-runner can handle
- Host mutations (use broker)
- Control plane operations (handle in main)

### 5. Research Coordinator (Phase 4+, added 2026-03-26)
**Capabilities**:
- Orchestrate multi-phase research tasks
- Spawn task-runner for data collection and experiments (up to 3 concurrent)
- Maintain persistent research state across sessions
- Track experiments with keep/discard/stop decision rules

**Use for**:
- Complex research goals requiring multiple phases (literature → analysis → report)
- Iterative experiment loops (autoresearch pattern)
- Tasks needing coordination across multiple task-runner sessions
- Long-running tasks that need state persistence

**Spawn syntax**: `sessions_spawn(runtime: "subagent", agentId: "research-coordinator", task: "...")`

**Do NOT use for**:
- Simple single-shot tasks (use task-runner directly)
- Tasks requiring ACP Claude Code (main handles ACP spawning)
- Host mutations or control plane operations

### 6. Auditor (Phase 4+, added 2026-03-26)
**Capabilities**:
- Read other agents' session history (cross-agent access enabled)
- Read shared container filesystem
- Fact-check via web search
- Produce structured audit reports

**Use for**:
- Quality review after research phases complete
- Code quality assessment of task-runner outputs
- Fact-checking research claims and citations
- Independent verification before reporting to operator

**Spawn syntax**: `sessions_spawn(runtime: "subagent", agentId: "auditor", task: "...")`

**Do NOT use for**:
- Execution of any kind (auditor is read-only)
- Tasks requiring file modification or code execution

### 7. Claude Code CLI (external to OpenClaw)
**Capabilities**:
- Full development environment access
- Git operations
- Code editing and refactoring
- Test writing
- Documentation updates

**Use for**:
- Development work in openclaw-dev repo
- Code review and refactoring
- Test writing
- Documentation updates
- Any work in /home/nick/projects/openclaw-dev

**Do NOT use for**:
- Production control plane operations
- Live runtime modifications
- Operations requiring OpenClaw context

### 8. Human escalation
**Use for**:
- Operations requiring approval (see approval-policy.md)
- Policy conflicts or ambiguities
- Host facts uncertain or missing from SOP
- Safety boundary unclear
- Unexpected errors or state

## Routing decision tree

```
User request
  |
  ├─ Is it prohibited? (check SOP.md)
  |    └─ YES → Explain prohibition, suggest alternatives
  |
  ├─ Is it a control plane query?
  |    └─ YES → Handle in main agent
  |
  ├─ Does user explicitly request ACP / Claude Code session?
  |    └─ YES → sessions_spawn(runtime: "acp", agentId: "claude", task: "...")
  |
  ├─ Is it a complex, multi-phase research task?
  |    └─ YES → sessions_spawn(agentId: "research-coordinator", task: "...")
  |
  ├─ Does user request quality audit / review?
  |    └─ YES → sessions_spawn(agentId: "auditor", task: "...")
  |
  ├─ Does it require engineering work?
  |    ├─ Complex / deep reasoning → ACP Claude Code
  |    └─ Standard / sandbox-safe → Spawn task-runner via sessions_spawn
  |
  ├─ Does it require host mutation?
  |    ├─ Check approval-policy.md
  |    ├─ If approval required → Escalate to human
  |    └─ If approved → Route to host-ops broker
  |
  ├─ Is it development work in openclaw-dev?
  |    └─ YES → Suggest using Claude Code CLI
  |
  └─ Uncertain?
       └─ Escalate to human
```

## Current capabilities (Phase 3+ operational, Phase 4 ACP verified 2026-03-26)
- task-runner: operational (2026-03-23) → Engineering tasks routed to Docker sandbox
- ACP Claude Code: verified (2026-03-26) → Complex engineering via `sessions_spawn(runtime: "acp", agentId: "claude")`
- research-coordinator: deployed (2026-03-26) → Multi-phase research orchestration
- auditor: deployed (2026-03-26) → Quality auditing with cross-agent session access (profile: coding with denied write/exec)
- host-ops broker: operational (2026-03-17) → Host mutations via broker + wrapper chain
- All 8 host_ops actions live E2E verified

## Multi-phase task orchestration — CRITICAL RULE

**When a task requires multiple phases, you MUST orchestrate the full sequence before reporting to the user.**

### Task directory + task-state.json protocol

Every multi-phase task uses:
- **task-id**: `YYYYMMDD-<short-slug>` (e.g., `20260328-model-routing-bench`)
- **task directory**: `/workspace/outputs/<task-id>/`
- **state file**: `/workspace/outputs/<task-id>/task-state.json`

Each step reads task-state.json to find previous step's outputs (file paths, summaries), then updates it with its own results. This avoids passing large data through spawn task descriptions.

### Model selection per step

Use `sessions_spawn(model: "provider/model")` to choose the right model per step:
- **Data collection** → default model (no override)
- **Algorithm implementation** → `duckcoding-claude/claude-opus-4-6`
- **Analysis/reasoning** → `duckcoding-claude/claude-opus-4-6`
- **Simple formatting/scripting** → default model

Do NOT:
- Report to user after the first subagent completes
- Spawn one subagent and consider the task done
- Treat a multi-phase task as a single spawn

DO:
- Identify all phases upfront (e.g., collect → implement → test → analyze → report)
- Include task-id in every spawn description
- Instruct each step to read/update task-state.json
- Spawn each phase sequentially, passing context via task-state.json
- Wait for each phase's completion event before spawning the next
- Select model per step based on complexity
- Spawn auditor for quality gates at critical points
- Report to user ONLY after all phases complete

See `skills/task-delegation/SKILL.md` for detailed multi-phase workflow pattern.

## Routing examples

### Example 1: "What is the current OpenClaw config path?"
- **Context**: Control plane query
- **Route to**: main agent (current context)
- **Action**: Read control/SOP.md and answer

### Example 2: "Run tests in openclaw-dev repo"
- **Context**: Engineering task in development repo
- **Route to**: Claude Code CLI (external)
- **Action**: Suggest user run Claude Code in openclaw-dev

### Example 3: "Add a new plugin to OpenClaw"
- **Context**: Engineering task requiring code + config change
- **Route to**: task-runner for code (Phase 3), then host-ops broker for config (Phase 2)
- **Action**: Currently → Explain limitation, suggest manual workflow

### Example 4: "Update /etc/openclaw/openclaw.json"
- **Context**: Host mutation requiring approval
- **Route to**: Human escalation → host-ops broker (Phase 2)
- **Action**: Present plan, request approval, wait for Phase 2 broker deployment

### Example 5: "What's in the prohibited operations list?"
- **Context**: Control plane query
- **Route to**: main agent (current context)
- **Action**: Read control/SOP.md and list prohibited operations
