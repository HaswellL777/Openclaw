---
name: task-delegation
description: |
  Delegate tasks to sub-agents (task-runner, research-coordinator, auditor) with appropriate context, timeout, and monitoring. Use when work should be distributed to specialized agents.
---

# Task Delegation Skill

## Skill identity
- **Name**: `task-delegation`
- **Owner**: `main` agent
- **Purpose**: Delegate tasks to subagents and orchestrate multi-phase work
- **Status**: operational (task-runner, research-coordinator, auditor, ACP claude)

## Prerequisites
- Phase 4 operational (all agents available)
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
| Data analysis / ML | task-runner | subagent | GPU + PyTorch/CUDA |
| Multi-phase research | research-coordinator | subagent | Orchestrates task-runner sub-tasks |
| Quality audit | auditor | subagent | Read-only, cross-agent session access |
| Deep code analysis | ACP claude | acp (run) | Claude Code capabilities, one-shot |
| Complex refactor | ACP claude | acp (run) | Multi-file awareness |

## Model selection

`sessions_spawn` accepts a `model` parameter. Use it when the default model is insufficient:

```
sessions_spawn(agentId: "task-runner", model: "duckcoding-claude/claude-opus-4-6", task: "...")
```

Guidelines:
- **Simple coding/scripting** → default model (no override needed)
- **Complex algorithm implementation** → `claude-opus-4-6` or `gpt-5.4`
- **Data collection/scraping** → default model is fine
- **Analysis requiring deep reasoning** → `claude-opus-4-6`

## Single-phase workflow (simple tasks)
1. Analyze the task request
2. Determine routing (see matrix above)
3. `sessions_spawn(agentId: "<agent>", task: "...")`
4. Wait for completion event (auto-announced as user message)
5. Review result and present to human

## Multi-phase workflow (complex/research tasks) — CRITICAL

**When a task clearly requires multiple phases (e.g., data collection → implementation → testing → report), you MUST orchestrate the full sequence. Do NOT report to user after the first phase.**

### Task directory convention

Every multi-phase task gets a dedicated directory:
```
/workspace/outputs/<task-id>/
```
Where `task-id` = `YYYYMMDD-<short-slug>` (e.g., `20260328-model-routing-bench`).

Include the task-id in every spawn's task description so all agents write to the same directory.

### Step-by-step state passing via task-state.json

Each step writes results to `/workspace/outputs/<task-id>/task-state.json`. The next step reads this file to know what the previous step produced and where files are located. This avoids stuffing large outputs into spawn task descriptions.

Pattern:
```
1. Identify all phases needed. Generate a task-id.
2. Spawn Phase 1: "task-id: <id>. Step 1/<total>: <description>"
3. WAIT for Phase 1 completion event
4. DO NOT report to user — evaluate if more phases needed
5. Spawn Phase 2: "task-id: <id>. Step 2/<total>: Read task-state.json from previous step. <description>"
6. WAIT for Phase 2 completion event
7. Repeat until all phases complete
8. (Optional) Spawn auditor for quality review
9. ONLY THEN report synthesized results to user
```

### Example: ML benchmark task

User asks: "拉取模型路由数据集，实现几种代表算法，测试并横向比较，出报告"

**Correct behavior:**
```
task-id: 20260328-model-routing-bench

Step 1/5: Spawn research-coordinator →
  "task-id: 20260328-model-routing-bench. Step 1/5: 搜索模型路由相关数据集
  (RouterBench, Martian, LMSYS等)，拉取到 /workspace/outputs/20260328-model-routing-bench/data/，
  记录数据集元信息到 task-state.json"
  ↓ (wait for completion)

Step 2/5: Spawn task-runner (model: claude-opus-4-6) →
  "task-id: 20260328-model-routing-bench. Step 2/5: 读取 task-state.json 了解数据集位置和格式。
  实现以下路由算法：(1) 基于规则 (2) LLM-as-judge (3) embedding相似度 (4) 级联路由。
  代码写入 /workspace/outputs/20260328-model-routing-bench/src/"
  ↓ (wait for completion)

Step 3/5: Spawn task-runner →
  "task-id: 20260328-model-routing-bench. Step 3/5: 读取 task-state.json。
  在所有数据集上运行所有算法，记录指标(accuracy, latency, cost)到 results/"
  ↓ (wait for completion)

Step 4/5: Spawn task-runner (model: claude-opus-4-6) →
  "task-id: 20260328-model-routing-bench. Step 4/5: 读取 task-state.json。
  横向比较所有算法在所有数据集上的表现，生成对比表格和图表到 analysis/"
  ↓ (wait for completion)

Step 5/5: Spawn task-runner →
  "task-id: 20260328-model-routing-bench. Step 5/5: 读取 task-state.json。
  基于 analysis/ 中的对比结果，撰写完整研究报告到 report.md"
  ↓ (wait for completion)

(Optional) Spawn auditor → "审计 20260328-model-routing-bench 报告质量"

FINAL: Read report, synthesize key findings, report to user
```

**WRONG behavior:**
```
Spawn step 1 → 收到结果 → 立即向用户汇报 ← 错！任务还没完成
```

### Key rules for multi-phase orchestration
1. **Count phases before starting**: Estimate how many phases the task needs
2. **Always include task-id**: Every spawn description starts with task-id
3. **Instruct to read task-state.json**: Step 2+ must read previous state
4. **Don't report early**: Only report to user after ALL phases complete
5. **Select model per step**: Use stronger models for reasoning-heavy steps
6. **Use auditor at quality gates**: Spawn auditor after critical phases
7. **Handle failures**: If a phase fails, retry with adjusted approach before giving up

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
