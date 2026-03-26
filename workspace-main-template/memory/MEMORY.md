# Main Agent Memory

> This file is auto-loaded into context at session start.
> Keep it concise — content costs tokens every turn.
> For detailed notes, use `memory/YYYY-MM-DD.md` daily logs.

## System identity
- Hostname: Ubuntu 24.04 LTS / Btrfs / systemd
- OpenClaw version: 2026.3.23-2 (upgraded 2026-03-25)
- Gateway port: 17777 (loopback)
- Default model: deepseek-chat (task-runner)

## Key paths
- Live config: `/etc/openclaw/openclaw.json`
- Workspace: `/var/lib/openclaw/.openclaw/workspace-main/`
- Dev repo: `/home/nick/projects/openclaw-dev/`
- Snapshots: `/.snapshots/`
- Vault: `/mnt/vault` (noauto, offline by default)

## Operational rules
- All host changes: pre-snapshot → change → health check → post-snapshot → vault sync
- Use `host_ops` tool for broker actions (8/8 verified)
- Never write directly to `/etc/openclaw/` — use candidate + deploy workflow
- `/var/lib/openclaw` is separate btrfs subvolume (not in root snapshots)

## Deployed capabilities
- Broker: 8/8 actions operational
- Task-runner: Docker sandbox, scope=shared, v3-full image (Ubuntu 24.04, Python 3, Node.js 22, Scrapling)
- Knowledge repos: /workspace/knowledge/ via host mount --bind (read-only)
  - LabClaw: 240 biomedical research SKILL.md files
  - autoresearch: ML autonomous experiment loop (Karpathy)
- GPU: RTX 5060 Ti 16GB available (vLLM stopped, SecureBoot disabled)
- ACP: configured and verified operational (2026-03-26) — spawnable via sessions_spawn(runtime: "acp", agentId: "claude")

## Maintenance log
- 2026-03-25: Major maintenance window — upgrade to 2026.3.23-2, vLLM shutdown,
  hook cleanup, scope→shared, Scrapling added, LabClaw+autoresearch cloned,
  workspace-main republished

## Operator preferences
<!-- Agent should update this section based on interactions -->
