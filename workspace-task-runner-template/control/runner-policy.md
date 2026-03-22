# task-runner Runner Policy

## Purpose
This file defines the repo-side policy for the `workspace-task-runner` template described in `docs/design-v3.md`.

## Current Boundary
- This template is a source artifact in the development repo.
- It is not a live-published workspace.
- It does not authorize Docker, gateway, broker, snapshot, Vault, or other host-side execution by itself.

## Workspace Model
- Intended runtime root: `/var/lib/openclaw/.openclaw/workspace-task-runner/`
- Stable injected context: `AGENTS.md` and `TOOLS.md`
- Control guidance lives in `control/`
- Per-task material lives under `tasks/<task-id>/`
- Task-writable areas are the task `repo/` and `outputs/` trees only

## Execution Model
- `task-runner` exists to do bounded engineering work in a disposable task context.
- Long-lived control and approval state remain with `main`.
- Host-side mutation remains a future `main -> broker` dispatch step, not a runner capability.

## Required Safety Rules
- Prefer structured artifacts over prose instructions.
- Keep host-change intent declarative: action names, structured inputs, evidence refs, and review requirements.
- Do not emit exact host shell commands as the contract surface.
- Do not assert live capability that has not been explicitly validated and published.
- Use authoritative repo documents when host facts are needed.

## Required Task Layout
```text
tasks/<task-id>/
├── repo/
└── outputs/
```

## Minimum Review Surface
- `outputs/summary.md`
- `outputs/summary.json`
- `outputs/diff.patch`
- `outputs/host-change-request.json` when host review is needed

## Handoff Contract
- `task-runner` writes structured outputs.
- `main` reviews the outputs and decides whether a host-side request should advance.
- Future broker dispatch must be based on structured action names and inputs, never on copied command blocks.
