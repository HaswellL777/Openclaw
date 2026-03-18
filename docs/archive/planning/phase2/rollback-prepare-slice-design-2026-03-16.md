# rollback_prepare — 下一安全切片实施设计

> 文档类型：**设计 / planning note**
> 创建日期：2026-03-16
> 作者：nick + ClaudeCode
> 前置完成：`gateway_health`, `validate_openclaw_json_candidate`, `deploy_openclaw_json_candidate`, `snapshot_pre`, `snapshot_post` 均已 live E2E verified
> 目标：为 `rollback_prepare` 的 agent-facing 开放建立严谨的实施方案
> 状态：**repo-side 实施完成（2026-03-16）— 待 live activation**
>
> - repo-side：plugin 代码 + wrapper 修正已提交，activation/revert 脚本已就绪
> - live-side：待 operator 执行 plugin + wrapper 双部署 + gateway restart + E2E 验收
> - 其余 2 个 action（`gateway_restart`, `vault_sync`）仍未 agent-facing 开放
> - rollback_prepare 的成功不代表 rollback 能力已完整——它只验证 snapshot 存在性并返回 prepare-only metadata，实际 rollback 仍需 LiveUSB/救援环境

---

## 1. 当前真实边界

### 1.1 已 live verified（5 个）

| Action | 类型 | 验证日期 | Evidence |
|--------|------|----------|----------|
| `gateway_health` | 只读 | 2026-03-15 | E2E 成功 |
| `validate_openclaw_json_candidate` | 只读 | 2026-03-15 | E2E 成功（正例 + 负例） |
| `deploy_openclaw_json_candidate` | 写操作 | 2026-03-15 | Route C live E2E verified（正例 + 负例含 wrapper 侧 + 回归通过） |
| `snapshot_pre` | 写操作（创建只读快照） | 2026-03-16 | live E2E verified（正例 + 负例 + 回归通过） |
| `snapshot_post` | 写操作（创建只读快照） | 2026-03-16 | live E2E verified（正例 + 负例 + 回归通过） |

### 1.2 仍未开放（3 个）

| Action | 类型 | 当前状态 |
|--------|------|----------|
| `rollback_prepare` | 纯只读（验证 snapshot 存在性 + 返回 metadata） | **本轮 repo-side ready，待 live activation** |
| `gateway_restart` | 写操作 | **未开放** — 返回语义不稳，依赖链根因待独立复核 |
| `vault_sync` | 写操作 | 未开放 — Vault receive 路径与 wrapper 代码存在漂移；`incremental` 契约与实现不一致 |

---

## 2. 为什么下一 slice 是 rollback_prepare

### 2.1 rollback_prepare 的优势

1. **纯只读 action**：仅执行 `btrfs subvolume show` 验证 snapshot 存在性，不执行任何变更
2. **副作用为零**：不创建快照、不删除文件、不修改配置、不重启服务
3. **代码改动已有基础**：wrapper 已实现，仅需将 `rollback_steps` 语义过强的字段替换为 prepare-only metadata
4. **不修改 `/etc/openclaw/openclaw.json`**：启用由 plugin 代码 `ENABLED_ACTIONS` 控制
5. **rollback 最简单**：恢复 plugin + wrapper 备份 + restart gateway 即可
6. **与前一 slice 差异明确**：本次需同时部署 plugin 和 wrapper（activation 脚本扩展覆盖）

### 2.2 wrapper 修正要点

**移除**：`ROLLBACK_STEPS` 变量及其在 dry-run 和 live 两条路径的引用

**替换为 prepare-only metadata**（dry-run 和 live 使用相同字段结构）：
- `prepare_only: true` — 明确声明这是 prepare-only 操作
- `rollback_executed: false` — 明确声明未执行实际 rollback
- `scope: "root-filesystem-only"` — 明确声明 rollback 范围仅覆盖 root filesystem
- `excluded_paths: ["/var/lib/openclaw"]` — 明确声明独立子卷不在 rollback 范围内
- `operator_action_required: true` — 明确声明实际 rollback 需要 operator 手动执行（LiveUSB/救援环境）
- `snapshot_verified`：dry-run 为 `null`，live 为 `true`

**不能出现的字段**：`rollback_steps`

### 2.3 为什么不是其他 2 个

| Action | 不选原因 |
|--------|----------|
| `gateway_restart` | 返回语义不稳（broker 被 SIGTERM 导致请求返回值不可靠），依赖链根因待独立复核 |
| `vault_sync` | Vault receive 路径（`/mnt/vault/recv/system`）与 wrapper 代码存在漂移；`incremental` 在接口层宣称存在但实现层未体现真正 incremental send 机制；依赖 Vault 挂载（`noauto`），运行时条件更复杂 |

---

## 3. Plugin 6 处修改点

1. **`ENABLED_ACTIONS`** 新增 `"rollback_prepare"`（从 5 扩展到 6）
2. **Tool `description`** 更新为包含 rollback_prepare
3. **`action` enum `description`** 更新为包含 rollback_prepare
4. **`inputs.properties`** 添加 `target_snapshot` 字段声明
5. **`reason` description** 更新为包含 rollback_prepare
6. **`inputs` description** 更新为包含 rollback_prepare

---

## 4. Activation 脚本覆盖 plugin + wrapper 双部署

关键差异（相比 snapshot_post 的 activation 脚本）：

### 4.1 双部署
- **Plugin 源**：`plugins/host-ops-tool/index.js` → `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js`（openclaw:openclaw 644）
- **Wrapper 源**：`broker/wrappers/ocw-rollback-prepare.sh` → `/opt/openclaw/broker/wrappers/ocw-rollback-prepare.sh`（root:root 755）

### 4.2 双备份
- Plugin 备份：`/var/lib/openclaw/host-ops-tool-backups/index.js.backup-before-rollback-prepare-slice-{TIMESTAMP}`
- Wrapper 备份：`/var/lib/openclaw/host-ops-tool-backups/ocw-rollback-prepare.sh.backup-before-rollback-prepare-slice-{TIMESTAMP}`

### 4.3 Preflight 内容验证
- 验证 repo plugin 含 `"rollback_prepare"` 字符串
- 验证 repo wrapper 含 `"prepare_only"` 字符串

### 4.4 result.env 扩展字段
- `WRAPPER_BACKUP_FILE`、`LIVE_WRAPPER_FILE`、`WRAPPER_BACKUP_SHA256`、`WRAPPER_DEPLOYED_SHA256`

### 4.5 Pre-change snapshot
- 在脚本内部完成
- **不创建 post-change snapshot**（E2E 通过后单独执行）

---

## 5. Revert 脚本覆盖 plugin + wrapper 双恢复

关键差异（相比 snapshot_post 的 rollback 脚本）：

- 从 result.env 读取 plugin 和 wrapper 双备份路径
- 恢复 plugin（openclaw:openclaw 644）
- 恢复 wrapper（root:root 755）
- 重启 gateway，健康检查

---

## 6. 同步的 fixture / example

- `examples/broker/rollback-prepare-result.json`：从 `rollback_steps` 同步为 prepare-only metadata 契约
- `tests/` 目录中无 `rollback_steps` 引用，无需修改

---

## 7. 验收口径

### 7.1 正例

```
host_ops(action: "rollback_prepare", inputs: {
  target_snapshot: "<已存在的 snapshot 名>",
  reason: "E2E verification of rollback_prepare agent slice"
})
```

期望：
- `ok: true`, `status: "ok"`
- `prepare_only: true`
- `rollback_executed: false`
- `excluded_paths` 含 `/var/lib/openclaw`
- **不存在** `rollback_steps` 字段

### 7.2 负例 1：缺失 target_snapshot

```
host_ops(action: "rollback_prepare", inputs: { reason: "test" })
```

期望：`status: "error"`（plugin `validateActionInputs` 拦截）

### 7.3 负例 2：不存在的 snapshot

```
host_ops(action: "rollback_prepare", inputs: {
  target_snapshot: "nonexistent-snapshot-xyz",
  reason: "negative test"
})
```

期望：`status: "error"`（wrapper `broker_error` 返回，`E_FILE_NOT_FOUND`）

### 7.4 负例 3：确认 vault_sync 不在 action enum 中

验证方式：确认 agent 看到的 action enum 恰好为 6 个值（gateway_health, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, rollback_prepare）且不含 vault_sync / gateway_restart。

尝试：
```
host_ops(action: "vault_sync", inputs: { snapshot_name: "test-denied" })
```

期望：gateway/tool schema validation reject（非 plugin 层 denied）— "Validation failed for tool \"host_ops\": action: must be equal to one of the allowed values"

### 7.5 回归

- `gateway_health` 返回 `ok: true`
- `snapshot_pre` 返回 `ok: true`
- `snapshot_post` 返回 `ok: true`

### 7.6 验收表述纪律

- 不得将 `rollback_prepare` 成功写成 "host_ops 已完整开放"（仍有 2 个 action 未开放）
- 不得将 `rollback_prepare` 成功写成 "rollback 能力已完整"（它只验证 snapshot 存在性并返回 metadata，实际 rollback 仍需 LiveUSB/救援环境）
- 只能写：`rollback_prepare` 已 live E2E verified；`vault_sync` / `gateway_restart` 仍未开放

---

## 8. Rollback 口径

### 8.1 首要 rollback：plugin + wrapper 文件回滚

使用 revert 脚本：
```bash
sudo bash scripts/revert-rollback-prepare-slice.sh <artifacts-dir>
```

效果：回到 `gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` + `snapshot_pre` + `snapshot_post` 可用的基线（5 个 ENABLED_ACTIONS）。

### 8.2 plugin 文件不在 root snapshot 保护范围内

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），**不在** root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor。

### 8.3 wrapper 文件在 root snapshot 保护范围内

wrapper 文件位于 `/opt/openclaw/broker/wrappers/`（root filesystem），在 root snapshot 保护范围内。但首要 rollback 仍使用文件级备份恢复（revert 脚本），root snapshot 作为额外锚点。

### 8.4 测试 snapshot 的处理

测试生成的验证结果应作为审计痕迹保留，不把"清理测试产物"写进成功定义。

---

## 9. Commit 计划

1. `docs(planning): rollback_prepare slice design`
   - `docs/planning/rollback-prepare-slice-design-2026-03-16.md`

2. `feat(host-ops-tool): enable rollback_prepare agent slice`
   - `broker/wrappers/ocw-rollback-prepare.sh`（修正：移除 rollback_steps，替换为 prepare-only metadata）
   - `plugins/host-ops-tool/index.js`（6 处修改）
   - `examples/broker/rollback-prepare-result.json`（同步新契约）
   - `scripts/activate-rollback-prepare-slice.sh`（新增：plugin + wrapper 双部署）
   - `scripts/revert-rollback-prepare-slice.sh`（新增：plugin + wrapper 双恢复）

3. `docs: complete rollback_prepare live E2E verified and sync boundary`（待 E2E 后）
   - activation record
   - `docs/host-sop.md`
   - `docs/design-v3.md`
   - `workspace-main-template/control/host-ops-api.md`

---

## 10. 文档更新面

| 文档 | 更新内容 |
|------|----------|
| `broker/wrappers/ocw-rollback-prepare.sh` | 移除 rollback_steps，替换为 prepare-only metadata |
| `plugins/host-ops-tool/index.js` | `ENABLED_ACTIONS` + description 文案 + target_snapshot 字段 |
| `examples/broker/rollback-prepare-result.json` | 同步新契约 |
| `scripts/activate-rollback-prepare-slice.sh` | Activation 脚本（新增，plugin + wrapper 双部署） |
| `scripts/revert-rollback-prepare-slice.sh` | Revert 脚本（新增，plugin + wrapper 双恢复） |
| `docs/planning/rollback-prepare-slice-design-2026-03-16.md` | 本文件（新增） |
| `docs/records/phase2-hostops-rollback-prepare-activation-2026-03-16.md` | Activation record（待 E2E 后新增） |
| `docs/host-sop.md` | 边界声明同步（待 E2E 后） |
| `docs/design-v3.md` | 边界声明同步（待 E2E 后） |
| `workspace-main-template/control/host-ops-api.md` | rollback_prepare 状态 + per-action 规格同步（待 E2E 后） |
