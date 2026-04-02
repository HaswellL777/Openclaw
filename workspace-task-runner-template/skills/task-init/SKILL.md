---
name: task-init
description: |
  Initialize a new task directory under /workspace/outputs/. MUST be called at the start of every new task before any work begins. Creates standardized directory structure and README.
---

# Task Initialization

**Trigger**: Call this skill at the very start of every new task, before doing any work.

## Steps

### 1. Generate task-id

Format: `YYYYMMDD-<slug>`

- Date: today's date
- Slug: 2-4 lowercase keywords from the task description, joined by hyphens
- Example: `20260401-protein-folding-survey`

### 2. Create directory structure

```
/workspace/outputs/<task-id>/
  data/         # Input data, downloaded files, raw materials
  results/      # Processed results, analysis output
  logs/         # Execution logs, test output
  README.md     # Task metadata (created in step 3)
```

Use `mkdir -p` to create all directories at once:
```bash
TASK_DIR="/workspace/outputs/<task-id>"
mkdir -p "$TASK_DIR"/{data,results,logs}
```

### 3. Write README.md

Create `/workspace/outputs/<task-id>/README.md` with:

```markdown
# <Task Title>

- **task-id**: <task-id>
- **status**: active
- **created**: <ISO 8601 timestamp>
- **description**: <1-2 sentence task description>

## Expected Outputs
- [ ] summary.json
- [ ] summary.md
- [ ] <other task-specific outputs>

## Notes
<empty, fill during execution>
```

### 4. Set working context

After initialization:
- All task outputs go into `/workspace/outputs/<task-id>/`
- `summary.json` and `summary.md` go directly in the task directory
- `diff.patch`, `test.log`, `lint.log` go in the task directory
- Data files go in `data/`
- Result files go in `results/`
- Log files go in `logs/`
- `host-change-request.json` goes in the task directory (if needed)

### 5. Announce

Report to the calling agent:
```
Task initialized: <task-id>
Output directory: /workspace/outputs/<task-id>/
```

## On Task Completion

When the task is done, you MUST:

1. Update README.md: change `status` to `completed` (or `failed`/`blocked`)
2. Write `summary.json` following the schema in `/workspace/schemas/task-runner-summary.schema.json`
3. Write `summary.md` with a human-readable summary
4. If host changes needed: write `host-change-request.json` following `/workspace/schemas/host-change-request.schema.json`

## Schema References

- Summary: `/workspace/schemas/task-runner-summary.schema.json`
- Host change request: `/workspace/schemas/host-change-request.schema.json`
- Artifact contract: `/workspace/control/artifact-contract.md`
