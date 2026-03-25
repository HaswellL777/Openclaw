# Main Agent Memory

> This file is auto-loaded into context at session start.
> Keep it concise — content costs tokens every turn.
> For detailed notes, use `memory/YYYY-MM-DD.md` daily logs.

## System identity
- Hostname: Ubuntu 24.04 LTS / Btrfs / systemd
- OpenClaw version: 2026.3.13
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
- Task-runner: Docker sandbox, v3-full image, openclaw-task-net
- Knowledge: /workspace/knowledge/ via host mount --bind (read-only)
- GPU: RTX 5060 Ti 16GB (vLLM occupying ~14.2GB)

## Operator preferences
<!-- Agent should update this section based on interactions -->
