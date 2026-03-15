# Phase 2 Host-Ops validate_openclaw_json_candidate Activation Record — 2026-03-15

> Operator: nick
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-hostops-main-activation-2026-03-15.md`
> Status: **repo-side ready, live deployment pending**

---

## 1. 当前基线

| 层级 | 状态 |
|------|------|
| Broker backend | **deployed** — active + enabled |
| Plugin config registration | **complete** |
| Plugin lifecycle activation | **complete** |
| Tool registration (live) | **complete** — `api.registerTool(hostOpsTool, {optional:true})` |
| Agent-facing `gateway_health` | **complete** — E2E 成功 |
| Agent-facing `validate_openclaw_json_candidate` | **repo-side ready, live deployment pending** |
| 其余 action | **未开放** |

---

## 2. 本轮范围

- 在 `plugins/host-ops-tool/index.js` 中将 `validate_openclaw_json_candidate` 加入 `ENABLED_ACTIONS`
- Tool schema 新增 `inputs` 属性（type: object），支持 agent 传入 action-specific 输入
- `execute()` 从 `params.inputs` 读取并透传到 `buildRequest()`，取代原来的硬编码 `{}`
- 新增 `inputs` 非 object 时的 fail-closed 拒绝
- `additionalProperties: false` 加入 tool schema 顶层
- 保持 `gateway_health` 无输入正常工作
- 同步文档漂移（host-sop.md, design-v3.md, host-ops-api.md）

---

## 3. Repo commits

| Commit | Message | Files |
|--------|---------|-------|
| (待填写) | `feat(host-ops-tool): enable validate_openclaw_json_candidate agent slice` | `plugins/host-ops-tool/index.js` |
| (待填写) | `docs: sync post-gateway_health boundary and validate-candidate next slice` | `docs/host-sop.md`, `docs/design-v3.md`, `workspace-main-template/control/host-ops-api.md` |
| (待填写) | `docs(records): scaffold validate-candidate activation record` | 本文件 |

---

## 4. Live plugin sync 步骤

### 4.1 备份当前 live plugin

```bash
sudo cp /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js.bak-pre-validate-slice
```

> 注意：plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），**不在** root snapshot 保护范围内。因此 plugin 文件级备份是首要 rollback anchor，而非根快照。

### 4.2 复制新版 index.js 到 live

```bash
# 从 dev-repo 或 staging 目录复制
sudo cp <staging-path>/plugins/host-ops-tool/index.js \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
```

### 4.3 重启 gateway

```bash
sudo systemctl restart openclaw-gateway.service
```

### 4.4 验证 gateway 健康

```bash
sudo systemctl status openclaw-gateway.service
sudo systemctl status openclaw-broker.service
sudo journalctl -u openclaw-gateway.service -n 30 --no-pager
```

验收标准：
- gateway + broker 均 active
- 无 plugin/tool 注册错误
- 无 duplicate tool name 冲突

---

## 5. 是否需要 candidate workflow（修改 /etc/openclaw/openclaw.json）

**不需要。** 原因：
- `host_ops` 已在 `main.tools.allow` 中（`openclaw.live.json` 确认）
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `validate_openclaw_json_candidate` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更
- 本轮只需 live plugin code sync + gateway restart

---

## 6. 正例 E2E

### 6.1 正例：合法 validate 请求

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {
  candidate_path: "/var/lib/openclaw/approvals/candidates/openclaw-test.json",
  expected_sha256: "<候选文件的实际 SHA256>"
})
```

验收标准：
- 返回 `ok: true`, `status: "ok"`
- `artifacts` 中包含 `sha256_match: true`, `json_valid: true`
- Broker 日志有对应 `validate_openclaw_json_candidate` 请求记录
- 无副作用（候选文件不被修改、live config 不被修改）

### 6.2 正例：gateway_health 仍正常

Agent 调用：
```
host_ops(action: "gateway_health")
```

验收标准：
- 返回 `ok: true`, `status: "ok"`
- 与之前行为一致

---

## 7. 负例 E2E

### 7.1 负例：路径越界

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {
  candidate_path: "/etc/openclaw/openclaw.json",
  expected_sha256: "a" * 64
})
```

预期：plugin 侧 `validateActionInputs` 拒绝（路径不以 `/var/lib/openclaw/approvals/candidates/` 开头），返回 `ok: false`, `status: "error"`。

### 7.2 负例：路径遍历

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {
  candidate_path: "/var/lib/openclaw/approvals/candidates/../../etc/shadow",
  expected_sha256: "a" * 64
})
```

预期：plugin 侧 `validateActionInputs` 拒绝（含 `..`），返回 `ok: false`, `status: "error"`。

### 7.3 负例：SHA256 格式错误

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {
  candidate_path: "/var/lib/openclaw/approvals/candidates/openclaw-test.json",
  expected_sha256: "not-a-valid-sha256"
})
```

预期：plugin 侧 `validateActionInputs` 拒绝（不匹配 `^[a-f0-9]{64}$`），返回 `ok: false`, `status: "error"`。

### 7.4 负例：缺失必要输入

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {})
```

预期：`validateActionInputs` 报 `requires inputs.candidate_path` 和 `requires inputs.expected_sha256`，返回 `ok: false`。

### 7.5 负例：inputs 为非 object

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: "not-an-object")
```

预期：execute() 中新增的 fail-closed 检查拒绝，返回 `ok: false`, `status: "error"`, `message: "inputs must be a plain object"`。

### 7.6 负例：非法 action

Agent 调用：
```
host_ops(action: "deploy_openclaw_json_candidate", inputs: {...})
```

预期：ENABLED_ACTIONS 拒绝，返回 `ok: false`, `status: "denied"`。

---

## 8. Rollback 步骤

### 8.1 首要 rollback：恢复 plugin 文件

```bash
sudo cp /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js.bak-pre-validate-slice \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo systemctl restart openclaw-gateway.service
```

效果：回到仅 `gateway_health` 可用的基线。

### 8.2 根快照不是本轮主要 rollback 手段

本轮只修改了 plugin 文件（位于 `/var/lib/openclaw`，独立子卷），未修改 `/etc/openclaw/openclaw.json`、systemd 单元或 `/opt/openclaw`。因此根快照不覆盖本次变更范围，plugin 文件备份是唯一有效 rollback anchor。

---

## 9. 当前边界声明

- **已完成**：`gateway_health` agent-facing E2E（live verified）
- **repo-side ready**：`validate_openclaw_json_candidate`（本 record 所述）
- **未开放**：`deploy_openclaw_json_candidate`, `gateway_restart`, `snapshot_pre`, `snapshot_post`, `vault_sync`, `rollback_prepare`
- 不得将 `validate_openclaw_json_candidate` repo-side ready 写成 live done
- 不得将单个 action 开放写成 host_ops 全面可用
