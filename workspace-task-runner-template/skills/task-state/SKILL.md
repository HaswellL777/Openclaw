---
name: task-state
description: |
  Read and update task-state.json for multi-step task pipelines.
---

# Task State Skill

## Skill identity
- **Name**: `task-state`
- **Owner**: `task-runner`
- **Purpose**: Read and update task-state.json for multi-step task pipelines

## When to use this skill
- Your task description contains a `task-id:` prefix
- Your task description instructs you to read/update `task-state.json`
- You are executing a step in a multi-phase pipeline managed by research-coordinator or main

## On start: read task-state.json

At the beginning of every task that has a `task-id:`, do this:

1. Extract task-id from task description
2. Read `/workspace/outputs/<task-id>/task-state.json`
3. Find your step entry (match by step number from task description)
4. Review previous steps' `outputs` to understand what data is available and where
5. Update your step's `status` to `"in_progress"` and set `started_at`

```python
import json
from pathlib import Path
from datetime import datetime, timezone

TASK_DIR = Path("/workspace/outputs/<task-id>")
STATE_FILE = TASK_DIR / "task-state.json"

state = json.loads(STATE_FILE.read_text())
my_step = state["steps"][STEP_INDEX]  # 0-based
my_step["status"] = "in_progress"
my_step["started_at"] = datetime.now(timezone.utc).isoformat()
STATE_FILE.write_text(json.dumps(state, indent=2))
```

## On completion: update task-state.json

When your step is done:

1. Update your step's `status` to `"completed"`
2. Set `completed_at` timestamp
3. List all output files in `outputs.files` (paths relative to task directory)
4. Write a brief `outputs.summary` describing what was produced
5. Update the top-level `current_step`

```python
my_step["status"] = "completed"
my_step["completed_at"] = datetime.now(timezone.utc).isoformat()
my_step["outputs"] = {
    "files": ["results/benchmark-results.csv", "results/metrics.json"],
    "summary": "Ran 4 algorithms on 3 datasets, 12 combinations total"
}
state["current_step"] = STEP_NUMBER + 1
state["updated_at"] = datetime.now(timezone.utc).isoformat()
STATE_FILE.write_text(json.dumps(state, indent=2))
```

## On failure: record error

If your step fails:

1. Set `status` to `"failed"`
2. Add error details to the top-level `errors[]` array
3. Still write partial outputs if any

```python
my_step["status"] = "failed"
state["errors"].append({
    "step": STEP_NUMBER,
    "error": "Dataset download failed: HTTP 403",
    "timestamp": datetime.now(timezone.utc).isoformat()
})
STATE_FILE.write_text(json.dumps(state, indent=2))
```

## Task directory conventions

All your output goes under `/workspace/outputs/<task-id>/`:

| Directory | Purpose |
|-----------|---------|
| `data/` | Raw data, datasets, downloads |
| `src/` | Source code, scripts, implementations |
| `results/` | Test results, metrics, raw output |
| `analysis/` | Comparative analysis, charts, tables |

Create subdirectories as needed. Never write outside the task directory.

## If task-state.json doesn't exist

You are the first step. Create the task directory and initialize task-state.json:

```python
TASK_DIR.mkdir(parents=True, exist_ok=True)
for sub in ["data", "src", "results", "analysis"]:
    (TASK_DIR / sub).mkdir(exist_ok=True)

state = {
    "task_id": "<task-id>",
    "title": "<from task description>",
    "status": "in_progress",
    "created_at": datetime.now(timezone.utc).isoformat(),
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "total_steps": TOTAL_STEPS,  # from task description "Step N/total"
    "current_step": 1,
    "steps": [{"step": 1, "name": "...", "status": "in_progress", ...}],
    "errors": [],
    "notes": []
}
STATE_FILE.write_text(json.dumps(state, indent=2))
```
