# ACP Policy Fix Analysis

> Date: 2026-03-26
> Close-by: 2026-03-27 — CLOSED: fix verified, archive candidate
> Status: fix deployed and verified (2026-03-26). Three-layer fix: allowedAgents removed + claude CLI deployed + acpx-wrapper.sh bypasses env stripping.

---

## 1. Problem Statement

After the Phase 4 maintenance window (2026-03-25), ACP claude-engineer fails with:

> ACP agent "claude-engineer" is not allowed by policy.

Error code: `ACP_SESSION_INIT_FAILED`

## 2. Root Cause

### Source code trace

The ACP agent policy check lives in `pi-embedded-CbCYZxIb.js` (lines 6283-6290):

```javascript
function isAcpAgentAllowedByPolicy(cfg, agentId) {
    const allowed = (cfg.acp?.allowedAgents ?? [])
        .map(entry => normalizeAgentId(entry))
        .filter(Boolean);
    if (allowed.length === 0) return true;  // empty = allow all
    return allowed.includes(normalizeAgentId(agentId));
}

function resolveAcpAgentPolicyError(cfg, agentId) {
    if (isAcpAgentAllowedByPolicy(cfg, agentId)) return null;
    return new AcpRuntimeError(
        "ACP_SESSION_INIT_FAILED",
        `ACP agent "${normalizeAgentId(agentId)}" is not allowed by policy.`
    );
}
```

### Call chain

1. Main agent calls `sessions_spawn(runtime: "acp", agentId: "claude-engineer", task: "...")`
2. `sessions_spawn` tool handler (line 115550): `agentId: requestedAgentId` → `"claude-engineer"`
3. `spawnAcpDirect` (line 114506): `resolveTargetAcpAgentId({ requestedAgentId: "claude-engineer", cfg })`
4. `resolveTargetAcpAgentId` (line 114190-114204): `normalizeOptionalAgentId("claude-engineer")` → `"claude-engineer"` (non-empty, so used directly)
5. Line 114515: `resolveAcpAgentPolicyError(cfg, "claude-engineer")`
6. `isAcpAgentAllowedByPolicy`: `allowedAgents = ["claude"]`, `"claude-engineer" ∉ ["claude"]` → **ERROR**

### Conceptual mismatch

The `acp.allowedAgents` field controls which **ACP harness IDs** are permitted:
- `"claude"` → Claude Code CLI
- `"codex"` → Codex CLI
- `"gemini"` → Gemini CLI
- `"opencode"` → OpenCode
- etc.

These are **NOT** OpenClaw agent IDs (like `"claude-engineer"`, `"task-runner"`).

In `sessions_spawn(runtime: "acp")`, the `agentId` parameter is the ACP harness ID, not the OpenClaw agent ID. This is documented in the system prompt (line 95896-95897):

> "For ACP harness sessions (codex/claudecode/gemini), use sessions_spawn with runtime: "acp" (set agentId unless acp.defaultAgent is configured)."
> "agents_list and subagents apply to OpenClaw sub-agents (runtime: "subagent"); ACP harness ids are controlled by acp.allowedAgents."

### Why main agent used wrong ID

The main agent saw `claude-engineer` in `agents.list` with `runtime.type: "acp"` and logically tried to spawn it by its OpenClaw agent ID. But the ACP spawn path doesn't resolve OpenClaw agent entries — it takes the agentId parameter directly as the ACP harness ID.

The per-agent runtime config (`agents.list[].runtime.acp.agent: "claude"`) is only used in the **agent command runtime path** (line 126587), not in the **sessions_spawn path** (line 114506).

## 3. Fix Options

### Option A: Remove allowedAgents (Recommended)

Remove `acp.allowedAgents` from the config entirely (or set to `[]`).

**Effect**: The empty-array check at line 6285 returns `true` → all ACP harnesses allowed.

**Config change**:
```diff
  acp: {
    enabled: true,
    dispatch: { enabled: true },
    defaultAgent: "claude",
-   allowedAgents: ["claude"],
    maxConcurrentSessions: 2,
```

**Pros**:
- Simplest fix. One line removal.
- `defaultAgent: "claude"` already constrains the default.
- Future ACP harnesses (codex, etc.) would work without config changes.

**Cons**:
- Any ACP harness ID would be accepted. Minimal security concern since only `"claude"` backend is registered.

### Option B: Keep allowedAgents, fix agent prompt

Keep `allowedAgents: ["claude"]` but ensure main agent uses `agentId: "claude"` in sessions_spawn.

**Config change**: None to openclaw.json.

**Workspace change**: Update workspace-main-template to document correct ACP spawn syntax.

**Pros**:
- Explicit allowlist.

**Cons**:
- Fragile — depends on LLM following instructions precisely.
- If any tool or skill mentions "claude-engineer" as a spawn target, it'll fail again.

### Option C: Add "claude-engineer" to allowedAgents

```diff
-   allowedAgents: ["claude"],
+   allowedAgents: ["claude", "claude-engineer"],
```

**Effect**: Both IDs pass the policy check.

**Pros**: Minimal change.

**Cons**:
- Conceptually wrong — "claude-engineer" is not an ACP harness.
- When `agentId: "claude-engineer"` passes policy, `resolveTargetAcpAgentId` returns it as the ACP harness ID, which gets passed to the ACP backend. The backend may not recognize "claude-engineer" as a valid harness.

**NOT recommended** — this would pass the policy check but likely fail at the backend level.

## 4. Recommendation

**Option A** (remove allowedAgents). It's safe because:
1. The ACP backend only has "claude" registered — unknown harness IDs fail at backend level anyway.
2. `defaultAgent: "claude"` means if no agentId is passed, "claude" is used.
3. It eliminates the conceptual mismatch entirely.

Combined with a workspace prompt update to guide main agent to use `agentId: "claude"` for ACP sessions.

## 5. Additional finding: `acp.runtime.permissionMode`

The execution pack deployed `acp.runtime.permissionMode: "approve-all"`, which was rejected by the config schema. This is **correct behavior** — the 2026.3.23-2 schema for `acp.runtime` (in `io-y3Az_Onx.js:5711-5714`) uses `.strict()` and only accepts:
- `ttlMinutes`
- `installCommand`

In 2026.3.22+ core ACP, permissions are controlled by:
1. Claude Code's `~/.claude/settings.json` (already deployed at `/var/lib/openclaw/.claude/settings.json`)
2. The acpx backend's built-in non-interactive permission handling

**No further config change needed** for permissions — the settings.json approach is correct.

## 6. Operator Commands

### Pre-snapshot (if not done recently)
```bash
sudo btrfs subvolume snapshot -r / /.snapshots/root-pre-acp-fix-20260326-$(date +%H%M)
```

### Apply fix
```bash
# Backup current config
sudo cp /etc/openclaw/openclaw.json /etc/openclaw/openclaw.json.bak.$(date +%Y%m%d-%H%M)

# Edit config: remove allowedAgents from acp block
sudo nano /etc/openclaw/openclaw.json
# Find:   allowedAgents: ["claude"],
# Delete that line entirely.
# Also remove acp.runtime.permissionMode if present (schema rejects it).

# Restart gateway
sudo systemctl restart openclaw-gateway

# Verify no schema errors
sudo journalctl -u openclaw-gateway -n 30 --no-pager | grep -i -E "error|warn|acp"
```

### Verify ACP
```bash
# From Feishu, ask main agent:
# "使用 ACP 模式启动一个 Claude Code session，执行简单任务：列出当前目录"
# Or equivalently, the agent should call:
# sessions_spawn(runtime: "acp", agentId: "claude", task: "list current directory")

# Check logs
sudo journalctl -u openclaw-gateway -n 50 --no-pager | grep -i acp
```

### Rollback
```bash
sudo cp /etc/openclaw/openclaw.json.bak.* /etc/openclaw/openclaw.json
sudo systemctl restart openclaw-gateway
```

## 7. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Removing allowedAgents allows any harness ID | Low | Only "claude" backend is registered; unknown IDs fail at backend |
| cwd bug #27627 still exists | Medium | Settings.json allowedDirectories already set; test after fix |
| MotChat proxy SSE compatibility unknown | Medium | Must verify when testing ACP spawn |

## 8. Candidate file

`candidates/openclaw.acp-fix.candidate.json5`
