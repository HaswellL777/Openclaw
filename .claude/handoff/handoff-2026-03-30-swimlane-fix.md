# OpenClaw 对话交接提示词

> 生成日期：2026-03-30
> 上一轮：Swimlane 时间轴修复 + Skill frontmatter + Phase 引用更新 + Gateway RPC Plugin
> 模型：Claude Opus 4.6 (1M context)

---

## 第零部分：必读文档（开始工作前必须读完）

**按此顺序读取，不可跳过**：
1. `CLAUDE.md` — 安全边界、escalation 规则、anti-stall 规则、skill 编写规则
2. `docs/current-boundary.md` — 唯一实时状态文件
3. `docs/map.md` — 文档总地图
4. `docs/host-sop.md` §0 — 当前阶段定位
5. `docs/planning/frontend-gui-design.md` — GUI 需求规格 v2
6. `.claude/handoff/handoff-2026-03-30-swimlane-fix.md` — 本文件

**然后自行探索**：
- `gui/src/` 前端源码
- `gui/src/api/` — RPC 客户端 + 类型 + Hooks + agent-colors
- `plugins/gateway-rpc-tool/` — 新开发的 Gateway RPC 插件
- OpenClaw 源码 `/opt/openclaw/node_modules/openclaw/dist/` — 不确定的行为从这里找证据

---

## 第一部分：工作纪律（长期规则，每轮都适用）

1. **先读后做**：按第零部分顺序读文档。
2. **产出 > 分析**：每个任务有可落盘产物。
3. **不猜测**：不确定的系统行为，从源码找证据。
4. **config 变更走 escalation**：pre-snapshot → backup → apply → verify → rollback plan。
5. **workspace 更新后提醒 publish**：`sudo bash scripts/publish-workspace-main.sh --apply --allow-live-target /var/lib/openclaw/.openclaw/workspace-main`
6. **发布前验证 skill**：`bash scripts/check-workspace-skills.sh`（已集成到 publish 流程）
7. **SKILL.md 必须有 YAML frontmatter**：`name` + `description` 字段，缺少则 skill 被静默丢弃。

### 踩过的坑（必须牢记）

| 坑 | 教训 |
|-----|------|
| **Gateway 消息用 `timestamp` 不是 `ts`** | chat.history 返回的消息字段是 `timestamp`（毫秒），GUI 之前读 `ts`（不存在→0），导致 swimlane 消息和控制事件完全分层 |
| SKILL.md 无 YAML frontmatter | skill 被 gateway 静默丢弃，不报错 |
| sessions.delete 是永久操作 | store 条目删除不可逆，用 localStorage 软归档替代 |
| Gateway RPC 不暴露给 agent | cron.add/config.get 等不是 agent 工具，需通过 GUI 或 plugin |
| agent 在 Docker 沙箱中运行 | 无法访问 /home/nick/，脚本路径不能引用 dev repo |
| /clear 等 slash 命令 | 必须通过 chat.send 发给 gateway，不能本地拦截 |
| agents.files API 只有 8 个文件 | AGENTS/SOUL/TOOLS/IDENTITY/USER/HEARTBEAT/BOOTSTRAP/MEMORY.md |
| config.patch 返回 EROFS | Gateway 进程无 config 文件写权限 |
| Task group ID 必须稳定 | 用 timestamp+runId，不用序号，否则重命名/归档数据错位 |
| host-sop.md 容易漂移 | 是权威源但需要手动同步 |
| **共享 parent session 不能加入 swimlane 列** | 飞书群聊等 shared session 包含所有不相关对话，只有 `:subagent:` 的专属 session 才能安全加入列 |
| **Gateway device pairing** | WebSocket 连接需要 device pairing，脚本无法直接调用 cron.add 等管理 API |

---

## 第二部分：已完成事项（截至 2026-03-30 本轮）

### 本轮 4 个 Commit

1. **`f67f269` fix: swimlane timestamp alignment + Chat connection + Sessions layout**
   - 根因修复：`msg.timestamp` vs `msg.ts` — gateway 用 `timestamp`，GUI 读 `ts`（不存在=0）
   - `msgTs()` helper 读取两个字段
   - 父 subagent session 加入为 column 0（仅限 `:subagent:` 专属 session）
   - ReceiptEvent：父 lane 中的子完成回执节点
   - 过滤父 lane 中重复的 `[Internal task completion event]`
   - 稳定排序 tiebreaker：spawn→return→receipt→gap→msg
   - ChatPage：等 WS 连接后再加载 `?session=` 参数
   - SessionsPage：`shrink-0` header + `min-h-0` messages + `overflow-hidden`

2. **`038ef8c` fix: add YAML frontmatter to 14 agent skills**
   - task-runner: 11 skills
   - research-coordinator: 2 skills
   - auditor: 1 skill
   - 修复 data-analysis name mismatch

3. **`aa4b697` chore: update stale Phase 1A references to Phase 4+**
   - 12 files：IDENTITY.md, USER.md, TOOLS.md, HEARTBEAT.md, README.md, 3 skills, approval-policy, 3 runbooks
   - 零残留 Phase 1A/1B 引用

4. **`8990ba4` feat: gateway-rpc-tool plugin + cron helper + boundary update**
   - 新插件 `plugins/gateway-rpc-tool/`：14 个 RPC 方法作为 agent 工具
   - `scripts/add-health-check-cron.js` helper
   - `docs/current-boundary.md` 更新

### 完整审计完成
- 4 个 workspace template 全量审计（main, task-runner, RC, auditor）
- 控制面文档内容摘要 + 陈旧检查 + 模板 vs 活跃 diff

---

## 第三部分：需要部署的变更（requires sudo）

### 1. 发布 main workspace template
```bash
sudo bash scripts/publish-workspace-main.sh --apply --allow-live-target /var/lib/openclaw/.openclaw/workspace-main
```

### 2. 发布其他 workspace templates（无正式 publish 脚本，需手动 rsync）
```bash
# task-runner
sudo rsync -av --delete \
  /home/nick/projects/openclaw-dev/workspace-task-runner-template/ \
  /var/lib/openclaw/.openclaw/workspace-task-runner/
# 注意：chown -R 对 knowledge/ 会失败（read-only bind mount），需单独 chown 其他路径

# research-coordinator
sudo rsync -av --delete \
  /home/nick/projects/openclaw-dev/workspace-research-coordinator-template/ \
  /var/lib/openclaw/.openclaw/workspace-research-coordinator/

# auditor
sudo rsync -av --delete \
  /home/nick/projects/openclaw-dev/workspace-auditor-template/ \
  /var/lib/openclaw/.openclaw/workspace-auditor/
```

### 3. 部署 Gateway RPC Plugin
```bash
sudo cp -r /home/nick/projects/openclaw-dev/plugins/gateway-rpc-tool/ \
  /var/lib/openclaw/.openclaw/extensions/gateway-rpc-tool/
sudo chown -R openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/gateway-rpc-tool/
# 然后在 /etc/openclaw/openclaw.json 中添加：
# plugins.allow: [..., "gateway-rpc-tool"]
# plugins.entries.gateway-rpc-tool: { "enabled": true }
# 以及在 main agent 的 tools.allow 中添加 "gateway_rpc"
```

### 4. 创建 Cron 健康检查任务
在 GUI `/cron` 页面手动创建：
- Name: `workspace-health-check`
- Schedule: `3 9 * * *` (cron)
- Session Target: isolated, Agent: main
- Wake Mode: now
- Message: 见 handoff-2026-03-30-gui-complete.md 第三部分 任务 B

---

## 第四部分：下轮待做任务

### 任务 A（高优）：安全加固
- IPv6 only 绑定（GUI + Gateway）
- GUI 前端登录鉴权

### 任务 B（中优）：Vault Sync
- Phase 5 大量变更以来未执行 Vault 同步
- 需要在维护窗口执行

### 任务 C（中优）：Sessions 页面按钮可见性验证
- dashboard session（`agent:main:dashboard:20ad2380-...`）按钮在 DOM 中但不可见
- 已加 `min-h-0` + `shrink-0` + `overflow-hidden` 修复，需用户验证
- 如仍有问题，可能是 flex 嵌套高度计算 bug，需检查 `<main>` 与 `h-screen` 的交互

### 任务 D（低优）：Docker/Broker 管理 API
- Gateway 无容器/broker lifecycle RPC
- 需要开发 broker plugin 暴露管理操作

### 任务 E（低优）：Workspace 发布自动化
- task-runner/RC/auditor 没有正式 publish 脚本（已反复遗忘 3+ 次）
- 建议创建 `publish-workspace-all.sh`

---

## 第五部分：技术参考

### Swimlane 时间轴模型（修复后）

```
parent lane (col 0)     child #2 (col 1)    child #3 (col 2)
    |                       |                    |
    msg (parent work)       |                    |
    |                       |                    |
    ──spawn arrow──────────>|                    |
    ──spawn arrow───────────────────────────────>|
    |                       msg (child work)     |
    |                       |                    msg (child work)
    |                       |                    |
    |<──return arrow────────|                    |
    receipt ✓ child#2       |                    |
    |                       |                    |
    |<──return arrow─────────────────────────────|
    receipt ✓ child#3       |                    |
    |                       |                    |
    msg (parent wrap-up)    |                    |
```

关键实现细节：
- `msgTs()` 读取 `msg.timestamp ?? msg.ts ?? 0`（gateway 用 `timestamp`）
- 父 session 仅在 `:subagent:` 时加入列（共享 channel session 不加入）
- `ReceiptEvent` 在 `run.endedAt + 0.5ms` 注入父 lane
- 父 lane 中 `[Internal task completion event]` 被过滤（由 receipt 替代）
- 排序 tiebreaker：spawn(0) → return(1) → receipt(2) → gap(3) → msg(4)

### Gateway RPC Plugin 架构

```
plugins/gateway-rpc-tool/
├── openclaw.plugin.json    # manifest: id, configSchema (allowedAgents)
├── package.json            # ESM entry
└── index.js                # register(api) → api.registerTool(factory, {optional:true})
                            # factory(ctx) → null if ctx.agentId not in allowedAgents
                            # tool.execute → runCommandWithTimeout("openclaw", [...])
```

14 methods: cron.{list,add,remove,run,enable,disable,status}, health, sessions.{list,abort}, config.get, usage.status, skills.status, agents.list

### 关键文件

| 文件 | 用途 |
|------|------|
| `gui/src/components/TaskDetailView.tsx` | Swimlane 时间轴（msgTs helper + ReceiptEvent + 父列逻辑） |
| `gui/src/components/MessageRenderer.tsx` | 消息渲染器（timestamp 修复） |
| `gui/src/pages/ChatPage.tsx` | Chat 页面（WS 连接等待修复） |
| `gui/src/pages/SessionsPage.tsx` | Sessions 页面（flex 布局修复） |
| `gui/src/api/types.ts` | ChatMessage 类型（新增 timestamp 字段） |
| `plugins/gateway-rpc-tool/` | Gateway RPC 插件（待部署） |

---

## 第六部分：启动 checklist

1. 读完第零部分文档
2. 确认 GUI 服务运行中：`systemctl is-active openclaw-gui.service`
3. 确认 Gateway 运行中：`systemctl is-active openclaw-gateway.service`
4. 访问 `http://10.129.40.88:3000/overview` 确认连接正常
5. 检查 Task Flow → 点进某个有子 agent 的 task → 确认 swimlane 时间轴正确
6. 处理第三部分的部署任务或第四部分的待做任务
