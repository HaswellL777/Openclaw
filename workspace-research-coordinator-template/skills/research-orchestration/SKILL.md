# Research Orchestration Skill

## Skill identity
- **Name**: `research-orchestration`
- **Owner**: `research-coordinator`
- **Purpose**: Manage long-running, multi-phase research tasks with iterative feedback loops

## When to use this skill
- Operator assigns a complex research goal (literature survey, technology evaluation, benchmark, etc.)
- Task requires multiple data-collection and analysis phases
- Task spans multiple sessions and needs persistent state tracking

## Task directory structure

Every research task gets a dedicated directory under `/workspace/outputs/`:

```
/workspace/outputs/<task-id>/
├── task-state.json          # Structured state (machine-readable)
├── research-plan.md         # Initial plan
├── research-state.md        # Human-readable progress log
├── data/                    # Raw data, datasets, downloads
├── src/                     # Source code, scripts, implementations
├── results/                 # Test results, metrics, raw output
├── analysis/                # Comparative analysis, charts, tables
└── report.md                # Final report
```

**task-id format**: `YYYYMMDD-<short-slug>` (e.g., `20260328-model-routing-bench`)

## task-state.json specification

Every step reads and updates this file. It is the primary mechanism for passing state between steps.

```json
{
  "task_id": "20260328-model-routing-bench",
  "title": "Model Routing Algorithm Benchmark",
  "status": "in_progress",
  "created_at": "2026-03-28T10:00:00Z",
  "updated_at": "2026-03-28T14:30:00Z",
  "total_steps": 5,
  "current_step": 3,
  "steps": [
    {
      "step": 1,
      "name": "pull-datasets",
      "status": "completed",
      "agent": "task-runner",
      "model": null,
      "started_at": "2026-03-28T10:05:00Z",
      "completed_at": "2026-03-28T10:45:00Z",
      "outputs": {
        "files": [
          "data/routerbench.parquet",
          "data/martian-eval.json",
          "data/lmsys-arena.csv"
        ],
        "summary": "3 datasets pulled: RouterBench (12k samples), Martian (5k), LMSYS Arena (8k)"
      }
    },
    {
      "step": 2,
      "name": "implement-algorithms",
      "status": "completed",
      "agent": "task-runner",
      "model": "duckcoding-claude/claude-opus-4-6",
      "outputs": {
        "files": ["src/rule_based.py", "src/llm_judge.py", "src/embedding_router.py", "src/cascade.py"],
        "summary": "4 algorithms implemented with common interface"
      }
    },
    {
      "step": 3,
      "name": "run-benchmarks",
      "status": "in_progress",
      "agent": "task-runner",
      "model": null,
      "outputs": null
    }
  ],
  "errors": [],
  "notes": []
}
```

### Rules for task-state.json
- Each task-runner step MUST read this file at start to understand context
- Each step MUST update its entry with `status`, `outputs`, timestamps
- Paths in `outputs.files` are relative to the task directory
- If a step fails, set `status: "failed"` and add error details to `errors[]`
- research-coordinator reads this file to decide next actions

## Workflow

### Phase 1: Scoping
1. Understand the research goal and success criteria
2. Generate task-id: `YYYYMMDD-<slug>`
3. Create task directory structure
4. Initialize task-state.json with all planned steps
5. Identify information sources (web, knowledge repos, code repos)
6. Break goal into concrete sub-tasks with measurable deliverables
7. Write initial plan to `<task-id>/research-plan.md`

### Phase 2: Data Collection
1. Spawn task-runner sessions for each data-collection sub-task:
   - Include task-id and step number in task description
   - Instruct task-runner to read/update task-state.json
   - Choose model based on task complexity (see AGENTS.md)
2. Track progress via task-state.json
3. Collected data goes to `<task-id>/data/`

### Phase 3: Implementation (if needed)
1. Spawn task-runner with strong model for algorithm/code work
2. Code goes to `<task-id>/src/`
3. task-runner reads task-state.json to find data locations

### Phase 4: Testing & Analysis
1. Spawn task-runner to run tests/benchmarks
2. Results go to `<task-id>/results/`
3. Spawn task-runner for comparative analysis
4. Analysis goes to `<task-id>/analysis/`

### Phase 5: Report Generation
1. Spawn task-runner to generate structured report
2. Report format: `<task-id>/report.md`
3. Include: executive summary, methodology, findings, recommendations, references

### Phase 6: Iteration (if needed)
1. Based on findings, identify follow-up questions
2. Return to Phase 2 with refined scope
3. Update task-state.json with iteration notes

## Spawn template

For each step, use this format:
```
sessions_spawn(
  agentId: "task-runner",
  model: "<model or omit for default>",
  task: "task-id: <task-id>. Step <N>/<total>: <step-name>.
    Read /workspace/outputs/<task-id>/task-state.json to understand previous steps and data locations.
    <detailed instructions for this step>
    When done, update task-state.json with your step's status and output file paths."
)
```

## Safety rules
- Do not fabricate data or citations — only report what task-runner actually found
- Track all sources with URLs/paths
- If uncertain about a finding, flag it as "needs verification"
- Do not modify knowledge repos (read-only mounts)
- Always write task-state.json updates even on failure
