# OpenClaw 对话交接提示词

> 生成日期：2026-03-30
> 上一轮：GUI 全量页面开发 + Task Detail Swimlane + 语法高亮 + 文档全量同步
> 模型：Claude Opus 4.6 (1M context)

---

## 第零部分：必读文档（开始工作前必须读完）

**按此顺序读取，不可跳过**：
1. `CLAUDE.md` — 安全边界、escalation 规则、anti-stall 规则、**skill 编写规则**
2. `docs/current-boundary.md` — 唯一实时状态文件
3. `docs/map.md` — 文档总地图
4. `docs/host-sop.md` §0 — 当前阶段定位（已于 2026-03-30 全量同步）
5. `docs/planning/frontend-gui-design.md` — GUI 需求规格 v2（P0/P1 已实现）
6. `.claude/handoff/handoff-2026-03-30-gui-complete.md` — 本文件

**然后自行探索**：
- `gui/src/` 前端源码（16 个页面组件）
- `gui/src/api/` — RPC 客户端 + 类型 + Hooks + agent-colors
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
| SKILL.md 无 YAML frontmatter | skill 被 gateway 静默丢弃，不报错 |
| sessions.delete 是永久操作 | store 条目删除不可逆，用 localStorage 软归档替代 |
| Gateway RPC 不暴露给 agent | cron.add/config.get 等不是 agent 工具，需通过 GUI 或 plugin |
| agent 在 Docker 沙箱中运行 | 无法访问 /home/nick/，脚本路径不能引用 dev repo |
| /clear 等 slash 命令 | 必须通过 chat.send 发给 gateway，不能本地拦截 |
| agents.files API 只有 8 个文件 | AGENTS/SOUL/TOOLS/IDENTITY/USER/HEARTBEAT/BOOTSTRAP/MEMORY.md |
| config.patch 返回 EROFS | Gateway 进程无 config 文件写权限 |
| Task group ID 必须稳定 | 用 timestamp+runId，不用序号，否则重命名/归档数据错位 |
| host-sop.md 容易漂移 | 是权威源但需要手动同步，Phase 5 整轮都没更新过 |

---

## 第二部分：已完成事项（截至 2026-03-30）

### GUI 前端（16 页面，全部功能可用）

| 页面 | 路由 | 功能 |
|------|------|------|
| Overview | /overview | Agent 卡片仪表板 + KPI + 最近任务 + 健康 + Presence |
| Chat | /chat | 新建/续接 session + streaming + slash 命令菜单 |
| Sessions | /sessions | 列表/树 + Abort/Clear History（Delete 已隐藏） |
| Task Flow | /tasks | dagre 自动布局 + 筛选/重命名/软归档 + 详细视图 |
| Task Detail | (内嵌) | Swimlane 消息流程图 + 跨列箭头 + 消息折叠/展开 |
| Inspector | /monitor | Gateway 健康 + Config 查看器 + 用量 + 内存 + Runs 表 |
| Logs | /logs | Gateway 日志查看器 |
| Cron | /cron | 定时任务管理（官方 API 格式） |
| Heartbeat | /heartbeat | 心跳监控 + 开关 + Wake + 实时事件日志 |
| Skills | /skills | Skills 列表 + 来源过滤 + 搜索 + Tools 目录 |
| MCP | /mcp | MCP 服务器列表 + 工具目录（只读） |
| Workspace | /files | Agent 控制面文件浏览 + 编辑/保存 |
| Docker | /docker | Sandbox 配置展示 + 无 API 提示 |
| Broker | /broker | Broker 健康 + 配置展示 |
| Settings | /settings | 配置只读展示 |
| Help | /docs | 操作参考手册（中文） |

### 基础设施
- `openclaw-gui.service` systemd 服务（已安装启用，开机自启）
- `check-workspace-skills.sh` 验证脚本（已集成到 publish 流程）
- `@dagrejs/dagre` 自动布局（替代静态网格）
- `react-syntax-highlighter` PrismLight（10 语言，one-dark 主题）
- 共享 agent 颜色：`gui/src/api/agent-colors.ts`
- 共享类型：RunRecord + TaskGroup 在 `gui/src/api/types.ts`

### 文档同步（2026-03-30）
- `docs/host-sop.md` — 从 2026-03-22 更新到 2026-03-30（修复重大漂移）
- `docs/current-boundary.md` — 全量更新
- `docs/map.md` — 新增脚本和页面
- `docs/planning/frontend-gui-design.md` — 状态更新为"P0/P1 全部实现"
- `docs/planning/api-migration-model-switch.md` — 归档（已完成）
- `CLAUDE.md` — 新增 skill 编写规则 + workspace publish 状态
- workspace-main 已发布（SOP + 5 skill 含 frontmatter 修复）

---

## 第三部分：本轮未完成 / 下轮待做任务

### 任务 A（高优）：Gateway RPC Plugin for Agents

**问题**：main agent 无法调用 `cron.add`、`config.get`、`sessions.list` 等 gateway 管理 API，限制了运维自动化。

**方向**：
- 开发一个 OpenClaw plugin，将关键 gateway RPC 方法暴露为 agent 可调用的工具
- 参考 `/opt/openclaw/node_modules/openclaw/dist/` 中的 plugin SDK
- 需要评估安全边界：哪些 RPC 可以暴露给 agent，哪些需要 operator approval

**技术基础**：
- Plugin SDK: `openclaw.plugin.json` + `index.js` in `/var/lib/openclaw/.openclaw/extensions/`
- 已有 host-ops-tool plugin 作为参考
- Gateway 有 89 个 RPC 方法，需要选择性暴露

### 任务 B（高优）：Cron Health Check Job

**问题**：workspace 健康检查未常态化。

**操作**：在 GUI Cron 页面 (`/cron`) 手动创建：
- Name: `workspace-health-check`
- Schedule: `3 9 * * *`
- Session Target: Main
- Wake Mode: Now
- Payload: Agent Turn
- Message: 见下方

```
静默健康检查 — 仅在发现问题时报告，全部正常则回复 HEARTBEAT_OK。
检查项：
1. 读取 workspace skills/ 目录，确认每个 SKILL.md 都以 --- 开头
2. 读取 control/SOP.md 前 5 行，确认不是占位符
3. 运行 du -sh /var/log/openclaw/openclaw.log，确认大小未超 400MB
4. 运行 df -h / 和 df -h /var/lib/openclaw，确认剩余大于 10%
5. 运行 docker ps --filter name=openclaw-sbx-shared，确认容器运行
规则：全 PASS → HEARTBEAT_OK。任何 FAIL → 报告 + 修复建议。
```

### 任务 C（中优）：安全加固

- IPv6 only 绑定（GUI + Gateway）
- 登录鉴权（GUI 前端）

### 任务 D（中优）：Vault Sync

- Phase 5 大量变更以来未执行 Vault 同步
- 需要在维护窗口执行

### 任务 E（低优）：Docker/Broker 管理 API

- Gateway 无容器/broker lifecycle RPC
- 需要开发 broker plugin 暴露管理操作
- 当前页面仅展示配置信息

---

## 第四部分：技术参考

### Gateway RPC 方法（完整列表，89 个）

**operator.read (33)**:
health, doctor.memory.status, logs.tail, channels.status, status, usage.status, usage.cost, models.list, tools.catalog, agents.list, agent.identity.get, skills.status, sessions.list, sessions.get, sessions.preview, sessions.resolve, sessions.subscribe, sessions.unsubscribe, sessions.messages.subscribe, sessions.messages.unsubscribe, sessions.usage, sessions.usage.timeseries, sessions.usage.logs, cron.list, cron.status, cron.runs, gateway.identity.get, system-presence, last-heartbeat, chat.history, config.get, config.schema.lookup, agents.files.list, agents.files.get

**operator.write (17)**:
chat.send, chat.abort, sessions.create, sessions.send, sessions.steer, sessions.abort, wake, node.invoke, browser.request, send, poll, agent, agent.wait, talk.mode, talk.speak, tts.enable, tts.disable

**operator.admin (23+)**:
sessions.patch, sessions.reset, sessions.delete, sessions.compact, agents.create, agents.update, agents.delete, agents.files.set, skills.install, skills.update, cron.add, cron.update, cron.remove, cron.run, set-heartbeats, system-event, chat.inject, config.set, config.apply, config.patch, config.schema, connect, update.run

### 关键文件

| 文件 | 用途 |
|------|------|
| `gui/.env` | VITE_GATEWAY_TOKEN（gitignored） |
| `gui/vite.config.ts` | Vite 配置 + WS proxy + `/api/runs` middleware |
| `gui/src/api/rpc-client.ts` | Gateway WebSocket 协议客户端 |
| `gui/src/api/hooks.ts` | Zustand store + React Query hooks |
| `gui/src/api/types.ts` | 共享类型（含 RunRecord, TaskGroup） |
| `gui/src/api/agent-colors.ts` | 共享 agent 颜色 |
| `gui/src/components/TaskDetailView.tsx` | Task 内部 swimlane 消息流程图 |
| `gui/src/components/MessageRenderer.tsx` | 消息渲染器（语法高亮 + tool call） |
| `gui/src/pages/TaskFlowPage.tsx` | Task Flow 图（dagre 自动布局） |
| `gui/src/pages/ChatPage.tsx` | Chat 页面（slash 命令 + streaming） |
| `gui/src/App.tsx` | 路由 + sidebar（16 路由） |
| `scripts/publish-workspace-main.sh` | Workspace 发布（含 skill 验证） |
| `scripts/check-workspace-skills.sh` | SKILL.md frontmatter 验证 |
| `scripts/openclaw-gui.service` | GUI systemd unit |

### Vite dev server

```bash
# 已作为 systemd 服务运行：
systemctl status openclaw-gui.service
journalctl -u openclaw-gui.service -f

# 访问：http://10.129.40.88:3000
```

---

## 第五部分：启动 checklist

1. 读完第零部分文档
2. 确认 GUI 服务运行中：`systemctl is-active openclaw-gui.service`
3. 确认 Gateway 运行中：`systemctl is-active openclaw-gateway.service`
4. 访问 `http://10.129.40.88:3000/overview` 确认连接正常
5. 检查 Skills 页面是否显示 5 个 workspace skill（来源过滤选 openclaw-workspace）
6. 开始处理第三部分的待做任务
