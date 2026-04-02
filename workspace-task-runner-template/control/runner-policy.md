# task-runner Runner Policy

## Purpose
This file defines the repo-side policy for the `workspace-task-runner` template described in `docs/design-v3.md`.

## Current Boundary
- This template is published to `/var/lib/openclaw/.openclaw/workspace-task-runner/`.
- It is a live-published workspace (via `publish-workspace-all.sh`).
- Task execution happens in Docker sandbox (scope=shared, ReadonlyRootfs=true).
- `/workspace/project-template/` contains ACP Claude Code project template (CLAUDE.md + .claude/agents).

## Workspace Model
- Runtime root: `/var/lib/openclaw/.openclaw/workspace-task-runner/`
- Container mount: `/workspace/`
- Stable injected context: `AGENTS.md` and `TOOLS.md`
- Control guidance lives in `control/`
- Task outputs live under `outputs/<task-id>/`
- Project template lives at `project-template/` (copied into each new task dir)
- Schemas live at `schemas/`
- Task-writable areas: `outputs/` tree only (rootfs is read-only)

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
