---
name: host-sop
description: |
  Provide authoritative host operational facts and procedures. Use when questions involve host configuration, directory structure, safety boundaries, snapshot discipline, or operational status.
---

# Host SOP Skill

## Skill identity
- **Name**: `host-sop`
- **Owner**: `main` agent
- **Purpose**: Provide authoritative host operational facts and procedures

## What this skill does
This skill provides access to the host SOP document, which contains:
- Current host configuration and state
- Prohibited operations (safety boundaries)
- Directory structure and ownership rules
- Snapshot and backup procedures
- Phase status (1A/1B/2/3)
- Known issues and workarounds

## Authority
The authoritative source is `openclaw-dev/docs/host-sop.md` in the development repo.

The runtime copy for main agent is `control/SOP.md` in workspace-main.

This skill should:
1. Reference `control/SOP.md` when answering host-related questions
2. Never invent host facts
3. Never contradict the SOP
4. Escalate to human when SOP is unclear or outdated
5. Track SOP version via `control/state/last-sop-hash.txt`

## Usage patterns
- "What is the current OpenClaw configuration path?"
  → Read control/SOP.md, answer: `/etc/openclaw/openclaw.json`

- "What operations are prohibited on this host?"
  → Read control/SOP.md prohibited operations section, list them

- "What is the current phase status?"
  → Read control/SOP.md, answer: Phase 1A (main bootstrap only)

- "How should I handle snapshot operations?"
  → Read control/SOP.md snapshot procedures, explain workflow

- "Where is the OpenClaw data directory?"
  → Read control/SOP.md, answer: `/var/lib/openclaw` (separate btrfs subvolume)

## SOP version tracking
1. On startup or health check, read `control/SOP.md`
2. Compute SHA256 hash
3. Compare with `control/state/last-sop-hash.txt`
4. If changed:
   - Note in health report
   - Update last-sop-hash.txt
   - Alert human if changes are significant

## When SOP is unclear
If SOP doesn't answer a question or is ambiguous:
1. State what SOP says (or doesn't say)
2. Explain the ambiguity
3. Escalate to human for clarification
4. Do NOT guess or invent facts

## Phase 1B implementation
- Markdown-first: skill definition in this file
- No code execution required
- main agent reads this skill definition
- main agent reads control/SOP.md for facts
- Future: may integrate with broker for live SOP queries

## Safety notes
- This skill is read-only
- It does not modify host state
- It does not execute commands
- It provides information only
- It is the authoritative source for host facts within workspace-main

## Related skills
- `routing`: determines when to use this skill vs others
- `approvals`: determines when human approval is needed based on SOP prohibited list
- `broker`: uses SOP facts to validate host operations (Phase 1B+)

## Example interactions

**User**: "Can I run openclaw onboard as nick?"
**Skill response**: No. This is explicitly prohibited in control/SOP.md. Running openclaw onboard as nick creates user-level config and gateway service, causing split configuration. Use system-level openclaw user only.

**User**: "Where is workspace-main?"
**Skill response**: According to control/SOP.md, workspace-main is at `/var/lib/openclaw/.openclaw/workspace-main/`. It is a published artifact, not backed by root snapshots because /var/lib/openclaw is a separate btrfs subvolume.

**User**: "What's the snapshot workflow?"
**Skill response**: According to control/SOP.md, the workflow is: pre-change snapshot → Vault sync → change → health validation → post-change snapshot → Vault sync. Never skip snapshots for host mutations.
