# Task Delegation Skill

## Skill identity
- **Name**: `task-delegation`
- **Owner**: `main` agent
- **Purpose**: Delegate tasks to subagents and orchestrate multi-phase work
- **Status**: operational (task-runner, research-coordinator, auditor, ACP claude)

## Prerequisites
- Phase 3+ operational (task-runner, research-coordinator, auditor available)
- `sessions_spawn` tool available
- Agents configured in openclaw.json

## What this skill does
Routes tasks from human requests to the appropriate execution agent.
For multi-phase tasks, orchestrates sequential spawn cycles — **do NOT report to user after the first phase; continue spawning until all phases complete.**

## When to use this skill
- Human requests an engineering task (code, research, testing)
- Task requires execution in a sandbox environment
- Task requires Claude Code capabilities (ACP)
- Task is complex and multi-phase (research, experiment loops)
- Task requires quality auditing

## Routing decision matrix

| Task type | Agent | Runtime | Reason |
|-----------|-------|---------|--------|
| Simple engineering | task-runner | subagent | Sandbox isolation |
| Build & test | task-runner | subagent | Sandbox isolation |
| Web scraping | task-runner | subagent | Network + Scrapling |
| Data analysis | task-runner | subagent | GPU + Python |
| Multi-phase research | research-coordinator | subagent | Orchestrates task-runner sub-tasks |
| Quality audit | auditor | subagent | Read-only, cross-agent session access |
| Deep code analysis | ACP claude | acp (run) | Claude Code capabilities, one-shot |
| Complex refactor | ACP claude | acp (run) | Multi-file awareness |

## Single-phase workflow (simple tasks)
1. Analyze the task request
2. Determine routing (see matrix above)
3. `sessions_spawn(agentId: "<agent>", task: "...")`
4. Wait for completion event (auto-announced as user message)
5. Review result and present to human

## Multi-phase workflow (complex/research tasks) — CRITICAL

**When a task clearly requires multiple phases (e.g., literature search → analysis → report), you MUST orchestrate the full sequence. Do NOT report to user after the first phase.**

Pattern:
```
1. Identify all phases needed for the task
2. Spawn Phase 1 (e.g., data collection)
3. WAIT for Phase 1 completion event
4. DO NOT report to user yet — evaluate if more phases are needed
5. Spawn Phase 2 with Phase 1 results as context
6. WAIT for Phase 2 completion event
7. Repeat until all phases complete
8. (Optional) Spawn auditor for quality review
9. ONLY THEN report synthesized results to user
```

### Example: Multi-phase research task

User asks: "调研多模型路由最新进展并产出报告"

**Correct behavior:**
```
Phase 1: Spawn research-coordinator → "搜索2024-2026年多模型路由相关论文，列出关键发现"
  ↓ (wait for completion)
Phase 2: Spawn research-coordinator → "基于Phase 1的论文列表，深度分析top 10论文，提取核心方法"
  ↓ (wait for completion)
Phase 3: Spawn task-runner → "找到关键论文的代码库，clone并分析代码结构"
  ↓ (wait for completion)
Phase 4: Spawn ACP claude → "基于Phase 2-3的分析，撰写完整研究报告"
  ↓ (wait for completion)
Phase 5: Spawn auditor → "审计研究报告的质量：文献覆盖度、引用准确性、结论合理性"
  ↓ (wait for completion)
FINAL: Synthesize all phases, report to user with complete report + audit findings
```

**WRONG behavior:**
```
Spawn research-coordinator → 收到Phase 1结果 → 立即向用户汇报 ← 这是错的！
```

### Key rules for multi-phase orchestration
1. **Count phases before starting**: Estimate how many phases the task needs
2. **Pass context forward**: Each spawn includes summary of previous phase results
3. **Don't report early**: Only report to user after ALL phases complete
4. **Use auditor at quality gates**: Spawn auditor after critical phases
5. **Handle failures**: If a phase fails, retry with adjusted approach before giving up
6. **Track state**: Mention the phase number and total in each spawn task description

## Using sessions_send for follow-up

If a subagent needs additional guidance after its initial response:
```
sessions_send(sessionKey: "<child-session-key>", message: "Follow up: also check X")
```
This sends a new message to an existing session. The subagent will process it and announce the result.

## Safety rules
- Never delegate host-ops actions to subagents (use broker skill)
- Verify task doesn't require elevated privileges before delegation
- Set appropriate timeout for long-running tasks
- Review task outputs before presenting to human
- For ACP: use `mode: "run"` only (one-shot). Do NOT use persistent sessions yet.

## Related skills
- `broker`: For host state mutations (not task delegation)
- `routing`: For general message routing policy
