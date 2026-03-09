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
- alter systemd units
- alter Docker privilege boundaries
- alter snapshot/backup behavior
- alter secrets handling
then stop and produce a plan, risk list, rollback note, and validation checklist before making the change.
