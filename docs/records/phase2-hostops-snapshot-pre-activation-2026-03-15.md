# Phase 2 Host-Ops snapshot_pre Activation Record — 2026-03-15

> Operator: nick
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-hostops-deploy-candidate-activation-2026-03-15.md`
> Status: **live E2E verified — 2026-03-16**

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
| 其余 action | **未开放** — `gateway_restart`, `snapshot_post`, `vault_sync`, `rollback_prepare` |

---

## 2. 本轮范围

本轮是 post-`deploy_openclaw_json_candidate` 的下一安全切片。`snapshot_pre` 创建只读 btrfs 快照，不修改任何现有状态。

### 2.1 为什么是 snapshot_pre

- 副作用最小（创建只读快照）
- 成功定义最清晰
- 验收和 rollback 路径最干净
- 代码改动最小（仅加入 ENABLED_ACTIONS + 文案更新）
- 详见 `docs/planning/snapshot-pre-slice-design-2026-03-15.md`

### 2.2 为什么不是 gateway_restart

`gateway_restart` 当前文档已记录返回值/契约语义不稳问题：通过 broker 发送 `gateway_restart` 请求时，因 `Requires=openclaw-gateway.service` 依赖，broker 也会被 SIGTERM 并重启，返回值可能为 `E_BROKER_INTERNAL`。该问题需独立收口后再作为切片候选。

### 2.3 repo-side 代码变更

在 `plugins/host-ops-tool/index.js` 中：

- **`ENABLED_ACTIONS`** 新增 `snapshot_pre`
- **Tool schema enum** 和描述文字更新为包含 snapshot_pre
- **inputs 描述** 更新为包含 snapshot_pre 的 label/reason
- **无其他逻辑变更**：snapshot_pre 的 `validateActionInputs` 分支已在早期 Phase 2 准备中实现（与 snapshot_post 共用 case 分支）
- execute/build/send 通用流程完全可复用

---

## 3. Repo commits

| Commit | Message | Files |
|--------|---------|-------|
| `f990c4b` | `docs(planning): add snapshot_pre slice design and pre-implementation boundary` | `docs/planning/snapshot-pre-slice-design-2026-03-15.md` |
| `ee935f4` | `feat(host-ops-tool): enable snapshot_pre agent slice` | `plugins/host-ops-tool/index.js` |
| `3886d83` | `docs(records): add snapshot_pre activation scaffold` | 本文件 |
| `6517413` | `docs: sync snapshot_pre boundary across authority docs` | `docs/host-sop.md`, `docs/design-v3.md`, `workspace-main-template/control/host-ops-api.md` |
| `(pending)` | `ops: add snapshot_pre slice activation + rollback operator scripts` | `scripts/activate-snapshot-pre-slice.sh`, `scripts/rollback-snapshot-pre-slice.sh`, `.gitignore` |
| `87f57f4` | `ops: add snapshot_pre activation scripts and fix inputs schema` | `scripts/activate-snapshot-pre-slice.sh`, `scripts/rollback-snapshot-pre-slice.sh`, `plugins/host-ops-tool/index.js`, `.gitignore` |
| `3a792b9` | `docs: complete snapshot_pre live E2E verified and sync boundary` | 本文件, `docs/host-sop.md`, `docs/design-v3.md`, `workspace-main-template/control/host-ops-api.md` |

---

## 4. Live plugin sync 步骤（已完成 2026-03-16 09:17 CST）

> 使用 operator 脚本 `scripts/activate-snapshot-pre-slice.sh` 一次性完成全部步骤。
> 脚本记录: `artifacts/phase2/snapshot-pre-live-activation-20260316-0917/`

### 4.1 备份当前 live plugin

```
备份路径: /var/lib/openclaw/host-ops-tool-backups/index.js.bak-pre-snapshot-pre-slice-20260316-0917
备份 SHA256: 99cb34b2907601587f999f08ba24265515da6868fc79bceba3e7919f16ede6d9
```

> 备份放在 extensions 目录之外（`/var/lib/openclaw/host-ops-tool-backups/`），避免 extensions 目录清理或重装时备份丢失。plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），**不在** root snapshot 保护范围内。因此 plugin 文件级备份是首要 rollback anchor，而非根快照。

### 4.2 复制新版 index.js 到 live

```
源文件: /home/nick/projects/openclaw-dev/plugins/host-ops-tool/index.js
目标: /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
部署后 SHA256: 128fab369853a59267333f6c4e637571a386d90cd3fcb56825b81f8384a21771
权限: openclaw:openclaw 644
```

### 4.3 重启 gateway

```
systemctl restart openclaw-gateway.service — 成功
```

### 4.4 验证

- [x] `systemctl is-active openclaw-gateway.service` → `active`
- [x] `systemctl is-active openclaw-broker.service` → `active`
- [x] gateway journal 无 plugin/tool 注册错误
- [x] agent 新 session 后可见 `snapshot_pre` 在 schema enum 中（E2E 确认）

---

## 5. 是否需要 candidate workflow（修改 /etc/openclaw/openclaw.json）

**不需要。** 原因：
- `host_ops` 已在 `main.tools.allow` 中
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `snapshot_pre` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更

---

## 6. E2E 验收结果（2026-03-16，OpenClaw agent session）

> 执行环境：OpenClaw agent (T800 Bot) via Feishu，fresh session
> 7/7 PASS

### 6.1 正例：合法 snapshot_pre 请求 — **PASS**

```
host_ops(action: "snapshot_pre", inputs: {
  label: "e2e-snapshot-pre-20260316",
  reason: "E2E verification of snapshot_pre agent slice"
})
```

结果：`ok: true`, `status: "ok"`, message: "Pre-change snapshot created"
快照路径：`/.snapshots/root-pre-e2e-snapshot-pre-20260316`（审计保留）

### 6.2 正例：gateway_health 仍正常（回归）— **PASS**

```
host_ops(action: "gateway_health")
```

结果：`ok: true`, `status: "ok"`, message: "Gateway health check completed"

### 6.3 正例：validate 回归 — **skipped**

> validate_openclaw_json_candidate 本轮未改动，gateway_health 回归已确认 tool registration pipeline 正常。

### 6.4 正例：deploy 回归 — **skipped**

> deploy_openclaw_json_candidate 本轮未改动，同上。

### 6.5 负例：label 非法字符 — **PASS**

```
host_ops(action: "snapshot_pre", inputs: {
  label: "bad label spaces!",
  reason: "negative test"
})
```

结果：`ok: false`, `status: "error"`, message 包含 "label must be alphanumeric"

### 6.6 负例：缺失 reason — **PASS**

```
host_ops(action: "snapshot_pre", inputs: {
  label: "test-no-reason"
})
```

结果：`ok: false`, `status: "error"`, message 包含 "snapshot_pre requires inputs.reason"

### 6.7 负例：inputs 非 object — **PASS**

```
host_ops(action: "snapshot_pre", inputs: "not-an-object")
```

结果：`ok: false`, `status: "error"`, message 包含 "inputs must be a plain object"

### 6.8 负例：顶层多余参数 — **PASS**

```
host_ops(action: "snapshot_pre", inputs: { label: "test-extra", reason: "test" }, extra_param: "bad")
```

结果：`ok: false`, `status: "error"`, message 包含 "Unknown parameter"

### 6.9 负例：非 enabled action 仍拒绝 — **PASS**

```
host_ops(action: "snapshot_post", inputs: { label: "test-denied", reason: "test" })
```

结果：`ok: false`, `status: "denied"`, message 包含 "not enabled"

---

## 7. Rollback 步骤

### 7.1 首要 rollback：operator 脚本

```bash
sudo bash scripts/rollback-snapshot-pre-slice.sh artifacts/phase2/snapshot-pre-live-activation-20260316-0917
```

脚本自动完成：读取 result.env → 恢复备份 plugin → restart gateway → 验证 health → 写 rollback 结果。

效果：回到仅 `gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` 可用的基线。

### 7.2 plugin 文件不在 root snapshot 保护范围

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），不在 root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor。

### 7.3 测试 snapshot 的处理

测试生成的 snapshot 应作为审计痕迹保留，不把"删除测试 snapshot"写进成功定义。

### 7.4 root snapshot 作为额外锚点

root snapshot 可作为 host 层额外锚点，但不是 plugin rollback 的首要手段。

---

## 8. 当前边界声明

- **已完成（live verified）**：`gateway_health` agent-facing E2E
- **已完成（live verified）**：`validate_openclaw_json_candidate` agent-facing E2E（正例 + 负例）
- **已完成（live verified）**：`deploy_openclaw_json_candidate` agent-facing E2E（Route C，正例 + 负例含 wrapper 侧 + 回归通过）
- **已完成（live verified）**：`snapshot_pre` agent-facing E2E（正例 + 负例 + 回归，2026-03-16）
- **未开放**：`gateway_restart`, `snapshot_post`, `vault_sync`, `rollback_prepare`
- 不得将本轮 snapshot_pre 的成功类推为 snapshot workflow 闭环（snapshot_post 未开放）
- 不得将本轮成功类推为其余 4 个 action 已安全开放
- `gateway_restart` 未作为本轮 slice 的原因是其返回值/契约语义不稳问题，不是因为它没价值

---

## 9. Snapshots

| 类型 | 路径 | 时间 |
|------|------|------|
| Pre-change | `/.snapshots/root-pre-snapshot-pre-slice-20260316-0917` | 2026-03-16 09:17 CST |
| Post-change | `/.snapshots/root-post-snapshot-pre-slice-20260316-0917` | 2026-03-16 09:17 CST |
| Vault sync | `(可选，待 operator 执行)` | |
