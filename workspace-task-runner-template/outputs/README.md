# Task Outputs

This directory is the designated output location for task-runner results.

## Expected files

| File | Purpose |
|------|---------|
| `plan.md` | Task execution plan |
| `summary.md` | Human-readable summary |
| `summary.json` | Machine-readable summary |
| `diff.patch` | Code changes (if any) |
| `test.log` | Test execution log |
| `lint.log` | Lint results |
| `host-change-request.json` | Host-side change request (if needed) |

## Convention

- One task's outputs go in a subdirectory: `outputs/<task-id>/`
- Top-level files are for the current/latest task
- Do not delete other tasks' output subdirectories
