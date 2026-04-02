# Phase 2 Host-Ops validate_openclaw_json_candidate Activation Record — 2026-03-15

> Operator: nick
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-hostops-main-activation-2026-03-15.md`
> Status: **live verified — agent-facing E2E 完成（正例 + 负例）**

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
| 其余 action | **未开放** — `deploy_openclaw_json_candidate`, `gateway_restart`, `snapshot_pre`, `snapshot_post`, `vault_sync`, `rollback_prepare` |

---

## 2. 本轮范围

本轮是 post-`gateway_health` 的下一安全切片。`validate_openclaw_json_candidate` 是只读操作，不修改任何 live 状态，因此风险可控，适合作为第二个 agent-facing action。

### 2.1 repo-side 代码变更

在 `plugins/host-ops-tool/index.js` 中：

- **`ENABLED_ACTIONS`** 新增 `validate_openclaw_json_candidate`
- **Tool schema** 新增 `inputs` 属性（type: object），支持 agent 传入 action-specific 输入
- **`execute()`** 从 `params.inputs` 读取并透传到 `buildRequest()`，取代原来的硬编码 `{}`
- **`execute()` 顶层参数白名单**：新增 `ALLOWED_PARAMS = ["action", "inputs"]`，拒绝未知参数（defense-in-depth，不依赖运行时 `additionalProperties:false` 强制）
- **inputs 非 object 的 fail-closed 拒绝**：`rawInputs` 为 null / 非 object / array 时立即返回 `ok: false`
- **`additionalProperties: false`** 加入 tool schema 顶层
- 保持 `gateway_health` 无输入正常工作

### 2.2 文档同步

同步了 `host-sop.md`、`design-v3.md`、`host-ops-api.md` 中的阶段边界描述。

---

## 3. Repo commits

| Commit | Message | Files |
|--------|---------|-------|
| `da98e83` | `feat(host-ops-tool): enable validate_openclaw_json_candidate agent slice` | `plugins/host-ops-tool/index.js` |
| `648e47f` | `docs: sync post-gateway_health boundary and validate-candidate next slice` | `docs/host-sop.md`, `docs/design-v3.md`, `workspace-main-template/control/host-ops-api.md` |
| `75071db` | `docs(records): scaffold validate-candidate activation record` | 本文件（scaffold 版本） |
| `b868fc6` | `harden(host-ops-tool): add execute() param whitelist and fix backup path` | `plugins/host-ops-tool/index.js`, 本文件 |

---

## 4. Live plugin sync 步骤（已执行）

### 4.1 备份当前 live plugin

```bash
sudo mkdir -p /var/lib/openclaw/host-ops-tool-backups
sudo cp /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js \
        /var/lib/openclaw/host-ops-tool-backups/index.js.bak-pre-validate-slice
```

> 备份放在 extensions 目录之外（`/var/lib/openclaw/host-ops-tool-backups/`），避免 extensions 目录清理或重装时备份丢失。plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），**不在** root snapshot 保护范围内。因此 plugin 文件级备份是首要 rollback anchor，而非根快照。

### 4.2 复制新版 index.js 到 live

```bash
sudo cp /home/nick/projects/openclaw-dev/plugins/host-ops-tool/index.js \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
```

### 4.3 重启 gateway

```bash
sudo systemctl restart openclaw-gateway.service
```

### 4.4 验证 gateway 健康（已通过）

```bash
sudo systemctl status openclaw-gateway.service   # active
sudo systemctl status openclaw-broker.service     # active
sudo journalctl -u openclaw-gateway.service -n 30 --no-pager
```

验收结果：
- gateway + broker 均 active
- 无 plugin/tool 注册错误
- 无 duplicate tool name 冲突

### 4.5 确认 live 文件与 repo 一致

live 上 `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js` 内容已与 repo `plugins/host-ops-tool/index.js` 一致。

---

## 5. 是否需要 candidate workflow（修改 /etc/openclaw/openclaw.json）

**不需要。** 原因：
- `host_ops` 已在 `main.tools.allow` 中（在 gateway_health 激活阶段已完成）
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `validate_openclaw_json_candidate` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更
- 本轮只需 live plugin code sync + gateway restart

---

## 6. 正例 E2E（已通过）

### 6.1 正例：合法 validate 请求

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {
  candidate_path: "/var/lib/openclaw/approvals/candidates/openclaw-test.json",
  expected_sha256: "<候选文件的实际 SHA256>"
})
```

验收结果：
- 返回 `ok: true`, `status: "ok"`
- `artifacts` 中包含 `sha256_match: true`, `json_valid: true`
- Broker 日志有对应 `validate_openclaw_json_candidate` 请求记录
- 无副作用（候选文件不被修改、live config 不被修改）

### 6.2 正例：gateway_health 仍正常

Agent 调用：
```
host_ops(action: "gateway_health")
```

验收结果：
- 返回 `ok: true`, `status: "ok"`
- 与 gateway_health slice 行为一致，未因 validate 扩展产生回退

---

## 7. 负例 E2E（已通过）

### 7.1 负例：白名单外路径拒绝

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {
  candidate_path: "/tmp/evil.json",
  expected_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
})
```

结果：plugin 侧 `validateActionInputs` 拒绝（路径不以 `/var/lib/openclaw/approvals/candidates/` 开头），返回 `ok: false`, `status: "error"`, message 包含 `candidate_path must start with /var/lib/openclaw/approvals/candidates/`。

### 7.2 负例：路径穿越拒绝

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {
  candidate_path: "/var/lib/openclaw/approvals/candidates/../evil.json",
  expected_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
})
```

结果：plugin 侧 `validateActionInputs` 拒绝（含 `..`），返回 `ok: false`, `status: "error"`, message 包含 `candidate_path must not contain path traversal`。

### 7.3 负例：SHA256 mismatch 拒绝

Agent 调用了一个 SHA256 与候选文件实际哈希不匹配的请求。

结果：broker wrapper 侧校验失败，返回 `ok: false`, `status: "error"`, message 包含 `SHA256 mismatch`。

### 7.4 负例：缺失必要输入

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {})
```

预期行为：`validateActionInputs` 报 `requires inputs.candidate_path` 和 `requires inputs.expected_sha256`，返回 `ok: false`。

### 7.5 负例：inputs 为非 object

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: "not-an-object")
```

预期行为：`execute()` 中的 fail-closed 检查拒绝，返回 `ok: false`, `status: "error"`, `message: "inputs must be a plain object"`。

### 7.6 负例：非法 action（ENABLED_ACTIONS 拒绝）

Agent 调用：
```
host_ops(action: "deploy_openclaw_json_candidate", inputs: {...})
```

结果：`ENABLED_ACTIONS` 不包含 `deploy_openclaw_json_candidate`，返回 `ok: false`, `status: "denied"`, message 包含 `Action 'deploy_openclaw_json_candidate' is not enabled`。

---

## 8. 现场经验与注意事项

### 8.1 旧 session 可能仍保留旧 tool schema

**重要发现**：plugin code sync + gateway restart 后，已有的 bot 会话可能仍持有旧版 tool schema（不包含 `inputs` 参数）。

原因：agent session bootstrap 时拿到的 tool list 被缓存在会话上下文中，gateway restart 不会主动推送新 schema 到已有会话。

解决方法：需要通过 `/reset` 或启动新 session，让 agent 重新 bootstrap 并获取包含 `inputs` 参数的新 tool schema。

### 8.2 本轮不涉及 /etc/openclaw/openclaw.json 变更

validate_openclaw_json_candidate 的启用完全由 plugin 代码控制（`ENABLED_ACTIONS` 列表），不需要修改 live config。这与 gateway_health 激活阶段不同——那一阶段需要通过 candidate workflow 将 `host_ops` 加入 `main.tools.allow`。

---

## 9. Rollback 步骤

### 9.1 首要 rollback：恢复 plugin 文件

```bash
sudo cp /var/lib/openclaw/host-ops-tool-backups/index.js.bak-pre-validate-slice \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo systemctl restart openclaw-gateway.service
```

效果：回到仅 `gateway_health` 可用的基线。

### 9.2 根快照不是本轮主要 rollback 手段

本轮只修改了 plugin 文件（位于 `/var/lib/openclaw`，独立子卷），未修改 `/etc/openclaw/openclaw.json`、systemd 单元或 `/opt/openclaw`。因此根快照不覆盖本次变更范围，plugin 文件备份是唯一有效 rollback anchor。

---

## 10. 当前边界声明

- **已完成（live verified）**：`gateway_health` agent-facing E2E
- **已完成（live verified）**：`validate_openclaw_json_candidate` agent-facing E2E（正例 + 负例）
- **未开放**：`deploy_openclaw_json_candidate`, `gateway_restart`, `snapshot_pre`, `snapshot_post`, `vault_sync`, `rollback_prepare`
- 不得将 `validate_openclaw_json_candidate` 的完成写成 host_ops 全面可用
- 不得将本轮只读 action 的成功类推为写操作 action 已安全
- 下一安全切片建议：`deploy_openclaw_json_candidate`（需先完成设计评审，因为是写操作，风险等级高于 validate）
