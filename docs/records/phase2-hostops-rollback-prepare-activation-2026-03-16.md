# Phase 2 Host-Ops rollback_prepare Activation Record — 2026-03-16

> Operator: nick
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-hostops-snapshot-post-activation-2026-03-16.md`
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
| Agent-facing `rollback_prepare` | **complete** — live E2E verified（正例 + 负例 + 回归，2026-03-16） |
| 其余 action | **未开放** — `gateway_restart`, `vault_sync` |

---

## 2. 本轮范围

本轮是 post-`snapshot_post` 的下一安全切片。`rollback_prepare` 是纯只读 action（验证 snapshot 存在性 + 返回 prepare-only metadata，不执行任何变更），且 wrapper 已有基础实现，本次修正将 `rollback_steps` 语义过强的字段替换为 prepare-only metadata。

### 2.1 为什么是 rollback_prepare

- 纯只读 action：仅执行 `btrfs subvolume show` 验证 snapshot 存在性，不执行任何变更
- 副作用为零：不创建快照、不删除文件、不修改配置、不重启服务
- wrapper 已有基础实现，修正语义即可使用
- 详见 `docs/planning/rollback-prepare-slice-design-2026-03-16.md`

### 2.2 为什么不是其他 2 个

| Action | 不选原因 |
|--------|----------|
| `gateway_restart` | 返回语义不稳（broker 被 SIGTERM 导致请求返回值不可靠），依赖链根因待独立复核 |
| `vault_sync` | Vault receive 路径与 wrapper 代码存在漂移；`incremental` 契约与实现不一致 |

### 2.3 本轮与前序 slice 的关键差异

- **首次同时部署 plugin + wrapper**：activation 脚本覆盖 plugin 和 wrapper 双部署，revert 脚本覆盖双恢复
- **wrapper 契约修正**：移除 `rollback_steps` 字段（语义过强），替换为 `prepare_only` / `rollback_executed` / `scope` / `excluded_paths` / `operator_action_required` metadata
- 前序 slice（snapshot_pre / snapshot_post）仅部署 plugin，wrapper 无需变更

### 2.4 repo-side 代码变更

在 `plugins/host-ops-tool/index.js` 中：

- **`ENABLED_ACTIONS`** 新增 `rollback_prepare`（从 5 扩展到 6）
- **Tool description** 更新为包含 rollback_prepare
- **Action enum description** 更新为包含 rollback_prepare
- **`inputs.properties`** 添加 `target_snapshot` 字段声明
- **`reason` description** 更新为包含 rollback_prepare
- **`inputs` description** 更新为包含 rollback_prepare

在 `broker/wrappers/ocw-rollback-prepare.sh` 中：

- 移除 `ROLLBACK_STEPS` 变量及其在 dry-run 和 live 两条路径的引用
- 替换为 prepare-only metadata：`prepare_only: true`, `rollback_executed: false`, `scope: "root-filesystem-only"`, `excluded_paths: ["/var/lib/openclaw"]`, `operator_action_required: true`
- dry-run 和 live 使用相同的 metadata 字段结构（`snapshot_verified` 在 dry-run 为 null，live 为 true）

在 `examples/broker/rollback-prepare-result.json` 中：

- 同步为 prepare-only metadata 契约（移除 `rollback_steps`）

---

## 3. Repo commits

| Commit | Message | Files |
|--------|---------|-------|
| `5355712` | `docs(planning): rollback_prepare slice design` | `docs/planning/rollback-prepare-slice-design-2026-03-16.md` |
| `55512cb` | `feat(host-ops-tool): enable rollback_prepare agent slice` | `plugins/host-ops-tool/index.js`, `broker/wrappers/ocw-rollback-prepare.sh`, `examples/broker/rollback-prepare-result.json`, `scripts/activate-rollback-prepare-slice.sh`, `scripts/revert-rollback-prepare-slice.sh` |

---

## 4. Live plugin + wrapper sync 步骤（已执行，2026-03-16 13:48 CST）

> 使用一键 activation 脚本执行。

### 4.1 Pre-change root snapshot

```
/.snapshots/root-pre-rollback-prepare-slice-20260316-1348
```

### 4.2 备份当前 live plugin + wrapper

```
Plugin backup: /var/lib/openclaw/host-ops-tool-backups/index.js.backup-before-rollback-prepare-slice-20260316-1348
  SHA256: 0451e7906f6bfaa7559564143f5efe46effb60431b1a56e9d6b3084deade6ab9

Wrapper backup: /var/lib/openclaw/host-ops-tool-backups/ocw-rollback-prepare.sh.backup-before-rollback-prepare-slice-20260316-1348
  SHA256: 7d694ac15569739dc803778809f148d1e64c98d7629464ca62aea95893352c78
```

### 4.3 部署新版 plugin + wrapper

```
Plugin deployed: /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js (openclaw:openclaw 644)
  SHA256: 49dd7762cd401551ded534b381e7dc7831270c0af9c3472052611b0ace4ee827

Wrapper deployed: /opt/openclaw/broker/wrappers/ocw-rollback-prepare.sh (root:root 755)
  SHA256: 8ca6b27df8ea35a49347b9bd883bf07538105f201c12dfea0810b4e139aed628
```

### 4.4 Restart gateway + 验证

- [x] `systemctl restart openclaw-gateway.service`
- [x] `systemctl is-active openclaw-gateway.service` → `active`
- [x] `systemctl is-active openclaw-broker.service` → `active`
- [x] journal logs captured to artifacts
- [x] agent 新 session 后可见 `rollback_prepare` 在 schema enum 中（E2E 确认，见 §6）

### 4.5 Activation artifacts

```
/home/nick/projects/openclaw-dev/artifacts/phase2/rollback-prepare-live-activation-20260316-1348/
```

---

## 5. 是否需要 candidate workflow（修改 /etc/openclaw/openclaw.json）

**不需要。** 原因：
- `host_ops` 已在 `main.tools.allow` 中
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `rollback_prepare` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更

---

## 6. E2E 验收结果（2026-03-16，OpenClaw agent session）

> 执行环境：OpenClaw agent (T800 Bot) via Feishu，fresh session
> 7/7 PASS

### 6.1 正例：合法 rollback_prepare 请求 — **PASS**

```
host_ops(action: "rollback_prepare", inputs: {
  target_snapshot: "root-pre-rollback-prepare-slice-20260316-1348",
  reason: "E2E verification of rollback_prepare agent slice"
})
```

结果：
```json
{
  "ok": true,
  "action": "rollback_prepare",
  "request_id": "req-20260316055044-q3b3xp",
  "task_id": "task-20260316055044-q3b3xp",
  "status": "ok",
  "message": "Rollback preparation completed — prepare-only metadata, actual rollback requires operator action in LiveUSB/rescue environment",
  "artifacts": {
    "target_snapshot": "root-pre-rollback-prepare-slice-20260316-1348",
    "reason": "E2E verification of rollback_prepare agent slice",
    "snapshot_path": "/.snapshots/root-pre-rollback-prepare-slice-20260316-1348",
    "snapshot_verified": true,
    "prepare_only": true,
    "rollback_executed": false,
    "scope": "root-filesystem-only",
    "excluded_paths": ["/var/lib/openclaw"],
    "operator_action_required": true,
    "mode": "live"
  },
  "rollback_hint": "Rollback preparation is read-only; no undo needed"
}
```

验收点：
- [x] `ok: true`, `status: "ok"`
- [x] `prepare_only: true`
- [x] `rollback_executed: false`
- [x] `excluded_paths` 含 `/var/lib/openclaw`
- [x] 不含 `rollback_steps` 字段

### 6.2 负例 1：缺失 target_snapshot — **PASS**

```
host_ops(action: "rollback_prepare", inputs: { reason: "negative test" })
```

结果：`ok: false`, `status: "error"`, message: "Request validation failed: rollback_prepare requires inputs.target_snapshot (string)"

拒绝层：plugin 侧 `validateActionInputs` → `validateRequest`

### 6.3 负例 2：不存在的 snapshot — **PASS**

```
host_ops(action: "rollback_prepare", inputs: {
  target_snapshot: "nonexistent-snapshot-xyz-99999",
  reason: "negative test nonexistent"
})
```

结果：
```json
{
  "ok": false,
  "action": "rollback_prepare",
  "request_id": "req-20260316055055-0fxmcn",
  "task_id": "task-20260316055055-0fxmcn",
  "status": "error",
  "error_code": "E_FILE_NOT_FOUND",
  "message": "Target snapshot not found: /.snapshots/nonexistent-snapshot-xyz-99999"
}
```

拒绝层：wrapper 侧 `broker_error`（请求到达 broker，wrapper 执行后返回错误）

### 6.4 负例 3：vault_sync 不在 action enum 中 — **PASS**

```
host_ops(action: "vault_sync", inputs: { snapshot_name: "test-denied" })
```

结果：gateway 层 schema 校验拒绝 — "Validation failed for tool \"host_ops\": action: must be equal to one of the allowed values"

验收点：确认 action enum 恰好为 6 个值（gateway_health, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, rollback_prepare）且不含 vault_sync / gateway_restart。

### 6.5 回归：gateway_health — **PASS**

```
host_ops(action: "gateway_health")
```

结果：
```json
{
  "ok": true,
  "action": "gateway_health",
  "request_id": "req-20260316055112-d8vkr1",
  "task_id": "task-20260316055112-d8vkr1",
  "status": "ok",
  "message": "Gateway health check completed",
  "artifacts": { "service_active": "active", "health_endpoint": null, "mode": "live" },
  "rollback_hint": "No rollback needed for health check"
}
```

### 6.6 回归：snapshot_pre — **PASS**

```
host_ops(action: "snapshot_pre", inputs: {
  label: "regress-pre-rollback-prepare-20260316",
  reason: "regression after rollback_prepare activation"
})
```

结果：
```json
{
  "ok": true,
  "action": "snapshot_pre",
  "request_id": "req-20260316055124-3zduu7",
  "task_id": "task-20260316055124-3zduu7",
  "status": "ok",
  "message": "Pre-change snapshot created",
  "artifacts": {
    "snapshot_name": "root-pre-regress-pre-rollback-prepare-20260316",
    "label": "regress-pre-rollback-prepare-20260316",
    "reason": "regression after rollback_prepare activation",
    "snapshot_path": "/.snapshots/root-pre-regress-pre-rollback-prepare-20260316",
    "mode": "live"
  },
  "rollback_hint": "Delete snapshot: btrfs subvolume delete /.snapshots/root-pre-regress-pre-rollback-prepare-20260316"
}
```

### 6.7 回归：snapshot_post — **PASS**

```
host_ops(action: "snapshot_post", inputs: {
  label: "regress-post-rollback-prepare-20260316",
  reason: "regression after rollback_prepare activation"
})
```

结果：
```json
{
  "ok": true,
  "action": "snapshot_post",
  "request_id": "req-20260316055130-thusrj",
  "task_id": "task-20260316055130-thusrj",
  "status": "ok",
  "message": "Post-change snapshot created",
  "artifacts": {
    "snapshot_name": "root-post-regress-post-rollback-prepare-20260316",
    "label": "regress-post-rollback-prepare-20260316",
    "reason": "regression after rollback_prepare activation",
    "snapshot_path": "/.snapshots/root-post-regress-post-rollback-prepare-20260316",
    "mode": "live"
  },
  "rollback_hint": "Delete snapshot: btrfs subvolume delete /.snapshots/root-post-regress-post-rollback-prepare-20260316"
}
```

---

## 7. E2E 观察：负例拒绝层分布

| 负例 | 拒绝层 | 说明 |
|------|--------|------|
| 缺失 target_snapshot | plugin 侧 `validateActionInputs` → `validateRequest` | 请求通过 schema，到达 plugin execute，被 request 校验拒绝 |
| 不存在的 snapshot | wrapper 侧 `broker_error` | 请求到达 broker，wrapper 检查 `/.snapshots/` 下不存在目标目录，返回 E_FILE_NOT_FOUND |
| 未开放 action（vault_sync） | gateway 层 tool schema 校验 | `enum: ENABLED_ACTIONS` 在 tool schema 层拦截 |

gateway 层 schema 校验和 plugin 侧 `validateRequest` 构成两层防御。gateway 层拦截的负例不会到达 broker。error（缺失 field / snapshot 不存在）和 schema-reject（未开放 action）是不同的拒绝机制。

---

## 8. Rollback 步骤

### 8.1 首要 rollback：恢复 plugin + wrapper 备份

```bash
sudo bash scripts/revert-rollback-prepare-slice.sh /home/nick/projects/openclaw-dev/artifacts/phase2/rollback-prepare-live-activation-20260316-1348
```

效果：回到 `gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` + `snapshot_pre` + `snapshot_post` 可用的基线（5 个 ENABLED_ACTIONS），wrapper 恢复为修正前版本。

### 8.2 plugin 文件不在 root snapshot 保护范围

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），不在 root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor。

### 8.3 wrapper 文件在 root snapshot 保护范围内

wrapper 文件位于 `/opt/openclaw/broker/wrappers/`（root filesystem），在 root snapshot 保护范围内。但首要 rollback 仍使用 revert 脚本（文件级备份恢复），root snapshot 作为额外锚点。

### 8.4 测试 snapshot 的处理

测试生成的 snapshot 应作为审计痕迹保留，不把"删除测试 snapshot"写进成功定义。

### 8.5 root snapshot 作为额外锚点

root snapshot 可作为 host 层额外锚点，但不是 plugin rollback 的首要手段。

---

## 9. 当前边界声明

- **已完成（live verified）**：`gateway_health` agent-facing E2E
- **已完成（live verified）**：`validate_openclaw_json_candidate` agent-facing E2E（正例 + 负例）
- **已完成（live verified）**：`deploy_openclaw_json_candidate` agent-facing E2E（Route C，正例 + 负例含 wrapper 侧 + 回归通过）
- **已完成（live verified）**：`snapshot_pre` agent-facing E2E（正例 + 负例 + 回归，2026-03-16）
- **已完成（live verified）**：`snapshot_post` agent-facing E2E（正例 + 负例 + 回归，2026-03-16）
- **已完成（live verified）**：`rollback_prepare` agent-facing E2E（正例 + 负例含 wrapper 侧 E_FILE_NOT_FOUND + 回归，2026-03-16）
- **未开放**：`gateway_restart`, `vault_sync`
- 不得将本轮 rollback_prepare 的成功类推为 host_ops 全量开放（仍有 2 个 action 未开放）
- 不得将本轮成功写成 rollback 能力已完整（rollback_prepare 只验证 snapshot 存在性并返回 prepare-only metadata，实际 rollback 仍需 LiveUSB/救援环境）
- `rollback_prepare` 返回的 `prepare_only: true` / `rollback_executed: false` / `operator_action_required: true` 明确声明了这是 prepare-only 操作

---

## 10. Snapshots

| 类型 | 路径 | 时间 | 备注 |
|------|------|------|------|
| Pre-change | `/.snapshots/root-pre-rollback-prepare-slice-20260316-1348` | 2026-03-16 13:48 CST | activation 脚本自动创建 |
| E2E 回归产生 | `/.snapshots/root-pre-regress-pre-rollback-prepare-20260316` | 2026-03-16 E2E 期间 | snapshot_pre 回归测试产生，审计保留 |
| E2E 回归产生 | `/.snapshots/root-post-regress-post-rollback-prepare-20260316` | 2026-03-16 E2E 期间 | snapshot_post 回归测试产生，审计保留 |
