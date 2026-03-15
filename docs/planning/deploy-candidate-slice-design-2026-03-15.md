# deploy_openclaw_json_candidate — 下一阶段实施设计

> 文档类型：**设计 / planning note（非实施事实）**
> 创建日期：2026-03-15
> 路线裁决日期：2026-03-15
> 作者：nick + ClaudeCode
> 前置完成：`gateway_health` E2E live verified, `validate_openclaw_json_candidate` E2E live verified
> 目标：为 `deploy_openclaw_json_candidate` 的 agent-facing 开放建立严谨的实施方案
> 状态：**repo-side 实施完成（plugin 代码已提交，docs/checklist/scaffold 已同步）— 待 live 实施**

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

### 3.3 候选路线比较

#### Route A：先单独开放 deploy，snapshot/restart 由 operator 手动

在 `ENABLED_ACTIONS` 中加入 `deploy_openclaw_json_candidate`。agent 可以 validate + deploy。但 `snapshot_pre` / `gateway_restart` / `snapshot_post` 仍不在 ENABLED_ACTIONS 中，必须由 operator 手动执行。

- 优势：一次只扩一个写操作 action，暴露面最小；与 validate slice 的逻辑延续性最强；plugin 代码改动最小（约 5-8 行）；deploy wrapper 已有 post-deploy hash verification + 自动回滚到 .bak
- 劣势：deploy 后系统处于"配置文件已更新但 gateway 仍运行旧配置"的中间状态；agent 无法自主完成完整 workflow

#### Route B：先开放 snapshot_pre + snapshot_post，再进入 deploy

先在 `ENABLED_ACTIONS` 中加入 `snapshot_pre` + `snapshot_post`，deploy 留到下一轮。

- 优势：snapshot 是更保守的操作（创建只读快照，不修改现有状态）
- 劣势：snapshot 的 agent-facing 价值在 deploy 未开放前很有限；增加一轮中间切片，延长 deploy 时间线；snapshot wrapper 曾有 stdout 污染 bug（已修复）

#### Route C：开放 deploy + 强制 operator-mediated checklist（推荐）

开放 deploy，代码变更与 Route A 完全相同。但在 SOP、workspace agent instructions、host-ops-api.md 中明确要求 deploy 必须运行在严格的 operator-mediated checklist 中。文档级别锁定"文件写入成功 ≠ 配置生效成功"。

- 优势：与 Route A 的代码改动完全一致，零额外工程成本；但文档约束更强，审计清晰度更高；对"deploy ≠ 配置生效"的歧义有最明确的文档锁定
- 劣势：文档级约束不是 hard block——但 Route A 也同样面对这一限制

#### Route D：Deploy + snapshot_pre 联合开放

同时开放 `deploy_openclaw_json_candidate` + `snapshot_pre`。

- 优势：agent 能执行"snapshot_pre → validate → deploy"的前半段完整流程
- 劣势：一次开放两个 action，暴露面较大；不对称状态（能做 pre 不能做 post）

#### 路线对比矩阵

| 评估维度 | Route A | Route B | Route C | Route D |
|----------|---------|---------|---------|---------|
| 最小 live 风险 | ★★★★ | ★★★★★ | ★★★★ | ★★★ |
| 最强 fail-closed | ★★★★ | ★★★★ | ★★★★ | ★★★ |
| 最清晰阶段边界 | ★★★★ | ★★★ | ★★★★★ | ★★★ |
| 最容易审计 | ★★★★ | ★★★ | ★★★★★ | ★★★ |
| 最少半生效中间状态 | ★★★ | ★★★★ | ★★★★ | ★★★ |
| 最少一次暴露 | ★★★★★ | ★★★★★ | ★★★★★ | ★★★ |
| 最容易复用 SOP/records | ★★★★ | ★★★ | ★★★★★ | ★★★ |
| 实际工程推进价值 | ★★★★★ | ★★ | ★★★★★ | ★★★★ |

### 3.4 路线裁决结论

**推荐路线：Route C — 开放 deploy + 强制 operator-mediated checklist。**

Route C 是 Route A 的严格增强版。两者代码层面完全一致（只在 `ENABLED_ACTIONS` 中加入 `deploy_openclaw_json_candidate`），但 Route C 额外要求：

1. planning 文档中必须有唯一明确的 deploy 成功定义（区分文件写入成功 vs 配置生效成功）
2. 文档中必须有 operator-mediated checklist，明确 deploy 后的 restart / health / snapshot 步骤
3. 文档中必须有 rejected alternatives 段落

### 3.5 Rejected Alternatives

**Route B 被拒绝**：snapshot 的独立 agent-facing 开放在 deploy 未开放前没有实际价值；增加了一轮无意义的中间切片；延长了 deploy 的开放时间线却未增加安全保障。

**Route D 被拒绝**：一次开放两个 action 违反了"最少一次性扩大 action 暴露面"的原则；snapshot_pre 的 agent-facing 验收引入额外测试负担；不对称状态（能做 pre 不能做 post）增加了认知负担。

**纯 Route A 未被采纳**：代码改动与 Route C 完全一致，但缺少文档层面的显式约束（operator-mediated checklist、deploy 成功定义精确化、rejected alternatives 记录）。Route C 在零额外工程成本下提供了更高的审计清晰度。

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
| params 中有未知字段 | plugin `execute()` 参数白名单 | 返回 `ok: false, status: error` |
| inputs 非 object | plugin `execute()` | 返回 `ok: false, status: error` |
| candidate_path 缺失或非 string | plugin `validateActionInputs` | 返回 `ok: false, status: error` |
| candidate_path 不在白名单前缀 | plugin `validateActionInputs` + wrapper `broker_validate_path` | 返回 `ok: false, status: error` |
| candidate_path 包含 `..` | plugin `validateActionInputs` + wrapper `broker_validate_path` | 返回 `ok: false, status: error` |
| expected_sha256 格式不合法 | plugin `validateActionInputs` + wrapper `broker_validate_sha256` | 返回 `ok: false, status: error` |
| 候选文件不存在 | wrapper live 执行 | 返回 `ok: false, status: error, E_FILE_NOT_FOUND` |
| 候选文件 SHA256 与 expected 不匹配 | wrapper live 执行（pre-deploy） | 返回 `ok: false, status: error, E_WRAPPER_FAILED` |
| 当前 config 备份（.bak）创建失败 | wrapper live 执行（`set -euo pipefail`） | wrapper 非零退出，broker 返回 error |
| `cp` / `chown` / `chmod` deploy 操作失败 | wrapper live 执行（`set -euo pipefail`） | wrapper 非零退出，broker 返回 error |
| post-deploy SHA256 验证失败 | wrapper live 执行 | **自动回滚到 .bak** + 返回 `ok: false` |
| broker 连接失败 | plugin `sendRequest` | 返回 `ok: false, status: error` |
| broker 返回非 JSON 或无效 result | plugin `validateResult` | 返回 `ok: false, status: error` |

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

## 7. Deploy 成功定义（精确化）

deploy slice 的"成功"必须严格区分三个层次：

| 层次 | 定义 | 谁负责 | 属于 deploy slice 吗？ |
|------|------|--------|----------------------|
| **deploy 写入成功** | candidate 文件通过 wrapper 写入 `/etc/openclaw/openclaw.json`，post-deploy hash 验证通过，.bak 已创建 | agent + broker wrapper | **是** |
| **配置生效成功** | gateway restart 后新配置被加载，`gateway_health` 返回 ok | operator（手动 restart）+ agent（health check） | **否** — 属于 restart gate |
| **变更窗口关闭** | snapshot_post 完成，可选 vault_sync | operator（手动） | **否** — 属于 snapshot gate |

**关键约束**：agent 在 deploy wrapper 返回 `ok: true` 后，可以声称"文件已写入"，但**不能声称"新配置已生效"**——除非 operator 手动 restart 后 agent 调用 `gateway_health` 确认。

---

## 8. Post-deploy health gate

deploy 成功后，必须验证：

1. **gateway_health**（通过 broker）：`ok: true, status: ok`
2. **gateway service status**：`systemctl is-active openclaw-gateway.service` → active
3. **broker service status**：`systemctl is-active openclaw-broker.service` → active
4. **gateway journal**：无 config validation errors

注意：deploy 本身不触发 gateway restart。新配置只有在 gateway restart 后才生效。因此 health gate 分两步：

- **deploy 后立即**：确认 deploy wrapper 返回 `ok: true`，文件已落盘，hash 匹配
- **gateway restart 后**：确认 gateway 以新配置正常启动（这一步在 deploy slice 中可能仍由 operator 手动执行）

---

## 9. repo-side 最小计划

### 9.1 plugin 代码变更

在 `plugins/host-ops-tool/index.js` 中：

- 将 `deploy_openclaw_json_candidate` 加入 `ENABLED_ACTIONS`
- 更新 tool description 和 schema enum 中的 supported actions 列表
- **不改变任何其他逻辑**：inputs 透传、参数白名单、fail-closed 均已在 validate slice 中完成

预计 diff：约 5-8 行。

### 9.2 文档 / records 变更

- 新增 `docs/records/phase2-hostops-deploy-candidate-activation-YYYY-MM-DD.md`（scaffold 版本）
- 更新 `docs/host-sop.md`、`docs/design-v3.md`、`host-ops-api.md` 中的阶段边界
- 本 planning 文档转为 "设计已审批" 状态

### 9.3 不应立即做的事

- **不应立即开放 gateway_restart**：deploy slice 中 gateway restart 由 operator 手动执行
- **不应立即开放 snapshot_pre/post**：同上
- **不应一次性开放多个写操作 action**

---

## 10. Live-side 纪律方案（仅方案，不执行）

### 10.1 deploy slice 的 live 实施流程

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

### 10.2 何时必须做 snapshot_pre

- 在任何 deploy 操作之前
- snapshot_pre 必须在 deploy 同一操作窗口内完成，不能跨天或跨多次变更

### 10.3 deploy 是否必须先通过 validate

- **是**：agent 行为规范要求先 validate 再 deploy
- 但 plugin 不强制会话级 validate-before-deploy 检查（无状态）

### 10.4 何时允许 vault_sync

- 在 snapshot_post 完成且 health gate 通过后
- 不应在 deploy 后、snapshot_post 前做 vault_sync

### 10.5 Rollback 的首要锚点

1. `/etc/openclaw/openclaw.json.bak`（deploy wrapper 自动创建）
2. root snapshot（snapshot_pre 创建）
3. plugin 文件 backup（恢复旧 ENABLED_ACTIONS）

---

## 11. Operator-Mediated Checklist（deploy slice 操作窗口）

> 以下 checklist 是 Route C 的核心交付物。deploy slice 的每次执行必须在一个操作窗口内完成所有步骤。本 checklist 是纪律约束，不由 plugin 或 wrapper 自动执行。

### 操作前

- [ ] operator: `snapshot_pre`（手动，`sudo btrfs subvolume snapshot -r / /.snapshots/root-pre-deploy-YYYYMMDD-HHMM`）
- [ ] operator: 备份当前 plugin index.js（如果本轮是首次 deploy slice 激活）

### 配置部署

- [ ] agent: `host_ops(action: "validate_openclaw_json_candidate", inputs: {...})` → 确认 `ok: true`
- [ ] agent: `host_ops(action: "deploy_openclaw_json_candidate", inputs: {...})` → 确认 `ok: true`
- [ ] operator 确认：deploy 返回 `ok: true` 代表的是**文件写入成功**，不代表配置已生效

### 配置生效

- [ ] operator: `sudo systemctl restart openclaw-gateway.service`
- [ ] operator: 确认 `systemctl is-active openclaw-gateway.service` → `active`
- [ ] operator: 确认 `systemctl is-active openclaw-broker.service` → `active`
- [ ] agent: `host_ops(action: "gateway_health")` → 确认 `ok: true`
- [ ] operator: 检查 gateway journal 无 config validation errors

### 变更窗口关闭

- [ ] operator: `snapshot_post`（手动）
- [ ] operator: `vault_sync`（可选，手动）
- [ ] operator: 确认本操作窗口内所有步骤已完成，记录到 activation record

---

## 12. deploy slice 的 E2E 验收计划（草案）

### 12.1 正例

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

### 12.2 负例（复用 validate 的负例框架）

- 白名单外路径：拒绝
- 路径穿越：拒绝
- SHA256 格式错误：拒绝
- 候选文件不存在：拒绝
- SHA256 不匹配：拒绝

### 12.3 gateway_health 回归

- deploy slice 不应影响 gateway_health 和 validate 的正常工作

---

## 13. 下一轮 ClaudeCode 提示词草案

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

## 14. 风险清单

| 风险 | 严重程度 | 缓解措施 |
|------|----------|----------|
| deploy 导致 config 损坏 | **高** | wrapper 有 post-deploy hash verification + 自动回滚到 .bak |
| .bak 文件被后续 deploy 覆盖 | **中** | 每次 deploy 覆盖同一个 .bak；如需多级回滚，依赖 root snapshot |
| agent 跳过 validate 直接 deploy | **中** | 纪律文档约束 + wrapper 独立做 SHA256 校验（不依赖 validate 结果） |
| deploy 后 gateway 无法启动 | **高** | health gate 检测 + .bak 回滚 + root snapshot |
| gateway_restart 未开放导致新配置不生效 | **低** | 明确 deploy ≠ 配置生效，operator 手动 restart |
| 旧 session 缓存旧 tool schema | **低** | /reset 或新 session |
