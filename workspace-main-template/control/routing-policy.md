# Routing Policy

## Purpose
This policy defines how main agent routes requests to appropriate execution contexts.

## Execution contexts

### 1. main agent (current context)
**Capabilities**:
- Read/write/edit files in workspace-main
- Query control files
- Update state files
- Spawn subagents (task-runner: Phase 3)
- Call host-ops broker (Phase 2)

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

### 2. task-runner (Phase 3, not yet available)
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

### 3. host-ops broker (Phase 2, not yet available)
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

### 4. Claude Code CLI (external to OpenClaw)
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

### 5. Human escalation
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
  ├─ Does it require engineering work?
  |    └─ YES → Route to task-runner (Phase 3)
  |
  ├─ Does it require host mutation?
  |    ├─ Check approval-policy.md
  |    ├─ If approval required → Escalate to human
  |    └─ If approved → Route to host-ops broker (Phase 2)
  |
  ├─ Is it development work in openclaw-dev?
  |    └─ YES → Suggest using Claude Code CLI
  |
  └─ Uncertain?
       └─ Escalate to human
```

## Current limitations (Phase 1 complete, Phase 2 not started)
- task-runner not yet available (Phase 3) → Cannot route engineering tasks
- host-ops broker not yet available (Phase 2) → Cannot route host mutations
- Current workaround: Explain limitation and suggest manual execution following runbooks

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
