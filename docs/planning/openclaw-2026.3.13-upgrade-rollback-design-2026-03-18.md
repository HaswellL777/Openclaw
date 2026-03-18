# OpenClaw 2026.3.13 升级 Rollback 设计

> 设计日期：2026-03-18
> 升级基线：2026.3.2 → 2026.3.13
> 依赖文档：`docs/runbook-openclaw-upgrade-2026.3.13.md`
> **升级状态：已完成（2026-03-18），rollback 未触发**

---

## 1. Rollback 不是一句"恢复 snapshot"就结束

本系统的 rollback 涉及三个独立存储层，root snapshot 只覆盖其中一层：

| 存储层 | 路径 | 是否在 root snapshot 中 | rollback 方式 |
|--------|------|------------------------|---------------|
| 系统层（含 `/opt/openclaw`、systemd units） | root filesystem | **是** | root snapshot 恢复 |
| 数据层（含 plugin 文件、workspace、session state） | `/var/lib/openclaw`（独立 btrfs 子卷） | **否** | 文件级备份恢复 |
| 配置层 | `/etc/openclaw/openclaw.json` | **是**（root snapshot 中） | `.bak` 文件恢复或 root snapshot |

**关键事实**：root snapshot 恢复后，`/var/lib/openclaw` 中的 plugin 文件仍然是升级后的状态。如果升级导致 plugin 不兼容，仅恢复 root snapshot 不够——还必须恢复 plugin 文件。

## 2. `/var/lib/openclaw` 独立子卷语义

`/var/lib/openclaw` 是独立 btrfs 子卷（在 `docs/host-sop.md` §0.3 中确认），包含：

| 内容 | 路径 | rollback 影响 |
|------|------|---------------|
| host-ops-tool plugin | `.openclaw/extensions/host-ops-tool/` | **不在 root snapshot 中**，必须独立恢复 |
| feishu plugin | `.openclaw/extensions/feishu/` | 同上（但 feishu 由 npm 安装，可重装） |
| workspace-main | `.openclaw/workspace-main/` | 同上（可从 dev repo 重新 publish） |
| session state | `.openclaw/` 下的 session 相关文件 | 不影响核心功能，不需要主动 rollback |
| plugin backups | `host-ops-tool-backups/` | **rollback 锚点**——升级前的 plugin 备份存放在此 |
| backup metadata | `backup/last_sent` | 不应回滚（记录实际 vault sync 状态） |

## 3. Root snapshot、Vault、配置/版本记录三者的关系

```
root snapshot（/.snapshots/root-pre-upgrade-*）
├── 覆盖：/opt/openclaw（OpenClaw 二进制 + node_modules）
├── 覆盖：/etc/openclaw/openclaw.json（配置）
├── 覆盖：/opt/openclaw/broker/wrappers/（wrapper 脚本）
├── 覆盖：systemd unit files
└── 不覆盖：/var/lib/openclaw（独立子卷）

Vault（/mnt/vault/recv/system/）
├── 存储：root snapshot 的 btrfs send/receive 副本
├── 不存储：/var/lib/openclaw 内容（独立子卷）
└── 用途：灾难恢复（系统盘损坏时）

配置/版本记录（在 dev repo 中）
├── B1 步骤记录的 hash/version 信息
├── 用途：验证恢复后状态是否回到了正确基线
└── 不可直接执行恢复——仅供验证
```

**三者协同 rollback 策略**：
1. root snapshot 恢复 → 系统层回到升级前
2. plugin 文件级备份恢复 → 数据层回到升级前
3. 配置/版本记录 → 验证回到了正确基线

## 4. Plugin 不兼容时的应对

### 4.1 症状识别

- gateway journal 出现 plugin registration error
- `host-ops-tool missing register/activate export` 警告重新出现
- `api.registerTool()` 调用报错
- agent 调用 `host_ops` 时返回 tool not found

### 4.2 处理步骤

**首选：恢复 plugin 备份**

```bash
# 确定 TIMESTAMP（B2.3 中使用的）
TS="<填写 B2.3 使用的 TIMESTAMP>"

# 恢复 plugin 文件
sudo cp /var/lib/openclaw/host-ops-tool-backups/index.js.backup-pre-upgrade-${TS} \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo cp /var/lib/openclaw/host-ops-tool-backups/openclaw.plugin.json.backup-pre-upgrade-${TS} \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/openclaw.plugin.json
sudo cp /var/lib/openclaw/host-ops-tool-backups/package.json.backup-pre-upgrade-${TS} \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/package.json

# 恢复权限
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/openclaw.plugin.json
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/package.json
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/openclaw.plugin.json
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/package.json

# restart gateway
sudo systemctl restart openclaw-gateway.service

# 验证
systemctl is-active openclaw-gateway.service
systemctl is-active openclaw-broker.service
```

**如果恢复 plugin 后仍然失败**：说明新版本 OpenClaw 的 plugin SDK 与旧版 plugin 不兼容，需要同时降级 OpenClaw（见 §7）。

## 5. Gateway 起不来时的应对

### 5.1 症状识别

- `systemctl is-active openclaw-gateway.service` 返回 `failed` 或 `activating`
- journal 中有 crash loop 或 config validation error

### 5.2 处理步骤

**Step 1：检查 journal**

```bash
sudo journalctl -u openclaw-gateway.service -n 50 --no-pager
```

**Step 2：判断原因**

| 原因 | journal 特征 | 处理 |
|------|-------------|------|
| config schema error | `Config invalid`、`Zod`、`validation` | 尝试 `.bak` 恢复 |
| plugin manifest error | `plugin manifest not found` | 检查 extensions 目录 |
| node_modules 缺失 | `MODULE_NOT_FOUND` | 重新 `npm install` 或降级 |
| 端口冲突 | `EADDRINUSE` | 检查是否有残留 gateway 进程 |

**Step 3：尝试 config 恢复**

```bash
sudo cp /etc/openclaw/openclaw.json.bak /etc/openclaw/openclaw.json
sudo systemctl restart openclaw-gateway.service
```

**Step 4：如果 config 恢复无效，降级 OpenClaw**

见 §7 完整降级流程。

## 6. Broker 起不来时的应对

### 6.1 症状识别

- gateway active 但 broker inactive/failed
- broker journal 有错误

### 6.2 处理步骤

**Step 1：检查 journal**

```bash
sudo journalctl -u openclaw-broker.service -n 50 --no-pager
```

**Step 2：尝试手动 restart**

```bash
sudo systemctl restart openclaw-broker.service
systemctl is-active openclaw-broker.service
```

**Step 3：检查 socket 权限**

```bash
ls -la /run/openclaw/broker.sock
# 预期: srw-rw---- root openclaw
```

**Step 4：如果 broker 持续失败**

broker 是独立 daemon，不直接依赖 OpenClaw 版本。如果 broker 在 OpenClaw 升级后失败，可能是 systemd 依赖关系变化导致。检查 broker unit 文件是否被升级覆盖。

> 注意：broker 失败时 gateway 仍可运行，agent 基础功能不受影响。
> 仅 host_ops tool 不可用。这不一定需要整体回滚。

## 7. 完整降级流程（最后手段）

> 仅在上述局部恢复措施全部无效时使用。

### 7.1 降级 OpenClaw

```bash
sudo systemctl stop openclaw-gateway.service

cd /opt/openclaw
sudo npm install --omit=dev openclaw@2026.3.2

# 恢复配置（如果已变更）
sudo cp /etc/openclaw/openclaw.json.bak /etc/openclaw/openclaw.json

sudo systemctl start openclaw-gateway.service

# 验证
systemctl is-active openclaw-gateway.service
systemctl is-active openclaw-broker.service
```

### 7.2 恢复 plugin 文件

见 §4.2。

### 7.3 验证回到基线

```bash
# 版本
cd /opt/openclaw && sudo node -e "console.log(require('./node_modules/openclaw/package.json').version)"
# 预期: 2026.3.2

# 配置 hash
sudo sha256sum /etc/openclaw/openclaw.json
# 与 B1.5 记录对比

# plugin hash
sudo sha256sum /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
# 与 B1.6 记录对比

# 服务状态
systemctl is-active openclaw-gateway.service
systemctl is-active openclaw-broker.service

# health check
sudo socat - UNIX-CONNECT:/run/openclaw/broker.sock <<'EOF'
{"action":"gateway_health","request_id":"req-rollback-verify-001","task_id":"task-rollback","requested_by":"operator:nick","inputs":{}}
EOF
```

### 7.4 root snapshot 恢复（灾难级 rollback）

> 仅在 npm 降级也无法恢复时使用。需要 LiveUSB/rescue 环境。

1. 引导到 LiveUSB/rescue
2. 挂载系统盘
3. 用 pre-upgrade snapshot 替换当前 root subvolume
4. 引导回正常系统
5. 独立恢复 `/var/lib/openclaw` 中的 plugin 文件（不在 root snapshot 中）

## 8. 立即停止并回滚的条件

以下情况应**立即停止继续测试并启动 rollback**：

1. **gateway crash loop**：gateway 反复启动失败（journal 中 3 次以上 restart 仍 failed）
2. **config schema 不兼容且 .bak 恢复无效**：说明新版本要求了不兼容的配置格式
3. **plugin 注册导致 gateway 崩溃**：不是 warning 而是 fatal error
4. **node_modules 结构性破坏**：`npm install` 后 gateway 无法找到核心模块
5. **systemd 依赖关系变化导致 broker 无法启动**：且手动 restart 无效
6. **安全相关异常**：如 socket 权限变化、非预期的端口监听

以下情况可以**继续测试，不需要立即回滚**：

1. 个别 action 因测试数据问题失败（如 snapshot 名拼写错误）
2. vault_sync 因 Vault 未挂载失败（环境问题，非版本兼容问题）
3. gateway 启动时有 warning 但无 error 且服务 active
4. 日志路径变化但内容正常

> **实际执行结果（2026-03-18）**：升级成功完成，P0 19/19 PASS，本 rollback 设计未被触发。Broker 需手动启动（非 rollback 场景），provenance 警告非阻塞。本文档保留为 rollback 参考设计，适用于未来同类升级。
