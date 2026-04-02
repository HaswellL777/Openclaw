# Phase 2 Host-Ops snapshot_post Activation Record — 2026-03-16

> Operator: nick
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-hostops-snapshot-pre-activation-2026-03-15.md`
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
| Agent-facing `snapshot_post` | **complete** — live E2E verified（正例 + 负例 + 回归，2026-03-16） |
| 其余 action | **未开放** — `gateway_restart`, `vault_sync`, `rollback_prepare` |

---

## 2. 本轮范围

本轮是 post-`snapshot_pre` 的下一安全切片。`snapshot_post` 与 `snapshot_pre` 代码结构高度对称，因此是当前最稳妥的下一 slice。但 `snapshot_pre` 的成功不代表 `snapshot_post` 已被间接验证，`snapshot_post` 必须独立完成 live E2E。

### 2.1 为什么是 snapshot_post

- 与 `snapshot_pre` 代码结构高度对称（wrapper、schema、plugin 校验均同构）
- 副作用最小（创建只读 btrfs 快照）
- 改动面小，风险低
- 详见 `docs/planning/snapshot-post-slice-design-2026-03-16.md`

### 2.2 为什么不是其他 3 个

| Action | 不选原因 |
|--------|----------|
| `gateway_restart` | 返回语义不稳，依赖链根因待独立复核 |
| `vault_sync` | Vault receive 路径与 wrapper 漂移；`incremental` 契约与实现不一致 |
| `rollback_prepare` | `rollback_steps` 输出语义过强，超出当前已验证恢复边界 |

### 2.3 repo-side 代码变更

在 `plugins/host-ops-tool/index.js` 中：

- **`ENABLED_ACTIONS`** 新增 `snapshot_post`
- **Tool schema enum** 和描述文字更新为包含 snapshot_post
- **inputs 描述** 更新为包含 snapshot_post 的 label/reason
- **无逻辑变更**：snapshot_post 的 `validateActionInputs` 分支已在早期 Phase 2 准备中实现（与 snapshot_pre 共用 case 分支）

---

## 3. Repo commits

| Commit | Message | Files |
|--------|---------|-------|
| `43f02ff` | `feat(host-ops-tool): enable snapshot_post agent slice` | `plugins/host-ops-tool/index.js`, `scripts/activate-snapshot-post-slice.sh`, `scripts/rollback-snapshot-post-slice.sh`, `docs/planning/snapshot-post-slice-design-2026-03-16.md` |

---

## 4. Live plugin sync 步骤（已执行，2026-03-16 11:22 CST）

> 手动逐步执行（未使用一键脚本）。

### 4.1 Pre-change root snapshot

```
/.snapshots/root-pre-snapshot-post-slice-20260316-1122
```

### 4.2 备份当前 live plugin

```bash
sudo cp /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js \
        /var/lib/openclaw/host-ops-tool-backups/index.js.backup-before-snapshot-post-slice-20260316-1122
```

### 4.3 部署新版 plugin

```bash
sudo cp /home/nick/projects/openclaw-dev/plugins/host-ops-tool/index.js \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
```

### 4.4 Restart gateway + 验证

- [x] `systemctl restart openclaw-gateway.service`
- [x] `systemctl is-active openclaw-gateway.service` → `active`
- [x] `systemctl is-active openclaw-broker.service` → `active`
- [x] gateway journal 无 plugin/tool 注册错误（hooks 正常加载，feishu WebSocket 已连接）
- [x] agent 新 session 后可见 `snapshot_post` 在 schema enum 中（E2E 确认，见 §6）

### 4.5 Post-change root snapshot

```
/.snapshots/root-post-snapshot-post-slice-20260316-1123
```

---

## 5. 是否需要 candidate workflow（修改 /etc/openclaw/openclaw.json）

**不需要。** 原因：
- `host_ops` 已在 `main.tools.allow` 中
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `snapshot_post` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更

---

## 6. E2E 验收结果（2026-03-16，OpenClaw agent session）

> 执行环境：OpenClaw agent (T800 Bot) via Feishu，fresh session
> 8/8 PASS

### 6.1 正例：合法 snapshot_post 请求 — **PASS**

```
host_ops(action: "snapshot_post", inputs: {
  label: "e2e-snapshot-post-20260316",
  reason: "E2E verification of snapshot_post agent slice"
})
```

结果：
```json
{
  "ok": true,
  "action": "snapshot_post",
  "request_id": "req-20260316032705-31g0cl",
  "task_id": "task-20260316032705-31g0cl",
  "status": "ok",
  "message": "Post-change snapshot created",
  "artifacts": {
    "snapshot_name": "root-post-e2e-snapshot-post-20260316",
    "label": "e2e-snapshot-post-20260316",
    "reason": "E2E verification of snapshot_post agent slice",
    "snapshot_path": "/.snapshots/root-post-e2e-snapshot-post-20260316",
    "mode": "live"
  },
  "rollback_hint": "Delete snapshot: btrfs subvolume delete /.snapshots/root-post-e2e-snapshot-post-20260316"
}
```

快照路径：`/.snapshots/root-post-e2e-snapshot-post-20260316`（审计保留）

### 6.2 负例：非法 label — **PASS**

```
host_ops(action: "snapshot_post", inputs: { label: "bad label spaces!", reason: "negative test" })
```

结果：`ok: false`, `status: "error"`, message: "Request validation failed: label must be alphanumeric with dots, hyphens, underscores only"

### 6.3 负例：缺失 reason — **PASS**

```
host_ops(action: "snapshot_post", inputs: { label: "test-no-reason" })
```

结果：`ok: false`, `status: "error"`, message: "Request validation failed: snapshot_post requires inputs.reason (string)"

### 6.4 负例：inputs 非 object — **PASS**

```
host_ops(action: "snapshot_post", inputs: "not-an-object")
```

结果：gateway 层 schema 校验拒绝 — "Validation failed for tool \"host_ops\": inputs: must be object"

### 6.5 负例：顶层多余参数 — **PASS**

```
host_ops(action: "snapshot_post", inputs: { label: "test-extra", reason: "test" }, extra_param: "bad")
```

结果：gateway 层 schema 校验拒绝 — "Validation failed for tool \"host_ops\": root: must NOT have additional properties"

### 6.6 负例：非 enabled action 仍拒绝 — **PASS**

```
host_ops(action: "vault_sync", inputs: { snapshot_name: "test-denied" })
```

结果：gateway 层 schema 校验拒绝 — "Validation failed for tool \"host_ops\": action: must be equal to one of the allowed values"

### 6.7 回归：gateway_health — **PASS**

```
host_ops(action: "gateway_health")
```

结果：
```json
{
  "ok": true,
  "action": "gateway_health",
  "request_id": "req-20260316032802-eyw5a1",
  "task_id": "task-20260316032802-eyw5a1",
  "status": "ok",
  "message": "Gateway health check completed",
  "artifacts": { "service_active": "active", "health_endpoint": null, "mode": "live" },
  "rollback_hint": "No rollback needed for health check"
}
```

### 6.8 回归：snapshot_pre — **PASS**

```
host_ops(action: "snapshot_pre", inputs: {
  label: "regress-pre-20260316",
  reason: "regression after snapshot_post activation"
})
```

结果：
```json
{
  "ok": true,
  "action": "snapshot_pre",
  "request_id": "req-20260316032814-uybruo",
  "task_id": "task-20260316032814-uybruo",
  "status": "ok",
  "message": "Pre-change snapshot created",
  "artifacts": {
    "snapshot_name": "root-pre-regress-pre-20260316",
    "label": "regress-pre-20260316",
    "reason": "regression after snapshot_post activation",
    "snapshot_path": "/.snapshots/root-pre-regress-pre-20260316",
    "mode": "live"
  },
  "rollback_hint": "Delete snapshot: btrfs subvolume delete /.snapshots/root-pre-regress-pre-20260316"
}
```

---

## 7. E2E 观察：负例拒绝层分布

| 负例 | 拒绝层 | 说明 |
|------|--------|------|
| 非法 label | plugin 侧 `validateActionInputs` → `validateRequest` | 请求通过 schema，到达 plugin execute，被 request 校验拒绝 |
| 缺失 reason | plugin 侧 `validateActionInputs` → `validateRequest` | 同上 |
| inputs 非 object | gateway 层 tool schema 校验 | `inputs: { type: "object" }` 在 tool schema 层拦截 |
| 顶层多余参数 | gateway 层 tool schema 校验 | `additionalProperties: false` 在 tool schema 层拦截 |
| 未开放 action | gateway 层 tool schema 校验 | `enum: ENABLED_ACTIONS` 在 tool schema 层拦截 |

gateway 层 schema 校验和 plugin 侧 `validateRequest` 构成两层防御。gateway 层拦截的负例不会到达 broker。

---

## 8. Rollback 步骤

### 8.1 首要 rollback：恢复 plugin 备份

```bash
sudo cp /var/lib/openclaw/host-ops-tool-backups/index.js.backup-before-snapshot-post-slice-20260316-1122 \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo systemctl restart openclaw-gateway.service
```

效果：回到 `gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` + `snapshot_pre` 可用的基线。

### 8.2 plugin 文件不在 root snapshot 保护范围

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），不在 root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor。

### 8.3 测试 snapshot 的处理

测试生成的 snapshot 应作为审计痕迹保留，不把"删除测试 snapshot"写进成功定义。

### 8.4 root snapshot 作为额外锚点

root snapshot 可作为 host 层额外锚点，但不是 plugin rollback 的首要手段。

---

## 9. 当前边界声明

- **已完成（live verified）**：`gateway_health` agent-facing E2E
- **已完成（live verified）**：`validate_openclaw_json_candidate` agent-facing E2E（正例 + 负例）
- **已完成（live verified）**：`deploy_openclaw_json_candidate` agent-facing E2E（Route C，正例 + 负例含 wrapper 侧 + 回归通过）
- **已完成（live verified）**：`snapshot_pre` agent-facing E2E（正例 + 负例 + 回归，2026-03-16）
- **已完成（live verified）**：`snapshot_post` agent-facing E2E（正例 + 负例 + 回归，2026-03-16）
- **未开放**：`gateway_restart`, `vault_sync`, `rollback_prepare`
- 不得将本轮 snapshot_post 的成功类推为 host_ops 全量开放
- 不得将本轮成功写成 snapshot workflow 完整闭环（vault_sync 未开放）
- `gateway_restart` 未作为本轮 slice 的原因是其返回语义不稳，依赖链根因待独立复核

---

## 10. Snapshots

| 类型 | 路径 | 时间 | 备注 |
|------|------|------|------|
| Pre-change | `/.snapshots/root-pre-snapshot-post-slice-20260316-1122` | 2026-03-16 11:22 CST | |
| Post-change | `/.snapshots/root-post-snapshot-post-slice-20260316-1123` | 2026-03-16 11:23 CST | |
| E2E 正例产生 | `/.snapshots/root-post-e2e-snapshot-post-20260316` | 2026-03-16 E2E 期间 | 正例 snapshot，审计保留 |
| E2E 回归产生 | `/.snapshots/root-pre-regress-pre-20260316` | 2026-03-16 E2E 期间 | snapshot_pre 回归测试产生，审计保留 |
