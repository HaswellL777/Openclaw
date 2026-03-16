# Phase 2 Host-Ops gateway_restart Activation Record — 2026-03-16

> Operator: nick
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-hostops-rollback-prepare-activation-2026-03-16.md`
> Status: **repo-side ready — 待 live activation 和 E2E 验收**

---

## 1. 当前基线

| 层级 | 状态 |
|------|------|
| Broker backend | **deployed** — active + enabled |
| Plugin config registration | **complete** |
| Plugin lifecycle activation | **complete** |
| Tool registration (live) | **complete** — `api.registerTool(hostOpsTool, {optional:true})` |
| Agent-facing `gateway_health` | **complete** — E2E 成功 |
| Agent-facing `validate_openclaw_json_candidate` | **complete** — live E2E verified（正例 + 负例） |
| Agent-facing `deploy_openclaw_json_candidate` | **complete** — live E2E verified（Route C，正例 + 负例含 wrapper 侧 + 回归通过） |
| Agent-facing `snapshot_pre` | **complete** — live E2E verified（正例 + 负例 + 回归，2026-03-16） |
| Agent-facing `snapshot_post` | **complete** — live E2E verified（正例 + 负例 + 回归，2026-03-16） |
| Agent-facing `rollback_prepare` | **complete** — live E2E verified（正例 + 负例含 wrapper 侧 E_FILE_NOT_FOUND + 回归，2026-03-16） |
| Agent-facing `gateway_restart` | **repo-side ready** — 待 live activation |
| 其余 action | **未开放** — `vault_sync` |

---

## 2. 本轮范围

本轮是 post-`rollback_prepare` 的下一切片。`gateway_restart` 是唯一需要契约修正才能安全启用的 action——因 broker systemd `Requires=openclaw-gateway.service` 依赖导致同步 restart 请求的返回值不可靠。

### 2.1 契约稳定化方案

- **Wrapper 修正**：`systemctl restart` → `systemctl restart --no-block`
- **语义变更**：从 "同次请求已验证 restart 成功" 变为 "restart job 已 dispatch，需后续 operator 独立 systemctl 检查 + agent gateway_health 验证"
- **完成判据**：dispatch 返回 `ok: true` + operator `systemctl is-active` 双服务 active + agent `gateway_health` 返回 `ok: true`
- **详见** `docs/planning/gateway-restart-slice-design-2026-03-16.md`

### 2.2 为什么不是 vault_sync

| Action | 不选原因 |
|--------|----------|
| `vault_sync` | Vault receive 路径与 wrapper 代码存在漂移；`incremental` 契约与实现不一致；依赖 Vault 挂载（`noauto`），运行时条件更复杂 |

### 2.3 repo-side 代码变更

在 `plugins/host-ops-tool/index.js` 中：

- **`ENABLED_ACTIONS`** 新增 `gateway_restart`（从 6 扩展到 7）
- **Tool description** 更新为包含 gateway_restart + --no-block 说明
- **Action enum description** 更新为包含 gateway_restart
- **`reason` description** 更新为包含 gateway_restart
- **`inputs` description** 更新为包含 gateway_restart

在 `broker/wrappers/ocw-gateway-restart.sh` 中：

- Live 路径改为 `systemctl restart --no-block`
- 移除 `sleep 2` 和 post-restart health check
- 返回 `restart_dispatched: true` / `verification_required: true` / `service_active_after: null`
- message 明确告知需后续 gateway_health 验证

---

## 3. Repo commits

| Commit | Message | Files |
|--------|---------|-------|
| *(待提交)* | `docs(planning): gateway_restart slice design` | `docs/planning/gateway-restart-slice-design-2026-03-16.md` |
| *(待提交)* | `feat(host-ops-tool): enable gateway_restart agent slice` | 见下文 |

---

## 4. Live plugin + wrapper sync 步骤（待执行）

### 4.1 Pre-change root snapshot

```
待执行
```

### 4.2 备份当前 live plugin + wrapper

```
待执行
```

### 4.3 部署新版 plugin + wrapper

```
待执行 — 使用一键脚本：sudo bash scripts/activate-gateway-restart-slice.sh
```

### 4.4 Restart gateway + 验证

- [ ] `systemctl restart openclaw-gateway.service`
- [ ] `systemctl is-active openclaw-gateway.service` → `active`
- [ ] `systemctl is-active openclaw-broker.service` → `active`
- [ ] gateway journal 无 plugin/tool 注册错误
- [ ] agent 新 session 后可见 `gateway_restart` 在 schema enum 中

### 4.5 Activation artifacts

```
待执行
```

---

## 5. 是否需要 candidate workflow（修改 /etc/openclaw/openclaw.json）

**不需要。** 原因：
- `host_ops` 已在 `main.tools.allow` 中
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `gateway_restart` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更

---

## 6. E2E 验收结果（待执行）

> 执行环境：待定
> 待执行

### 6.1 正例：合法 gateway_restart 请求 — **待执行**

```
host_ops(action: "gateway_restart", inputs: {
  reason: "E2E verification of gateway_restart agent slice"
})
```

期望：
- `ok: true`, `status: "ok"`
- `restart_dispatched: true`
- `verification_required: true`
- `service_active_after: null`
- message 含 `--no-block`，**不含** "restart succeeded" 或 "已完成重启"

**重要**：`ok: true` 仅表示 restart job 已提交给 systemd。不表示 gateway 已完成重启，不表示 gateway 当前处于 active 状态。

### 6.2 正例后续：等待 + operator 独立检查 + agent gateway_health — **待执行**

**Step 1 — 等待 gateway + broker 完成 restart 周期**：

等待 5-10 秒。

**Step 2 — Operator 独立确认 gateway + broker 均恢复 active**：

```bash
systemctl is-active openclaw-gateway.service   # 期望: active
systemctl is-active openclaw-broker.service     # 期望: active
```

如果任一不为 active，E2E 不通过，不继续。

**Step 3 — Agent 调用 gateway_health 验证**：

```
host_ops(action: "gateway_health")
```

期望：`ok: true`, `service_active: "active"`

gateway_health 返回 `ok: true` 同时隐式验证了 broker 的健康（请求通过 broker Unix socket 成功往返）。

### 6.3 负例 1：缺失 reason — **待执行**

```
host_ops(action: "gateway_restart", inputs: {})
```

期望：`status: "error"`，message: "gateway_restart requires inputs.reason (string)"

拒绝层：plugin 侧 `validateActionInputs` → `validateRequest`

### 6.4 负例 2：reason 为空字符串 — **待执行**

```
host_ops(action: "gateway_restart", inputs: { reason: "" })
```

期望：`status: "error"`，message: "gateway_restart requires inputs.reason (string)"

拒绝层：plugin 侧 `validateActionInputs`（`!inputs.reason` 对空字符串为 falsy）

### 6.5 负例 3：reason 为非字符串 — **待执行**

```
host_ops(action: "gateway_restart", inputs: { reason: 12345 })
```

期望：`status: "error"`，message: "gateway_restart requires inputs.reason (string)"

拒绝层：plugin 侧 `validateActionInputs`（`typeof inputs.reason !== "string"`）

### 6.6 负例 4：vault_sync 不在 action enum 中 — **待执行**

```
host_ops(action: "vault_sync", inputs: { snapshot_name: "test-denied" })
```

期望：gateway 层 schema 校验拒绝 — "action: must be equal to one of the allowed values"

验收点：确认 action enum 恰好为 7 个值（gateway_health, gateway_restart, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, rollback_prepare）且不含 vault_sync。

### 6.7 负例 5：完全未知的 action — **待执行**

```
host_ops(action: "nonexistent_action", inputs: {})
```

期望：gateway 层 schema 校验拒绝 — "action: must be equal to one of the allowed values"

### 6.8 回归：gateway_health — **待执行**

```
host_ops(action: "gateway_health")
```

期望：`ok: true`, `service_active: "active"`

### 6.9 回归：snapshot_pre — **待执行**

```
host_ops(action: "snapshot_pre", inputs: {
  label: "regress-pre-gateway-restart-20260316",
  reason: "regression after gateway_restart activation"
})
```

期望：`ok: true`

### 6.10 回归：snapshot_post — **待执行**

```
host_ops(action: "snapshot_post", inputs: {
  label: "regress-post-gateway-restart-20260316",
  reason: "regression after gateway_restart activation"
})
```

期望：`ok: true`

### 6.11 回归：rollback_prepare — **待执行**

```
host_ops(action: "rollback_prepare", inputs: {
  target_snapshot: "<已存在的 snapshot 名>",
  reason: "regression after gateway_restart activation"
})
```

期望：`ok: true`, `prepare_only: true`

---

## 7. Rollback 步骤

### 7.1 首要 rollback：恢复 plugin + wrapper 备份

```bash
sudo bash scripts/revert-gateway-restart-slice.sh <artifacts-dir>
```

效果：回到 6 个 ENABLED_ACTIONS 的基线，wrapper 恢复为修正前版本。

### 7.2 plugin 文件不在 root snapshot 保护范围

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），不在 root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor。

### 7.3 wrapper 文件在 root snapshot 保护范围内

wrapper 文件位于 `/opt/openclaw/broker/wrappers/`（root filesystem），在 root snapshot 保护范围内。首要 rollback 仍使用 revert 脚本，root snapshot 作为额外锚点。

---

## 8. 当前边界声明

- **已完成（live verified）**：`gateway_health`, `validate_openclaw_json_candidate`, `deploy_openclaw_json_candidate`, `snapshot_pre`, `snapshot_post`, `rollback_prepare`
- **repo-side ready**：`gateway_restart`（待 live activation + E2E 验收）
- **未开放**：`vault_sync`
- 不得将本轮 repo-side 实施完成写成 live verified
- 不得将 gateway_restart 返回的 `ok: true` 写成 "restart 已完成" 或 "gateway 已恢复 active"——`ok: true` 仅表示 restart job dispatch 成功
- gateway_restart 的 live verified 完成判据必须同时包含：(1) dispatch 返回 `restart_dispatched: true`，(2) operator 独立 `systemctl is-active` 双服务确认 active，(3) agent `gateway_health` 返回 `ok: true`

---

## 9. Snapshots

| 类型 | 路径 | 时间 | 备注 |
|------|------|------|------|
| Pre-change | *(待执行)* | | activation 脚本自动创建 |
