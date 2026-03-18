# gateway_restart — 契约稳定化 + agent-facing 启用切片实施设计

> 文档类型：**设计 / planning note**
> 创建日期：2026-03-16
> 作者：nick + ClaudeCode
> 前置完成：`gateway_health`, `validate_openclaw_json_candidate`, `deploy_openclaw_json_candidate`, `snapshot_pre`, `snapshot_post`, `rollback_prepare` 均已 live E2E verified
> 目标：解决 `gateway_restart` 的返回语义不稳问题，并完成 agent-facing 开放的 repo-side 实施
> 状态：**repo-side 实施完成（2026-03-16）— 待 live activation**
>
> - repo-side：wrapper 契约修正 + plugin 代码 + activation/revert 脚本已提交
> - live-side：待 operator 执行 plugin + wrapper 双部署 + gateway restart + E2E 验收
> - `vault_sync` 仍未 agent-facing 开放
> - gateway_restart 的成功不代表 host_ops 全量开放

---

## 1. 当前真实边界

### 1.1 已 live verified（6 个）

| Action | 类型 | 验证日期 | Evidence |
|--------|------|----------|----------|
| `gateway_health` | 只读 | 2026-03-15 | E2E 成功 |
| `validate_openclaw_json_candidate` | 只读 | 2026-03-15 | E2E 成功（正例 + 负例） |
| `deploy_openclaw_json_candidate` | 写操作 | 2026-03-15 | Route C live E2E verified（正例 + 负例含 wrapper 侧 + 回归通过） |
| `snapshot_pre` | 写操作（创建只读快照） | 2026-03-16 | live E2E verified（正例 + 负例 + 回归通过） |
| `snapshot_post` | 写操作（创建只读快照） | 2026-03-16 | live E2E verified（正例 + 负例 + 回归通过） |
| `rollback_prepare` | 纯只读（验证 snapshot 存在性） | 2026-03-16 | live E2E verified（正例 + 负例含 wrapper 侧 E_FILE_NOT_FOUND + 回归通过） |

### 1.2 仍未开放（2 个）

| Action | 类型 | 当前状态 |
|--------|------|----------|
| `gateway_restart` | 写操作（服务重启） | **本轮 repo-side ready，待 live activation** — 契约已稳定化（`--no-block` 两段式语义） |
| `vault_sync` | 写操作 | 未开放 — Vault receive 路径与 wrapper 代码存在漂移；`incremental` 契约与实现不一致 |

---

## 2. 为什么 gateway_restart 不能原样启用

### 2.1 根因分析

三层叠加导致当前 wrapper 的返回契约不可达：

**第一层 — systemd 依赖链**

```
[Unit]
Description=OpenClaw Host-Ops Broker
After=network.target openclaw-gateway.service
Requires=openclaw-gateway.service
```

`openclaw-broker.service` 声明了 `Requires=openclaw-gateway.service`。当 gateway 被 restart 时，systemd 会对 broker 也发 SIGTERM 并重启（host-sop.md:751-771 记录在案）。

**第二层 — wrapper 同步阻塞 + 不可达的 post-restart 验证**

当前 wrapper live 路径：
1. `systemctl restart openclaw-gateway.service`（同步阻塞，等待 restart 完成）
2. `sleep 2`
3. `systemctl is-active --quiet openclaw-gateway.service`
4. 返回 `"Gateway restarted successfully"` + `service_active_after=active`

但实际执行序列：
1. wrapper 调用 `systemctl restart` → systemd 开始停止 gateway
2. systemd 发现 `Requires=` → SIGTERM broker
3. broker 进程死亡 → Unix socket 连接断开
4. wrapper 进程可能也被杀死（子进程）
5. 步骤 2-4 的代码永远不会执行，或即使执行，结果也无法传回 plugin

**第三层 — plugin 正确的 fail-closed**

plugin 对 transport error 返回 `ok:false / status:error / Broker transport error`。这对其他 action 完全正确，但对 gateway_restart 而言，transport error 是 **成功** restart 的预期后果。

### 2.2 核心矛盾

wrapper 声称在同一请求中验证了 restart 后的 active 状态，但 broker 生命周期保证了 plugin 永远收不到这个返回值。这是一个不可解的自引用矛盾。

---

## 3. 契约稳定化方案：`--no-block` 两段式语义

### 3.1 Wrapper 侧修改

将 live 路径的 `systemctl restart openclaw-gateway.service` 改为 `systemctl restart --no-block openclaw-gateway.service`。

`--no-block` 让 systemctl 立即返回（仅向 systemd 提交重启 job，不等待完成）。这创造了一个可靠的时间窗口：

```
时间线：
t0: wrapper 调用 systemctl restart --no-block → systemctl 立即返回
t1: wrapper 输出 JSON 结果到 stdout（微秒级）
t2: broker 读取 wrapper stdout，写回 Unix socket（微秒级）
t3: plugin 收到响应（微秒级）
...
t_n: systemd 开始执行 restart job（stop gateway → SIGTERM broker → start gateway → start broker）
```

`t0` 到 `t3` 是微秒级操作，`t_n` 涉及 systemd job 排队 + 进程停止 + 启动序列，延迟远大于 `t3 - t0`。因此 wrapper 可以在 broker 被 SIGTERM 前可靠地返回响应。

### 3.2 返回语义

成功返回（`ok: true`）的 artifacts：

```json
{
  "reason": "Post config-deploy restart",
  "restart_dispatched": true,
  "verification_required": true,
  "service_active_after": null,
  "mode": "live"
}
```

- `restart_dispatched: true` — 重启 job 已提交给 systemd
- `verification_required: true` — 本次请求不验证 post-restart 状态
- `service_active_after: null` — 未在本次请求中检查（诚实声明）

message: `"Gateway restart dispatched (--no-block). Broker returns before restart completes due to Requires= dependency. Call gateway_health to verify."`

### 3.3 dry-run 语义

dry-run 返回相同字段结构，`restart_dispatched: false`。

### 3.4 移除的内容

- `sleep 2`（与 `--no-block` 语义冲突）
- post-restart `systemctl is-active` 检查（无法在同一请求中验证）
- `"Gateway restarted successfully"` message（不再声称同次请求已验证）

### 3.5 Plugin 侧修改

- 将 `gateway_restart` 加入 `ENABLED_ACTIONS`（6 → 7）
- 更新 tool description、action enum description、reason description、inputs description
- **不需要**对 transport error 做特殊处理 — `--no-block` 消除了 broker SIGTERM 竞态
- 如果出现极端残余竞态，通用的 `Broker transport error` 仍然是正确的 fail-closed

### 3.6 Agent-facing 两段式使用契约

agent 使用 gateway_restart 的完整流程：

1. `host_ops(action: "gateway_restart", inputs: { reason: "..." })` → 返回 `restart_dispatched: true`
2. 等待 5-10 秒（gateway + broker restart 需要时间）
3. Operator 独立确认：`systemctl is-active openclaw-gateway.service` + `systemctl is-active openclaw-broker.service` 均为 active
4. `host_ops(action: "gateway_health")` → 验证 `service_active: "active"`

**完成判据**：Step 3 + Step 4 均通过。Step 1 的 `ok: true` 仅表示 dispatch 成功，不等于 gateway 已完成重启。

如果 Step 3 或 Step 4 返回失败，agent 应告知 operator 查看 `journalctl -u openclaw-gateway.service`。

### 3.7 残余竞态分析

理论上，如果 systemd 异常快速地执行 restart job（在 wrapper JSON 输出完成之前），broker 仍可能被 SIGTERM。但这需要 systemd 在微秒级内完成 job 排队 → 进程停止序列，实际不可能。即使发生，plugin 返回通用 `Broker transport error`，agent 可以调 `gateway_health` 确认。

### 3.8 为什么不选纯 plugin 侧方案

如果只在 plugin 侧对 gateway_restart 的 transport error 做特殊处理（如返回 "restart may have succeeded"），而不改 wrapper：
- wrapper 仍会同步阻塞 → broker 仍被 SIGTERM → transport error 仍是常态
- plugin 需要区分 "因 restart 导致的 transport error" 和 "真正的 broker 故障"
- 这种区分不可靠，依赖时序猜测
- 不如从根本上消除问题

---

## 4. Plugin 修改点

1. **`ENABLED_ACTIONS`** 新增 `"gateway_restart"`（从 6 扩展到 7）
2. **Header 注释** 更新 action 列表
3. **Tool `description`** 更新为包含 gateway_restart + --no-block 说明
4. **`action` enum `description`** 更新为包含 gateway_restart
5. **`reason` description** 更新为包含 gateway_restart
6. **`inputs` description** 更新为包含 gateway_restart
7. **`hostOpsToolSkeleton` note** 更新为包含 gateway_restart

---

## 5. Wrapper 修改点

1. **Header 注释** 更新状态 + 添加 contract note
2. **Live 路径** `systemctl restart` → `systemctl restart --no-block`
3. **移除** `sleep 2` + post-restart health check
4. **Result artifacts** `service_active_after` → `null`，新增 `restart_dispatched` + `verification_required`
5. **Message** → 两段式说明
6. **Dry-run 路径** 同步新字段结构（`restart_dispatched: false`）

---

## 6. Activation 脚本覆盖 plugin + wrapper 双部署

关键点（与 rollback_prepare activation 脚本同构）：

### 6.1 双部署
- **Plugin 源**：`plugins/host-ops-tool/index.js` → live（openclaw:openclaw 644）
- **Wrapper 源**：`broker/wrappers/ocw-gateway-restart.sh` → live（root:root 755）

### 6.2 Preflight 内容验证
- 验证 repo plugin 含 `"gateway_restart"` 字符串
- 验证 repo wrapper 含 `--no-block` 字符串
- 验证 repo wrapper 含 `restart_dispatched` 字符串
- 验证 repo wrapper **不含** `Gateway restarted successfully`（旧契约已移除）

### 6.3 Pre-change snapshot
- 脚本内部完成
- **不创建 post-change snapshot**（E2E 通过后单独执行）

---

## 7. Revert 脚本覆盖 plugin + wrapper 双恢复

- 从 result.env 读取 plugin 和 wrapper 双备份路径
- 恢复 plugin（openclaw:openclaw 644）
- 恢复 wrapper（root:root 755）
- 重启 gateway，健康检查

---

## 8. 验收口径

### 8.1 正例

```
host_ops(action: "gateway_restart", inputs: {
  reason: "E2E verification of gateway_restart agent slice"
})
```

期望：
- `ok: true`, `status: "ok"`
- `restart_dispatched: true`
- `verification_required: true`
- `service_active_after: null`（诚实：本次请求未验证）
- message 含 `--no-block`，**不含** "restart succeeded" 或 "已完成重启"

**重要**：`ok: true` 仅表示 restart job 已提交给 systemd。不表示 gateway 已完成重启。

### 8.2 正例后续：等待 + operator 独立检查 + agent gateway_health

**Step 1** — 等待 5-10 秒让 gateway + broker 完成 restart 周期。

**Step 2** — Operator 独立确认 gateway + broker 均恢复 active：
```bash
systemctl is-active openclaw-gateway.service   # 期望: active
systemctl is-active openclaw-broker.service     # 期望: active
```

**Step 3** — Agent 调用 gateway_health：
```
host_ops(action: "gateway_health")
```
- 期望 `ok: true`, `service_active: "active"`
- gateway_health 返回成功同时隐式验证了 broker 健康（请求通过 broker Unix socket 成功往返）

**完成判据**：Step 2 的 operator 独立 systemctl 检查 + Step 3 的 agent gateway_health 均通过。仅有 Step 3 不够——operator 必须独立确认 broker service 状态。

### 8.3 负例 1：缺失 reason

```
host_ops(action: "gateway_restart", inputs: {})
```

期望：`status: "error"`（plugin `validateActionInputs` 拦截："gateway_restart requires inputs.reason (string)"）

### 8.4 负例 2：reason 为空字符串

```
host_ops(action: "gateway_restart", inputs: { reason: "" })
```

期望：`status: "error"`（`!inputs.reason` 对空字符串为 falsy → 同上错误信息）

### 8.5 负例 3：reason 为非字符串

```
host_ops(action: "gateway_restart", inputs: { reason: 12345 })
```

期望：`status: "error"`（`typeof inputs.reason !== "string"` → 同上错误信息）

### 8.6 负例 4：vault_sync 不在 action enum 中

```
host_ops(action: "vault_sync", inputs: { snapshot_name: "test-denied" })
```

期望：gateway 层 schema 校验拒绝 — action enum 恰好为 7 个值，不含 vault_sync

### 8.7 负例 5：完全未知的 action

```
host_ops(action: "nonexistent_action", inputs: {})
```

期望：gateway 层 schema 校验拒绝 — "action: must be equal to one of the allowed values"

### 8.8 回归

- `gateway_health` 返回 `ok: true`
- `snapshot_pre` 返回 `ok: true`（含 valid label + reason）
- `snapshot_post` 返回 `ok: true`（含 valid label + reason）
- `rollback_prepare` 返回 `ok: true`（含 valid target_snapshot + reason）

### 8.9 验收表述纪律

- 不得将 `gateway_restart` 返回 `ok: true` 写成 "restart 已完成"——`ok: true` 仅表示 dispatch 成功
- 不得将 `gateway_restart` 成功写成 "host_ops 已完整开放"（`vault_sync` 仍未开放）
- 不得省略 operator 独立 `systemctl is-active` 检查步骤
- 完成判据必须同时包含：agent-side `gateway_health` 通过 + operator-side `systemctl` 双服务 active
- 只能写：`gateway_restart` 已 live E2E verified（两段式契约：dispatch + operator 独立检查 + gateway_health 验证）；`vault_sync` 仍未开放

---

## 9. Rollback 口径

### 9.1 首要 rollback：plugin + wrapper 文件回滚

```bash
sudo bash scripts/revert-gateway-restart-slice.sh <artifacts-dir>
```

效果：回到 `gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` + `snapshot_pre` + `snapshot_post` + `rollback_prepare` 可用的基线（6 个 ENABLED_ACTIONS），wrapper 恢复为修正前版本。

### 9.2 plugin 文件不在 root snapshot 保护范围内

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），不在 root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor。

### 9.3 wrapper 文件在 root snapshot 保护范围内

wrapper 文件位于 `/opt/openclaw/broker/wrappers/`（root filesystem），在 root snapshot 保护范围内。首要 rollback 仍使用 revert 脚本，root snapshot 作为额外锚点。

### 9.4 测试 snapshot 的处理

测试生成的验证结果应作为审计痕迹保留，不把"清理测试产物"写进成功定义。

---

## 10. host-sop.md 漂移标记

在 repo-side 实施过程中发现以下漂移（仅标记，不在本轮修正——应在 live E2E 通过后的边界同步 commit 中统一处理）：

| 位置（host-sop.md 行号） | 当前内容 | 应为 |
|--------------------------|----------|------|
| ~114 | "agent-facing 切片已完成五项"...其余 3 个 | 六项已完成（含 rollback_prepare）...其余 2 个 |
| ~116 | "五项已 live E2E verified，其余 3 个仍未开放" | 六项...其余 2 个 |
| ~162 | "其余 3 个 action（gateway_restart, vault_sync, rollback_prepare）" | 其余 2 个（gateway_restart, vault_sync） |
| ~495 | "agent-facing 切片已完成五项...其余 3 个" | 六项...其余 2 个 |
| ~521 | "五项已完成...其余 3 个 action" | 六项...其余 2 个 |

这些漂移来自 rollback_prepare live E2E 完成后的边界同步未覆盖所有位置。应在下一个边界同步 commit 中统一修正。

---

## 11. Commit 计划

1. `docs(planning): gateway_restart slice design`
   - `docs/planning/gateway-restart-slice-design-2026-03-16.md`

2. `feat(host-ops-tool): enable gateway_restart agent slice`
   - `broker/wrappers/ocw-gateway-restart.sh`（契约修正：--no-block 两段式语义）
   - `plugins/host-ops-tool/index.js`（ENABLED_ACTIONS + description 文案）
   - `scripts/activate-gateway-restart-slice.sh`（新增：plugin + wrapper 双部署）
   - `scripts/revert-gateway-restart-slice.sh`（新增：plugin + wrapper 双恢复）
   - `docs/records/phase2-hostops-gateway-restart-activation-2026-03-16.md`（scaffold）
   - `workspace-main-template/control/host-ops-api.md`（gateway_restart 契约 + 状态更新）

3. `docs: complete gateway_restart live E2E verified and sync boundary`（待 E2E 后）
   - activation record 补全
   - `docs/host-sop.md`（含漂移修正）
   - `docs/design-v3.md`

---

## 12. 未验证事项

- [ ] live plugin sync 尚未执行
- [ ] live wrapper sync 尚未执行
- [ ] live E2E 尚未执行
- [ ] `--no-block` 在当前 systemd 版本下的实际行为尚未 live 验证
- [ ] 两段式时间窗口（wrapper 返回 → systemd 执行 restart）的可靠性尚未 live 验证
- [ ] 残余竞态在生产环境中的概率尚未评估
- [ ] `vault_sync` Vault receive 路径漂移 + incremental 机制问题仍未处理
- [ ] host-sop.md 中 rollback_prepare 相关漂移（§10 标记）仍未修正
