---
name: report
description: |
  Generate structured reports from task execution results.
---

# Report Skill

## Skill identity
- **Name**: `report`
- **Owner**: `task-runner`
- **Purpose**: Generate structured reports from task execution results
- **Status**: operational

## Prerequisites
- Task outputs available in /workspace/outputs/
- Task repo available in /workspace/repo/

## What this skill does
Produces structured reports summarizing task execution. Collates outputs from
coding, testing, and research skills into a coherent deliverable. Supports
multiple output formats (markdown, JSON summary).

## When to use this skill
- Task is nearing completion and needs a deliverable summary
- Main agent or user requests a progress or final report
- Multiple skill outputs need to be consolidated

## Workflow
1. Read all outputs in /workspace/outputs/
2. Read task inputs for context
3. Synthesize findings into a coherent report
4. Write report to /workspace/outputs/report.md
5. Write machine-readable summary to /workspace/outputs/summary.json

## Output format
/workspace/outputs/summary.json:
```json
{
  "task_id": "<task-id>",
  "status": "completed|partial|failed",
  "skills_used": ["coding", "testing"],
  "files_produced": ["report.md", "test-results.json"],
  "summary": "one-paragraph summary",
  "host_change_requests": []
}
```

## Safety rules
- Reports must not contain secrets or credentials
- Reports must accurately reflect what was done (no fabrication)
- If task produced host-change-request.json, include it in summary
