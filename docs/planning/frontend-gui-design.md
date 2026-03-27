# 前端 GUI 需求规格 & 技术选型

> 日期：2026-03-27（v2: 集成内置 Control UI 功能）
> close-by：2026-04-05（设计文档，作为独立工程的启动输入）
> 状态：**设计完成，未实施**

---

## 1. 设计原则

**替代而非补充**：新前端完全替代内置 Control UI，成为唯一管理入口。内置 UI 保留但仅作为紧急后备。原因：
- 内置 UI 功能已全部有 RPC API 支撑，可完整集成
- 维护两个 UI 增加认知负担
- 新前端可以做到内置 UI 做不到的事（拓扑图、broker、Docker）

## 2. 需求清单

### P0 — 核心操作

| # | 功能 | Gateway API | 状态 |
|---|------|------------|------|
| 1 | Agent 拓扑可视化 | `agents.list` + `sessions.list` + `presence` 事件 | ✅ 可直接实现 |
| 2 | Session 对话查看 | `chat.history` + `sessions.messages.subscribe` | ✅ 可直接实现 |
| 3 | 直接对话 | `sessions.create` + `chat.send` + streaming | ✅ 可直接实现 |
| 4 | Session 管理 | `sessions.list/create/patch/delete/abort/reset/compact` | ✅ 可直接实现 |

### P1 — 管理 & 监控

| # | 功能 | Gateway API | 状态 |
|---|------|------------|------|
| 5 | Token 用量仪表盘 | `sessions.usage` (date range, 分组, per-session) | ✅ 可直接实现 |
| 6 | 健康 & Presence 监控 | `health` + `system-presence` + `channels.status` | ✅ 可直接实现 |
| 7 | Gateway 日志 | `logs.tail` (cursor, limit, maxBytes) | ✅ 可直接实现 |
| 8 | Cron 定时任务管理 | `cron.list/add/update/remove/run/runs/status` | ✅ 可直接实现 |
| 9 | Skills 管理 | `skills.status/bins/install/update` | ✅ 可直接实现 |
| 10 | Tools 目录 | `tools.catalog` (per-agent, 含 plugin tools) | ✅ 可直接实现 |
| 11 | Workspace 文件浏览 | `agents.files.list/get/set` | ✅ 可直接实现 |
| 12 | 模型/Provider/Key 管理 | `config.get/patch/schema` + `models.list` | ✅ 可直接实现 |
| 13 | Agent 配置管理 | `agents.create/update/delete` + config API | ✅ 可直接实现 |
| 14 | Docker 容器管理 | **[GAP]** 需 broker action | 需开发 |
| 15 | Broker 管理 | **[GAP]** 需 broker-proxy plugin | 需开发 |

### P2 — 增强

| # | 功能 | 说明 |
|---|------|------|
| 16 | Heartbeat 配置 | per-agent heartbeat 开关 + 间隔配置（via config.patch） |
| 17 | 设备配对管理 | `device.pair.list/approve/reject/remove` + `device.token.rotate` |
| 18 | 渠道管理 | `channels.status` + config 中 channel 块编辑 |
| 19 | 用量成本追踪 | `usage.status/cost` + `sessions.usage` 组合 |

---

## 3. Gateway API 完整清单

### RPC 方法（WebSocket JSON-RPC at ws://127.0.0.1:17777）

源码：`gateway-cli-Dsd9gHBa.js`、`method-scopes-BiEi0X2g.js`

#### Session 管理

| Method | 功能 | 关键参数 |
|--------|------|----------|
| `sessions.list` | 列出 session | limit, activeMinutes, agentId, search, spawnedBy, includeLastMessage |
| `sessions.create` | 创建 session | agentId, label, model, parentSessionKey |
| `sessions.send` | 发送消息（streaming） | key, message |
| `sessions.abort` | 中断运行中的 session | key |
| `sessions.delete` | 删除 session | key, deleteTranscript |
| `sessions.patch` | 修改 session | key, label, model |
| `sessions.reset` | 重置 session（清空历史） | key, reason |
| `sessions.compact` | 压缩 session 历史 | key |
| `sessions.preview` | 批量获取消息预览 | keys[] (max 64), limit, maxChars |
| `sessions.usage` | Token 用量统计 | startDate, endDate, mode, utcOffset, limit, key |
| `sessions.subscribe` | 订阅 session 元数据变更 | — |
| `sessions.messages.subscribe` | 订阅指定 session 实时消息 | key |

#### Agent 管理

| Method | 功能 |
|--------|------|
| `agents.list` | 列出所有 agent 配置 |
| `agents.create` | 创建新 agent |
| `agents.update` | 更新 agent 配置 |
| `agents.delete` | 删除 agent |
| `agents.files.list` | 列出 agent workspace 文件 |
| `agents.files.get` | 读取 workspace 文件内容 |
| `agents.files.set` | 写入 workspace 文件 |
| `agent.wait` | 等待 agent run 完成 (runId, timeoutMs) |

#### Cron 定时任务

| Method | 功能 | 关键参数 |
|--------|------|----------|
| `cron.list` | 列出定时任务 | includeDisabled, limit, offset, query, sortBy |
| `cron.status` | Cron 系统健康状态 | — |
| `cron.add` | 创建定时任务 | name, schedule, sessionTarget, wakeMode, payload, delivery, failureAlert |
| `cron.update` | 更新定时任务 | id, patch (name, schedule, state, failureAlert...) |
| `cron.remove` | 删除定时任务 | id |
| `cron.run` | 立即触发执行 | id, mode ("due"\|"force") |
| `cron.runs` | 查看执行历史 | scope, id, limit, offset, statuses, sortDir |

#### Skills 管理

| Method | 功能 |
|--------|------|
| `skills.status` | 获取 skill 状态（per agent） |
| `skills.bins` | 列出所有可用 skill binary |
| `skills.install` | 安装 skill（local 或 ClawHub） |
| `skills.update` | 更新已安装 skill |

#### 配置 & 系统

| Method | 功能 |
|--------|------|
| `config.get` | 读取配置 |
| `config.set` | 写入配置 |
| `config.patch` | 部分更新配置 |
| `config.schema` | 获取完整 JSON Schema |
| `config.schema.lookup` | 查找指定路径的 schema |
| `models.list` | 列出可用模型 |
| `tools.catalog` | 获取工具目录（per-agent, 含 plugin） |
| `health` | 健康状态快照 (probe=true 触发全量探测) |
| `status` | 系统状态（需 admin scope） |
| `channels.status` | 渠道连接状态 |
| `logs.tail` | 获取 gateway 日志 (cursor, limit, maxBytes) |
| `usage.status` | 用量统计概览 |
| `usage.cost` | 成本统计 |

#### 系统 Presence & Heartbeat

| Method | 功能 |
|--------|------|
| `system-presence` | 列出当前设备/实例在线状态 |
| `last-heartbeat` | 最后一次 heartbeat 时间戳 |
| `set-heartbeats` | 全局 heartbeat 开关 |
| `gateway.identity.get` | 获取 gateway 设备 ID |

#### 设备配对

| Method | 功能 |
|--------|------|
| `device.pair.list` | 列出已配对设备 |
| `device.pair.approve/reject/remove` | 配对审批 |
| `device.token.rotate/revoke` | Token 管理 |

#### Chat

| Method | 功能 |
|--------|------|
| `chat.history` | 读取 session 对话历史 |
| `chat.send` | 发送消息（支持 streaming） |
| `chat.abort` | 中断生成 |

### WebSocket 推送事件

| Event | 触发条件 | 刷新频率 |
|-------|----------|----------|
| `health` | 健康状态变更 | ~5-10s |
| `presence` | 设备/实例在线状态变更 | 按需 |
| `tick` | Heartbeat | ~10s |
| `sessions.changed` | Session 元数据变更 | 按需 |
| `sessions.messages` | 订阅 session 的新消息 | 实时 |
| `chat` | 对话消息 streaming delta | 实时 |
| `agent` | Agent run 事件 (状态、token、cache) | 实时 |
| `cron` | Cron 任务执行事件 | 按需 |
| `shutdown` | Gateway 关闭通知 | 一次 |

---

## 4. API Gap 分析

| Gap | 影响功能 | 方案 |
|-----|----------|------|
| Docker 容器操作 | 容器管理、容器内文件浏览 | broker 新增 `container-*` actions |
| Broker 管理暴露 | Broker action 历史、审批 | gateway broker-proxy plugin（推荐）或 HTTP sidecar |
| 错误率聚合 | 监控仪表盘 | 前端从 session 状态推导 |

### broker-proxy plugin 设计（推荐方案）

在 gateway 加载一个 plugin，将 broker Unix socket API 暴露为 gateway RPC method：
```
broker.action.list    → 列出可用 action
broker.action.invoke  → 触发 action（含参数）
broker.action.history → 查看执行历史
broker.approval.list  → 查看待审批项
broker.approval.approve/reject → 审批操作
```

前端统一用一个 WebSocket 连接访问所有 API。

### container-* broker actions

| Action | 实现 | 参数 |
|--------|------|------|
| `container-list` | `docker ps --format json` | — |
| `container-stats` | `docker stats --no-stream --format json` | containerId |
| `container-files-list` | `docker exec <id> find <path> -maxdepth 1` | containerId, path |
| `container-files-get` | `docker exec <id> cat <path>` | containerId, path |
| `container-files-put` | `docker cp` | containerId, path, content |
| `container-lifecycle` | `docker stop/restart/rm` | containerId, action |
| `container-logs` | `docker logs --tail N` | containerId, tail |

---

## 5. 技术选型

### 前端框架：React + TypeScript + Vite

### UI 组件库：Shadcn/UI + Tailwind CSS（dark mode 默认）

### 可视化库

| 用途 | 库 |
|------|-----|
| Agent 拓扑图 | **React Flow** |
| Token/用量图表 | **Recharts** |
| 日志查看器 | **@xterm/xterm**（终端风格）或自实现 |
| 文件树 | Shadcn Tree / 自实现 |
| Markdown 渲染 | **react-markdown** + rehype |

### 部署：Nginx reverse proxy

```
Browser :3000 → Nginx → Gateway :17777 (WebSocket + HTTP)
```

---

## 6. 功能模块设计

### 6.1 Agent 拓扑视图（P0）

```
┌─────────────────────────────────────────┐
│  Agent Topology                          │
│                                          │
│  ┌──────────┐    spawn    ┌───────────┐ │
│  │   main   │──────────▶│  research  │ │
│  │  opus-4  │            │coordinator │ │
│  │  ● idle  │            │  opus-4    │ │
│  └────┬─────┘            │  ● running │ │
│       │                  └─────┬──────┘ │
│       │ spawn                  │ spawn   │
│       ▼                        ▼         │
│  ┌──────────┐           ┌───────────┐   │
│  │ auditor  │           │task-runner │   │
│  │  opus-4  │           │  gpt-5.4  │   │
│  │  ○ idle  │           │  ● running│   │
│  └──────────┘           └───────────┘   │
│                                          │
│  Legend: ● active  ○ idle  ✗ error      │
└─────────────────────────────────────────┘
```

数据源：`agents.list` + `sessions.list` (spawnedBy → 父子) + `presence` + `health` 事件

### 6.2 Session 管理 & 对话查看（P0）

左栏 session 列表 + 右栏对话内容。支持：
- 按 agent 过滤、搜索
- 实时消息流（subscribe）
- Session 操作：patch label/model、abort、reset、compact、delete
- Tool call 展开显示
- Token 用量 per-message

数据源：`sessions.list/preview` + `chat.history` + `sessions.messages.subscribe`

### 6.3 直接对话（P0）

内嵌聊天组件，支持：
- 选择目标 agent
- 选择 model override（下拉菜单 from `models.list`）
- Streaming 输出
- 创建新 session 或继续已有 session

数据源：`sessions.create` + `chat.send` + `sessions.messages.subscribe`

### 6.4 监控仪表盘（P1）

四格面板：

```
┌──────────────────┬──────────────────┐
│ Token Usage      │ System Health    │
│ [7d chart]       │ Gateway: ● OK   │
│ 今日: 125k      │ Feishu:  ● OK   │
│ 本周: 890k      │ Broker:  ● OK   │
│                  │ GPU: 45% used   │
├──────────────────┼──────────────────┤
│ Active Sessions  │ Presence         │
│ main: 2 active   │ Host: nick-pc   │
│ t-run: 3 active  │ IP: 10.0.0.1   │
│ audit: 0 idle    │ Ver: 2026.3.23  │
│                  │ Uptime: 48h     │
└──────────────────┴──────────────────┘
```

数据源：`sessions.usage` + `health` + `system-presence` + `channels.status` + `health` 事件 (5-10s)

### 6.5 Gateway 日志（P1）

终端风格的实时日志查看器，支持：
- 自动滚动 + 暂停
- 按级别过滤（info/warn/error）
- 关键词搜索
- 时间范围

数据源：`logs.tail` (cursor 分页, limit max 5000, maxBytes max 1MB)

### 6.6 Cron 定时任务（P1）

```
┌──────────────────────────────────────────┐
│ Cron Jobs                                 │
│                                           │
│ ✅ daily-health-check  0 9 * * *  ● on  │
│    Last: 09:00 today (0.3s, 1.2k tokens)│
│    Next: 09:00 tomorrow                  │
│    [Run Now] [Edit] [Disable] [Delete]   │
│                                           │
│ ⏸ weekly-report       0 18 * * 5  ○ off │
│    Last: never                            │
│    [Enable] [Edit] [Delete]              │
│                                           │
│ [+ Add Job]                              │
│                                           │
│ ── Run History ──                        │
│ 09:00 daily-health  ✅ 0.3s  1.2k tok   │
│ 08:00 hourly-check  ✅ 0.1s  0.5k tok   │
│ 07:00 hourly-check  ❌ timeout           │
└──────────────────────────────────────────┘
```

数据源：`cron.list/add/update/remove/run/runs/status` + `cron` WebSocket 事件

### 6.7 Skills 管理（P1）

```
┌──────────────────────────────────────────┐
│ Skills — task-runner                      │
│                                           │
│ Installed (11):                           │
│ ├── autoresearch        v1.0  ● active   │
│ ├── coding              v1.0  ● active   │
│ ├── data-analysis       v1.0  ● active   │
│ ├── experiment-loop     v1.0  ● active   │
│ ├── task-state          v1.0  ● active   │
│ └── ...                                   │
│                                           │
│ [Install from ClawHub]  [Update All]     │
└──────────────────────────────────────────┘
```

数据源：`skills.status` (per agent) + `skills.bins` + `skills.install/update`

### 6.8 Tools 目录（P1）

显示每个 agent 可用的工具列表，按 profile 分组：

数据源：`tools.catalog` (agentId, includePlugins=true)

### 6.9 文件浏览器（P1）

Workspace 文件 + 容器内文件双视图。

数据源：
- Workspace: `agents.files.list/get/set` ✅
- 容器: broker `container-files-*` actions（需开发）

### 6.10 模型/Provider/Key 管理（P1）

数据源：`config.get/patch` + `config.schema` + `models.list`

### 6.11 Docker 容器管理（P1 — 需 broker 支持）

数据源：broker `container-*` actions

### 6.12 Broker 管理（P1 — 需 broker-proxy）

数据源：broker-proxy gateway plugin

### 6.13 Agent 配置管理（P1）

编辑 agent 的 model、tools profile、sandbox scope、workspace 等。

数据源：`agents.update` + `config.patch` + `config.schema.lookup`

### 6.14 Heartbeat 配置（P2）

全局开关 + per-agent heartbeat 间隔。

数据源：`set-heartbeats` + `last-heartbeat` + `config.patch` (agents.list[].heartbeat)

### 6.15 设备配对（P2）

数据源：`device.pair.list/approve/reject/remove` + `device.token.rotate`

### 6.16 渠道管理（P2）

飞书等渠道的连接状态和配置。

数据源：`channels.status` + `config.patch` (channels.*)

---

## 7. 项目结构

```
openclaw-gui/
├── src/
│   ├── api/
│   │   ├── rpc-client.ts       # WebSocket JSON-RPC 客户端 + 事件订阅
│   │   ├── types.ts            # Gateway RPC 类型定义
│   │   └── hooks/              # React hooks
│   │       ├── useAgents.ts
│   │       ├── useSessions.ts
│   │       ├── useCron.ts
│   │       ├── useHealth.ts
│   │       └── ...
│   ├── components/
│   │   ├── topology/           # Agent 拓扑图 (React Flow)
│   │   ├── sessions/           # Session 列表 + 对话查看器
│   │   ├── chat/               # 直接对话组件 (streaming)
│   │   ├── dashboard/          # 监控仪表盘 (Recharts)
│   │   ├── logs/               # Gateway 日志查看器
│   │   ├── cron/               # Cron 任务管理
│   │   ├── skills/             # Skills 管理
│   │   ├── tools/              # Tools 目录
│   │   ├── files/              # 文件浏览器 (workspace + container)
│   │   ├── docker/             # Docker 容器管理
│   │   ├── broker/             # Broker action 管理
│   │   ├── config/             # 模型/Provider/Key/Agent 配置
│   │   └── devices/            # 设备配对管理
│   ├── layouts/
│   │   └── MainLayout.tsx      # 侧边导航 + 顶栏
│   ├── App.tsx
│   └── main.tsx
├── package.json
├── vite.config.ts
├── tailwind.config.ts
└── nginx.conf
```

## 8. 导航结构

```
┌────────────┐
│ 🏠 Overview │  ← 拓扑图 + 健康状态 + 活跃 session 概览
│ 💬 Chat     │  ← 直接对话
│ 📋 Sessions │  ← Session 列表 + 对话查看
│ 📊 Monitor  │  ← Token 用量 + 健康 + Presence
│ 📜 Logs     │  ← Gateway 日志
│ ⏰ Cron     │  ← 定时任务管理
│ 🔧 Skills   │  ← Skills + Tools 目录
│ 📁 Files    │  ← 文件浏览器
│ 🐳 Docker   │  ← 容器管理
│ ⚡ Broker   │  ← Broker action 管理
│ ⚙️ Settings │  ← 模型/Provider/Agent/Channel 配置
└────────────┘
```

## 9. 实施路线图

| 阶段 | 交付 | 依赖 | 工作量 |
|------|------|------|--------|
| 0 | 搭建：Vite+React+Shadcn+WS RPC 客户端+主布局 | 无 | 基础 |
| 1 | Overview：拓扑图 + 健康 + 活跃概览 | Gateway API 已有 | 中等 |
| 2 | Chat + Sessions：对话 + session 管理 + streaming | Gateway API 已有 | 较多 |
| 3 | Monitor：Token 图表 + 健康仪表盘 + Presence | Gateway API 已有 | 中等 |
| 4 | Logs + Cron：日志查看器 + 定时任务管理 | Gateway API 已有 | 中等 |
| 5 | Skills + Tools + Files：技能管理 + 工具目录 + 文件浏览 | Gateway API 已有 | 中等 |
| 6 | Settings：模型/Provider/Key/Agent/Channel 管理 | Gateway API 已有 | 中等 |
| 7 | Docker + Broker：容器管理 + Broker UI | **需先实现 broker actions + proxy plugin** | 较多 |
| 8 | 设备 + 增强：配对管理 + Heartbeat 配置 + 用量成本 | Gateway API 已有 | 较少 |

## 10. Gateway API 交互示例

### 连接

```typescript
const ws = new WebSocket("ws://127.0.0.1:17777");
ws.send(JSON.stringify({
  jsonrpc: "2.0", method: "auth",
  params: { token: GATEWAY_TOKEN }, id: 1
}));
```

### 订阅实时事件

```typescript
// 订阅所有 session 元数据变更
ws.send(JSON.stringify({ jsonrpc: "2.0", method: "sessions.subscribe", id: 2 }));

// 订阅指定 session 消息流
ws.send(JSON.stringify({
  jsonrpc: "2.0", method: "sessions.messages.subscribe",
  params: { key: "agent:main:subagent:abc123" }, id: 3
}));

// Server pushes:
// { jsonrpc: "2.0", method: "sessions.changed", params: { sessionKey, ... } }
// { jsonrpc: "2.0", method: "sessions.messages", params: { ... } }
// { jsonrpc: "2.0", method: "health", params: { ts, health, stateVersion } }
// { jsonrpc: "2.0", method: "presence", params: { presence: [...] } }
// { jsonrpc: "2.0", method: "cron", params: { ... } }
```

### 查看日志

```typescript
ws.send(JSON.stringify({
  jsonrpc: "2.0", method: "logs.tail",
  params: { limit: 500, maxBytes: 250000 }, id: 4
}));
// Response: { file, cursor, size, lines[], truncated, reset }
// 下次用 cursor 获取增量
```

### Cron 管理

```typescript
// 创建定时任务
ws.send(JSON.stringify({
  jsonrpc: "2.0", method: "cron.add",
  params: {
    name: "daily-health-check",
    schedule: { cron: "0 9 * * *" },
    sessionTarget: { agent: "main" },
    wakeMode: "idle",
    payload: { kind: "message", message: "Run daily health check" }
  }, id: 5
}));

// 查看执行历史
ws.send(JSON.stringify({
  jsonrpc: "2.0", method: "cron.runs",
  params: { scope: "all", limit: 20, sortDir: "desc" }, id: 6
}));
```
