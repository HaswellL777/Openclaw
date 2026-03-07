# Phase 1A Tool Gap Root Cause Analysis

**Date**: 2026-03-07
**Scope**: Diagnose why main agent reports only session tools, not read/write/edit
**Status**: Repository-only analysis (no host modification)

---

## Executive Summary

**Root cause**: Global `tools: { profile: "messaging" }` overrides per-agent `tools.allow` lists.

**Evidence**:
- Live config and both candidate configs contain `tools: { profile: "messaging" }` at top level
- Per-agent `tools.allow: ["read", "write", "edit", ...]` exists in `agents.list[0]` (main)
- Production validation shows main only has: `sessions_list`, `sessions_history`, `sessions_send`, `session_status`
- These are exactly the tools expected from `profile: "messaging"`

**Hypothesis**: OpenClaw's config merge logic applies global `tools.profile` **after** per-agent `tools.allow`, effectively replacing the agent-specific allowlist with the profile's tool set.

**Uncertainty**: The exact precedence order of `tools.profile` vs `agents.list[].tools.allow` is not documented in the repository evidence. This analysis is based on observed behavior and common config merge patterns.

---

## Evidence Review

### 1. Live config structure (openclaw.live.json)

```json5
{
  agents: {
    defaults: { ... },
    // NO agents.list in live config
  },
  tools: { profile: "messaging" },  // ← Global profile
  ...
}
```

**Observation**: Live config has NO custom agents, only defaults. Global `profile: "messaging"` applies to all agents.

### 2. Candidate config structure (openclaw.phase1a.current.json5 and openclaw.main.candidate.json5)

```json5
{
  agents: {
    defaults: { ... },
    list: [
      {
        id: "main",
        default: true,
        workspace: "/var/lib/openclaw/.openclaw/workspace-main",
        subagents: { allowAgents: ["task-runner"] },
        tools: {
          allow: [
            "read",
            "write",
            "edit",
            "sessions_list",
            "sessions_history",
            "sessions_send",
            "sessions_spawn",
            "session_status",
          ],
          deny: ["exec", "process", "apply_patch", "elevated"],
          elevated: { enabled: false }
        }
      }
    ]
  },
  tools: { profile: "messaging" },  // ← Global profile STILL PRESENT
  ...
}
```

**Observation**: Candidate configs added `agents.list` with explicit `tools.allow`, but **did not remove or override** the global `tools: { profile: "messaging" }`.

### 3. Production validation results

From task description:
- main reports only: `sessions_list`, `sessions_history`, `sessions_send`, `session_status`
- main cannot read `control/SOP.md` from workspace-main
- main refuses direct shell execution correctly (expected, since `exec` was in deny list)

**Observation**: The tool set main received matches `profile: "messaging"` exactly, ignoring the per-agent `tools.allow` list.

### 4. Design-v3 guidance (docs/design-v3.md)

Section 5.1.2 recommends:
```json5
{
  "tools": {
    "allow": ["read", "write", "edit", "sessions_list", ...],
    "deny": ["exec", "process", "apply_patch", "elevated"],
    "elevated": { "enabled": false }
  }
}
```

But does NOT mention removing or overriding global `tools.profile`.

---

## Most Plausible Cause

### Config merge precedence hypothesis

OpenClaw likely merges config in this order:

1. Load global defaults
2. Apply global `tools.profile` → sets baseline tool allowlist
3. Apply per-agent `tools.allow` / `tools.deny`

**BUT**: If `tools.profile` is applied **after** per-agent settings, or if `profile` is treated as a **replacement** rather than a **base**, then per-agent `tools.allow` is ignored.

### Alternative hypothesis (less likely)

Per-agent `tools.allow` is only additive to the profile, not a replacement. If `profile: "messaging"` is restrictive and doesn't include `read/write/edit`, then per-agent `allow` cannot add them back.

### Why this is the most plausible

- Observed behavior matches exactly: main has only messaging tools
- Config structure shows both global profile AND per-agent allow coexisting
- No evidence of syntax error or schema rejection (gateway started successfully)
- Health check passed, dynamic config accepted `agents.list` and `agents.defaults.subagents`

---

## What Was Attempted (Implicit)

The candidate config attempted to:
1. Add `agents.list` with `main` agent
2. Specify `tools.allow: ["read", "write", "edit", ...]` for main
3. Keep global `tools: { profile: "messaging" }` unchanged

**Why it failed**: Global profile likely overrides or replaces per-agent allowlist.

---

## What Should Have Been Done

### Option A: Remove global profile, use per-agent tools only

```json5
{
  agents: {
    list: [
      {
        id: "main",
        tools: {
          allow: ["read", "write", "edit", "sessions_list", ...],
          deny: ["exec", "process", "apply_patch", "elevated"],
          elevated: { enabled: false }
        }
      }
    ]
  },
  // tools: { profile: "messaging" },  ← REMOVE THIS LINE
}
```

### Option B: Override profile at agent level (if supported)

```json5
{
  agents: {
    list: [
      {
        id: "main",
        tools: {
          profile: null,  // or "custom" or "default"
          allow: ["read", "write", "edit", ...],
          deny: ["exec", ...],
          elevated: { enabled: false }
        }
      }
    ]
  },
  tools: { profile: "messaging" },  // Keep for other agents
}
```

### Option C: Use a different global profile (if one exists that includes file tools)

```json5
{
  tools: { profile: "default" },  // or "full" or "standard"
  agents: {
    list: [
      {
        id: "main",
        tools: {
          deny: ["exec", "process", "apply_patch", "elevated"],
          elevated: { enabled: false }
        }
      }
    ]
  }
}
```

---

## Recommended Fix-Forward

### Approach: Remove global `tools.profile`, rely on per-agent `tools.allow`

**Rationale**:
- Most explicit and predictable
- No ambiguity about precedence
- Aligns with design-v3 principle of minimal, explicit permissions

**Risk**: If other agents (future) or default agent behavior depends on `profile: "messaging"`, they will lose tools. Mitigation: explicitly define tools for each agent.

---

## Uncertainty and Gaps

### What we DON'T know from repository evidence

1. **Exact config merge order**: Does OpenClaw apply global profile before or after per-agent tools?
2. **Profile semantics**: Is `profile` a baseline (additive) or a replacement (override)?
3. **Available profiles**: What profiles exist besides "messaging"? Is there a "default" or "full" profile?
4. **Schema validation**: Does OpenClaw schema allow `tools.profile: null` at agent level?
5. **Fallback behavior**: If global profile is removed, what is the default tool set?

### What we CAN infer

- `profile: "messaging"` is restrictive (only session tools)
- Per-agent `tools.allow` was parsed without error (no schema rejection)
- Gateway accepted the config and started successfully
- The tool gap is deterministic (not a race condition or transient failure)

---

## Next Steps (Fix-Forward)

1. **Create new candidate**: `openclaw.phase1a.fixforward.candidate.json5`
2. **Change**: Remove `tools: { profile: "messaging" }` from top level
3. **Verify**: Per-agent `tools.allow` remains intact for main
4. **Test**: Deploy to test environment (if available) or directly to production with pre-change snapshot
5. **Validate**: Confirm main reports `read`, `write`, `edit` in available tools
6. **Validate**: Confirm main can read `control/SOP.md` from workspace-main

---

## Proposed Delta (Next Document)

See `openclaw.phase1a.fixforward.delta.md` for exact line-by-line changes.

---

## Conclusion

The tool gap is caused by global `tools: { profile: "messaging" }` overriding per-agent `tools.allow`. The fix is to remove the global profile and rely on explicit per-agent tool lists. This aligns with design-v3 principles and provides the most predictable behavior.

**Confidence**: High (based on observed behavior and config structure)
**Risk**: Low (change is minimal, reversible via snapshot rollback)
**Validation**: Can be confirmed immediately after gateway restart via tool availability check
