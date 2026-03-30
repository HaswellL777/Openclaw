# OpenClaw Host Development Repo

## Purpose
This repository is the human-led development workspace for the OpenClaw host architecture.
It is used to design, review, and implement:
- broker logic
- plugins
- publish scripts
- validation tests
- workspace scaffolding
- future task-runner inputs

It is **not** the production control plane itself.
It is **not** the task container workspace.
It must never be treated as the authoritative runtime state.

## Source of truth
- Host runtime facts and operational history live in `docs/host-sop.md`
- Architecture and implementation target live in `docs/design-v3.md`
- The authoritative SOP is currently edited in this dev repo: `docs/host-sop.md` (future: `/srv/openclaw-control/docs/host-sop.md` when that repo is independently operational)
- The authoritative OpenClaw runtime config path is `/etc/openclaw/openclaw.json`

Do not invent host facts in this file.
If a host fact is needed, read `docs/host-sop.md`.

## Safety boundaries
- Never run `openclaw onboard` as `nick`
- Never run `openclaw doctor --repair` or similar auto-repair flows as `nick`
- Never start a user-level `openclaw gateway`
- Never assume `~/.openclaw/` is a valid runtime source of truth
- Never place secrets, API keys, or tokens into this repository
- Never propose direct edits to `/etc/openclaw/openclaw.json` without an explicit reviewable patch and rollback note
- Never treat plugin `before_tool_call` as a guaranteed hard block unless host-side enforcement has been verified

## Snapshot and Vault discipline
- Root snapshot and OpenClaw runtime data are not the same thing: `/var/lib/openclaw` is a separate btrfs subvolume and is not included in root snapshots
- Do not describe a root snapshot rollback as if it restores all OpenClaw runtime state
- Vault is normally offline (`/mnt/vault` noauto) and must not be treated as a routine writable workspace
- Do not mount, unmount, send, receive, or modify Vault paths from repo-local development flows
- Any host-affecting change must be framed as: pre-change snapshot -> Vault sync -> change -> health validation -> post-change snapshot -> Vault sync
- Future host-side snapshot actions must go through broker/wrapper design, not direct ad hoc shell execution from this repository

## Working style
When making changes in this repo:
1. read `docs/design-v3.md`
2. read relevant sections of `docs/host-sop.md`
3. keep changes minimal and reviewable
4. prefer scripts and tests over one-off manual commands
5. produce diff-friendly artifacts
6. write acceptance or validation notes when behavior changes

## Workspace publish status
- **main workspace**: published on 2026-03-29 via `publish-workspace-main.sh --apply --allow-live-target`
  - Target: `/var/lib/openclaw/.openclaw/workspace-main`
  - SOP hash updated from `docs/host-sop.md`
  - Ownership fixed to openclaw:openclaw
- **Other agent workspaces**: task-runner/RC/auditor need manual rsync if templates change

## Expected repository zones
- `broker/` for host-side broker logic
- `plugins/` for OpenClaw plugin work
- `scripts/` for publish/check/bootstrap helpers
- `tests/` for validation scripts
- `examples/` for sample payloads and fixtures
- `.claude/agents/` for project-specific Claude Code subagents

## Output expectations
When asked to make implementation changes:
- explain assumptions
- name affected files first
- prefer patch-style edits
- add or update a test when behavior changes
- avoid broad refactors unless explicitly requested

## Escalation rule
If a requested change would:
- alter `/etc/openclaw/openclaw.json`
- alter systemd units (add/remove/modify unit files)
- alter host-level privilege boundaries (user groups, sudoers, file ownership outside /var/lib/openclaw)
- alter snapshot/backup behavior
- alter secrets handling
then stop and produce a plan, risk list, rollback note, and validation checklist before making the change.

Docker container operations that stay within the configured `sandbox.docker` boundary
(container create/run/stop/rm, image build/tag, network management within openclaw-task-net)
are expected operational actions once Phase 3 is active. They do NOT require escalation.
Only changes to Docker's host-level configuration (daemon.json, systemd overrides, group membership)
require escalation.

## Anti-stall rules

### Rule 1: Options over escalation
When facing a technical decision, default to producing "3 options + recommendation
with reasoning" instead of "operator must decide." Only escalate to "operator must
decide" for: (a) security boundary changes that increase attack surface,
(b) resource authorization that incurs cost, (c) changes that cannot be rolled back
via snapshot. Information integration and technical analysis are agent responsibilities,
not operator responsibilities.

### Rule 2: Blocker status must track technical reality
When a blocker's technical root cause is resolved, its documentation status must be
updated in the same commit or the immediately following commit. Do not leave
documentation saying "BLOCKED" or "NO-GO" when the blocking condition no longer exists.
`docs/current-boundary.md` is the single authoritative status source; other files
reference it rather than maintaining independent status copies.

### Rule 3: Planning documents have a close-by date
Every planning document must include a "close-by" field (date or condition).
When the condition is met or the date passes, the document must be either:
(a) closed and archived to docs/archive/, or (b) explicitly extended with a new
close-by. Planning documents open longer than 5 days without implementation progress
should be reviewed for whether they are blocking rather than enabling progress.

### Rule 4: Cross-sync is not work
Updating the same status across multiple documents (design-v3.md, host-sop.md,
current-boundary.md, map.md, planning/README.md) does not count as progress.
Only `docs/current-boundary.md` needs real-time status updates. Other authority
documents are updated at phase boundaries, not at every state change. A commit
that only syncs status across documents without any implementation change should
be questioned.

### Rule 5: Repo-side scaffolding requires a live-side target
Do not build validators, schemas, replay harnesses, or candidate packs for
a runtime that does not yet exist. Scaffolding is justified only when: (a) the
runtime it targets is operational or will be within the current work session,
or (b) the scaffolding is needed to validate a design before implementation.
Building elaborate dry-run infrastructure to avoid making a decision is
procrastination, not engineering.
