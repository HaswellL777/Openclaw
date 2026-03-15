# Phase 2 Plugin Activation & SDK Investigation Record — 2026-03-15

> Operator: nick
> Execution date: 2026-03-15
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-broker-deployment-2026-03-14.md`

---

## 1. Live completed items

### 1.1 Plugin lifecycle activation — COMPLETED

- Deployed updated `index.js` (with `register(api)` default export) and `package.json` (with `openclaw.extensions` field) to `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/`.
- Restarted gateway: `sudo systemctl restart openclaw-gateway`.
- Post-restart: `openclaw-gateway.service` active, `openclaw-broker.service` active.
- The `missing register/activate export` warning has **disappeared** from gateway logs.
- Plugin lifecycle activation is now complete.

### 1.2 Broker remains active

- `openclaw-broker.service` active + enabled (unchanged from 2026-03-14 deployment).
- Verified via `sudo socat` call to `/run/openclaw/broker.sock`:
  - `gateway_health` action returned `ok: true, status: "ok"`.

### 1.3 Permission boundary observation

- `/run/openclaw/broker.sock` permissions: `root:openclaw 660`.
- `nick` is not in the `openclaw` group.
- Direct `socat` call as `nick` results in `Permission denied` — this is expected and correct.
- Requires `sudo socat` for manual testing.

---

## 2. SDK investigation results

### 2.1 api.registerTool confirmed in live SDK

Live SDK version: `openclaw@2026.3.2` installed at `/opt/openclaw/node_modules/openclaw/`.

Read-only investigation of live SDK source confirmed:

| Evidence | File | Line |
|----------|------|------|
| `OpenClawPluginApi.registerTool` method | `.../plugin-sdk/plugins/types.d.ts` | 233 |
| JS implementation of `registerTool` | `.../plugin-sdk/registry-DmSqCQJS.js` | 323-337, 594 |
| `resolvePluginTools` runtime injection | `.../plugin-sdk/reply-DFFRlayb.js` | 65825, 75859-75879 |
| `createOpenClawTools` appends plugin tools | `.../plugin-sdk/reply-DFFRlayb.js` | 75879 |
| Bundled `llm-task` uses identical pattern | `.../extensions/llm-task/index.ts` | `api.registerTool(tool, { optional: true })` |
| `AgentTool` shape: `{name, label, description, parameters, execute}` | `@mariozechner/pi-agent-core/dist/types.d.ts` | 126-129 |
| `optional: true` requires allowlist to make tool visible | `.../plugin-sdk/reply-DFFRlayb.js` | 65864 |

### 2.2 What this means

- The Plugin SDK **does** support plugin-registered agent-callable tools.
- `api.registerTool(tool, { optional: true })` is the correct API.
- `optional: true` means the tool is registered in the plugin registry but only appears in the agent's tool list when the tool name or plugin id is included in `tools.allow` (or equivalent allowlist path).
- The `before_tool_call` hook is **not** the mechanism for registering new tools — it can only intercept/block existing tool calls.

---

## 3. Current boundary (precise)

| Layer | Status |
|-------|--------|
| Broker backend | **deployed** — active + enabled since 2026-03-14 |
| Plugin config registration | **complete** — `host-ops-tool` in `plugins.allow`, gateway accepted |
| Plugin lifecycle activation | **complete** — `register(api)` export active, no warnings |
| Tool registration mechanism | **confirmed** — `api.registerTool(...)` exists in live SDK v2026.3.2 |
| registerTool-based `index.js` | **implemented in dev-repo only** — not yet deployed to live |
| `main.tools.allow` update | **not done** — `host_ops` not in any allowlist |
| Agent-facing activation | **pending** — requires both registerTool deploy + allowlist update |

---

## 4. Rollback information

| Item | Value |
|------|-------|
| Pre-activation backup | `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js.bak-phase2` (backup of pre-register version) |
| Pre-activation backup | `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/package.json.bak-phase2` |
| Root snapshot (from 2026-03-14) | `root-post-phase2-broker-20260314`, ID `310` |

---

## 5. Next steps

### Step 1 (Deployment beat 1): Deploy registerTool version

- Copy updated `index.js` (with `api.registerTool(createHostOpsTool(), { optional: true })`) to live extensions directory.
- Restart gateway.
- Acceptance criteria (externally observable):
  - Gateway starts normally (`systemctl status openclaw-gateway` shows active).
  - No plugin/tool registration errors in gateway logs (no duplicate, conflict, already registered, or tool name collision messages).
  - Agent behavior unchanged (no `host_ops` visible to agent because `main.tools.allow` has not been modified).
- Risk: low, minimal blast radius. Not zero-risk — if tool shape or execute return structure does not match runtime contract, plugin loader or tool registration errors are possible. The acceptance criteria above are the detection mechanism.

### Step 2 (Deployment beat 2): Enable agent-facing via candidate workflow

- Create `/etc/openclaw/openclaw.json` candidate adding `host_ops` to `main.tools.allow` (per-agent allowlist, not global `tools.alsoAllow` — minimum privilege for a host mutation tool).
- Follow validate → deploy candidate workflow.
- Restart gateway.
- Verify: agent can invoke `host_ops(action: "gateway_health")` and receives broker response.
- Rollback: revert candidate, tool disappears from agent tool list, agent behavior restored.
