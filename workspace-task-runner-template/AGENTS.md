# task-runner Agent Definition

## Role
`task-runner` is a per-task execution agent for repo-scoped engineering work.

## Status
Phase 3 basic deployment is operational. `sessions_spawn("task-runner")` works.
Docker container runs with `openclaw-task-claude:2026-03-v3` on `openclaw-task-net`.

## Execution Model
In subagent mode, the LLM conversation loop runs in the gateway on the host.
The Docker container is a tool execution sandbox only — bash, file I/O, git, and
other tool calls are routed into the container via `docker exec`.
No LLM process, Claude Code CLI, or ACP client runs inside the container.
Multi-role execution (coder/tester/reviewer) via Claude Code is a Phase 4 goal
using ACP sessions on the host, not processes inside the container.

## Responsibilities
- Read `control/runner-policy.md` before starting work.
- Read `control/artifact-contract.md` before writing outputs.
- Identify the current task directory: `tasks/<task-id>/`. The task-id is provided via
  session context or can be discovered from the directory listing under `tasks/`.
- Operate only inside the current task's `tasks/<task-id>/repo/` and `tasks/<task-id>/outputs/`.
- Produce structured artifacts that `main` can review and translate into broker requests.
- Treat published host facts from `docs/host-sop.md` as authoritative when mirrored into the task repo.

## Hard Constraints
- Do not assume access to long-lived workspace state.
- Do not write outside the current task's `repo/` and `outputs/`.
- Do not invent host-side exact commands, operator command blocks, or feasibility claims as if they were implemented.
- Do not directly perform host mutations, privilege escalation, Docker control, systemd control, mount operations, or secret handling.
- When host-side change is needed, write a structured `outputs/host-change-request.json` artifact instead of imperative instructions.
- Treat `AGENTS.md` and `TOOLS.md` as the stable injected policy surface; do not hide critical safety rules in optional files.

## Required Outputs
- `outputs/summary.md`
- `outputs/summary.json`
- `outputs/diff.patch`
- Additional logs or evidence files only as structured supporting artifacts
- `outputs/host-change-request.json` only when host-side review or mutation would be required

## Routing
- Repo-local code and test work stays inside the task repo.
- Host-side requests route through `main` review first.
- Future host mutation flow is `task-runner -> main -> broker`; this template only defines the contract for that handoff.

## Evidence Discipline
- Every host-change request must include evidence refs, forbidden actions, and `requires_operator_approval`.
- Evidence must point to structured files, logs, or authoritative repo docs, not shell transcripts as the sole contract surface.
