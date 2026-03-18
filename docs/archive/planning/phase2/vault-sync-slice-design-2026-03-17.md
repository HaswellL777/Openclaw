# vault_sync — agent-facing 启用切片实施设计

> 文档类型：**设计 / planning note**
> 创建日期：2026-03-17
> 作者：nick + ClaudeCode
> 前置完成：`gateway_health`, `validate_openclaw_json_candidate`, `deploy_openclaw_json_candidate`, `snapshot_pre`, `snapshot_post`, `rollback_prepare`, `gateway_restart` 均已 live E2E verified (7/8)
> 目标：完成 `vault_sync` 的 repo-side 实施，启用 8/8 最后一个 action
> 状态：**repo-side 实施中（2026-03-17）— 待 live activation**

---

## 1. 当前真实边界

### 1.1 已 live verified（7 个）

| Action | 类型 | 验证日期 | Evidence |
|--------|------|----------|----------|
| `gateway_health` | 只读 | 2026-03-15 | E2E 成功 |
| `validate_openclaw_json_candidate` | 只读 | 2026-03-15 | E2E 成功（正例 + 负例） |
| `deploy_openclaw_json_candidate` | 写操作 | 2026-03-15 | Route C live E2E verified |
| `snapshot_pre` | 写操作（创建只读快照） | 2026-03-16 | live E2E verified |
| `snapshot_post` | 写操作（创建只读快照） | 2026-03-16 | live E2E verified |
| `rollback_prepare` | 纯只读 | 2026-03-16 | live E2E verified |
| `gateway_restart` | 写操作（deferred dispatch） | 2026-03-16 | live E2E verified（12/12 PASS） |

### 1.2 仍未开放（1 个）

| Action | 类型 | 当前状态 |
|--------|------|----------|
| `vault_sync` | 写操作（btrfs send/receive） | **本轮 repo-side ready，待 live activation** |

---

## 2. vault_sync 定位

### 2.1 是什么

> send 指定已有 snapshot 到 vault 的 broker wrapper

- 接收 `snapshot_name` 参数，发送 `/.snapshots/$snapshot_name` 到 vault
- 支持 incremental send（通过 `last_sent` 追踪 parent）
- 不创建快照（创建是 snapshot_pre/snapshot_post 的职责）
- 不管理 gateway lifecycle（不需要 stop/start gateway）

### 2.2 不是什么

- **不是** 权威脚本 `/usr/local/sbin/vault-backup-root-btrfs` 的 façade
  - 权威脚本自行创建 `root-auto-*` 快照，不接受外部 snapshot_name 参数
  - 权威脚本有 gateway stop/start 逻辑（当前 no-op 因检查的是 `openclaw.service`）
  - wrapper 与权威脚本是独立并行的两条路径
- **不是** 自动创建 snapshot 的工具
- **不是** gateway lifecycle 工具

### 2.3 wrapper 与权威脚本的职责划分

| 维度 | 权威脚本 `vault-backup-root-btrfs` | wrapper `ocw-vault-sync.sh` |
|------|-------------------------------------|------------------------------|
| 触发方式 | systemd timer（每日 03:40）或手动 | broker 请求（agent 发起） |
| 快照创建 | 自行创建 `root-auto-*` | 不创建，仅发送已有快照 |
| 接收路径 | `/mnt/vault/recv/system` | `/mnt/vault/recv/system`（修正后一致） |
| last_sent | `/var/lib/openclaw/backup/last_sent` | 同一文件（共享状态） |
| gateway 管理 | 检查 `openclaw.service`（当前 no-op） | 不管理 |
| 挂载/卸载 | 自行 mount/umount + cleanup trap | 自行 mount/umount + cleanup trap |

**共享 last_sent 的影响**：wrapper 写入 last_sent 后，权威脚本下次运行时会以 wrapper 写入的快照为 parent 做增量 send。这是正确的行为——两条路径共享增量链，避免冗余 full send。

---

## 3. 现有代码问题与修正

### 3.1 Wrapper `ocw-vault-sync.sh`

| 问题 | 修正 |
|------|------|
| `VAULT_SNAPSHOT_DIR="${VAULT_MOUNT}/snapshots"` 路径错误 | → `"${VAULT_MOUNT}/recv/system"` |
| 无 `LAST_SENT_FILE` 变量 | 新增 `LAST_SENT_FILE="/var/lib/openclaw/backup/last_sent"` |
| 无 cleanup trap | 新增 `cleanup()` + `trap cleanup EXIT`，仅在 wrapper 自己挂载时才 umount |
| 无 incremental send 实现 | 实现完整 incremental 逻辑（读 last_sent → 验证双端 parent → send -p） |
| `incremental` 结果回显输入而非实际行为 | `incremental` 反映实际行为，新增 `actual_mode` 字段 |
| `btrfs receive` stderr 污染 stdout | 所有 btrfs/mount 输出重定向到 stderr |
| dry-run 路径语义过简 | 同步更新为反映 incremental/last_sent 语义 |
| mount 失败时 stderr 污染 stdout（`2>&1`） | 修正为 `>&2` |

### 3.2 Plugin `index.js`

| 问题 | 修正 |
|------|------|
| `vault_sync` 不在 `ENABLED_ACTIONS` 中 | 加入 ENABLED_ACTIONS（7 → 8） |
| `validateActionInputs` 无 `incremental` 类型校验 | 新增：若提供则必须是 boolean |
| Tool description 不含 vault_sync | 更新 |
| Tool parameters 缺少 `snapshot_name`、`incremental` | 补充 |

### 3.3 文档/示例中的错误 vault 路径

| 文件 | 问题 |
|------|------|
| `workspace-main-template/control/runbooks/rollback.md` | `/mnt/vault/snapshots` → `/mnt/vault/recv/system` |
| `workspace-main-template/control/runbooks/openclaw-config-change.md` | `/mnt/vault/snapshots/` → `/mnt/vault/recv/system/` |
| `examples/broker/vault-sync-result.json` | vault_path 路径错误 + 缺少 actual_mode |

---

## 4. Incremental send / last_sent 设计

### 4.1 决策逻辑

```
IF INCREMENTAL=true AND LAST_SENT_FILE 存在:
  读取 PARENT_NAME = cat LAST_SENT_FILE
  IF /.snapshots/$PARENT_NAME 存在 AND btrfs subvolume show 成功:
    IF $VAULT_SNAPSHOT_DIR/$PARENT_NAME 也能 btrfs subvolume show 成功:
      → incremental send: btrfs send -p parent source | btrfs receive dest
      → ACTUAL_MODE="incremental"
    ELSE:
      → fallback: full send
  ELSE:
    → fallback: full send
ELSE:
  → full send
```

### 4.2 成功后状态更新

send/receive 成功 **且** 目标存在验证通过后：
1. `echo "$SNAPSHOT_NAME" > "$LAST_SENT_FILE"`
2. `chmod 600 "$LAST_SENT_FILE"`

仅在验证成功后才写 last_sent，确保 last_sent 始终指向一个已成功同步到 vault 的快照。

### 4.3 cleanup trap

```bash
VAULT_MOUNTED_BY_US="false"

cleanup() {
  if [ "$VAULT_MOUNTED_BY_US" = "true" ]; then
    umount "$VAULT_MOUNT" 2>/dev/null || true
  fi
}
trap cleanup EXIT
```

仅当 wrapper 自己挂载了 vault 时才在退出时卸载。如果 vault 在进入 wrapper 前已挂载，wrapper 不负责卸载。

---

## 5. 返回值契约

### 5.1 成功返回 artifacts

```json
{
  "snapshot_name": "root-pre-config-deploy-20260317",
  "incremental": true,
  "actual_mode": "incremental",
  "parent_snapshot": "root-auto-2026-03-17-0340",
  "vault_path": "/mnt/vault/recv/system/root-pre-config-deploy-20260317",
  "last_sent_updated": true,
  "mode": "live"
}
```

- `incremental`: 反映实际行为（true=实际做了增量，false=实际做了 full），不是回显输入
- `actual_mode`: `"incremental"` / `"full"` / `"dry-run"`
- `parent_snapshot`: 实际使用的 parent 名称，full send 时为 `null`
- `last_sent_updated`: 是否更新了 last_sent 文件

### 5.2 dry-run 返回

同结构，`mode: "dry-run"`，`last_sent_updated: false`。

---

## 6. 不需要 candidate workflow

**不需要修改 `/etc/openclaw/openclaw.json`。** 原因：
- `host_ops` 已在 `main.tools.allow` 中
- `host-ops-tool` 已在 `plugins.allow` 和 `plugins.entries` 中启用
- `vault_sync` 的启用由 plugin 代码中 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更

---

## 7. 不需要 deferred dispatch

权威脚本检查的是 `openclaw.service`（而非 `openclaw-gateway.service`），在当前 live 系统中其 stop/start 逻辑是 no-op。`vault_sync` wrapper 不需要管理 gateway lifecycle，也不会触发 broker SIGTERM 竞态。因此不需要 `systemd-run` deferred dispatch 设计。

---

## 8. Operator activation 步骤概述

1. Pre-change root snapshot
2. 记录当前 `last_sent`
3. 备份 live plugin + wrapper
4. 部署新版 plugin + wrapper
5. Restart gateway
6. 检查 gateway + broker active
7. E2E 验收（正例 + 负例 + 回归）
8. 若失败，执行 rollback

---

## 9. 验收口径

### 9.1 正例：incremental send（Vault 挂载 + last_sent 存在 + parent 双端可用）

```
host_ops(action: "vault_sync", inputs: {
  snapshot_name: "<一个已知存在的 snapshot>",
  incremental: true
})
```

期望：
- `ok: true`, `status: "ok"`
- `actual_mode: "incremental"` 或 `"full"`（取决于 parent 是否双端可用）
- `vault_path` 以 `/mnt/vault/recv/system/` 开头
- `last_sent_updated: true`

### 9.2 负例 1：snapshot 不存在

```
host_ops(action: "vault_sync", inputs: {
  snapshot_name: "nonexistent-snapshot-xyz-99999"
})
```

期望：`status: "error"`，message 含 "Source snapshot not found"，error_code: `E_FILE_NOT_FOUND`

### 9.3 负例 2：缺失 snapshot_name

```
host_ops(action: "vault_sync", inputs: {})
```

期望：plugin 侧 `validateActionInputs` 拒绝

### 9.4 负例 3：snapshot_name 含非法字符

```
host_ops(action: "vault_sync", inputs: { snapshot_name: "bad name spaces!" })
```

期望：plugin 侧 `validateActionInputs` 拒绝

### 9.5 负例 4：incremental 非 boolean

```
host_ops(action: "vault_sync", inputs: { snapshot_name: "test", incremental: "yes" })
```

期望：plugin 侧 `validateActionInputs` 拒绝

### 9.6 回归

- `gateway_health` → `ok: true`
- `snapshot_pre` → `ok: true`
- `snapshot_post` → `ok: true`
- `gateway_restart` → `restart_scheduled: true`（+ 后续 gateway_health 验证）

### 9.7 特殊验证

- E2E 完成后检查 `last_sent` 内容是否已更新为发送的 snapshot 名称
- 检查 vault 中目标 snapshot 目录是否存在

---

## 10. Rollback 口径

### 10.1 首要 rollback：恢复 plugin + wrapper 备份

手动恢复 plugin + wrapper 备份文件 → restart gateway → 验证 health。

效果：回到 7 个 ENABLED_ACTIONS 的基线（不含 vault_sync）。

### 10.2 plugin 文件不在 root snapshot 保护范围

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），不在 root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor。

### 10.3 wrapper 文件在 root snapshot 保护范围内

wrapper 文件位于 `/opt/openclaw/broker/wrappers/`（root filesystem），在 root snapshot 保护范围内。首要 rollback 仍使用文件级备份恢复，root snapshot 作为额外锚点。

### 10.4 last_sent 的 rollback

如果 wrapper 已成功执行并更新了 `last_sent`，rollback plugin/wrapper 不会回滚 `last_sent` 文件。这是正确的——last_sent 记录了实际已同步到 vault 的最新快照，回滚代码不应改变这个事实。

---

## 11. Commit 计划

1. `docs(planning): vault_sync slice design`
   - `docs/planning/vault-sync-slice-design-2026-03-17.md`

2. `feat(host-ops-tool): enable vault_sync agent slice`
   - `broker/wrappers/ocw-vault-sync.sh`（路径修正 + incremental 实现 + cleanup trap）
   - `plugins/host-ops-tool/index.js`（ENABLED_ACTIONS + description + parameters）
   - `workspace-main-template/control/runbooks/rollback.md`（vault 路径修正）
   - `workspace-main-template/control/runbooks/openclaw-config-change.md`（vault 路径修正）
   - `examples/broker/vault-sync-result.json`（vault 路径修正 + actual_mode）
   - `workspace-main-template/control/host-ops-api.md`（状态更新）

3. `docs: complete vault_sync live E2E verified and sync boundary`（待 E2E 后）
   - `docs/records/phase2-hostops-vault-sync-activation-2026-03-17.md`
   - `docs/host-sop.md`
   - `docs/design-v3.md`
   - `workspace-main-template/control/host-ops-api.md`
