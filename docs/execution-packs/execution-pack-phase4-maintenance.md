# 综合维护窗口执行指引

> 日期：2026-03-25
> 预估时间：30-60 分钟（不含镜像构建）
> 前置：确保飞书暂时不需要 agent 回复（gateway 会重启）

---

## 阶段 0：Pre-snapshot

```bash
# 0.1 创建变更前快照
sudo btrfs subvolume snapshot -r / /.snapshots/root-pre-maintenance-20260325-$(date +%H%M)
```

---

## 阶段 1：停掉 vLLM

```bash
# 1.1 检查 vLLM 运行方式
ps aux | grep -v grep | grep vllm
systemctl status vllm 2>/dev/null || echo "不是 systemd 服务"

# 1.2 如果是 systemd 服务：
sudo systemctl stop vllm
sudo systemctl disable vllm

# 1.3 如果是手动进程：
# sudo kill $(pgrep -f vllm)

# 1.4 验证 GPU 已释放
nvidia-smi
# 期望：Processes 列表无 vllm，GPU Memory Used 接近 0
```

---

## 阶段 2：升级 OpenClaw 到 2026.3.23-2

```bash
# 2.1 检查当前版本
sudo -u openclaw openclaw --version

# 2.2 检查 Node.js 版本（需要 >= 22.16）
node --version

# 2.3 升级
sudo npm i -g openclaw@2026.3.23-2

# 2.4 运行 doctor 修复
sudo -u openclaw openclaw doctor --fix

# 2.5 验证新版本
sudo -u openclaw openclaw --version
# 期望：2026.3.23-2
```

---

## 阶段 3：编辑 openclaw.json

```bash
# 3.1 备份当前配置
sudo cp /etc/openclaw/openclaw.json /etc/openclaw/openclaw.json.bak.$(date +%Y%m%d-%H%M)

# 3.2 编辑配置
sudo nano /etc/openclaw/openclaw.json
```

**需要做的改动（逐项）：**

### 3.2a 删除 hooks 块
找到并删除整个 `hooks` 块：
```
  // ---- 测试用 hooks（验证后删除） ----
  hooks: {
    internal: {
      enabled: true,
      entries: {
        "tool-audit-probe": {
          enabled: true,
        },
      },
    },
  },
```

### 3.2b 修改 plugins.allow
```
// 旧：
allow: ["feishu", "tool-audit-plugin"],
// 新：
allow: ["feishu"],
```

### 3.2c 添加 acp 顶级块
在顶层（与 `gateway`、`models`、`agents` 同级）添加：
```json5
  acp: {
    enabled: true,
    dispatch: {
      enabled: true,
    },
    defaultAgent: "claude",
    allowedAgents: ["claude"],
    maxConcurrentSessions: 2,
    stream: {
      coalesceIdleMs: 300,
      maxChunkChars: 1200,
    },
    runtime: {
      ttlMinutes: 60,
      permissionMode: "approve-all",
    },
  },
```

### 3.2d 修改 agents.defaults.subagents
```json5
  // 旧：
  subagents: { maxConcurrent: 8 },
  // 新：
  subagents: {
    maxConcurrent: 8,
    runTimeoutSeconds: 14400,
    archiveAfterMinutes: 1440,
  },
```

### 3.2e 修改 agents.defaults.sandbox.prune
```json5
  // 旧：
  prune: {
    idleHours: 4,
    maxAgeDays: 3,
  },
  // 新：
  prune: {
    idleHours: 24,
    maxAgeDays: 7,
  },
```

### 3.2f 修改 task-runner agent 的 sandbox
在 `agents.list` 中找到 `id: "task-runner"` 的条目，修改其 `sandbox`：
```json5
  // 旧：
  scope: "session",
  // 新：
  scope: "shared",
```
并在 `docker` 块中添加：
```json5
  docker: {
    // ... 已有的 image, network 等保留 ...
    gpus: "all",
  },
```

### 3.2g 添加 claude-engineer agent
在 `agents.list` 数组中追加新条目：
```json5
      {
        id: "claude-engineer",
        name: "Claude Engineer (ACP)",
        model: {
          primary: "motchat-claude-4-6/claude-opus-4-6",
        },
        tools: {
          profile: "coding",
        },
        workspace: "workspace-claude-engineer",
        runtime: {
          type: "acp",
          acp: {
            agent: "claude",
            mode: "persistent",
            cwd: "/var/lib/openclaw/task-workspaces",
          },
        },
      },
```

### 3.2h 确认没有 acpx 相关条目
确保 `plugins.allow` 中没有 `"acpx"`，`plugins.entries` 中没有 `acpx` 块。
2026.3.22+ ACP 在 core，不需要 plugin。

```bash
# 3.3 保存退出后，验证 JSON5 语法（可选）
sudo -u openclaw openclaw doctor 2>&1 | head -20
```

---

## 阶段 4：设置 ACP 环境变量

```bash
# 4.1 检查 openclaw.env 是否存在
sudo cat /etc/openclaw/openclaw.env

# 4.2 追加 ANTHROPIC 变量（不要覆盖已有内容）
echo 'ANTHROPIC_BASE_URL=https://new.motchat.com' | sudo tee -a /etc/openclaw/openclaw.env
echo 'ANTHROPIC_API_KEY=替换为你的motchat-api-key' | sudo tee -a /etc/openclaw/openclaw.env

# 4.3 验证
sudo cat /etc/openclaw/openclaw.env
# 确认 ANTHROPIC_BASE_URL 和 ANTHROPIC_API_KEY 存在且正确
```

---

## 阶段 5：创建 ACP 所需目录

```bash
# 5.1 创建 workspace-claude-engineer
sudo mkdir -p /var/lib/openclaw/.openclaw/workspace-claude-engineer
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/workspace-claude-engineer

# 5.2 创建 task-workspaces（ACP 工作目录）
sudo mkdir -p /var/lib/openclaw/task-workspaces
sudo chown openclaw:openclaw /var/lib/openclaw/task-workspaces

# 5.3 创建 Claude Code settings（openclaw 用户）
sudo mkdir -p /var/lib/openclaw/.claude
sudo tee /var/lib/openclaw/.claude/settings.json <<'SETTINGS'
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
SETTINGS
sudo chown -R openclaw:openclaw /var/lib/openclaw/.claude
```

---

## 阶段 6：重启 Gateway 并验证

```bash
# 6.1 重启
sudo systemctl daemon-reload
sudo systemctl restart openclaw-gateway

# 6.2 检查状态
sudo systemctl status openclaw-gateway

# 6.3 检查日志（无 error）
sudo journalctl -u openclaw-gateway -n 30 --no-pager

# 6.4 验证飞书对话
# 从飞书发送任意消息给 agent，确认能回复

# 6.5 验证 hook/plugin 已清理
grep -c 'tool-audit' /etc/openclaw/openclaw.json
# 期望：0

# 6.6 验证 ACP 配置生效
sudo journalctl -u openclaw-gateway -n 50 --no-pager | grep -i acp
# 期望：看到 ACP 相关初始化日志（可能显示 enabled 或 ready）
```

---

## 阶段 7：Clone 参考仓库

```bash
# 7.1 Clone LabClaw 和 autoresearch
cd /home/nick/repos
git clone https://github.com/wu-yc/LabClaw.git
git clone https://github.com/karpathy/autoresearch.git

# 7.2 验证 mount --bind 仍在生效
mount | grep knowledge
# 如果没有输出（没挂载），重新挂载：
# sudo mount --bind /home/nick/repos /var/lib/openclaw/.openclaw/workspace-task-runner/knowledge
# sudo mount -o remount,bind,ro /var/lib/openclaw/.openclaw/workspace-task-runner/knowledge

# 7.3 验证容器内可见
# 等镜像重建后再验证，先继续
ls /home/nick/repos/
# 期望看到：LabClaw/  autoresearch/  （加上之前已有的仓库）
```

---

## 阶段 8：重建 Docker 镜像

```bash
# 8.1 检查 nvidia-container-toolkit（GPU 镜像需要）
dpkg -l | grep nvidia-container-toolkit
# 如果没安装：
# sudo apt-get install -y nvidia-container-toolkit
# sudo systemctl restart docker

# 8.2 重建 full 镜像（含 Scrapling）
cd ~/projects/openclaw-dev/task-runner-container
sudo docker build -f Dockerfile.full -t openclaw-task-claude:2026-03-v3-full .

# 8.3 验证 full 镜像
sudo docker run --rm openclaw-task-claude:2026-03-v3-full python3 -c "import scrapling; print(f'Scrapling {scrapling.__version__}')"
sudo docker run --rm openclaw-task-claude:2026-03-v3-full id
# 期望：uid=997(runner) gid=984(runner)

# 8.4 构建 GPU 镜像
sudo docker build -f Dockerfile.gpu -t openclaw-task-claude:2026-03-v3-gpu .

# 8.5 验证 GPU 镜像
sudo docker run --rm --gpus all openclaw-task-claude:2026-03-v3-gpu nvidia-smi
sudo docker run --rm --gpus all openclaw-task-claude:2026-03-v3-gpu python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
sudo docker run --rm openclaw-task-claude:2026-03-v3-gpu uv --version

# 8.6 验证容器内能看到 knowledge
# 启动一个临时容器看看（使用 full 镜像，bind workspace）
sudo docker run --rm \
  -v /var/lib/openclaw/.openclaw/workspace-task-runner:/workspace:ro \
  openclaw-task-claude:2026-03-v3-full \
  ls /workspace/knowledge/
# 期望看到：LabClaw/  autoresearch/
```

---

## 阶段 9：Publish workspace-main-template

```bash
# 9.1 回到 dev repo
cd ~/projects/openclaw-dev

# 9.2 Dry run 先看看
bash scripts/publish-workspace-main.sh --dry-run

# 9.3 正式发布
sudo bash scripts/publish-workspace-main.sh --apply --allow-live-target

# 9.4 验证发布结果
sudo ls /var/lib/openclaw/.openclaw/workspace-main/skills/
# 期望看到：approvals/ broker/ host-sop/ routing/ task-delegation/

sudo ls /var/lib/openclaw/.openclaw/workspace-main/memory/
# 期望看到：MEMORY.md

sudo cat /var/lib/openclaw/.openclaw/workspace-main/memory/MEMORY.md | head -5
# 期望看到 "# Main Agent Memory"
```

---

## 阶段 10：功能验证

```bash
# 10.1 验证 shared scope
# 从飞书发送："请让 task-runner 在 /workspace/outputs/ 创建一个 test-shared.txt 文件，内容为 hello"
# 等任务完成后，再发送第二个任务：
# "请让 task-runner 读取 /workspace/outputs/test-shared.txt 的内容"
# 期望：第二次能读到第一次写入的内容（同一容器）

# 10.2 验证记忆系统
# 从飞书发送（私聊）："请记住：维护窗口于 2026-03-25 执行完成"
# 然后检查：
sudo ls /var/lib/openclaw/.openclaw/workspace-main/memory/
# 期望看到 MEMORY.md 被更新或新的日期文件

# 10.3 验证 ACP（可选，可能需要调试）
# 从飞书发送："使用 claude-engineer 执行一个简单任务：列出 /var/lib/openclaw/task-workspaces/ 目录内容"
# 检查日志：
sudo journalctl -u openclaw-gateway -n 50 --no-pager | grep -i acp

# 10.4 验证 GPU 透传（通过飞书）
# 从飞书发送："请让 task-runner 执行 python3 -c 'import torch; print(torch.cuda.is_available())'"
# 注意：需要 task-runner 使用 GPU 镜像。如果当前 config 指向 v3-full，
#       需要先在 openclaw.json 中把 task-runner 的 image 改为 v3-gpu 才能测试 GPU

# 10.5 验证 broker 仍然工作
# 从飞书发送："执行系统健康检查"
# 期望：调用 gateway_health，返回健康状态
```

---

## 阶段 11：Post-snapshot + Vault sync

```bash
# 11.1 Post-snapshot
sudo btrfs subvolume snapshot -r / /.snapshots/root-post-maintenance-20260325-$(date +%H%M)

# 11.2 Vault sync（如果 vault 在线）
# 通过飞书让 agent 调用 vault_sync
# 或手动：
# sudo mount /mnt/vault  # 如果 noauto
# sudo btrfs send /.snapshots/root-post-maintenance-20260325-HHMM | sudo btrfs receive /mnt/vault/snapshots/
# sudo umount /mnt/vault
```

---

## 阶段 12：清理旧容器（可选）

```bash
# 12.1 查看运行中的容器
sudo docker ps

# 12.2 停止使用旧 v3 slim 镜像的容器（如果还在）
# sudo docker stop <container-id>
# sudo docker rm <container-id>

# 12.3 清理悬空镜像
sudo docker image prune -f
```

---

## 快速回滚指引（如果出问题）

```bash
# 恢复配置
sudo cp /etc/openclaw/openclaw.json.bak.* /etc/openclaw/openclaw.json

# 移除 ANTHROPIC 变量
sudo sed -i '/ANTHROPIC_BASE_URL/d; /ANTHROPIC_API_KEY/d' /etc/openclaw/openclaw.env

# 如果需要恢复 vLLM
sudo systemctl start vllm
sudo systemctl enable vllm

# 如果需要降级 OpenClaw
sudo npm i -g openclaw@2026.3.13

# 重启
sudo systemctl daemon-reload
sudo systemctl restart openclaw-gateway

# 验证
sudo systemctl status openclaw-gateway
```

---

## 完成后检查清单

- [ ] vLLM 已停止，nvidia-smi 显示 GPU 空闲
- [ ] OpenClaw 版本 2026.3.23-2
- [ ] Gateway 正常运行
- [ ] 飞书对话正常
- [ ] hooks/tool-audit-plugin 已清理
- [ ] ACP 配置已生效
- [ ] ANTHROPIC 环境变量已设置
- [ ] LabClaw + autoresearch 已 clone
- [ ] Knowledge mount 生效
- [ ] Full 镜像重建成功（含 Scrapling）
- [ ] GPU 镜像构建成功
- [ ] workspace-main 已 publish（含 MEMORY.md + 新 skills）
- [ ] Shared scope 验证通过
- [ ] Post-snapshot 已创建
- [ ] Vault sync 已完成
