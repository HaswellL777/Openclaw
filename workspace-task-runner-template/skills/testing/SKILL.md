---
name: testing
description: |
  Write and execute tests for task repo code, reporting results in structured format.
---

# Testing Skill

## Skill identity
- **Name**: `testing`
- **Owner**: `task-runner`
- **Purpose**: Write and execute tests for task repo code
- **Status**: operational

## Prerequisites
- git, bash, python3, node (available in v3-full image)
- Task repo with testable code in /workspace/repo

## What this skill does
Creates and runs tests for the code in the task repo. Supports Python (pytest),
Node.js (jest/vitest), and shell-based test scripts. Reports results in
structured format.

## When to use this skill
- After coding skill produces new code
- User or main agent explicitly requests testing
- Task requires validation of existing code

## Workflow
1. Identify testing framework from repo (package.json, pyproject.toml, etc.)
2. Write test files if needed
3. Execute tests
4. Collect results
5. Write test report to /workspace/outputs/test-results.json

## Output format
```json
{
  "task_id": "<task-id>",
  "skill": "testing",
  "framework": "pytest",
  "total": 10,
  "passed": 9,
  "failed": 1,
  "failures": [
    {"test": "test_name", "error": "assertion message"}
  ]
}
```

## Safety rules
- Tests must not require external network (mock external calls)
- Tests must not modify files outside /workspace/
- Test execution timeout: respect container lifecycle limits
