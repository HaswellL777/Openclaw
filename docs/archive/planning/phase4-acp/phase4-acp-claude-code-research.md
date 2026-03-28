# Phase 4: ACP Claude Code Integration Research

> Date: 2026-03-25
> Close-by: 2026-03-30 (implementation decision) or archive
> Status: research complete, implementation verified (2026-03-26). ACP E2E operational.

---

## 1. Findings per Question

### 1.1 What is `acpx`? How to install it?

**acpx** is a headless CLI client for the Agent Client Protocol (ACP). It provides
a single command surface for orchestrators to talk to coding agents (Claude Code,
Codex, Pi, OpenCode, Gemini CLI, Kimi) over a structured JSON-RPC protocol instead
of PTY scraping. Primary user is another agent, not a human.

**Installation**: Requires Node.js >= 22.12.0.

- Global: `sudo npm install -g acpx@latest`
- npx (ephemeral): `npx acpx`
- Session state persists in `~/.acpx/` regardless of method

**Who needs it**: The `openclaw` system user needs access to acpx because the
gateway spawns ACP sessions. However, OpenClaw 2026.3.13 **bundles acpx as a
plugin** in `extensions/acpx/`. The bundled version is acpx 0.2.0.

**Known issue on 2026.3.13**: After `npm install -g openclaw@2026.3.13`, the
bundled extension's `node_modules` may not be installed. Workaround:
```bash
cd "$(npm root -g)/openclaw/extensions/acpx" && npm install
```
Then restart gateway. Also set `expectedVersion: "any"` if version mismatch
blocks startup (issue #43997).

**Plugin activation**:
```bash
openclaw plugins install @openclaw/acpx    # may already be bundled, skip if so
openclaw config set plugins.entries.acpx.enabled true
openclaw config set acp.defaultAgent "claude"
openclaw gateway restart
```

Sources:
- [acpx GitHub](https://github.com/openclaw/acpx)
- [OpenClaw ACP Agents Docs](https://docs.openclaw.ai/tools/acp-agents)
- [DeepWiki Installation Guide](https://deepwiki.com/openclaw/acpx/1.1-installation-and-quick-start)
- [Issue #43997: version mismatch](https://github.com/openclaw/openclaw/issues/43997)
- [Issue #47543: node_modules not installed after upgrade](https://github.com/openclaw/openclaw/issues/47543)

### 1.2 openclaw.json ACP config structure

The ACP configuration block in `openclaw.json` (JSON5 format):

```json5
{
  // Top-level ACP block
  "acp": {
    "enabled": true,
    "dispatch": { "enabled": true },
    "backend": "acpx",
    "defaultAgent": "claude",
    "allowedAgents": ["claude", "codex", "opencode", "gemini", "kimi"],
    "maxConcurrentSessions": 8,
    "stream": {
      "coalesceIdleMs": 300,
      "maxChunkChars": 1200
    },
    "runtime": {
      "ttlMinutes": 120
    }
  },

  // Plugin entry
  "plugins": {
    "entries": {
      "acpx": {
        "enabled": true,
        "config": {
          "permissionMode": "approve-all",
          "nonInteractivePermissions": "fail",
          "expectedVersion": "any"  // workaround for version mismatch
        }
      }
    }
  },

  // Per-agent ACP runtime config (within agents block)
  "agents": {
    "entries": {
      "claude-engineer": {
        "id": "claude-engineer",
        "runtime": {
          "type": "acp",
          "acp": {
            "agent": "claude",
            "backend": "acpx",
            "mode": "persistent",
            "cwd": "/var/lib/openclaw/task-workspaces"
          }
        }
      }
    }
  }
}
```

Key parameters for `sessions_spawn`:
- `runtime: "acp"` (vs `"subagent"` for native)
- `agentId`: target harness (e.g., `"claude"`)
- `thread`: boolean, for thread-bound routing
- `mode`: `"run"` (default) or `"session"` (requires thread=true)
- `resumeSessionId`: resume existing ACP session
- `runTimeoutSeconds`: abort after N seconds
- `attachments`: NOT supported for ACP runtime (subagent only)

**Critical**: ACP sessions run on the host runtime, NOT in the Docker sandbox.
If the requesting session is sandboxed, ACP spawns are blocked by default.

Sources:
- [OpenClaw ACP Agents Docs](https://docs.openclaw.ai/tools/acp-agents)
- [OpenClaw Configuration Reference](https://openclawx.cloud/en/gateway/configuration-reference)
- [Fossies docs/tools/acp-agents.md](https://fossies.org/linux/openclaw/docs/tools/acp-agents.md)
- [OpenClaw Config Example (Gist)](https://gist.github.com/digitalknk/4169b59d01658e20002a093d544eb391)

### 1.3 Claude Code authentication with MotChat proxy

Claude Code uses two environment variables for custom endpoints:
- `ANTHROPIC_BASE_URL` - the proxy endpoint URL
- `ANTHROPIC_API_KEY` - authentication credential

**For MotChat proxy** (`https://new.motchat.com`):
```bash
export ANTHROPIC_BASE_URL="https://new.motchat.com"
export ANTHROPIC_API_KEY="<motchat-provided-key>"
```

**Proxy requirements**:
- Must speak the Anthropic API format (not OpenAI format)
- Must support Server-Sent Events (SSE) streaming
- Must forward headers: `anthropic-beta`, `anthropic-version`
- Must expose `/v1/messages` and optionally `/v1/messages/count_tokens`

**Known issue**: Fast mode availability check is hardcoded to
`https://api.anthropic.com` and does not respect `ANTHROPIC_BASE_URL`
(issue #29015). In environments where direct `api.anthropic.com` is blocked,
fast mode gets disabled. This may or may not matter for ACP sessions.

**For ACP passthrough**: The openclaw.json `env` block supports `${VAR_NAME}`
substitution at startup. The gateway process environment is inherited by acpx
child processes. So if the gateway's systemd unit has `ANTHROPIC_BASE_URL` and
`ANTHROPIC_API_KEY` in its environment (via `openclaw.env` or the systemd unit
`Environment=` directive), Claude Code sessions spawned via acpx should inherit
them. There is no documented "per-agent env passthrough" feature -- it relies on
process environment inheritance.

**OpenClaw's own Anthropic provider** config also supports `base_url` via
`${ANTHROPIC_BASE_URL}` in the provider block. But this is separate from the
ACP/Claude Code session env.

Sources:
- [Claude Code LLM Gateway Config](https://code.claude.com/docs/en/llm-gateway)
- [Claude Code Issue #216: Custom API Endpoint](https://github.com/anthropics/claude-code/issues/216)
- [Claude Code Issue #29015: Fast mode disabled with ANTHROPIC_BASE_URL](https://github.com/anthropics/claude-code/issues/29015)
- [OpenRouter Claude Code Integration](https://openrouter.ai/docs/guides/guides/claude-code-integration)
- [Custom API Setup Guide 2026](https://ofox.ai/blog/cursor-claude-code-cline-custom-api-setup-2026/)

### 1.4 ACP permissions: `permissionMode` and `nonInteractivePermissions`

ACP sessions are non-interactive (no TTY). The two critical config keys:

| Key | Default | Options | Effect |
|-----|---------|---------|--------|
| `permissionMode` | `approve-reads` | `approve-reads`, `approve-all` | Which operations auto-approve |
| `nonInteractivePermissions` | `fail` | `fail`, `deny` | What happens when a prompt fires |

**Default behavior**: With `approve-reads` + `fail`, any write/exec triggers
`AcpRuntimeError: Permission prompt unavailable in non-interactive mode`.
This is the #1 cause of "ACP session immediately dies" reports.

**Required for engineering work**: `permissionMode: approve-all` is essential.
Otherwise writing files or executing commands fails immediately. This is the
equivalent of `--dangerously-skip-permissions` but scoped to ACP sessions.

**Security implication**: ACP sessions run on the host, not in sandbox.
`approve-all` means Claude Code can write/exec anything the `openclaw` user
can access. This is why the Docker sandbox exists for task-runner -- but ACP
sessions explicitly bypass it.

**Configuration**:
```bash
openclaw config set plugins.entries.acpx.config.permissionMode approve-all
openclaw config set plugins.entries.acpx.config.nonInteractivePermissions fail
openclaw gateway restart
```

Setting `nonInteractivePermissions: "deny"` is a softer alternative -- sessions
degrade gracefully instead of crashing, but writes/execs silently fail.

Sources:
- [OpenClaw ACP Agents Docs](https://docs.openclaw.ai/tools/acp-agents)
- [Big Hat Group: ACP with OpenClaw](https://www.bighatgroup.com/blog/using-acp-with-openclaw-to-prevent-agent-hangs/)
- [Issue #31065: ACP_TURN_FAILED](https://github.com/openclaw/openclaw/issues/31065)

### 1.5 cwd bug #27627

**Status**: Open, labeled `stale` (no fix merged as of research date).

**Bug**: Claude Code ACP sessions always start with `cwd=/` regardless of the
configured workspace path (`agents.defaults.workspace` or per-agent
`runtime.acp.cwd` in openclaw.json). This causes Claude Code's sandbox to
block all file operations to the actual workspace directory.

**Impact**: Even with `permissionMode: approve-all`, Claude Code's internal
path validation rejects writes because its own sandbox thinks the working
directory is `/`, not the workspace.

**Workaround**: Use `node -e 'fs.writeFileSync(...)'` from Bash to bypass
Claude Code's sandbox path validation. Works but defeats the purpose.

**Proposed fix (not yet merged)**: Pass `cwd` from the config to the child
process options when spawning Claude Code sessions. The value is already in
the config -- it just is not used.

**Practical implication**: This bug means ACP Claude Code sessions may need
the cwd manually set or the workspace path added to Claude Code's
`settings.json` allowlist. Test before relying on it in production.

Sources:
- [Issue #27627](https://github.com/openclaw/openclaw/issues/27627)
- [Issue #28786: PTY/raw mode crash](https://github.com/openclaw/openclaw/issues/28786)
- [Issue #30346: agentId=claude ACP_TURN_FAILED](https://github.com/openclaw/openclaw/issues/30346)

### 1.6 Third-party plugin: `13rac1/openclaw-plugin-claude-code`

**What it does**: Executes Claude Code CLI sessions in rootless Podman/Docker
containers. Not ACP -- it provides custom tools (`claude_code_start`,
`claude_code_status`, `claude_code_output`, `claude_code_cancel`, etc.) that
OpenClaw agents call directly.

**Key features**:
- Sessions run in isolated containers (Podman rootless preferred)
- Supports OAuth subscription auth (mounts `~/.claude` into container)
- Supports API key auth
- `--dangerously-skip-permissions` inside the container (contained by Podman)
- Multiple concurrent sessions with resource limits
- `--cap-drop ALL`, memory/CPU/PID limits, tmpfs /tmp with nosuid

**Authentication model**: OAuth subscription tokens are mounted from the host's
`~/.claude` directory. For API key auth, the key is passed as an env var.

**Why Podman over Docker**: Rootless by default. Container escape from rootless
Podman lands in unprivileged user namespace. Docker default = root daemon =
container escape = full root access.

**Limitations**:
- Not ACP protocol -- custom tool interface, no standard sessions_spawn
- OAuth usage may violate Anthropic ToS (January 2026 shutdown + reinstatement)
- Requires separate plugin management outside OpenClaw's native ACP
- No thread binding, no session resume, no prompt queue

Sources:
- [13rac1/openclaw-plugin-claude-code](https://github.com/13rac1/openclaw-plugin-claude-code)
- [README](https://github.com/13rac1/openclaw-plugin-claude-code/blob/main/README.md)

---

## 2. Three Integration Options

### Option A: Official ACP via acpx (Recommended)

**Architecture**: OpenClaw gateway -> acpx plugin -> Claude Code CLI (host process)
Claude Code uses MotChat proxy via `ANTHROPIC_BASE_URL`.

**Setup**:
1. Enable bundled acpx plugin
2. Configure `acp` block in openclaw.json
3. Set `permissionMode: approve-all`
4. Set `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY` in gateway env
5. Define a "claude-engineer" agent with `runtime.type: "acp"`
6. Test with `sessions_spawn(runtime: "acp", agentId: "claude")`

**Pros**:
- Native OpenClaw integration; uses `sessions_spawn`, thread binding, session resume
- Already bundled in 2026.3.13
- Standardized ACP protocol; future-proof for other harnesses
- Claude Code sessions are full-featured (Read, Write, Edit, Bash, etc.)
- MotChat proxy auth is straightforward (env vars)
- No container overhead for the LLM session itself

**Cons**:
- ACP sessions run on host as `openclaw` user, not sandboxed
- cwd bug #27627 is still open -- may need workaround
- Known bugs: #28786 (PTY crash), #30346 (ACP_TURN_FAILED for claude agentId),
  #35861 (exit code 5 on 2026.3.2+)
- `approve-all` permission mode is equivalent to `--dangerously-skip-permissions`
  on the host filesystem
- acpx node_modules install issue after upgrade (issue #47543)
- Security advisories: CVE-2026-27646 (sandbox escape via /acp spawn, fixed in
  2026.3.7; our 2026.3.13 includes the fix)

**Risk mitigations**:
- cwd: Set explicit `cwd` in agent runtime config + add path to Claude Code
  settings.json allowlist
- Security: ACP only runs for `main` agent (not from sandboxed task-runner);
  `openclaw` user has limited filesystem access
- Stability: Test with `expectedVersion: "any"` and latest acpx

### Option B: 13rac1/openclaw-plugin-claude-code (Container-isolated)

**Architecture**: OpenClaw gateway -> plugin tools -> Docker/Podman container
-> Claude Code CLI (container process)

**Setup**:
1. Install plugin from GitHub
2. Configure container runtime (Docker, since Podman is not installed)
3. Build Claude Code container image with Node.js + Claude Code CLI
4. Pass `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY` as container env vars
5. Agent calls `claude_code_start` tool instead of `sessions_spawn`

**Pros**:
- Full container isolation; `--dangerously-skip-permissions` is safe
- Resource limits (memory, CPU, PID)
- Multiple concurrent sessions with workspace isolation
- No cwd bug (container cwd is explicit)
- Failure contained -- bad code stays in container

**Cons**:
- Not ACP protocol -- custom tool interface, no sessions_spawn integration
- No thread binding, no session resume, no prompt queue
- Requires building and maintaining a separate container image
- Requires Podman for proper security (Docker rootless not set up)
- Plugin is community-maintained, not official
- Adds complexity: two different container strategies (task-runner + Claude Code)
- OAuth auth path may violate Anthropic ToS (but we use API key via MotChat, so N/A)

### Option C: Hybrid -- ACP for orchestration, Docker sandbox for execution

**Architecture**: OpenClaw main agent -> ACP Claude Code (host, orchestration)
-> Claude Code spawns commands that run in Docker sandbox via task-runner

**Setup**:
1. Set up Option A (ACP)
2. Configure Claude Code's workspace to be a shared volume with task-runner
3. Claude Code plans and writes code on host; task-runner executes in container
4. Or: Claude Code ACP session delegates heavy execution to task-runner via
   sessions_spawn(runtime: "subagent") from within the ACP session

**Pros**:
- Best of both: ACP protocol benefits + container isolation for execution
- Claude Code does the thinking (file analysis, code generation) on host
- Dangerous operations (build, test, run) go through Docker sandbox
- Leverages existing Phase 3 task-runner infrastructure

**Cons**:
- Most complex to set up and reason about
- Two-hop latency for execution tasks
- Unclear if ACP sessions can spawn sub-agents (protocol limitation)
- More failure modes
- Premature optimization before ACP basics are proven

---

## 3. Recommendation

**Option A (Official ACP via acpx)** is recommended, with the following reasoning:

1. **Already bundled**: 2026.3.13 ships with acpx. No new dependencies to manage.

2. **Protocol alignment**: ACP is where OpenClaw is heading. The `sessions_spawn`
   interface, thread binding, and session management are all ACP-native. Building
   on the official path means less migration work later.

3. **MotChat proxy works cleanly**: `ANTHROPIC_BASE_URL` + `ANTHROPIC_API_KEY` in
   the gateway environment is all that is needed. No OAuth complexity.

4. **Security is acceptable**: The `openclaw` user is already a nologin system user
   with limited filesystem access. ACP sessions inherit its permissions. The
   CVE-2026-27646 sandbox escape is fixed in our version (2026.3.13 > 2026.3.7).
   The `approve-all` permission mode is scoped to what `openclaw` can do, which is
   constrained by Unix permissions.

5. **cwd bug is workable**: Set `cwd` in the agent runtime config and add the
   workspace path to Claude Code's settings.json. If that is not sufficient, the
   `node -e fs.writeFileSync()` workaround exists while waiting for the fix.

6. **Container isolation is already solved**: Phase 3 task-runner provides Docker
   sandbox for dangerous operations. ACP Claude Code handles the "thinking" layer
   (code analysis, generation, review). The task-runner handles "doing" (build,
   test, deploy). This natural separation means we do not need to put Claude Code
   itself in a container.

**Defer Option B** unless ACP proves fundamentally broken in testing. The plugin
adds complexity without protocol benefits.

**Defer Option C** until ACP is proven and there is a concrete need for two-hop
execution that the current architecture does not satisfy.

---

## 4. Draft openclaw.json ACP Config

This is a **candidate patch** for `/etc/openclaw/openclaw.json`. It must go through
the standard escalation path: snapshot -> validate -> deploy -> health check.

```json5
{
  // === ACP block (new, top-level) ===
  "acp": {
    "enabled": true,
    "dispatch": {
      "enabled": true
    },
    "backend": "acpx",
    "defaultAgent": "claude",
    "allowedAgents": ["claude"],
    "maxConcurrentSessions": 2,       // conservative start
    "stream": {
      "coalesceIdleMs": 300,
      "maxChunkChars": 1200
    },
    "runtime": {
      "ttlMinutes": 60                // 1hr session lifetime
    }
  },

  // === Plugin entry (add to existing plugins block) ===
  "plugins": {
    "entries": {
      // ... existing entries ...
      "acpx": {
        "enabled": true,
        "config": {
          "permissionMode": "approve-all",
          "nonInteractivePermissions": "fail",
          "expectedVersion": "any"
        }
      }
    }
  }

  // === Environment (ensure these are in openclaw.env or systemd unit) ===
  // ANTHROPIC_BASE_URL=https://new.motchat.com
  // ANTHROPIC_API_KEY=<motchat-key>
  //
  // These are NOT in openclaw.json. They go in:
  //   /etc/openclaw/openclaw.env  (if gateway reads it)
  //   or systemd unit Environment= / EnvironmentFile=
  //   or ~/.openclaw/.env
}
```

### Environment variable delivery

The gateway systemd unit needs `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY`
in its environment so that child processes (acpx -> Claude Code) inherit them.

**Option 1**: Add to `/etc/openclaw/openclaw.env`:
```
ANTHROPIC_BASE_URL=https://new.motchat.com
ANTHROPIC_API_KEY=<key>
```

**Option 2**: systemd override:
```ini
# /etc/systemd/system/openclaw-gateway.service.d/env.conf
[Service]
Environment=ANTHROPIC_BASE_URL=https://new.motchat.com
Environment=ANTHROPIC_API_KEY=<key>
```

Both require `systemctl daemon-reload && systemctl restart openclaw-gateway`.

---

## 5. Implementation Steps (if operator approves Option A)

1. **Pre-snapshot**: `snapshot_pre` via broker
2. **Verify acpx is bundled**: Check `/opt/openclaw/extensions/acpx/`
3. **Install acpx node_modules** (if missing): `cd extensions/acpx && npm install`
4. **Set env vars**: Add `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY` to gateway env
5. **Prepare config candidate**: Generate openclaw.json candidate with ACP block
6. **Validate candidate**: `validate_openclaw_json_candidate` via broker
7. **Deploy candidate**: `deploy_openclaw_json_candidate` via broker
8. **Restart gateway**: `gateway_restart` via broker
9. **Test ACP spawn**: From Feishu, ask main agent to spawn a Claude Code session
10. **Verify cwd**: Check that the session's working directory is correct
11. **Post-snapshot**: `snapshot_post` via broker
12. **Vault sync**: `vault_sync` via broker

---

## 6. Known Risks and Open Questions

| Risk | Severity | Mitigation |
|------|----------|------------|
| cwd bug #27627 (session starts at /) | Medium | Set cwd in config + Claude Code settings.json allowlist |
| ACP_TURN_FAILED (#30346, #35861) | High | Test on 2026.3.13 first; these bugs were reported on earlier versions |
| approve-all runs on host filesystem | Medium | openclaw user has limited access; broker wraps dangerous ops |
| acpx node_modules missing after install | Low | Manual `npm install` in extensions/acpx |
| MotChat proxy SSE compatibility | Unknown | Must verify MotChat supports Anthropic SSE streaming format |
| Fast mode disabled with custom BASE_URL | Low | Performance impact only; functionality unaffected |

**Open questions**:
1. Does MotChat proxy support Anthropic SSE streaming? (Must verify before implementation)
2. Can the gateway's existing Anthropic provider config coexist with ACP env vars?
   (Different code paths: provider config is for main agent's own model calls;
   ACP env vars are for spawned Claude Code processes)
3. Is `openclaw` user's `~/.claude/` directory set up? Claude Code may need
   `~/.claude/settings.json` for the spawned process. Since `openclaw` is nologin,
   its home is `/var/lib/openclaw` -- check if Claude Code respects `$HOME`.
