# ACP Spike: Claude Code via acpx — 变更计划

> 日期：2026-03-25
> 候选文件：`candidates/openclaw.acp-spike.candidate.json5`
> 研究报告：`docs/planning/phase4-acp-claude-code-research.md`
> 选定方案：Option A（官方 ACP via acpx）

---

## 1. 变更摘要

| 变更项 | 内容 |
|--------|------|
| `acp` 顶级块 | 新增。启用 ACP dispatch，backend=acpx，maxConcurrentSessions=2，ttl=60min |
| `plugins.allow` | 追加 `"acpx"` |
| `plugins.entries.acpx` | 新增。permissionMode=approve-all, expectedVersion=any |
| `agents.list[]` | 追加 claude-engineer agent，runtime.type=acp |
| 环境变量 | `ANTHROPIC_BASE_URL` + `ANTHROPIC_API_KEY` 写入 openclaw.env 或 systemd override |
| workspace | 需创建 `/var/lib/openclaw/.openclaw/workspace-claude-engineer/` |

## 2. 前置条件检查

operator 在部署前需逐项确认：

```bash
# 2.1 确认 acpx 已 bundled
ls -la /opt/openclaw/extensions/acpx/
# 期望：目录存在，含 package.json

# 2.2 确认 acpx node_modules 已安装（issue #47543）
ls /opt/openclaw/extensions/acpx/node_modules/
# 如果 node_modules 为空或不存在：
#   cd /opt/openclaw/extensions/acpx && sudo npm install

# 2.3 确认 Node.js 版本 >= 22.12.0（acpx 要求）
node --version
# 期望：v22.x.x

# 2.4 确认 Claude Code CLI 可被 openclaw 用户访问
sudo -u openclaw which claude || sudo -u openclaw npx -y @anthropic-ai/claude-code --version
# 注：acpx 会自行管理 Claude Code 进程，但需确认 npm/npx 可用

# 2.5 确认 MotChat proxy 支持 Anthropic SSE streaming
curl -s -o /dev/null -w "%{http_code}" https://new.motchat.com/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: <test-key>" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-sonnet-4-6","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
# 期望：200（或至少不是 404/502）
```

## 3. 部署步骤

### 3.1 Pre-snapshot

```bash
# 通过 broker 或手动：
sudo btrfs subvolume snapshot -r / /.snapshots/root-pre-acp-spike-20260325-HHMM
```

### 3.2 设置环境变量

**选项 1（推荐）：openclaw.env**

```bash
# 检查 openclaw.env 是否存在且 gateway 读取它
cat /etc/openclaw/openclaw.env
# 追加（不要覆盖现有内容）：
echo 'ANTHROPIC_BASE_URL=https://new.motchat.com' | sudo tee -a /etc/openclaw/openclaw.env
echo 'ANTHROPIC_API_KEY=<motchat-api-key>' | sudo tee -a /etc/openclaw/openclaw.env
```

**选项 2：systemd override**

```bash
sudo mkdir -p /etc/systemd/system/openclaw-gateway.service.d/
sudo tee /etc/systemd/system/openclaw-gateway.service.d/acp-env.conf <<'EOF'
[Service]
Environment=ANTHROPIC_BASE_URL=https://new.motchat.com
Environment=ANTHROPIC_API_KEY=<motchat-api-key>
EOF
sudo systemctl daemon-reload
```

### 3.3 创建 workspace

```bash
sudo mkdir -p /var/lib/openclaw/.openclaw/workspace-claude-engineer
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/workspace-claude-engineer
```

### 3.4 创建 Claude Code settings（cwd bug #27627 workaround）

```bash
# openclaw 用户的 home 是 /var/lib/openclaw
# Claude Code 查找 ~/.claude/settings.json
sudo mkdir -p /var/lib/openclaw/.claude
sudo tee /var/lib/openclaw/.claude/settings.json <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)"
    ]
  },
  "allowedDirectories": [
    "/var/lib/openclaw/task-workspaces",
    "/var/lib/openclaw/.openclaw/workspace-claude-engineer"
  ]
}
EOF
sudo chown -R openclaw:openclaw /var/lib/openclaw/.claude
```

### 3.5 创建 task-workspaces 目录

```bash
sudo mkdir -p /var/lib/openclaw/task-workspaces
sudo chown openclaw:openclaw /var/lib/openclaw/task-workspaces
```

### 3.6 部署配置

```bash
# 通过 broker validate + deploy，或手动：
# 1. 将 candidate delta 合并到 /etc/openclaw/openclaw.json
# 2. 验证 JSON5 语法
# 3. 重启 gateway
sudo systemctl restart openclaw-gateway
sudo systemctl status openclaw-gateway
```

### 3.7 Spike 测试

```
# 从飞书向 main agent 发送：
"请使用 claude-engineer 执行一个简单任务：在 /var/lib/openclaw/task-workspaces/ 创建一个 hello.txt 文件"

# 或通过 API：
# sessions_spawn(runtime: "acp", agentId: "claude")
```

### 3.8 验证

```bash
# 检查 gateway 日志
sudo journalctl -u openclaw-gateway -n 50 --no-pager | grep -i acp

# 检查 acpx 进程
ps aux | grep acpx

# 检查 Claude Code 进程
ps aux | grep claude

# 检查 cwd
# 如果日志显示 cwd=/ 而非 task-workspaces，确认 #27627 仍存在
# 此时 settings.json allowedDirectories 应该作为 workaround

# 检查文件输出
ls -la /var/lib/openclaw/task-workspaces/
```

### 3.9 Post-snapshot

```bash
sudo btrfs subvolume snapshot -r / /.snapshots/root-post-acp-spike-20260325-HHMM
```

### 3.10 Vault sync

```bash
# 通过 broker vault_sync action
```

## 4. 风险评估

| 风险 | 严重度 | 缓解措施 |
|------|--------|----------|
| cwd bug #27627：ACP session 启动在 `/` | 中 | settings.json `allowedDirectories` 作为 workaround；candidate 已设置 `cwd` 字段 |
| `permissionMode: approve-all` 在宿主机运行 | 中 | `openclaw` 是 nologin 系统用户，fs 权限受限；broker 包裹危险操作；CVE-2026-27646 已在 2026.3.13 修复 |
| ACP_TURN_FAILED (#30346, #35861) | 高 | 这些 bug 报告于早期版本；2026.3.13 可能已修复。spike 测试即验证 |
| acpx node_modules 未安装 (#47543) | 低 | 前置检查步骤 2.2 解决 |
| MotChat SSE 兼容性未知 | 中 | 前置检查步骤 2.5 验证；如不兼容则 ACP 方案整体不可用 |
| fast mode 在自定义 BASE_URL 下被禁用 (#29015) | 低 | 仅影响性能，不影响功能 |
| gateway 重启影响 main agent 在线状态 | 低 | 短暂中断，飞书会话自动恢复 |

## 5. 回滚方案

### 5.1 快速回滚（不回滚 snapshot）

```bash
# 从 openclaw.json 中移除 acp 块、acpx plugin 和 claude-engineer agent
# 重启 gateway
sudo systemctl restart openclaw-gateway

# 清理环境变量（如果用了 openclaw.env）
sudo sed -i '/ANTHROPIC_BASE_URL/d; /ANTHROPIC_API_KEY/d' /etc/openclaw/openclaw.env

# 清理环境变量（如果用了 systemd override）
sudo rm /etc/systemd/system/openclaw-gateway.service.d/acp-env.conf
sudo systemctl daemon-reload
```

### 5.2 完整回滚（snapshot restore）

```bash
# 如果快速回滚不够：
sudo btrfs subvolume snapshot /.snapshots/root-pre-acp-spike-20260325-HHMM /root-restore
# 然后按标准回滚流程操作
```

## 6. 安全评估：`permissionMode: approve-all`

**结论：可接受，但需理解边界。**

`approve-all` 意味着 ACP Claude Code session 自动批准所有工具调用（Read、Write、Edit、Bash 等），无需人类确认。这等价于 `--dangerously-skip-permissions`，但限定在 `openclaw` 用户权限范围内。

**`openclaw` 用户能做什么：**
- 读写 `/var/lib/openclaw/` 下的文件
- 执行 Docker 命令（在 docker 组）
- 执行一般用户级命令

**`openclaw` 用户不能做什么：**
- 写入 `/etc/openclaw/`（root 所有）
- 修改 systemd units
- 修改 `/opt/openclaw/`
- 执行 sudo（nologin 用户无 sudoers 条目）
- 访问 nick 的 home 目录中的私密文件

**额外保护层：**
- broker 8/8 action 对宿主机变更提供结构化包裹
- ACP session TTL 限制为 60 分钟
- maxConcurrentSessions 限制为 2

## 7. 开放问题

1. **MotChat SSE 兼容性**：必须在部署前验证。如果 MotChat 不支持 Anthropic SSE streaming 格式，整个方案不可用。
2. **`openclaw` 用户的 `~/.claude/` 目录**：Claude Code 可能需要此目录。已在步骤 3.4 处理。
3. **workspace-claude-engineer 模板**：需后续创建（类似 workspace-task-runner-template）。spike 阶段先用空 workspace。
4. **与现有 Anthropic provider 配置共存**：gateway 已通过 `motchat-claude-4-6` provider 访问 Claude。ACP 环境变量走不同 code path（子进程继承 vs provider config），应该不冲突。

---

> 此变更涉及 `/etc/openclaw/openclaw.json`，按 CLAUDE.md escalation rule 处理。
> Operator 需审阅本计划后手动执行部署步骤。
