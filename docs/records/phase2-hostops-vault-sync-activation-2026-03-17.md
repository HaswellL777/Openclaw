# Phase 2 Host-Ops vault_sync Activation Record — 2026-03-17

> Operator: nick
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Preceding record: `docs/records/phase2-hostops-gateway-restart-activation-2026-03-16.md`
> Status: **live E2E verified — 2026-03-17**

---

## 1. 当前基线（activation 完成后）

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
| Agent-facing `rollback_prepare` | **complete** — live E2E verified（正例 + 负例含 wrapper 侧 E_FILE_NOT_FOUND + 回归，2026-03-16） |
| Agent-facing `gateway_restart` | **complete** — live E2E verified（两段式契约：deferred dispatch via systemd-run + operator 独立检查 + gateway_health 验证，12/12 PASS，2026-03-16） |
| Agent-facing `vault_sync` | **complete** — live E2E verified（incremental send 成功 + 4 个负例全部正确拒绝 + 最小回归通过，2026-03-17） |
| **已 live verified action 总数** | **8 / 8** |

---

## 2. 本轮范围

本轮是 post-`gateway_restart` 的最后一个切片。`vault_sync` 是 8 个 host-ops action 中唯一仍未开放的 action。

### 2.1 vault_sync 定位

> send 指定已有 snapshot 到 vault 的 broker wrapper

- 接收 `snapshot_name` 参数，发送 `/.snapshots/$snapshot_name` 到 vault
- 支持 incremental send（通过 `/var/lib/openclaw/backup/last_sent` 追踪 parent）
- 不创建快照（创建是 snapshot_pre/snapshot_post 的职责）
- 不管理 gateway lifecycle
- 共享 `last_sent` 文件与权威脚本 `/usr/local/sbin/vault-backup-root-btrfs`

### 2.2 wrapper 与权威脚本的关系

| 维度 | 权威脚本 `vault-backup-root-btrfs` | wrapper `ocw-vault-sync.sh` |
|------|-------------------------------------|------------------------------|
| 触发方式 | systemd timer（每日 03:40）或手动 | broker 请求（agent 发起） |
| 快照创建 | 自行创建 `root-auto-*` | 不创建，仅发送已有快照 |
| 接收路径 | `/mnt/vault/recv/system` | `/mnt/vault/recv/system` |
| last_sent | `/var/lib/openclaw/backup/last_sent` | 同一文件（共享增量链） |
| gateway 管理 | 检查 `openclaw.service`（当前 no-op，见 §2.3） | 不管理 |

### 2.3 审计发现：权威脚本服务名漂移

权威脚本 `/usr/local/sbin/vault-backup-root-btrfs` 中检查的是 `openclaw.service`，而非实际运行中的 `openclaw-gateway.service`。在当前 live 系统中，`openclaw.service` 不存在或非 active，因此脚本的 stop/start gateway 逻辑实际为 no-op。

这意味着：
- 权威脚本的 Vault 同步实际上在 gateway 运行状态下执行（一致性风险极低，btrfs send 读取的是只读快照）
- `vault_sync` wrapper 不需要实现 gateway stop/start
- 不需要 deferred dispatch 设计

此漂移不阻塞 vault_sync 收口，但应记录为已知审计事项。

### 2.4 repo-side 代码变更

1. **`broker/wrappers/ocw-vault-sync.sh`** — 完全重写：
   - 修正 vault 接收路径（`/mnt/vault/snapshots` → `/mnt/vault/recv/system`）
   - 新增 `LAST_SENT_FILE="/var/lib/openclaw/backup/last_sent"`
   - 新增 `cleanup()` + `trap cleanup EXIT`（仅在 wrapper 自己挂载 vault 时才 umount）
   - 实现 incremental send（读 last_sent → 验证双端 parent → `btrfs send -p`）
   - full send fallback
   - send/receive 成功后验证目标存在 → 写 last_sent + chmod 600
   - `incremental` 返回值反映实际行为，新增 `actual_mode` 字段
   - 所有 btrfs/mount 输出重定向到 stderr，不污染 JSON stdout
   - dry-run 分支同步更新

2. **`plugins/host-ops-tool/index.js`**：
   - `ENABLED_ACTIONS` 新增 `vault_sync`（7 → 8）
   - `validateActionInputs` 新增 `incremental` 类型校验
   - Tool description / action enum description 更新
   - Tool parameters properties 新增 `snapshot_name`、`incremental`

3. **Vault 路径修正**（三个文件）：
   - `workspace-main-template/control/runbooks/rollback.md`
   - `workspace-main-template/control/runbooks/openclaw-config-change.md`
   - `examples/broker/vault-sync-result.json`
   - 所有 `/mnt/vault/snapshots` → `/mnt/vault/recv/system`

---

## 3. Repo commits（全部已 push）

| Commit | Message | Files |
|--------|---------|-------|
| `5648702` | `docs(planning): vault_sync slice design` | `docs/planning/vault-sync-slice-design-2026-03-17.md` |
| `50ee9cb` | `feat(host-ops-tool): enable vault_sync agent slice` | `broker/wrappers/ocw-vault-sync.sh`, `plugins/host-ops-tool/index.js`, `workspace-main-template/control/host-ops-api.md`, `workspace-main-template/control/runbooks/rollback.md`, `workspace-main-template/control/runbooks/openclaw-config-change.md`, `examples/broker/vault-sync-result.json` |

---

## 4. Live activation

### 4.1 Pre-change snapshot

```
/.snapshots/root-pre-vault-sync-slice-20260317-1621
```

### 4.2 备份

```
备份路径: /var/lib/openclaw/host-ops-tool-backups/index.js.backup-before-vault-sync-slice-20260317-1621
备份路径: /var/lib/openclaw/host-ops-tool-backups/ocw-vault-sync.sh.backup-before-vault-sync-slice-20260317-1621
```

### 4.3 部署

Plugin + wrapper 部署到 live，SHA256 校验：

```
Plugin:
  repo:  0cbb52fa118e6e256fff83d8c6249da5d920e744dc4191a965c9d2557587e048
  live:  0cbb52fa118e6e256fff83d8c6249da5d920e744dc4191a965c9d2557587e048  (match)

Wrapper:
  repo:  aa6545de421111f58dd1ea980afbbd8fd48bca65b51e488befd51e28b9c7631b
  live:  aa6545de421111f58dd1ea980afbbd8fd48bca65b51e488befd51e28b9c7631b  (match)
```

### 4.4 Restart + health gate

```
systemctl is-active openclaw-gateway.service   # active
systemctl is-active openclaw-broker.service     # active
journalctl 无 plugin/tool 注册错误
```

---

## 5. 是否需要 candidate workflow（修改 /etc/openclaw/openclaw.json）

**不需要。** 原因：
- `host_ops` 已在 `main.tools.allow` 中
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `vault_sync` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更

---

## 6. E2E 验收结果（2026-03-17，OpenClaw agent session）

> 执行环境：OpenClaw agent (T800 Bot) via Feishu，fresh session

### 6.1 正例：incremental vault_sync — **PASS**

```
host_ops(action: "vault_sync", inputs: {
  snapshot_name: "root-post-vault-sync-e2e-20260317",
  incremental: true
})
```

结果：
- `ok: true`, `status: "ok"`
- `message: "Vault sync completed (incremental)"`
- `artifacts.snapshot_name: "root-post-vault-sync-e2e-20260317"`
- `artifacts.incremental: true`
- `artifacts.actual_mode: "incremental"`
- `artifacts.parent_snapshot: "root-auto-2026-03-17-0340"`
- `artifacts.vault_path: "/mnt/vault/recv/system/root-post-vault-sync-e2e-20260317"`
- `artifacts.last_sent_updated: true`
- `artifacts.mode: "live"`

验收点：
- [x] `ok: true` 表示 send/receive 成功完成
- [x] `actual_mode: "incremental"` — 实际走了增量路径（parent 双端可用）
- [x] `parent_snapshot: "root-auto-2026-03-17-0340"` — 与 activation 前 last_sent 一致
- [x] `vault_path` 以 `/mnt/vault/recv/system/` 开头（修正后路径）

### 6.2 正例后续：operator 现场核查 — **PASS**

**Step 1 — 确认 last_sent 已更新**：

```bash
sudo cat /var/lib/openclaw/backup/last_sent
# 结果: root-post-vault-sync-e2e-20260317
```

**Step 2 — 确认 vault 中目标 snapshot 存在**：

```bash
sudo mount /mnt/vault
sudo ls /mnt/vault/recv/system/ | grep 'root-post-vault-sync-e2e-20260317'
# 结果: root-post-vault-sync-e2e-20260317（存在）
sudo umount /mnt/vault
```

**Step 3 — 确认 cleanup trap 正常**：

```bash
mount | grep /mnt/vault
# 结果: 无输出（vault 已被 wrapper cleanup trap 卸载）
```

### 6.3 负例 1：snapshot 不存在 — **PASS**

```
host_ops(action: "vault_sync", inputs: {
  snapshot_name: "nonexistent-snapshot-xyz-99999"
})
```

结果：
- `ok: false`, `status: "error"`
- `error_code: "E_FILE_NOT_FOUND"`
- `message: "Source snapshot not found: /.snapshots/nonexistent-snapshot-xyz-99999"`

拒绝层：**wrapper 层**（请求到达 broker，wrapper 执行时发现源 snapshot 不存在）

### 6.4 负例 2：缺失 snapshot_name — **PASS**

```
host_ops(action: "vault_sync", inputs: {})
```

结果：
- `ok: false`, `status: "error"`
- `message: "Request validation failed: vault_sync requires inputs.snapshot_name (string)"`

拒绝层：**plugin 侧** `validateActionInputs` → `validateRequest`

### 6.5 负例 3：非法 snapshot_name — **PASS**

```
host_ops(action: "vault_sync", inputs: { snapshot_name: "bad name spaces!" })
```

结果：
- `ok: false`, `status: "error"`
- `message: "Request validation failed: snapshot_name must be alphanumeric with dots, hyphens, underscores only"`

拒绝层：**plugin 侧** `validateActionInputs` → `validateRequest`

### 6.6 负例 4：incremental 非 boolean — **PASS**

```
host_ops(action: "vault_sync", inputs: { snapshot_name: "test-name", incremental: "yes" })
```

结果：
- `Validation failed for tool "host_ops": inputs/incremental: must be boolean`

拒绝层：**gateway 层 tool schema validation**（`incremental` 在 tool parameters 中声明为 `type: "boolean"`，gateway 在调用 plugin 前即拒绝）

**注意**：此负例不是由 plugin `validateActionInputs` 拒绝的，而是由 gateway 层的 tool schema 校验拒绝。Plugin 侧的 `incremental` 类型检查（`typeof inputs.incremental !== "boolean"`）是第二层防线，本轮被 gateway 层先行拦截。

### 6.7 回归：gateway_health — **PASS**

```
host_ops(action: "gateway_health")
```

结果：`ok: true`, `service_active: "active"`

### 6.8 回归：snapshot_pre — **PASS**

```
host_ops(action: "snapshot_pre", inputs: {
  label: "regress-pre-vault-sync-20260317",
  reason: "regression after vault_sync activation"
})
```

结果：`ok: true`, `snapshot_name: "root-pre-regress-pre-vault-sync-20260317"`

### 6.9 回归：snapshot_post — **PASS**

本轮正例使用的 snapshot `root-post-vault-sync-e2e-20260317` 本身即由 snapshot_post 创建（E2E 准备阶段），可视为 snapshot_post 回归成功。

### 6.10 回归：gateway_restart — **PASS**

```
host_ops(action: "gateway_restart", inputs: {
  reason: "regression after vault_sync activation"
})
```

结果：`ok: true`, `restart_scheduled: true`

后续确认：

```bash
systemctl is-active openclaw-gateway.service   # active
systemctl is-active openclaw-broker.service     # active
```

```
host_ops(action: "gateway_health")
```

结果：`ok: true`

---

## 7. 负例拒绝层分布

| 负例 | 拒绝层 | 说明 |
|------|--------|------|
| snapshot 不存在 | wrapper 层（`E_FILE_NOT_FOUND`） | 请求到达 broker，wrapper 检查 `/.snapshots/` 目录后拒绝 |
| 缺失 snapshot_name | plugin 侧 `validateActionInputs` | `!inputs.snapshot_name` |
| 非法 snapshot_name | plugin 侧 `validateActionInputs` | regex `/^[a-zA-Z0-9._-]+$/` 不匹配 |
| incremental 非 boolean | **gateway 层 tool schema validation** | tool parameters 声明 `type: "boolean"`，gateway 先行拦截 |

三层防御结构：gateway 层 tool schema → plugin 侧 validateRequest → wrapper 层运行时检查。

---

## 8. Rollback 步骤

### 8.1 首要 rollback：恢复 plugin + wrapper 备份

```bash
TS="20260317-1621"

# 恢复 plugin
sudo cp /var/lib/openclaw/host-ops-tool-backups/index.js.backup-before-vault-sync-slice-${TS} \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js

# 恢复 wrapper
sudo cp /var/lib/openclaw/host-ops-tool-backups/ocw-vault-sync.sh.backup-before-vault-sync-slice-${TS} \
        /opt/openclaw/broker/wrappers/ocw-vault-sync.sh
sudo chown root:root /opt/openclaw/broker/wrappers/ocw-vault-sync.sh
sudo chmod 755 /opt/openclaw/broker/wrappers/ocw-vault-sync.sh

# Restart gateway
sudo systemctl restart openclaw-gateway.service

# 验证
systemctl is-active openclaw-gateway.service
systemctl is-active openclaw-broker.service
```

效果：回到 7 个 ENABLED_ACTIONS 的基线（不含 vault_sync）。

### 8.2 plugin 文件不在 root snapshot 保护范围

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），不在 root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor。

### 8.3 wrapper 文件在 root snapshot 保护范围内

wrapper 文件位于 `/opt/openclaw/broker/wrappers/`（root filesystem），在 root snapshot 保护范围内。首要 rollback 仍使用文件级备份恢复，root snapshot 作为额外锚点。

### 8.4 last_sent 的 rollback

如果 vault_sync 已成功执行并更新了 `last_sent`，rollback plugin/wrapper 不会回滚 `last_sent` 文件。这是正确的——`last_sent` 记录了实际已同步到 vault 的最新快照，回滚代码不应改变这个事实。

---

## 9. 当前边界声明

- **已完成（live verified）**：`gateway_health`, `validate_openclaw_json_candidate`, `deploy_openclaw_json_candidate`, `snapshot_pre`, `snapshot_post`, `rollback_prepare`, `gateway_restart`, `vault_sync`
- **已 live verified 的 action 总数**：**8 / 8**
- **Phase 2 agent-facing host_ops 全部 8 个 action 已完成 live E2E 验收**
- 后续工作方向：task-runner / Docker 执行面 / 控制面备份链（均属 Phase 2 以后阶段）

---

## 10. Snapshots

| 类型 | 路径 | 时间 | 备注 |
|------|------|------|------|
| Pre-change | `/.snapshots/root-pre-vault-sync-slice-20260317-1621` | 2026-03-17 16:21 CST | operator 手动创建 |
| Post-change | `/.snapshots/root-post-vault-sync-slice-20260317-1636` | 2026-03-17 16:36 CST | operator 手动创建，E2E 通过后 |
| E2E 回归产生 | `/.snapshots/root-pre-regress-pre-vault-sync-20260317` | 2026-03-17 E2E 期间 | snapshot_pre 回归测试产生，审计保留 |
| Vault sync | `root-post-vault-sync-e2e-20260317` → `/mnt/vault/recv/system/` | 2026-03-17 E2E 期间 | 正例 vault_sync 成功入库，last_sent 已更新 |
