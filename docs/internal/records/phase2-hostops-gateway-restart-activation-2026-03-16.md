# Phase 2 Host-Ops gateway_restart Activation Record — 2026-03-16

> Operator: nick
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-hostops-rollback-prepare-activation-2026-03-16.md`
> Status: **live E2E verified — 2026-03-16**

---

## 1. 当前基线（activation 完成后）

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
| Agent-facing `gateway_restart` | **complete** — live E2E verified（两段式契约：deferred dispatch via systemd-run + operator 独立检查 + gateway_health 验证，12/12 PASS，2026-03-16） |
| 其余 action | **未开放** — `vault_sync` |

---

## 2. 本轮范围

本轮是 post-`rollback_prepare` 的下一切片。`gateway_restart` 是唯一需要契约修正才能安全启用的 action——因 broker systemd `Requires=openclaw-gateway.service` 依赖导致同步 restart 请求的返回值不可靠。

### 2.1 为什么 gateway_restart 需要契约稳定化

三层叠加导致原始 wrapper 的返回契约不可达：

1. **systemd 依赖链**：broker unit 声明 `Requires=openclaw-gateway.service` + `After=openclaw-gateway.service`。gateway restart 时 systemd 按 After= 反向顺序先 SIGTERM broker，再停止 gateway。
2. **wrapper 同步阻塞**：原始 wrapper 使用 `systemctl restart`（同步阻塞），等待 restart 完成后做 post-restart 验证。但 broker 在 restart 过程中被 SIGTERM，wrapper 进程随之死亡，JSON 结果永远无法传回 plugin。
3. **plugin fail-closed**：plugin 对 transport error 返回 `ok:false / Broker transport error`，这对其他 action 正确，但对 gateway_restart 而言 transport error 是成功 restart 的预期后果。

### 2.2 为什么不是 vault_sync

| Action | 不选原因 |
|--------|----------|
| `vault_sync` | Vault receive 路径与 wrapper 代码存在漂移；`incremental` 契约与实现不一致；依赖 Vault 挂载（`noauto`），运行时条件更复杂 |

### 2.3 最终成功路径概述

gateway_restart 经历了三次 live activation 尝试才最终通过 E2E 验收：

1. **第一次（--no-block 方案）**：失败——`systemctl restart --no-block` 的时间窗口被 systemd After= 反向 stop 顺序摧毁，broker 在 wrapper 返回前被 SIGTERM。
2. **第二次（systemd-run deferred dispatch）**：部分失败——正例通过（deferred dispatch 消除了 SIGTERM 竞态），但发现两个问题：(a) systemd-run stdout 输出污染了 wrapper 的 JSON（已通过 stderr 重定向修复），(b) 负例 `reason=12345`（字符串类型）绕过了现有验证并触发了真实 restart side effect。
3. **第三次（input hardening）**：成功——在 plugin `validateActionInputs` 中增加了 trim + minLength 3 + 非纯数字检查，12/12 E2E PASS。

### 2.4 成功语义声明

- `ok: true` / `restart_scheduled: true` **仅表示** restart 已通过 systemd-run transient timer scheduled，将在 ~2 秒后执行
- `ok: true` **不表示** gateway restart 已完成，**不表示** gateway 当前处于 active 状态
- **真正的完成判据**必须同时满足：
  1. dispatch 返回 `restart_scheduled: true`
  2. operator 独立 `systemctl is-active openclaw-gateway.service` + `systemctl is-active openclaw-broker.service` 双服务确认 active
  3. agent `gateway_health` 返回 `ok: true`

---

## 3. Repo commits（全部已 push）

| Commit | Message | Files |
|--------|---------|-------|
| `c07e34b` | `docs(planning): gateway_restart slice design` | `docs/planning/gateway-restart-slice-design-2026-03-16.md` |
| `f2b8083` | `feat(host-ops-tool): enable gateway_restart agent slice` | `plugins/host-ops-tool/index.js`, `broker/wrappers/ocw-gateway-restart.sh`, `scripts/activate-gateway-restart-slice.sh`, `scripts/revert-gateway-restart-slice.sh`, `docs/records/phase2-hostops-gateway-restart-activation-2026-03-16.md`, `workspace-main-template/control/host-ops-api.md` |
| `9a7407f` | `docs(planning): gateway_restart deferred-dispatch redesign` | `docs/planning/gateway-restart-deferred-dispatch-design-2026-03-16.md` |
| `eb35048` | `fix(host-ops-tool): gateway_restart deferred dispatch via systemd-run` | `broker/wrappers/ocw-gateway-restart.sh`, `scripts/activate-gateway-restart-slice.sh`, `workspace-main-template/control/host-ops-api.md`, `plugins/host-ops-tool/index.js` |
| `17149ce` | `fix(host-ops-tool): redirect systemd-run output to stderr in gateway_restart wrapper` | `broker/wrappers/ocw-gateway-restart.sh` |
| `4aa0bfe` | `docs(planning): gateway_restart validation hardening design` | `docs/planning/gateway-restart-validation-hardening-2026-03-16.md` |
| `9eff1bb` | `fix(host-ops-tool): harden gateway_restart reason validation` | `plugins/host-ops-tool/index.js`, `broker/schemas/actions/gateway-restart.schema.json`, `workspace-main-template/control/host-ops-api.md` |

---

## 4. Live activation 历程（三次尝试）

### 4.1 第一次 activation：--no-block 方案（失败）

**方案**：将 wrapper live 路径从 `systemctl restart` 改为 `systemctl restart --no-block`，期望利用 --no-block 立即返回的特性在 broker 被 SIGTERM 前完成响应。

**部署**：使用 activation 脚本完成 plugin + wrapper 双部署。

**E2E 结果**：正例返回 `E_BROKER_INTERNAL`（broker dispatch 子进程退出码 -15，即 SIGTERM）。

**根因**：`--no-block` 的 "立即返回" 仅指 systemctl 命令本身不等待 job 完成就返回，但 systemd PID 1 在毫秒级内就开始处理 restart job 的 stop 阶段。由于 `After=` 定义了启动顺序（gateway 先于 broker 启动），systemd 的 stop 阶段按反序执行（broker 先于 gateway 停止）。因此 broker 进程在 wrapper 还没来得及输出 JSON 之前就被 SIGTERM。

**恢复**：使用 revert 脚本恢复 plugin + wrapper 到 6-action 基线。SHA256 校验通过，gateway_health smoke test 通过。

### 4.2 第二次 activation：systemd-run deferred dispatch（部分失败）

**方案**：将 restart 执行彻底移到 broker cgroup 之外。使用 `systemd-run --on-active=2s` 创建 transient timer unit，延迟 2 秒后在独立 cgroup 中执行 restart。wrapper 职责简化为创建 transient timer unit + 确认创建成功 + 输出 JSON 结果。

**部署**：使用 activation 脚本完成 plugin + wrapper 双部署。

**E2E 结果（部分）**：

- **正例（合法 reason）**：第一次尝试时发现 systemd-run stdout 输出（transient unit 名）混入了 wrapper 的 JSON stdout，导致 broker JSON 解析失败。修复方式：将 systemd-run 的 stdout/stderr 重定向到 stderr（commit `17149ce`）。修复后正例 PASS。
- **负例 `reason=12345`**：未被 fail-closed reject。`"12345"` 作为字符串通过了 `typeof inputs.reason !== "string"` 检查（它确实是 string），也通过了 `!inputs.reason` 检查（非空字符串是 truthy）。请求到达 broker 并触发了真实 restart side effect。

**根因（负例失败）**：现有 `validateActionInputs` 只验证 reason 的类型正确性（是字符串、非空），没有验证语义正确性（是否具备人类可读的操作理由含义）。纯数字 "12345" 通过了类型检查但不是有效的操作理由。

**恢复**：本次未执行 revert（正例已通过，问题仅在输入验证层），直接在 repo 侧实施 input hardening。

### 4.3 第三次 activation：input hardening（成功）

**方案**：在 plugin `validateActionInputs` 的 `gateway_restart` 分支增加语义检查：

```javascript
const trimmed = inputs.reason.trim();
if (trimmed.length < 3) {
  errors.push("gateway_restart reason must be at least 3 non-whitespace characters");
} else if (/^\d+$/.test(trimmed)) {
  errors.push("gateway_restart reason must not be purely numeric");
}
```

同时将 broker schema `gateway-restart.schema.json` 的 `minLength` 从 1 改为 3（契约对齐，plugin 为真相源）。

**部署**：使用 activation 脚本完成 plugin + wrapper + schema 双部署。

**E2E 结果**：**12/12 PASS**（见 §6）。

---

## 5. 是否需要 candidate workflow（修改 /etc/openclaw/openclaw.json）

**不需要。** 原因：
- `host_ops` 已在 `main.tools.allow` 中
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `gateway_restart` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更

---

## 6. E2E 验收结果（2026-03-16，OpenClaw agent session）

> 执行环境：OpenClaw agent (T800 Bot) via Feishu，fresh session
> 12/12 PASS

### 6.1 正例：合法 gateway_restart 请求 — **PASS**

```
host_ops(action: "gateway_restart", inputs: {
  reason: "E2E verification of gateway_restart input hardening"
})
```

结果：
- `ok: true`, `status: "ok"`
- `restart_scheduled: true`
- `delay_seconds: 2`
- `dispatch_method: "systemd-run-transient-timer"`
- `verification_required: true`
- `service_active_after: null`
- message 含 `systemd-run`，不含 "restart succeeded" 或 "已完成重启"

验收点：
- [x] `ok: true` 仅表示 transient timer unit 已创建
- [x] `restart_scheduled: true`（非 `restart_dispatched`）
- [x] `dispatch_method` 为 `"systemd-run-transient-timer"`

### 6.2 正例后续：等待 + operator 独立检查 + agent gateway_health — **PASS**

**Step 1 — 等待 gateway + broker 完成 restart 周期**：等待约 10 秒。

**Step 2 — Operator 独立确认 gateway + broker 均恢复 active**：

```bash
systemctl is-active openclaw-gateway.service   # 结果: active
systemctl is-active openclaw-broker.service     # 结果: active
```

**Step 3 — Agent 调用 gateway_health 验证**：

```
host_ops(action: "gateway_health")
```

结果：`ok: true`, `service_active: "active"`

gateway_health 返回 `ok: true` 同时隐式验证了 broker 的健康（请求通过 broker Unix socket 成功往返）。

### 6.3 负例 1：缺失 reason — **PASS**

```
host_ops(action: "gateway_restart", inputs: {})
```

结果：`status: "error"`，message: "gateway_restart requires inputs.reason (string)"

拒绝层：plugin 侧 `validateActionInputs` → `validateRequest`

### 6.4 负例 2：reason 为空字符串 — **PASS**

```
host_ops(action: "gateway_restart", inputs: { reason: "" })
```

结果：`status: "error"`，message: "gateway_restart requires inputs.reason (string)"

拒绝层：plugin 侧 `validateActionInputs`（`!inputs.reason` 对空字符串为 falsy）

### 6.5 负例 3：reason 为非字符串（数字 12345） — **PASS**

```
host_ops(action: "gateway_restart", inputs: { reason: 12345 })
```

结果：`status: "error"`，message: "gateway_restart requires inputs.reason (string)"

拒绝层：plugin 侧 `validateActionInputs`（`typeof inputs.reason !== "string"`）

### 6.6 负例 4：reason 为纯数字字符串 "12345" — **PASS**

```
host_ops(action: "gateway_restart", inputs: { reason: "12345" })
```

结果：`status: "error"`，message 含 "must not be purely numeric"

拒绝层：plugin 侧 `validateActionInputs`（`/^\d+$/.test(trimmed)`）

**此负例是第二次 activation 的 blocking fail 复现修复验证。**

### 6.7 负例 5：reason 为过短字符串 — **PASS**

```
host_ops(action: "gateway_restart", inputs: { reason: "ab" })
```

结果：`status: "error"`，message 含 "at least 3 non-whitespace characters"

拒绝层：plugin 侧 `validateActionInputs`（`trimmed.length < 3`）

### 6.8 负例 6：vault_sync 不在 action enum 中 — **PASS**

```
host_ops(action: "vault_sync", inputs: { snapshot_name: "test-denied" })
```

结果：gateway 层 schema 校验拒绝 — "action: must be equal to one of the allowed values"

验收点：确认 action enum 恰好为 7 个值（gateway_health, gateway_restart, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, rollback_prepare）且不含 vault_sync。

### 6.9 负例 7：完全未知的 action — **PASS**

```
host_ops(action: "nonexistent_action", inputs: {})
```

结果：gateway 层 schema 校验拒绝 — "action: must be equal to one of the allowed values"

### 6.10 回归：gateway_health — **PASS**

```
host_ops(action: "gateway_health")
```

结果：`ok: true`, `service_active: "active"`

### 6.11 回归：snapshot_pre — **PASS**

```
host_ops(action: "snapshot_pre", inputs: {
  label: "regress-pre-gateway-restart-20260316",
  reason: "regression after gateway_restart activation"
})
```

结果：`ok: true`

### 6.12 回归：snapshot_post — **PASS**

```
host_ops(action: "snapshot_post", inputs: {
  label: "regress-post-gateway-restart-20260316",
  reason: "regression after gateway_restart activation"
})
```

结果：`ok: true`

---

## 7. E2E 观察：负例拒绝层分布

| 负例 | 拒绝层 | 说明 |
|------|--------|------|
| 缺失 reason | plugin 侧 `validateActionInputs` → `validateRequest` | 请求通过 schema，到达 plugin execute，被 request 校验拒绝 |
| reason 空字符串 | plugin 侧 `validateActionInputs` | `!inputs.reason` 对空字符串为 falsy |
| reason 非字符串（12345） | plugin 侧 `validateActionInputs` | `typeof inputs.reason !== "string"` |
| reason 纯数字字符串 | plugin 侧 `validateActionInputs` | `/^\d+$/.test(trimmed)` — 第三次 activation 新增 |
| reason 过短（< 3 字符） | plugin 侧 `validateActionInputs` | `trimmed.length < 3` — 第三次 activation 新增 |
| 未开放 action（vault_sync） | gateway 层 tool schema 校验 | `enum: ENABLED_ACTIONS` 在 tool schema 层拦截 |
| 未知 action | gateway 层 tool schema 校验 | 同上 |

gateway 层 schema 校验和 plugin 侧 `validateRequest` 构成两层防御。gateway 层拦截的负例不会到达 broker。plugin 侧的语义验证（minLength、non-numeric）是 JSON Schema 的补充，覆盖 Schema 难以表达的约束。

---

## 8. Rollback 步骤

### 8.1 首要 rollback：恢复 plugin + wrapper 备份

```bash
sudo bash scripts/revert-gateway-restart-slice.sh <artifacts-dir>
```

效果：回到 6 个 ENABLED_ACTIONS 的基线（gateway_health + validate_openclaw_json_candidate + deploy_openclaw_json_candidate + snapshot_pre + snapshot_post + rollback_prepare），wrapper 恢复为修正前版本。

### 8.2 plugin 文件不在 root snapshot 保护范围

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），不在 root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor。

### 8.3 wrapper 文件在 root snapshot 保护范围内

wrapper 文件位于 `/opt/openclaw/broker/wrappers/`（root filesystem），在 root snapshot 保护范围内。首要 rollback 仍使用 revert 脚本，root snapshot 作为额外锚点。

### 8.4 测试 snapshot 的处理

测试生成的 snapshot 应作为审计痕迹保留，不把"删除测试 snapshot"写进成功定义。

---

## 9. 当前边界声明

- **已完成（live verified）**：`gateway_health`, `validate_openclaw_json_candidate`, `deploy_openclaw_json_candidate`, `snapshot_pre`, `snapshot_post`, `rollback_prepare`, `gateway_restart`
- **已 live verified 的 action 总数**：7 / 8
- **未开放**：`vault_sync`
- 不得将 gateway_restart 的成功写成 host_ops 全量开放（`vault_sync` 仍未开放）
- 不得将 `gateway_restart` 返回的 `ok: true` 写成 "restart 已完成" 或 "gateway 已恢复 active"——`ok: true` 仅表示 restart 已 scheduled
- gateway_restart 的 live verified 完成判据必须同时包含：(1) dispatch 返回 `restart_scheduled: true`，(2) operator 独立 `systemctl is-active` 双服务确认 active，(3) agent `gateway_health` 返回 `ok: true`

---

## 10. Snapshots

| 类型 | 路径 | 时间 | 备注 |
|------|------|------|------|
| Post-change | `/.snapshots/root-post-gateway-restart-slice-20260316-1930` | 2026-03-16 19:30 CST | operator 手动创建，E2E 12/12 PASS 后 |
| E2E 回归产生 | `/.snapshots/root-pre-regress-pre-gateway-restart-20260316` | 2026-03-16 E2E 期间 | snapshot_pre 回归测试产生，审计保留 |
| E2E 回归产生 | `/.snapshots/root-post-regress-post-gateway-restart-20260316` | 2026-03-16 E2E 期间 | snapshot_post 回归测试产生，审计保留 |
