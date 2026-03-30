---
name: coding
description: |
  Write, modify, and refactor code within the task repo sandbox.
---

# Coding Skill

## Skill identity
- **Name**: `coding`
- **Owner**: `task-runner`
- **Purpose**: Write, modify, and refactor code within the task repo
- **Status**: operational

## Prerequisites
- git, bash, python3, node (available in v3-full image)
- Task repo cloned to /workspace/repo

## What this skill does
Handles code creation and modification tasks. Follows the task's CLAUDE.md
constraints, writes clean code, and ensures outputs conform to the artifact
contract in `control/artifact-contract.md`.

## When to use this skill
- User or main agent requests code writing, refactoring, or modification
- Task involves creating new files, fixing bugs, or implementing features

## Workflow
1. Read task inputs from /workspace/inputs/ (if any)
2. Understand the codebase context (read existing files)
3. Write or modify code in /workspace/repo/
4. Run available linters/formatters if configured
5. Write summary to /workspace/outputs/summary.json

## Output format
All code outputs go to /workspace/repo/.
Summary goes to /workspace/outputs/summary.json:
```json
{
  "task_id": "<task-id>",
  "skill": "coding",
  "files_changed": ["path/to/file.py"],
  "summary": "description of changes"
}
```

## Safety rules
- Do not modify files outside /workspace/repo and /workspace/outputs
- Do not execute commands that require network access unless explicitly needed
- Do not install system packages (apt/pip install to system)
- Use venv for Python dependencies if needed
