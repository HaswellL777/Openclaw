# Phase 0 Baseline

Date: 2026-03-07

## Goal
Establish the development-side control skeleton for OpenClaw v3 without modifying live runtime behavior.

## Completed
- development repo initialized under `~/projects/openclaw-dev`
- authoritative SOP source exists at `/srv/openclaw-control/docs/host-sop.md`
- SOP publish script implemented and tested
- publish metadata/log flow implemented
- Claude Code project files created:
  - `CLAUDE.md`
  - `.claude/settings.json`
  - `.claude/agents/*`
- snapshot/Vault discipline documented
- broker skeleton created
- plugin skeleton created (development-only, not deployed)
- mock gate shim and example tests created
- repo-local tests passing:
  - `tests/test_sop_publish.sh`
  - `tests/test_gate_examples.sh`

## Explicit non-goals of Phase 0
- no modification to `/etc/openclaw/openclaw.json`
- no deployment into `/var/lib/openclaw/.openclaw/extensions/`
- no systemd unit changes
- no Docker runtime integration
- no `workspace-main/`
- no `workspace-task-runner/`

## Current safety status
- no second user-level gateway
- authoritative runtime config remains `/etc/openclaw/openclaw.json`
- runtime plugin directory remains untouched by this repo
- repo-local work has not introduced host runtime side effects

## Next phase boundary
Phase 1 starts when `workspace-main/` is created and OpenClaw runtime config is updated to add `main`.

That phase requires:
- pre-change snapshot
- config change
- gateway restart
- validation
- post-change snapshot
- Vault sync
