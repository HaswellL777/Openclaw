# deploy_openclaw_json_candidate — 下一阶段实施设计

> 文档类型：**设计准备 / planning note（非实施事实）**
> 创建日期：2026-03-15
> 作者：nick + ClaudeCode
> 前置完成：`gateway_health` E2E live verified, `validate_openclaw_json_candidate` E2E live verified
> 目标：为 `deploy_openclaw_json_candidate` 的 agent-facing 开放建立严谨的实施方案
> 状态：**设计草案，未执行**

---

## 1. 阶段目标定义

本阶段的目标**不是**"开放所有写操作"，而是仅为 `deploy_openclaw_json_candidate` 建立：

- 清晰的 preconditions
- 明确的 candidate workflow
- 明确的 rollback anchor
- 明确的 post-deploy health gate
- 明确的 records / docs / commit discipline
- 与相邻 action（`gateway_restart`、`snapshot_pre/post`）的边界关系

---

## 2. 为什么 deploy 不能被视为"再开一个 action"

### 2.1 validate vs deploy 的风险差异

| 维度 | `validate_openclaw_json_candidate` | `deploy_openclaw_json_candidate` |
|------|----|----|
| 操作类型 | **只读** — 检查候选文件完整性 | **写操作** — 替换 `/etc/openclaw/openclaw.json` |
| 副作用 | 无 — 不修改任何文件 | **修改宿主机唯一配置源**，影响所有后续 gateway 重启 |
| 可逆性 | N/A（只读） | 需要 backup restore 或 snapshot rollback |
| 失败影响 | agent 收到 `ok: false`，系统无变化 | 配置损坏可能导致 gateway 无法启动 |
| 依赖关系 | 无前置 | 必须先通过 validate |

### 2.2 deploy 涉及的系统层面

- **修改 `/etc/openclaw/openclaw.json`**：宿主机唯一配置文件，位于 root 文件系统（在 root snapshot 保护范围内）
- **需要 root 权限**：`chown root:openclaw` + `chmod 640`
- **backup 创建**：wrapper 自动创建 `.bak` 文件
- **post-deploy hash verification**：wrapper 在 deploy 后验证哈希，不匹配时自动回滚到 `.bak`

### 2.3 deploy 不等于"配置生效"

deploy 只是**文件替换**。新配置要生效，必须：
1. deploy 完成 → 2. `gateway_restart` → 3. health gate 验证

如果只做 deploy 而不做 restart，系统处于 "配置文件已更新但 gateway 仍运行旧配置" 的不一致状态。这不危险，但需要在纪律文档中明确。

---

## 3. deploy 与相邻 action 的依赖关系

### 3.1 依赖图

```
snapshot_pre  ─────────────────────────────────────────────┐
  │                                                        │
  ▼                                                        │
validate_openclaw_json_candidate  ──── precondition ──►    │
  │                                                        │
  ▼                                                        │
deploy_openclaw_json_candidate                             │
  │                                                        │
  ▼                                                        │
gateway_restart                                            │
  │                                                        │
  ▼                                                        │
gateway_health  ──── health gate                           │
  │                                                        │
  ▼                                                        │
snapshot_post  ────────────────────────────────────────────┘
  │
  ▼
vault_sync  (可选)
```

### 3.2 关键问题：snapshot_pre / post / gateway_restart 尚未 agent-facing 开放

当前 `ENABLED_ACTIONS` 只包含 `gateway_health` 和 `validate_openclaw_json_candidate`。

如果先开放 deploy 而不开放 snapshot_pre/post 和 gateway_restart：
- agent 无法自主做变更前快照
- agent 无法在 deploy 后重启 gateway 让新配置生效
- agent 无法自主做变更后快照

这意味着 **deploy 的完整工作流仍需要人工介入**（快照 + restart 步骤由 operator 手动执行）。

### 3.3 两种可选路线

**路线 A（保守）**：先单独开放 deploy，但要求 operator 手动执行 snapshot + restart。文档中明确这是 "半自动" 模式。

**路线 B（完整切片）**：一次性开放 deploy + gateway_restart + snapshot_pre + snapshot_post 四个 action，使 agent 可以执行完整工作流。但这一次性扩面较大，风险更高。

**建议采用路线 A**：先单独验证 deploy 的 agent-facing 安全性，snapshot + restart 暂由 operator 手动执行。后续再逐步开放其余 action。

---

## 4. deploy_openclaw_json_candidate 的 preconditions

在 agent 调用 deploy 之前，以下条件**必须**满足：

### 4.1 必须先通过 validate

- agent 必须先成功调用 `validate_openclaw_json_candidate` 并获得 `ok: true`
- validate 返回的 `sha256_match: true`, `json_valid: true` 是 deploy 的输入依据
- **这一约束由纪律文档和 agent 行为规范保证，不由 plugin 代码强制**（plugin 不跟踪会话状态）

### 4.2 候选文件必须存在于白名单路径

- 路径必须以 `/var/lib/openclaw/approvals/candidates/` 开头
- 路径不能包含 `..`
- 这由 plugin 侧 `validateActionInputs` 和 broker wrapper 侧 `broker_validate_path` 双重校验

### 4.3 expected_sha256 必须匹配候选文件

- plugin 侧格式校验：`/^[a-f0-9]{64}$/`
- wrapper 侧实际校验：`sha256sum` 比对
- deploy wrapper 在部署后还做 post-deploy hash verification，不匹配则自动回滚

### 4.4 当前处于安全快照点

- **operator 纪律**：deploy 前必须已做 `snapshot_pre`（手动或通过 broker）
- 这是纪律要求，不由 deploy wrapper 检查（wrapper 不检查快照状态）

---

## 5. deploy 的 fail-closed 条件

以下任一条件触发时，deploy 必须失败且不产生副作用：

| 条件 | 检查层 | 行为 |
|------|--------|------|
| `deploy_openclaw_json_candidate` 不在 ENABLED_ACTIONS | plugin `execute()` | 返回 `ok: false, status: denied` |
| inputs 非 object | plugin `execute()` | 返回 `ok: false, status: error` |
| candidate_path 不在白名单前缀 | plugin `validateActionInputs` + wrapper `broker_validate_path` | 返回 `ok: false, status: error` |
| candidate_path 包含 `..` | plugin `validateActionInputs` + wrapper `broker_validate_path` | 返回 `ok: false, status: error` |
| expected_sha256 格式不合法 | plugin `validateActionInputs` + wrapper `broker_validate_sha256` | 返回 `ok: false, status: error` |
| 候选文件不存在 | wrapper live 执行 | 返回 `ok: false, status: error, E_FILE_NOT_FOUND` |
| 候选文件 SHA256 与 expected 不匹配 | wrapper live 执行 | 返回 `ok: false, status: error, E_WRAPPER_FAILED` |
| post-deploy SHA256 验证失败 | wrapper live 执行 | **自动回滚到 .bak** + 返回 `ok: false` |
| broker 连接失败 | plugin `sendRequest` | 返回 `ok: false, status: error` |

---

## 6. Rollback anchor

### 6.1 首要 rollback：config .bak 文件

deploy wrapper 在覆盖 `/etc/openclaw/openclaw.json` 前自动创建 `.bak` 副本：

```bash
cp /etc/openclaw/openclaw.json /etc/openclaw/openclaw.json.bak
```

回滚：
```bash
sudo cp /etc/openclaw/openclaw.json.bak /etc/openclaw/openclaw.json
sudo systemctl restart openclaw-gateway.service
```

### 6.2 root snapshot

`/etc/openclaw/openclaw.json` 位于 root 文件系统，在 root snapshot 保护范围内。如果 `.bak` 文件也被损坏，可通过 root snapshot 恢复。

### 6.3 plugin 文件 rollback

如果需要取消 deploy action 的 agent-facing 可用性，恢复旧版 plugin（移除 deploy from ENABLED_ACTIONS）：

```bash
sudo cp /var/lib/openclaw/host-ops-tool-backups/index.js.bak-pre-deploy-slice \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo systemctl restart openclaw-gateway.service
```

---

## 7. Post-deploy health gate

deploy 成功后，必须验证：

1. **gateway_health**（通过 broker）：`ok: true, status: ok`
2. **gateway service status**：`systemctl is-active openclaw-gateway.service` → active
3. **broker service status**：`systemctl is-active openclaw-broker.service` → active
4. **gateway journal**：无 config validation errors

注意：deploy 本身不触发 gateway restart。新配置只有在 gateway restart 后才生效。因此 health gate 分两步：

- **deploy 后立即**：确认 deploy wrapper 返回 `ok: true`，文件已落盘，hash 匹配
- **gateway restart 后**：确认 gateway 以新配置正常启动（这一步在 deploy slice 中可能仍由 operator 手动执行）

---

## 8. repo-side 最小计划

### 8.1 plugin 代码变更

在 `plugins/host-ops-tool/index.js` 中：

- 将 `deploy_openclaw_json_candidate` 加入 `ENABLED_ACTIONS`
- 更新 tool description 和 schema enum 中的 supported actions 列表
- **不改变任何其他逻辑**：inputs 透传、参数白名单、fail-closed 均已在 validate slice 中完成

预计 diff：约 5-8 行。

### 8.2 文档 / records 变更

- 新增 `docs/records/phase2-hostops-deploy-candidate-activation-YYYY-MM-DD.md`（scaffold 版本）
- 更新 `docs/host-sop.md`、`docs/design-v3.md`、`host-ops-api.md` 中的阶段边界
- 本 planning 文档转为 "设计已审批" 状态

### 8.3 不应立即做的事

- **不应立即开放 gateway_restart**：deploy slice 中 gateway restart 由 operator 手动执行
- **不应立即开放 snapshot_pre/post**：同上
- **不应一次性开放多个写操作 action**

---

## 9. Live-side 纪律方案（仅方案，不执行）

### 9.1 deploy slice 的 live 实施流程

```
operator: snapshot_pre（手动或通过 sudo broker 直接调用）
     │
     ▼
operator: 备份当前 plugin index.js
     │
     ▼
operator: 复制新版 index.js 到 live（含 deploy in ENABLED_ACTIONS）
     │
     ▼
operator: sudo systemctl restart openclaw-gateway.service
     │
     ▼
operator: 验证 gateway + broker 健康
     │
     ▼
agent: /reset 或 new session（获取新 tool schema）
     │
     ▼
agent: host_ops(action: "validate_openclaw_json_candidate", inputs: {...})
     │  → 确认候选文件合法
     ▼
agent: host_ops(action: "deploy_openclaw_json_candidate", inputs: {...})
     │  → 部署候选文件到 /etc/openclaw/openclaw.json
     ▼
operator: sudo systemctl restart openclaw-gateway.service（因为 gateway_restart 未开放）
     │
     ▼
agent: host_ops(action: "gateway_health")
     │  → 确认 gateway 以新配置正常启动
     ▼
operator: snapshot_post（手动）
     │
     ▼
operator: vault_sync（可选，手动）
```

### 9.2 何时必须做 snapshot_pre

- 在任何 deploy 操作之前
- snapshot_pre 必须在 deploy 同一操作窗口内完成，不能跨天或跨多次变更

### 9.3 deploy 是否必须先通过 validate

- **是**：agent 行为规范要求先 validate 再 deploy
- 但 plugin 不强制会话级 validate-before-deploy 检查（无状态）

### 9.4 何时允许 vault_sync

- 在 snapshot_post 完成且 health gate 通过后
- 不应在 deploy 后、snapshot_post 前做 vault_sync

### 9.5 Rollback 的首要锚点

1. `/etc/openclaw/openclaw.json.bak`（deploy wrapper 自动创建）
2. root snapshot（snapshot_pre 创建）
3. plugin 文件 backup（恢复旧 ENABLED_ACTIONS）

---

## 10. deploy slice 的 E2E 验收计划（草案）

### 10.1 正例

```
host_ops(action: "deploy_openclaw_json_candidate", inputs: {
  candidate_path: "/var/lib/openclaw/approvals/candidates/<test-candidate>.json",
  expected_sha256: "<actual sha256>"
})
```

验收标准：
- 返回 `ok: true`, `status: "ok"`
- `artifacts` 包含 `deployed_path`, `deployed_sha256`, `backup_path`
- `/etc/openclaw/openclaw.json` 内容已更新
- `.bak` 文件已创建
- broker 日志有对应请求记录

### 10.2 负例（复用 validate 的负例框架）

- 白名单外路径：拒绝
- 路径穿越：拒绝
- SHA256 格式错误：拒绝
- 候选文件不存在：拒绝
- SHA256 不匹配：拒绝

### 10.3 gateway_health 回归

- deploy slice 不应影响 gateway_health 和 validate 的正常工作

---

## 11. 下一轮 ClaudeCode 提示词草案

> 你当前的任务是为 `deploy_openclaw_json_candidate` 完成 agent-facing 开放的 repo-side 实施。
>
> 前置条件：
> - `gateway_health` 和 `validate_openclaw_json_candidate` 已 live verified
> - 本设计文档已审批
>
> 你需要做的：
> 1. 在 `plugins/host-ops-tool/index.js` 的 `ENABLED_ACTIONS` 中加入 `deploy_openclaw_json_candidate`
> 2. 更新 tool description 和 schema enum
> 3. 创建 `docs/records/phase2-hostops-deploy-candidate-activation-YYYY-MM-DD.md`（scaffold 版本，包含正例/负例/rollback）
> 4. 最小同步 docs（host-sop, design-v3, host-ops-api）
> 5. Commit（不 push）
>
> 你不能做的：
> - 不开放 gateway_restart / snapshot_pre / snapshot_post
> - 不做 live deploy
> - 不做 agent-facing E2E
> - 不修改 /etc/openclaw/openclaw.json
>
> Live 实施将在 repo-side 审批后，由 operator 按照设计文档中的流程手动执行。

---

## 12. 风险清单

| 风险 | 严重程度 | 缓解措施 |
|------|----------|----------|
| deploy 导致 config 损坏 | **高** | wrapper 有 post-deploy hash verification + 自动回滚到 .bak |
| .bak 文件被后续 deploy 覆盖 | **中** | 每次 deploy 覆盖同一个 .bak；如需多级回滚，依赖 root snapshot |
| agent 跳过 validate 直接 deploy | **中** | 纪律文档约束 + wrapper 独立做 SHA256 校验（不依赖 validate 结果） |
| deploy 后 gateway 无法启动 | **高** | health gate 检测 + .bak 回滚 + root snapshot |
| gateway_restart 未开放导致新配置不生效 | **低** | 明确 deploy ≠ 配置生效，operator 手动 restart |
| 旧 session 缓存旧 tool schema | **低** | /reset 或新 session |
