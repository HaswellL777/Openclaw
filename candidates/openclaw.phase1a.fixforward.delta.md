# Phase 1A Fix-Forward Delta

**Date**: 2026-03-07
**Purpose**: Remove global `tools.profile` to allow per-agent `tools.allow` to take effect
**Target**: `/etc/openclaw/openclaw.json`
**Source**: `candidates/openclaw.phase1a.current.json5` → `candidates/openclaw.phase1a.fixforward.candidate.json5`

---

## Change Summary

**Single change**: Remove line `tools: { profile: "messaging" },` from top-level config.

**Rationale**: Global `tools.profile` overrides per-agent `tools.allow`, preventing main agent from receiving `read`, `write`, `edit` tools.

**Expected outcome**: main agent will receive tools specified in `agents.list[0].tools.allow`.

---

## Exact Delta

### Before (openclaw.phase1a.current.json5, line 233)

```json5
  },
  tools: { profile: "messaging" },
  messages: { ackReactionScope: "group-mentions" },
```

### After (openclaw.phase1a.fixforward.candidate.json5, line 233)

```json5
  },
  messages: { ackReactionScope: "group-mentions" },
```

**Line removed**: `tools: { profile: "messaging" },`

---

## Full Context (Lines 230-240)

### Before

```json5
      },
    ],
  },
  tools: { profile: "messaging" },
  messages: { ackReactionScope: "group-mentions" },
  commands: {
    native: "auto",
    nativeSkills: "auto",
    restart: true,
    ownerDisplay: "raw",
  },
```

### After

```json5
      },
    ],
  },
  messages: { ackReactionScope: "group-mentions" },
  commands: {
    native: "auto",
    nativeSkills: "auto",
    restart: true,
    ownerDisplay: "raw",
  },
```

---

## No Other Changes

All other sections remain identical:
- `gateway` (unchanged)
- `models` (unchanged)
- `agents.defaults` (unchanged)
- `agents.list[0]` (main agent definition, unchanged)
- `channels` (unchanged)
- `plugins` (unchanged)
- `logging` (unchanged)
- `hooks` (unchanged)
- `session` (unchanged)
- `commands` (unchanged)
- `messages` (unchanged)

---

## Validation Plan

### Pre-deployment
1. Create pre-change snapshot: `/.snapshots/root-pre-toolfix-$(date +%F-%H%M)`
2. Run Vault backup: `sudo /usr/local/sbin/vault-backup-root-btrfs`
3. Verify Vault unmounted: `findmnt /mnt/vault` returns empty

### Deployment
1. Copy `candidates/openclaw.phase1a.fixforward.candidate.json5` to `/etc/openclaw/openclaw.json`
2. Verify permissions: `0640 root:openclaw`
3. Restart gateway: `sudo systemctl restart openclaw-gateway.service`

### Post-deployment validation
1. Health check (with retry, SOP 13.2 template)
2. Verify gateway active: `sudo systemctl is-active openclaw-gateway.service`
3. Check logs for errors: `sudo journalctl -u openclaw-gateway.service -n 50 --no-pager`
4. **Critical**: Ask main to list available tools
5. **Critical**: Ask main to read `control/SOP.md`
6. Verify main can write to workspace (test file creation)
7. Verify main still CANNOT execute shell commands (boundary check)
8. Verify Feishu channel reconnected

### Expected tool list for main (after fix)
- `read`
- `write`
- `edit`
- `sessions_list`
- `sessions_history`
- `sessions_send`
- `sessions_spawn`
- `session_status`

### NOT expected (should remain denied)
- `exec`
- `process`
- `apply_patch`
- `elevated`

### Post-validation
1. Create post-change snapshot: `/.snapshots/root-post-toolfix-$(date +%F-%H%M)`
2. Run Vault backup: `sudo /usr/local/sbin/vault-backup-root-btrfs`
3. Update SOP change log (section 15)

---

## Rollback Procedure

If main still lacks `read/write/edit` after this change:

1. Stop gateway: `sudo systemctl stop openclaw-gateway.service`
2. Restore previous config: `sudo cp candidates/openclaw.phase1a.current.json5 /etc/openclaw/openclaw.json`
3. Start gateway: `sudo systemctl start openclaw-gateway.service`
4. Verify health check passes
5. Investigate alternative hypotheses (see tool-gap.md "Alternative hypothesis")

If gateway fails to start:

1. Check logs: `sudo journalctl -u openclaw-gateway.service -n 100 --no-pager`
2. If syntax error: fix and retry
3. If schema error: restore previous config and investigate
4. If unfixable within 5 minutes: restore previous config

If main gains unexpected tools (security boundary violation):

1. **IMMEDIATELY** stop gateway: `sudo systemctl stop openclaw-gateway.service`
2. Restore previous config
3. Investigate why removal of global profile caused over-permissive behavior
4. Do NOT proceed until root cause understood

---

## Risk Assessment

**Likelihood of success**: High
- Change is minimal (one line removal)
- Hypothesis is well-grounded in observed behavior
- Config structure is otherwise unchanged

**Blast radius**: Low
- Only affects tool availability for agents
- Does not affect models, channels, plugins, or gateway core
- Reversible via config restore + restart (no data loss)

**Failure modes**:
1. Main still lacks tools → rollback, investigate alternative fix
2. Gateway fails to start → rollback, fix syntax/schema
3. Main gains too many tools → rollback, investigate profile semantics

**Mitigation**: Pre-change snapshot + Vault backup ensures full rollback capability.

---

## Open Questions (Post-Deployment)

If this fix succeeds, document:
1. Confirmed behavior: global `tools.profile` overrides per-agent `tools.allow`
2. Recommended pattern: always use per-agent `tools.allow`, avoid global profile
3. Update design-v3.md to explicitly warn about global profile precedence

If this fix fails, investigate:
1. Are there other config locations that set tool profiles?
2. Does OpenClaw require a global `tools` section (even if empty)?
3. Is there a schema constraint that requires `tools.profile` or `tools.allow` at top level?
4. Check OpenClaw logs for tool resolution messages (if available)

---

## Approval

**Change type**: Configuration fix (minimal, single-line removal)
**Risk level**: Low
**Reversibility**: Full (snapshot + config backup)
**Validation**: Immediate (tool list check)

**Recommended**: Proceed with deployment during low-traffic window, with operator standing by for rollback if needed.

---

**Next step**: Generate `openclaw.phase1a.fixforward.candidate.json5` with this exact change applied.
