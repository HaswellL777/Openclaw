# gateway_restart — input validation hardening

> 文档类型：**设计 / planning note**
> 创建日期：2026-03-16
> 作者：nick + ClaudeCode
> 前置文档：
>   - `docs/planning/gateway-restart-deferred-dispatch-design-2026-03-16.md`
>   - `docs/records/phase2-hostops-gateway-restart-activation-2026-03-16.md`
> 状态：**repo-side 实施中**

---

## 1. 第二轮 E2E blocking FAIL 摘要

第二轮 live activation 使用了 systemd-run deferred dispatch 方案（替代已失败的 `--no-block`）。wrapper 侧 stderr 重定向修复后，gateway_restart 正例（合法 reason 字符串）通过。

**Blocking FAIL**：负例 `reason=12345` 未被 fail-closed reject，实际触发了真实 restart side effect。

### 1.1 失败机制

当 agent 发送 `reason: "12345"`（字符串类型）时，plugin `validateActionInputs` 的现有检查：

```javascript
case "gateway_restart":
  if (!inputs.reason || typeof inputs.reason !== "string") {
    errors.push("gateway_restart requires inputs.reason (string)");
  }
  break;
```

- `!"12345"` → `false`（非空字符串是 truthy）
- `typeof "12345" !== "string"` → `false`（它确实是 string 类型）
- 两个条件均为 false → 验证通过 → 请求到达 broker → wrapper 执行 → 真实 restart

### 1.2 问题本质

现有检查只验证了 reason 的**类型正确性**（是字符串、非空），没有验证**语义正确性**（是否具备人类可读的操作理由含义）。纯数字 "12345" 通过了类型检查，但不是一个有效的操作理由。

---

## 2. 已证实事实 vs 未证实推断

### 2.1 已证实事实

| 事实 | 来源 |
|------|------|
| `reason: "12345"` 通过 plugin `validateActionInputs` | 代码逻辑分析：`typeof "12345" !== "string"` 为 false |
| 通过后触发了真实 restart | 第二轮 E2E 结果（operator 报告） |
| wrapper + systemd-run 侧正常工作 | 正例通过 |
| 当前 broker schema (`gateway-restart.schema.json`) 只有 `minLength: 1` | 文件内容 |

### 2.2 未证实推断

| 推断 | 说明 |
|------|------|
| 是否存在 gateway/tool schema 层对 reason 的额外类型强制转换 | 未 live 验证，但从 plugin 代码路径分析，`params.inputs.reason` 应保持 agent 发送的原始类型 |
| reason 为纯空白字符串（如 `"   "`）是否也会通过 | 代码分析确认会通过（非空字符串，类型正确），但未在 E2E 中验证 |

---

## 3. 为什么选择 input hardening 而非改 wrapper / systemd

| 替代方案 | 不选原因 |
|----------|----------|
| 修改 wrapper 侧验证 | wrapper 是 bash 脚本，正则验证能力有限；且本轮明确不触碰 wrapper |
| 修改 systemd unit | 超出本轮范围，且 unit 依赖关系与输入验证无关 |
| 修改 broker dispatch 逻辑 | 输入验证应在 plugin 层完成（fail-early），不应依赖 broker 层 |
| 在 gateway tool schema 层加约束 | tool schema 是辅助约束，语义真相源是 plugin `validateActionInputs` |

Plugin `validateActionInputs` 是语义验证的真相源：
1. 它在请求到达 broker 之前执行（fail-early）
2. 它可以表达 JSON Schema 难以表达的语义规则（如"非纯数字"）
3. 其他 action（snapshot_pre/post、rollback_prepare）的 label/reason 约束也在此层实现

---

## 4. 修复方案

### 4.1 Plugin `validateActionInputs` — gateway_restart 分支

保留现有类型检查，增加语义检查：

```javascript
case "gateway_restart":
  if (!inputs.reason || typeof inputs.reason !== "string") {
    errors.push("gateway_restart requires inputs.reason (string)");
  } else {
    const trimmed = inputs.reason.trim();
    if (trimmed.length < 3) {
      errors.push("gateway_restart reason must be at least 3 non-whitespace characters");
    } else if (/^\d+$/.test(trimmed)) {
      errors.push("gateway_restart reason must not be purely numeric");
    }
  }
  break;
```

**新增拒绝条件**：
- trim 后长度不足 3 → reject（错误信息：`gateway_restart reason must be at least 3 non-whitespace characters`）
- trim 后是纯数字 → reject（错误信息：`gateway_restart reason must not be purely numeric`）

**仅限 gateway_restart**，不扩展到 snapshot_pre / snapshot_post / rollback_prepare。

### 4.2 Plugin tool parameters — reason description 更新

在 `reason` 字段的 `description` 中为 gateway_restart 补充约束说明。

### 4.3 Broker schema — 一致性对齐

`broker/schemas/actions/gateway-restart.schema.json` 中：
- `minLength` 从 1 改为 3
- `description` 补充约束说明

**明确**：这只是契约对齐/文档一致性补充。plugin `validateActionInputs` 才是语义真相源。JSON Schema 无法优雅表达"非纯数字"约束。

### 4.4 host-ops-api.md — gateway_restart 输入约束说明更新

补充 reason 的语义约束说明，并明确 `ok: true` 仅表示 restart 已 scheduled。

---

## 5. 不做的事

- 不修改 snapshot_pre / snapshot_post / rollback_prepare 的 reason 约束
- 不修改 wrapper (`ocw-gateway-restart.sh`)
- 不修改 activation / revert 脚本
- 不修改 ENABLED_ACTIONS
- 不修改 plugin execute 逻辑
- 不修改 systemd unit
- 不做 live activation
- 不做 E2E
- 不修改 docs/host-sop.md 或 docs/design-v3.md

---

## 6. 下一轮验收口径

### 6.1 新增负例：reason 为纯数字字符串

```
host_ops(action: "gateway_restart", inputs: { reason: "12345" })
```

期望：`status: "error"`，message 含 `"must not be purely numeric"`

拒绝层：plugin `validateActionInputs`

### 6.2 新增负例：reason 为过短字符串

```
host_ops(action: "gateway_restart", inputs: { reason: "ab" })
```

期望：`status: "error"`，message 含 `"at least 3 non-whitespace characters"`

拒绝层：plugin `validateActionInputs`

### 6.3 新增负例：reason 为纯空白

```
host_ops(action: "gateway_restart", inputs: { reason: "   " })
```

期望：`status: "error"`，message 含 `"at least 3 non-whitespace characters"`

拒绝层：plugin `validateActionInputs`（trim 后长度为 0，不足 3）

### 6.4 保留正例

```
host_ops(action: "gateway_restart", inputs: {
  reason: "E2E verification of gateway_restart input hardening"
})
```

期望：通过验证，到达 broker 正常执行。

### 6.5 保留的其他负例

- reason 缺失 → reject
- reason 为空字符串 → reject
- reason 为非字符串（数字 12345） → reject（typeof check）

### 6.6 回归

- gateway_health / snapshot_pre / snapshot_post / rollback_prepare 不受影响
