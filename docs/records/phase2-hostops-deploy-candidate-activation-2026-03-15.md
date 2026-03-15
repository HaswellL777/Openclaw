# Phase 2 Host-Ops deploy_openclaw_json_candidate Activation Record — 2026-03-15

> Operator: nick
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-hostops-validate-candidate-activation-2026-03-15.md`
> Route: **Route C**（deploy + operator-mediated checklist）
> Status: **live verified — deploy E2E 完成（正例 + 负例含 wrapper 侧 + 回归通过）**

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
| Agent-facing `deploy_openclaw_json_candidate` | **complete** — live E2E verified（正例 + 负例含 wrapper 侧 + 回归通过，2026-03-15） |
| 其余 action | **未开放** — `gateway_restart`, `snapshot_pre`, `snapshot_post`, `vault_sync`, `rollback_prepare` |

---

## 2. 本轮范围

本轮是 post-`validate_openclaw_json_candidate` 的下一安全切片。`deploy_openclaw_json_candidate` 是**写操作**，将候选配置文件部署到 `/etc/openclaw/openclaw.json`。

### 2.1 repo-side 代码变更

在 `plugins/host-ops-tool/index.js` 中：

- **`ENABLED_ACTIONS`** 新增 `deploy_openclaw_json_candidate`
- **Tool schema enum** 和描述文字更新为包含 deploy action
- **无其他逻辑变更**：deploy 的 `validateActionInputs` 分支已在 validate slice 中实现（与 validate 共用 case 分支）

### 2.2 Route C 特有交付物

- `docs/checklists/deploy-candidate-route-c-checklist.md`：operator-mediated checklist
- 本 record 文件（scaffold 版本）
- 权威文档边界同步

### 2.3 deploy 成功定义（精确区分）

| 层次 | 定义 | 谁负责 | 属于 deploy slice 吗？ |
|------|------|--------|----------------------|
| **deploy 写入成功** | candidate 通过 wrapper 写入 `/etc/openclaw/openclaw.json`，post-deploy hash 验证通过，.bak 已创建 | agent + broker wrapper | **是** |
| **配置生效成功** | gateway restart 后新配置被加载，`gateway_health` 返回 ok | operator（手动 restart）+ agent（health check） | **否** — 属于 restart gate |
| **变更窗口关闭** | snapshot_post 完成，可选 vault_sync | operator（手动） | **否** — 属于 snapshot gate |

---

## 3. Repo commits

以下列出本轮 repo-side 实施相关提交；后续纯记录补丁不计入本表。

| Commit | Message | Files |
|--------|---------|-------|
| `dd6eef3` | `feat(host-ops-tool): enable deploy_openclaw_json_candidate agent slice` | `plugins/host-ops-tool/index.js` |
| `ecaca17` | `docs: add route-c deploy checklist, scaffold record, and sync repo-ready boundary` | 多个 docs 文件 |
| `987ef68` | `docs: fix host-ops api state drift and fill deploy record commits` | `workspace-main-template/control/host-ops-api.md`, 本文件 |

---

## 4. Live plugin sync 步骤（已执行，2026-03-15 15:54）

### 4.1 备份当前 live plugin

```bash
sudo cp /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js \
        /var/lib/openclaw/host-ops-tool-backups/index.js.bak-pre-deploy-slice
```

> 备份已创建（19375 bytes，对应 validate slice 版本）。

### 4.2 复制新版 index.js 到 live

```bash
sudo cp /home/nick/projects/openclaw-dev/plugins/host-ops-tool/index.js \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
```

> 文件大小 19606 bytes，与 repo 完全一致。

### 4.3 重启 gateway

```bash
sudo systemctl restart openclaw-gateway.service
```

### 4.4 验证（已通过）

- [x] `systemctl is-active openclaw-gateway.service` → `active`
- [x] `systemctl is-active openclaw-broker.service` → `active`
- [x] gateway journal 无 plugin/tool 注册错误
- [x] agent 新 session 后可见 deploy action 在 schema enum 中

### 4.5 Pre-change snapshot

> `/.snapshots/root-pre-deploy-20260315-1552`（在 plugin sync 前创建）

---

## 5. 是否需要 candidate workflow（修改 /etc/openclaw/openclaw.json）

**不需要。** 原因：
- `host_ops` 已在 `main.tools.allow` 中
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `deploy_openclaw_json_candidate` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更

---

## 6. E2E 验收结果（2026-03-15 执行完成）

### 6.1 正例：合法 deploy 请求（已通过）

```
host_ops(action: "deploy_openclaw_json_candidate", inputs: {
  candidate_path: "/var/lib/openclaw/approvals/candidates/openclaw.validate-smoke.json",
  expected_sha256: "f4b1bf6d431f642b0cec07408b0d7acd3d06c78f08a626dc893b341da305d302"
})
```

验收结果：
- 返回 `ok: true`, `status: "ok"` ✓
- `artifacts` 包含 `deployed_path`, `deployed_sha256`, `backup_path` ✓
- `/etc/openclaw/openclaw.json` SHA256 与候选文件一致 ✓
- `/etc/openclaw/openclaw.json.bak` 已创建 ✓
- 注：本次候选文件内容与旧 config 相同（SHA256 一致），验证的是 deploy 机制的端到端可用性

### 6.2 三层状态确认（Route C 纪律）

| 层次 | 状态 | 确认方式 |
|------|------|----------|
| Deploy 写入成功 | **是** | wrapper 返回 ok:true, post-deploy SHA256 验证通过, .bak 已创建 |
| 配置生效成功 | **是** | operator 手动 restart gateway 后, gateway_health 返回 ok:true |
| 变更窗口关闭 | **是** | post-snapshot `root-post-deploy-20260315-1615` + vault sync 完成 |

### 6.3 负例（已通过）

| 负例 | 拒绝层 | 错误信息 | 结果 |
|------|--------|----------|------|
| 路径白名单外 (`/tmp/evil.json`) | plugin 侧 `validateActionInputs` | `candidate_path must start with /var/lib/openclaw/approvals/candidates/` | ✓ 拒绝 |
| 路径穿越 (`../../../etc/shadow`) | plugin 侧 `validateActionInputs` | `candidate_path must not contain path traversal (..)` | ✓ 拒绝 |
| 候选文件不存在 (`nonexistent-file.json`) | **wrapper 侧**（请求到达 broker） | `Candidate file not found` + `E_FILE_NOT_FOUND` | ✓ 拒绝 |

未覆盖的设计负例（可选后续补充）：
- SHA256 格式错误（plugin 侧拒绝）
- SHA256 不匹配（wrapper 侧拒绝）

### 6.4 回归：gateway_health + validate 仍正常（已通过）

- `gateway_health` 返回 `ok: true` ✓
- `validate_openclaw_json_candidate` 正例仍返回 `ok: true` ✓

---

## 7. Rollback 步骤

### 7.1 首要 rollback：恢复 plugin 文件

```bash
sudo cp /var/lib/openclaw/host-ops-tool-backups/index.js.bak-pre-deploy-slice \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo systemctl restart openclaw-gateway.service
```

效果：回到仅 `gateway_health` + `validate_openclaw_json_candidate` 可用的基线。

### 7.2 config rollback（如果 deploy 已执行且需撤销）

```bash
sudo cp /etc/openclaw/openclaw.json.bak /etc/openclaw/openclaw.json
sudo systemctl restart openclaw-gateway.service
```

---

## 8. 当前边界声明

- **已完成（live verified）**：`gateway_health` agent-facing E2E
- **已完成（live verified）**：`validate_openclaw_json_candidate` agent-facing E2E（正例 + 负例）
- **已完成（live verified）**：`deploy_openclaw_json_candidate` agent-facing E2E（正例 + 负例含 wrapper 侧 + 回归通过）
- **未开放**：`gateway_restart`, `snapshot_pre`, `snapshot_post`, `vault_sync`, `rollback_prepare`
- 不得将 deploy 的成功类推为其余 5 个 action 已安全开放
- 不得将 deploy 的文件写入成功类推为配置生效成功（本轮已区分验证，但纪律约束不变）
- deploy 后的 restart / health / snapshot / vault 仍属于 operator-mediated checklist 范围

## 9. Snapshots

| 类型 | 路径 | 时间 |
|------|------|------|
| Pre-change | `/.snapshots/root-pre-deploy-20260315-1552` | 15:52 |
| Post-change | `/.snapshots/root-post-deploy-20260315-1615` | 16:15 |
| Vault sync | `root-auto-2026-03-15-1615` (incremental from `root-auto-2026-03-15-0340`) | 16:15 |
