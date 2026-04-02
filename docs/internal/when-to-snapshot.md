# When to Snapshot

## Core rule
Change the repo only -> usually no host snapshot.
Change the host -> snapshot is required.

## Why
- Root snapshots do **not** include `/var/lib/openclaw`
- `/var/lib/openclaw` is a separate btrfs subvolume
- Rolling back `/` does not roll back OpenClaw runtime data
- Vault is normally offline (`/mnt/vault`, noauto)

## Required snapshot cases
You must do a pre-change snapshot and Vault sync before:
- editing `/etc/openclaw/openclaw.json`
- changing `/etc/openclaw/openclaw.env`
- changing systemd units or drop-ins related to OpenClaw
- upgrading `/opt/openclaw`
- changing snapshot / backup / Vault scripts
- changing broker or wrapper code that will actually execute on host
- changing Docker privilege or host-boundary rules
- any other host-affecting configuration change

You must do a post-change snapshot and Vault sync after:
- the host change is completed
- health validation has passed

## Standard host change sequence
1. pre-change snapshot
2. Vault sync
3. apply host change
4. health validation
5. post-change snapshot
6. Vault sync

## Usually no snapshot needed
These usually do not require a host snapshot:
- editing `~/projects/openclaw-dev/CLAUDE.md`
- editing `.claude/settings.json`
- editing `.claude/agents/*.md`
- editing repo-local docs/scripts/tests
- changing prototypes that are not yet deployed to host runtime paths

## Important caution
Do not describe a root snapshot rollback as if it restores all OpenClaw state.
Root system state and `/var/lib/openclaw` runtime state are separate.

## Operational note
The daily timer is a safety baseline, not a replacement for explicit pre/post change milestones.
