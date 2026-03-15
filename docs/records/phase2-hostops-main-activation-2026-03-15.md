# Phase 2 Host-Ops Agent-Facing Activation Record — 2026-03-15

> Operator: nick
> Execution date: 2026-03-15
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-plugin-activation-2026-03-15.md`

---

## 1. Live completed items

### 1.1 registerTool 版 plugin 已部署

- 将包含 `api.registerTool(createHostOpsTool(), { optional: true })` 的 `index.js` 部署到 `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/`。
- Gateway 重启后正常加载，无 plugin/tool 注册错误。

### 1.2 `main.tools.allow` 已追加 `host_ops`

- 通过 candidate validate → deploy 工作流，将 `host_ops` 加入 `/etc/openclaw/openclaw.json` 的 `main.tools.allow`。
- 使用 per-agent allowlist（非全局 `tools.alsoAllow`），符合最小权限原则。
- Gateway 重启后 agent 可见 `host_ops` 工具。

### 1.3 Agent-facing `host_ops(action="gateway_health")` E2E 成功

- 机器人成功调用 `host_ops` tool。
- 参数：`action: "gateway_health", inputs: {}`。
- Broker 日志出现来自 openclaw 运行用户的 `gateway_health` 请求。
- Bot 返回结果：`ok: true`, `status: ok`。

### 1.4 Candidate validate / deploy 已成功

- `validate_openclaw_json_candidate` 和 `deploy_openclaw_json_candidate` 两个 broker action 在 live 上执行成功。

### 1.5 Snapshot pre/post 已成功

- `snapshot_pre` 和 `snapshot_post` 两个 broker action 在 live 上执行成功。
- 发现并修复了 wrapper stdout 污染 bug（见下方 §3）。

---

## 2. 证据摘要

| 证据项 | 内容 |
|--------|------|
| Bot 调用参数 | `host_ops(action: "gateway_health", inputs: {})` |
| Bot 返回结果 | `ok: true`, `status: "ok"` |
| Broker 日志 | 收到来自 openclaw 用户的 `gateway_health` 请求并成功响应 |
| Candidate workflow | validate + deploy 均成功 |
| Snapshot | `snapshot_pre` + `snapshot_post` 均成功 |

---

## 3. Wrapper bug 记录

### 3.1 受影响文件

- `broker/wrappers/ocw-snapshot-pre.sh`
- `broker/wrappers/ocw-snapshot-post.sh`

### 3.2 问题根因

两个 wrapper 在 live 模式下执行 `btrfs subvolume snapshot` 时使用了 `2>&1`：

```bash
if ! btrfs subvolume snapshot -r / "$snapshot_path" 2>&1; then
```

`2>&1` 将 stderr 合并到 stdout，但 `btrfs` 命令本身在 stdout 输出进度信息（如 `Create a readonly snapshot of '/' in '/.snapshots/...'`），导致 broker 解析 wrapper stdout 时遇到非 JSON 内容，报错：

```
Wrapper returned invalid JSON on stdout
```

### 3.3 Live 热修内容

将 `2>&1` 改为 `>/dev/null`：

```bash
if ! btrfs subvolume snapshot -r / "$snapshot_path" >/dev/null; then
```

- `>/dev/null` 丢弃 stdout 的 btrfs 进度信息。
- stderr 仍保留，若 btrfs 执行失败，错误信息仍可被日志捕获（wrapper 通过 `set -euo pipefail` + `if !` 捕获退出码）。
- 修复后 `snapshot_pre` 和 `snapshot_post` 均正常返回结构化 JSON。

### 3.4 Repo 同步

本次 commit 将相同修复同步回 repo 中的两个 wrapper 文件。

---

## 4. 当前边界

| Layer | Status |
|-------|--------|
| Broker backend | **deployed** — active + enabled |
| Plugin config registration | **complete** |
| Plugin lifecycle activation | **complete** |
| Tool registration (live) | **complete** — `api.registerTool(hostOpsTool, {optional:true})` |
| Agent-facing `host_ops` | **初始只读切片已完成** — `gateway_health` E2E 成功 |
| 其余 action（gateway_restart, validate/deploy candidate, snapshot, vault_sync, rollback_prepare） | **尚未逐项开放/验收** — broker 端已部署，但 agent 端未逐项测试 |

---

## 5. 后续建议

1. **逐项扩展 action 验收**：当前只有 `gateway_health`（只读）经过完整 agent-facing E2E 验证。其余 7 个 action（含写操作如 `gateway_restart`、`deploy_openclaw_json_candidate`、`snapshot_pre/post`、`vault_sync`、`rollback_prepare`）应逐项测试、逐项开放。
2. **保持最小权限原则**：`host_ops` 工具本身虽然已对 agent 可见，但 broker wrapper 端的 action 权限仍是逐项控制的，不应一次性放开全部高风险 action。
3. **监控 broker 日志**：持续关注 broker 日志中是否有异常调用或非预期 action 请求。
4. **wrapper 测试覆盖**：考虑为 wrapper 添加 dry-run 模式的自动化回归测试，避免类似 stdout 污染问题在未来重新引入。
