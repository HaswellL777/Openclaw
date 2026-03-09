# workspace-main Template

## Purpose
This is the **template source** for the `workspace-main` published artifact.

`workspace-main` is the runtime workspace for the `main` agent in the OpenClaw control plane.

## Key principles
1. This template is the **authoritative source** for workspace-main structure in the development repo.
2. The published artifact at `/var/lib/openclaw/.openclaw/workspace-main/` is a **deployment target**, not the source of truth.
3. The ultimate authoritative source for host facts is `/srv/openclaw-control/docs/host-sop.md`.
4. Changes to workspace-main must be made here first, then published via `scripts/publish-workspace-main.sh`.
5. workspace-main is **not backed by root snapshots** because `/var/lib/openclaw` is a separate btrfs subvolume.
6. workspace-main must be treated as a **repeatable published artifact**, not a stateful runtime source.

## Structure
```
workspace-main/
├── AGENTS.md                    # Agent role and responsibilities
├── IDENTITY.md                  # Agent identity and boundaries
├── SOUL.md                      # Communication style and personality
├── USER.md                      # User context and preferences
├── HEARTBEAT.md                 # Health monitoring procedures
├── TOOLS.md                     # Tool usage guidelines
├── control/                     # Control plane artifacts
│   ├── SOP.md                  # Host SOP (published copy)
│   ├── routing-policy.md       # Routing decision logic
│   ├── approval-policy.md      # Approval requirements
│   ├── allowed-workers.md      # Subagent whitelist
│   ├── host-ops-api.md         # Host operations API contract
│   ├── state/                  # Runtime state (gitignored in live)
│   │   ├── pending-approvals.json
│   │   ├── last-health.md
│   │   ├── last-sop-hash.txt
│   │   └── last-task-index.json
│   └── runbooks/               # Operational runbooks
│       ├── openclaw-config-change.md
│       ├── gateway-restart.md
│       └── rollback.md
├── skills/                      # Skill definitions
│   ├── host-sop/               # Host SOP skill
│   │   └── SKILL.md
│   ├── routing/                # Routing skill
│   │   └── SKILL.md
│   ├── approvals/              # Approvals skill
│   │   └── SKILL.md
│   └── broker/                 # Broker skill (Phase 1B+)
│       └── SKILL.md
├── memory/                      # Optional: long-term memory
└── .gitignore                   # Ignore runtime state
```

## Authority chain
1. `openclaw-dev/docs/host-sop.md` (authoritative host facts in development repo)
2. `openclaw-dev/docs/design-v3.md` (authoritative design in development repo)
3. `openclaw-dev/workspace-main-template/` (development template source)
4. `/var/lib/openclaw/.openclaw/workspace-main/` (runtime published artifact)

## Publishing
Use `scripts/publish-workspace-main.sh` to deploy this template to a target directory.

Default behavior: dry-run mode, does not touch live paths.

```bash
# Dry-run to test deployment
./scripts/publish-workspace-main.sh /tmp/workspace-main-test

# Actually publish to live path
./scripts/publish-workspace-main.sh --apply /var/lib/openclaw/.openclaw/workspace-main
```

## Validation
Use `scripts/check-workspace-main.sh` to validate a deployed workspace-main artifact.

```bash
# Check template in repo
./scripts/check-workspace-main.sh

# Check published artifact
./scripts/check-workspace-main.sh /var/lib/openclaw/.openclaw/workspace-main
```

## Phase 1B status
- [x] Template structure created
- [x] Core control files (AGENTS, IDENTITY, SOUL, USER, HEARTBEAT, TOOLS)
- [x] Control policies (routing, approval, allowed-workers, host-ops-api)
- [x] Control state files (pending-approvals, last-health, last-sop-hash, last-task-index)
- [x] Runbooks (openclaw-config-change, gateway-restart, rollback)
- [x] Skills (host-sop, routing, approvals, broker)
- [ ] SOP.md populated (requires publish-sop.sh)
- [ ] Broker/wrapper integration (Phase 1B later)
- [ ] Live deployment validation (Phase 1B later)
- [ ] task-runner integration (Phase 1B later)

## File categories

### Phase 1A/1B required (must be present and valid)
- AGENTS.md, IDENTITY.md, SOUL.md, USER.md, HEARTBEAT.md, TOOLS.md
- control/SOP.md (must be published from authoritative source)
- control/routing-policy.md
- control/approval-policy.md
- control/allowed-workers.md
- control/host-ops-api.md
- control/state/*.json, control/state/*.txt, control/state/*.md
- control/runbooks/*.md
- skills/*/SKILL.md

### Phase 1B+ (planned, not yet operational)
- skills/broker/SKILL.md (defined but broker not yet deployed)
- control/host-ops-api.md (defined but broker not yet deployed)

### Optional (may be added later)
- BOOT.md (if internal boot flow needed)
- MEMORY.md (if long-term memory needed)
- memory/*.md (if long-term memory used)

## Notes
- This is a development repo artifact
- Host facts come from `openclaw-dev/docs/host-sop.md`
- Design specs come from `openclaw-dev/docs/design-v3.md`
- This template is for building the published artifact only
