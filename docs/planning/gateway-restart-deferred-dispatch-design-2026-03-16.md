# gateway_restart — deferred dispatch redesign（systemd-run transient timer）

> 文档类型：**设计 / planning note**
> 创建日期：2026-03-16
> 作者：nick + ClaudeCode
> 前置文档：`docs/planning/gateway-restart-slice-design-2026-03-16.md`（上一轮 --no-block 方案，已失败）
> 前置 record：`docs/records/phase2-hostops-gateway-restart-activation-2026-03-16.md`
> 状态：**repo-side 实施中 — 待 live activation**

---

## 1. 上一轮失败复盘

### 1.1 方案概要

上一轮将 wrapper 的 `systemctl restart openclaw-gateway.service`（同步阻塞）改为 `systemctl restart --no-block openclaw-gateway.service`，期望利用 `--no-block` 立即返回的特性在 broker 被 SIGTERM 前完成响应。

### 1.2 失败现象

live activation 后执行 E2E 正例，plugin 收到 `E_BROKER_INTERNAL`（broker dispatch 子进程退出码 -15，即 SIGTERM）。wrapper 的 JSON 响应未能传回 plugin。

### 1.3 根因分析：`--no-block` 时间窗口被 systemd After= 反向 stop 顺序摧毁

**systemd unit 依赖关系**：

```ini
[Unit]
Description=OpenClaw Host-Ops Broker
After=network.target openclaw-gateway.service
Requires=openclaw-gateway.service
```

**预期时间线（设计假设）**：

```
t0: wrapper 调用 systemctl restart --no-block → systemctl 立即返回
t1: wrapper 输出 JSON 到 stdout（微秒级）
t2: broker 读取 wrapper stdout，写回 Unix socket（微秒级）
t3: plugin 收到响应
...
t_n: systemd 开始执行 restart job（stop gateway → SIGTERM broker → start gateway → start broker）
```

设计假设 t0→t3（微秒级）远小于 t_n 的延迟。

**实际发生的时间线**：

```
t0: wrapper 调用 systemctl restart --no-block → systemctl 立即返回
t0+ε: systemd 将 restart job 入队
t0+ε': systemd 开始处理 restart job：
       1. 发现 Requires=openclaw-gateway.service
       2. 确定 openclaw-broker.service 依赖于 openclaw-gateway.service
       3. 按 After= 反向顺序：先 SIGTERM broker，再停止 gateway
t0+ms: broker 进程收到 SIGTERM
       broker cgroup 内所有子进程（dispatch subprocess + wrapper + jq）同时被 SIGTERM
t1: wrapper 已死（或正在死），JSON 输出中断或丢失
```

**关键发现**：`--no-block` 的 "立即返回" 仅指 `systemctl` 命令本身不等待 job 完成就返回，但 systemd PID 1 在毫秒级内就开始处理 restart job 的 stop 阶段。由于 `After=` 定义了**启动顺序**（gateway 先于 broker 启动），systemd 的 stop 阶段按**反序**执行（broker 先于 gateway 停止）。因此 broker 进程在 wrapper 还没来得及输出 JSON 之前就被 SIGTERM。

### 1.4 为什么 `--no-block` 不可行

`--no-block` 的时间窗口（wrapper 返回 → broker 被 SIGTERM）取决于：
1. systemd job 队列的处理延迟
2. broker cgroup 内的进程层级
3. 系统负载

这不是一个可靠的时间窗口。在测试中，这个窗口为零或接近零——broker 在 wrapper 还在执行时就被 SIGTERM 了。

### 1.5 live 恢复情况

上一轮 activation 失败后已完成 revert：
- live plugin 已 revert 到 6-action 基线（不含 gateway_restart）
- live wrapper 已 revert 到部署前备份版本
- plugin + wrapper SHA256 校验通过
- revert 后 gateway_health smoke test 通过
- 因此下一轮 live activation 必须同时重新部署 plugin + wrapper

---

## 2. 根本修复方案：systemd-run transient timer

### 2.1 核心思路

将 restart 执行彻底移到 broker cgroup 之外。使用 `systemd-run` 创建一个 transient timer unit，延迟 2 秒后执行 `systemctl restart openclaw-gateway.service`。

由于 transient timer unit 和它触发的 service unit 属于独立的 cgroup，不受 broker service stop 顺序影响。wrapper 的职责简化为：

1. 创建 transient timer unit（`systemd-run --on-active=2s`）
2. 确认 `systemd-run` 返回成功（exit code 0 = transient unit 已注册）
3. 输出结构化 JSON 结果（`restart_scheduled: true`）
4. 退出

broker 完整处理完这个请求后，2 秒后 systemd 独立执行 restart。

### 2.2 命令形式

```bash
systemd-run --on-active=2s --timer-property=AccuracySec=100ms \
  --unit=openclaw-gateway-restart-deferred \
  --description="Deferred gateway restart (host-ops broker)" \
  -- systemctl restart openclaw-gateway.service
```

- `--on-active=2s`：2 秒后执行
- `--timer-property=AccuracySec=100ms`：精度 100ms（默认 1min 太粗）
- `--unit=openclaw-gateway-restart-deferred`：明确 unit 名称，便于审计
- `--description`：便于 journalctl 追踪

### 2.3 为什么 2 秒

- 足够 broker 完成响应传递（实际只需毫秒级）
- 不会太长（operator 等待时间）
- 可在 live 验证后微调

### 2.4 systemd-run 返回值语义

**`systemd-run` 返回 exit code 0**：
- 仅表示 transient timer unit 已成功创建并注册到 systemd
- **不表示** gateway restart 已完成
- **不表示** gateway restart 一定会成功
- 后续 timer 触发后的 `systemctl restart` 如果失败，与 wrapper 请求无关

**`systemd-run` 返回非零 exit code**：
- 表示 transient unit 创建失败（如权限不足、unit 名称冲突）
- wrapper 应返回 `E_WRAPPER_FAILED`

### 2.5 完成判据

systemd-run 成功 **仅表示** transient timer/unit 已成功创建。

完成判据仍是三段式：
1. `restart_scheduled: true` — transient timer unit 已创建
2. Operator 独立确认：`systemctl is-active openclaw-gateway.service` + `systemctl is-active openclaw-broker.service` 均为 active
3. Agent `gateway_health` 返回 `ok: true`

Step 1 成功不等于 gateway restart 已完成。Step 2 + Step 3 通过才是完成判据。

---

## 3. Wrapper 修改点

### 3.1 Header 注释更新

- `--no-block two-stage semantic` → `deferred dispatch via systemd-run transient timer`
- 描述 systemd-run 的语义：创建 transient timer unit，2 秒后独立执行 restart

### 3.2 Live 路径

替换：
```bash
# 旧（--no-block，已失败）
systemctl restart --no-block openclaw-gateway.service

# 新（systemd-run deferred dispatch）
systemd-run --on-active=2s --timer-property=AccuracySec=100ms \
  --unit=openclaw-gateway-restart-deferred \
  --description="Deferred gateway restart (host-ops broker)" \
  -- systemctl restart openclaw-gateway.service
```

### 3.3 Artifacts 字段变更

| 旧字段 | 新字段 | 说明 |
|--------|--------|------|
| `restart_dispatched` | `restart_scheduled` | 语义更准确：restart 被调度（而非立即 dispatch） |
| （无） | `delay_seconds` | 值为 `2`，明确延迟时间 |
| （无） | `dispatch_method` | 值为 `"systemd-run-transient-timer"`，明确调度机制 |
| `verification_required` | `verification_required` | 不变，值仍为 `true` |
| `service_active_after` | `service_active_after` | 不变，值仍为 `null` |

### 3.4 Dry-run 路径

同步新字段结构：
- `restart_scheduled: false`
- `delay_seconds: 2`
- `dispatch_method: "systemd-run-transient-timer"`
- `verification_required: true`
- `service_active_after: null`

### 3.5 Message 更新

```
Gateway restart scheduled via systemd-run transient timer (delay=2s).
Restart has NOT been executed yet — it will execute ~2s after this response.
Broker returns before restart occurs due to Requires= dependency.
Call gateway_health after 5-10s to verify.
```

---

## 4. Plugin 修改点（仅 description 文案）

### 4.1 修改内容

- `"--no-block dispatch"` → `"deferred dispatch via systemd-run"`
- `"dispatches restart via --no-block"` → `"schedules restart via systemd-run transient timer"`
- 其他 `--no-block` 相关文案同步更新

### 4.2 不修改的内容

- `ENABLED_ACTIONS` 不变（已含 `gateway_restart`）
- `execute` 逻辑不变
- transport error 处理不变
- `validateActionInputs` 不变

### 4.3 为什么需要重新部署 plugin

live plugin 在上一轮 revert 时已回退到 6-action 基线（不含 `gateway_restart`）。即使本轮 plugin 修改仅是 description 文案，下一轮 live activation 仍必须重新部署 plugin，将 `gateway_restart` 重新暴露给 agent。

不存在 "只部署 wrapper" 的可行路径。activation 脚本已实现 plugin + wrapper 双部署逻辑。

---

## 5. Activation 脚本 preflight 更新

### 5.1 修改点

| 旧 preflight 检查 | 新 preflight 检查 |
|-------------------|-------------------|
| `grep -q '\-\-no-block'` | `grep -q 'systemd-run'` |
| `grep -q 'restart_dispatched'` | `grep -q 'restart_scheduled'` |

### 5.2 不修改的检查

- `grep -q '"gateway_restart"'`（plugin 含 gateway_restart）
- `grep -q 'Gateway restarted successfully'` 否定检查（旧契约不存在）

---

## 6. 验收口径

### 6.1 正例

```
host_ops(action: "gateway_restart", inputs: {
  reason: "E2E verification of gateway_restart deferred dispatch"
})
```

期望：
- `ok: true`, `status: "ok"`
- `restart_scheduled: true`
- `delay_seconds: 2`
- `dispatch_method: "systemd-run-transient-timer"`
- `verification_required: true`
- `service_active_after: null`
- message 含 `systemd-run`，**不含** "restart succeeded" 或 "已完成重启"

**重要**：`ok: true` 仅表示 transient timer unit 已成功创建。不表示 gateway restart 已完成。不表示 gateway 当前处于 active 状态。完成判据是后续 operator systemctl 检查 + agent gateway_health。

### 6.2 正例后续

1. 等待 5-10 秒
2. Operator 独立确认：`systemctl is-active openclaw-gateway.service` + `systemctl is-active openclaw-broker.service`
3. Agent `gateway_health` 返回 `ok: true`, `service_active: "active"`

### 6.3 负例：reason 为非字符串（如 12345）

```
host_ops(action: "gateway_restart", inputs: { reason: 12345 })
```

**必须 fail-closed reject**。可接受的拒绝层：
- **可接受**：gateway/tool schema reject（JSON Schema type check 拒绝非 string）
- **可接受**：plugin `validateActionInputs` reject（`typeof inputs.reason !== "string"`）
- **不可接受**：broker internal error（不应到达 broker）
- **不可接受**：真实执行到 restart（绝对不可接受）

当前实现中，plugin 侧 `validateActionInputs` 会拦截（`typeof inputs.reason !== "string"` → `"gateway_restart requires inputs.reason (string)"`），因此该负例在到达 broker 之前就被拒绝。这是正确的 fail-closed 行为。

### 6.4 其他负例

- 缺失 reason：plugin `validateActionInputs` 拦截
- reason 为空字符串：plugin `validateActionInputs` 拦截（`!inputs.reason` 对空字符串为 falsy）
- vault_sync：gateway schema 拒绝（不在 action enum 中）
- 未知 action：gateway schema 拒绝

### 6.5 回归

- `gateway_health` 返回 `ok: true`
- `snapshot_pre` / `snapshot_post` / `rollback_prepare` 均正常

---

## 7. 与上一轮方案的对比

| 维度 | 上一轮（--no-block） | 本轮（systemd-run） |
|------|---------------------|---------------------|
| 核心机制 | `systemctl restart --no-block`，依赖 "systemd 来不及处理 job" 的时间窗口 | `systemd-run --on-active=2s`，restart 执行在独立 cgroup 中，与 broker 生命周期完全解耦 |
| SIGTERM 竞态 | 存在。systemd job 排队后毫秒内即开始 stop 序列，broker 先于 gateway 被 SIGTERM | 消除。transient timer unit 在 broker cgroup 之外，broker SIGTERM 不影响调度的 restart |
| 时间窗口依赖 | 依赖 wrapper 在 SIGTERM 到达前完成输出（不可靠） | 不依赖时间窗口。2 秒延迟保证 broker 完成响应后才开始 restart |
| 返回语义 | `restart_dispatched: true`（"已提交 job"） | `restart_scheduled: true`（"已调度，将在 ~2s 后执行"） |
| live 验证结果 | 失败（E_BROKER_INTERNAL / -15） | 待验证 |

---

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| `systemd-run` 不可用或版本不支持 | systemd 236+ 支持 `--on-active`，当前系统 systemd 版本应远超此要求；activation 脚本 preflight 可新增版本检查 |
| transient unit 名称冲突（连续快速调用） | wrapper 使用固定 unit 名 `openclaw-gateway-restart-deferred`，如果上一个 timer 还未触发，`systemd-run` 会失败并返回非零，wrapper 正确返回 `E_WRAPPER_FAILED` |
| 2 秒延迟不够（极端负载下 broker 响应慢） | 实际 broker 响应在毫秒级完成，2 秒有充分余量；如需调整可在 live 验证后修改 |
| 调度的 restart 最终失败 | 这与 wrapper 请求语义解耦——wrapper 只负责调度，完成判据由 operator + gateway_health 承担 |

---

## 9. Commit 计划

1. `docs(planning): gateway_restart deferred-dispatch redesign`
   - `docs/planning/gateway-restart-deferred-dispatch-design-2026-03-16.md`（本文档）

2. `fix(host-ops-tool): gateway_restart deferred dispatch via systemd-run`
   - `broker/wrappers/ocw-gateway-restart.sh`（systemd-run 替换 --no-block）
   - `scripts/activate-gateway-restart-slice.sh`（preflight 更新）
   - `workspace-main-template/control/host-ops-api.md`（契约更新）
   - `plugins/host-ops-tool/index.js`（description 文案更新）

3. `docs: complete gateway_restart live E2E verified and sync boundary`（待 E2E 后）
   - activation record 补全
   - `docs/host-sop.md`
   - `docs/design-v3.md`

---

## 10. 未验证事项

- [ ] systemd-run 在当前系统上的可用性
- [ ] `--on-active=2s` 在当前 systemd 版本下的行为
- [ ] transient timer unit 的实际触发延迟
- [ ] broker 响应时间（从 wrapper 输出到 plugin 收到）
- [ ] 连续快速调用时的 unit 名称冲突处理
- [ ] live plugin + wrapper 双部署 + E2E 验证
