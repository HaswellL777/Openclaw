# 前端 GUI 需求规格 & 技术选型

> 日期：2026-03-27
> close-by：2026-04-05（设计文档，作为独立工程的启动输入）
> 状态：**设计完成，未实施**

---

## 1. Operator 核心需求

| # | 需求 | 优先级 |
|---|------|--------|
| 1 | Agent 拓扑可视化——名字、状态、父子关系图 | P0 |
| 2 | Session 内容查看——完整对话、agent 间消息流向 | P0 |
| 3 | **直接对话**——在 GUI 中直接与任意 agent 对话 | P0 |
| 4 | 文件浏览器——容器内 + 宿主机 workspace，可下载 | P1 |
| 5 | **Docker 容器管理**——查看容器状态、浏览容器内文件、执行操作 | P1 |
| 6 | 监控仪表盘——token 用量、耗时、错误率 | P1 |
| 7 | **Broker 管理**——查看 broker action 历史、审批队列、手动触发 action | P1 |
| 8 | **模型/地址/Key 管理**——便捷修改 provider endpoint、API key、agent 模型选择 | P1 |
| 9 | 不重复 Gateway 内置 dashboard 已有功能 | 约束 |

## 2. Gateway API 能力清单

### 可用 RPC 方法（WebSocket JSON-RPC at ws://127.0.0.1:17777）

**源码**：`gateway-cli-Dsd9gHBa.js`

#### Session 管理（覆盖需求 #1, #2）

| Method | 功能 | 关键参数 |
|--------|------|----------|
| `sessions.list` | 列出所有 session（含 agent/parent 关系） | — |
| `sessions.create` | 创建 session | agentId, label, model, parentSessionKey |
| `sessions.send` | 发送消息 | key, message |
| `sessions.abort` | 中断运行 | key |
| `sessions.delete` | 删除 session | key, deleteTranscript |
| `sessions.patch` | 修改 session（label/model） | key, label, model |
| `sessions.preview` | 获取消息预览（截断） | keys[], limit, maxChars |
| `sessions.usage` | Token 用量统计 | startDate, endDate, mode, key |
| `sessions.subscribe` | 订阅 session 变更事件 | — |
| `sessions.messages.subscribe` | 订阅实时消息流 | key |

#### Agent 管理

| Method | 功能 |
|--------|------|
| `agents.list` | 列出所有 agent |
| `agents.create/update/delete` | Agent CRUD |
| `agents.files.list/get/set` | Agent workspace 文件操作 |

#### 配置 & 监控

| Method | 功能 |
|--------|------|
| `config.get` | 获取完整配置 |
| `config.schema` | 获取 config JSON schema |
| `models.list` | 列出可用模型 |
| `tools.catalog` | 获取工具目录 |
| `health` | 健康状态 |
| `status` | 系统状态（需 admin scope） |
| `channels.status` | 渠道连接状态 |

#### 推送事件（Server → Client）

| Event | 触发条件 |
|-------|----------|
| `sessions.changed` | Session 元数据变更 |
| `sessions.messages` | 订阅 session 的新消息 |
| `presence` | Agent 在线状态变更 |
| `health` | 健康快照更新 |

### HTTP 端点

| Path | 功能 |
|------|------|
| `/health`, `/healthz` | 健康检查探针 |
| `/__openclaw__/control-ui-config.json` | 内置 Control UI 配置 |

### API 覆盖度分析

| 需求 | Gateway API 覆盖 | 需额外开发 |
|------|------------------|-----------|
| Agent 拓扑 | `agents.list` + `sessions.list`（含 parent 关系） ✅ | 前端可视化渲染 |
| Session 内容 | `chat.history` ✅ | 消息格式化展示 |
| 直接对话 | `sessions.create` + `chat.send` + `sessions.messages.subscribe` ✅ | 聊天 UI 组件 |
| 实时更新 | `sessions.subscribe` + `sessions.messages.subscribe` ✅ | WebSocket 客户端 |
| Token 用量 | `sessions.usage` ✅ | 图表渲染 |
| Workspace 文件 | `agents.files.list/get/set` ✅ | 文件树 + 编辑器 |
| 容器内文件 | 无直接 API **[API GAP]** | broker action: `container-files-*` |
| 容器管理 | 无直接 API **[API GAP]** | broker action: `container-lifecycle/stats` |
| Broker 管理 | 无直接 API **[API GAP]** | broker-proxy gateway plugin 或 HTTP sidecar |
| 模型/Key 管理 | `config.get/patch` + `config.schema` ✅ | 表单 UI + 验证 |
| 错误率 | 无聚合 API **[API GAP]** | 从 session 状态推导 |

### [API GAP] 标注

1. **容器内文件浏览**：`agents.files.list/get` 只操作 workspace 文件，不直接暴露容器文件系统。
   - **方案**：新增 broker actions（`container-files-list`, `container-files-get`, `container-files-put`）
   - 封装 `docker exec` 和 `docker cp`，通过 broker 审批链控制访问权限

2. **容器管理操作**：Gateway 不暴露 Docker 操作。
   - **方案**：新增 broker actions（`container-list`, `container-stats`, `container-lifecycle`）
   - 封装 `docker ps`、`docker stats`、`docker stop/restart`

3. **Broker 管理 API**：Broker 走 Unix socket，前端无法直接访问。
   - **方案 A（推荐）**：gateway broker-proxy plugin，将 broker RPC 暴露为 gateway method
   - **方案 B**：HTTP proxy sidecar，独立进程转发到 Unix socket

4. **错误率统计**：Gateway 没有聚合错误率的 API。
   - **方案**：前端从 session 列表中统计 error 状态，自行聚合

5. **完整对话历史 API**：`chat.history` 存在，但需确认返回格式。
   - **验证方式**：通过 WebSocket 调用 `chat.history` 测试

## 3. 内置 Dashboard 功能（避免重复）

Gateway 在 `:17777` 端口提供内置 Control UI：
- Session 列表和基本管理
- 配置编辑器（带 schema 验证）
- Channel 状态
- 基本监控

**不重复的策略**：
- 自定义 GUI 聚焦于 **多 agent 编排视图** 和 **研究任务管理**
- 内置 dashboard 保留为 **低级管理/调试工具**
- 两者共存，面向不同使用场景

## 4. 技术选型

### 前端框架

**推荐：React + TypeScript + Vite**

| 选项 | 优势 | 劣势 |
|------|------|------|
| React + TS + Vite (**推荐**) | 生态最大、组件库丰富、Claude/GPT 生成质量最高 | 无明显劣势 |
| Vue 3 + TS | 轻量、模板直观 | 生态略小、agent 生成质量稍低 |
| Svelte 5 | 极轻量、编译时优化 | 组件库少、agent 生成质量不稳定 |

### UI 组件库

**推荐：Shadcn/UI + Tailwind CSS**
- 组件可定制性强，不引入重依赖
- 支持 dark mode（运维工具标配）

### 图表/可视化

| 用途 | 库 |
|------|-----|
| Agent 拓扑图 | **React Flow**（节点编辑器/流程图） |
| Token 用量图表 | **Recharts**（轻量 React 图表库） |
| 文件树 | 自实现或 Shadcn Tree |

### WebSocket 客户端

- 使用原生 WebSocket + 自定义 JSON-RPC 封装
- Gateway 使用标准 JSON-RPC 2.0 over WebSocket

### 部署方式

**方案：静态文件 + Nginx reverse proxy**

```
┌─────────────────────────────────┐
│  Browser                        │
│  http://localhost:3000          │
│  ├── / → GUI 静态文件           │
│  └── /ws → ws://127.0.0.1:17777│
└─────────────┬───────────────────┘
              │ nginx proxy
┌─────────────▼───────────────────┐
│  OpenClaw Gateway :17777        │
│  ├── WebSocket RPC              │
│  └── /__openclaw__/ 内置 UI     │
└─────────────────────────────────┘
```

**替代方案**：直接在 gateway 端口上部署（通过 gateway 的 controlUi.assetsRoot 配置替换内置 UI），但这会覆盖内置 dashboard，不推荐。

## 5. 功能模块设计

### 5.1 Agent 拓扑视图（P0）

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

数据源：
- `agents.list` → agent 配置（id, name, model）
- `sessions.list` → 活跃 session（parentSessionKey → 父子关系）
- `presence` 事件 → 实时状态更新

### 5.2 Session 对话查看器（P0）

```
┌──────────┬──────────────────────────────┐
│ Sessions │  main / session-abc123        │
│          │                               │
│ ▸ main   │  [user] 请分析蛋白质折叠数据 │
│   s-abc  │  [assistant] 好的，我来...    │
│ ▸ t-run  │  [tool:sessions_spawn]        │
│   s-def  │    → spawned task-runner      │
│ ▸ audit  │  [assistant] task-runner 已   │
│   s-ghi  │    完成初步分析...            │
│          │                               │
│          │  [12:34] 3,420 tokens         │
└──────────┴──────────────────────────────┘
```

数据源：
- `chat.history` → 完整对话
- `sessions.messages.subscribe` → 实时消息流
- `sessions.preview` → 列表中的消息预览

### 5.3 直接对话（P0）

```
┌──────────────────────────────────────────┐
│  Chat with: [main ▾]                      │
│                                            │
│  [user] 帮我分析一下最近的 token 消耗趋势 │
│  [assistant] 好的，让我查看最近的用量...   │
│  [assistant] 过去7天平均每天消耗...        │
│                                            │
│  ┌──────────────────────────────────┐      │
│  │ 输入消息...                  [⏎] │      │
│  └──────────────────────────────────┘      │
└──────────────────────────────────────────┘
```

数据源：
- `sessions.create` → 创建新 session（指定 agentId）
- `chat.send` → 发送消息
- `sessions.messages.subscribe` → 实时消息流
- 支持选择目标 agent（main, task-runner, research-coordinator, auditor）
- 支持选择 model override

### 5.4 文件浏览器（P1）

```
┌───────────────────┬────────────────────────┐
│ workspace-main/   │  control/SOP.md        │
│ ├── control/      │                        │
│ │   ├── SOP.md ◄──│  # Host SOP            │
│ │   └── state/    │  ## Current state       │
│ ├── skills/       │  ...                    │
│ └── memory/       │                        │
│                   │  [Download] [Raw]       │
│ ── Docker ──      │                        │
│ /workspace/       │                        │
│ ├── outputs/      │                        │
│ │   └── 20260328- │                        │
│ └── knowledge/    │                        │
└───────────────────┴────────────────────────┘
```

数据源：
- `agents.files.list/get` → workspace 文件 ✅
- 容器内文件 → **需要 broker action 或 Docker exec 封装**（见下方 §5.6）

### 5.5 监控仪表盘（P1）

数据源：
- `sessions.usage` → token 用量（支持 date range + 分组）
- `health` → 系统健康状态
- `channels.status` → 渠道连接状态

### 5.6 Docker 容器管理（P1）

```
┌──────────────────────────────────────────┐
│  Containers                               │
│                                           │
│  openclaw-sbx-shared  ● running  16h ago │
│  Image: openclaw-task-claude:2026-03-v3   │
│  CPU: 12%  MEM: 1.2G/16G  GPU: 45%      │
│                                           │
│  [Files] [Shell] [Logs] [Stop] [Restart] │
│                                           │
│  ── Container Files ──                    │
│  /workspace/outputs/                      │
│  ├── 20260328-model-routing-bench/       │
│  │   ├── task-state.json (3min ago)      │
│  │   ├── data/ (4 files)                 │
│  │   └── src/ (3 files)                  │
└──────────────────────────────────────────┘
```

**API 方案**：Gateway API 不直接暴露 Docker 操作。需要通过 broker 或新的 gateway plugin 封装。

| 操作 | 实现方式 |
|------|----------|
| 列出容器 | broker action: `container-list` → `docker ps` |
| 容器内文件列表 | broker action: `container-files-list` → `docker exec ls` |
| 容器内文件内容 | broker action: `container-files-get` → `docker exec cat` |
| 容器文件上传 | broker action: `container-files-put` → `docker cp` |
| 容器 shell | **[需设计]** WebSocket terminal → `docker exec -it bash` |
| 容器 stop/restart | broker action: `container-lifecycle` → `docker stop/restart` |
| 容器资源监控 | broker action: `container-stats` → `docker stats` |

### 5.7 Broker 管理（P1）

```
┌──────────────────────────────────────────┐
│  Broker Actions                           │
│                                           │
│  Recent:                                  │
│  ✅ gateway_health      12:30  0.2s      │
│  ✅ container-list      12:25  0.5s      │
│  ⏳ snapshot-create     12:20  pending   │
│  ❌ config-deploy       11:45  rejected  │
│                                           │
│  [New Action ▾]  [Pending Approvals (1)] │
│                                           │
│  ── Pending ──                            │
│  snapshot-create: "pre-model-switch"      │
│  Requested by: main agent                 │
│  [Approve] [Reject] [Details]            │
└──────────────────────────────────────────┘
```

**API 方案**：Broker 走 Unix socket (`/run/openclaw-broker.sock`)，前端无法直接访问。

方案选择：
| 方案 | 实现 | 复杂度 |
|------|------|--------|
| A: Gateway plugin（推荐） | 在 gateway 内加载 broker-proxy plugin，将 broker API 暴露为 RPC method | 中 |
| B: HTTP proxy sidecar | 独立进程监听 HTTP，转发到 Unix socket | 低 |
| C: 直接改 broker 加 HTTP 端口 | broker 同时监听 Unix socket 和 TCP | 中 |

推荐方案 A：broker-proxy plugin 最自然地融入 gateway 的 RPC 体系，前端统一用一个 WebSocket 连接。

### 5.8 模型/地址/Key 管理（P1）

```
┌──────────────────────────────────────────┐
│  Provider Configuration                   │
│                                           │
│  ── Providers ──                          │
│  motchat-claude-4-6                       │
│    Base URL: [https://new.motchat.com/v1]│
│    API Key:  [••••••••••] [Show] [Test]  │
│    API:      [openai-completions ▾]      │
│    Models:   opus-4-6, sonnet-4-6, ...   │
│                                           │
│  custom-api-deepseek-com                  │
│    Base URL: [https://api.deepseek.com/v1]│
│    API Key:  [••••••••••] [Show] [Test]  │
│                                           │
│  ── Agent Models ──                       │
│  main:                 [opus-4-6 ▾]      │
│  research-coordinator: [opus-4-6 ▾]      │
│  task-runner:          [(default) ▾]     │
│  auditor:              [opus-4-6 ▾]      │
│                                           │
│  [Save & Restart]  [Test All Providers]  │
└──────────────────────────────────────────┘
```

数据源：
- `config.get` → 读取当前 models.providers + agents 配置 ✅
- `config.patch` → 修改 provider baseUrl/apiKey/models ✅
- `config.schema` → 获取字段验证规则 ✅
- `models.list` → 列出可用模型 ✅

**安全注意**：
- API Key 显示时默认遮蔽，点击 Show 才显示
- "Test" 按钮发送一个简单请求验证 endpoint/key 可用
- "Save & Restart" 需要确认对话框（config 变更会重启 gateway）

## 6. 项目结构

```
openclaw-gui/
├── src/
│   ├── api/
│   │   ├── rpc-client.ts       # WebSocket JSON-RPC 客户端
│   │   ├── types.ts            # Gateway RPC 类型定义
│   │   └── hooks.ts            # React hooks (useAgent, useSession, etc.)
│   ├── components/
│   │   ├── topology/           # Agent 拓扑图
│   │   ├── sessions/           # Session 列表 + 对话查看器
│   │   ├── chat/               # 直接对话组件
│   │   ├── files/              # 文件浏览器 (workspace + container)
│   │   ├── docker/             # Docker 容器管理
│   │   ├── broker/             # Broker action 管理
│   │   ├── config/             # 模型/Provider/Key 管理
│   │   └── dashboard/          # 监控仪表盘
│   ├── App.tsx
│   └── main.tsx
├── package.json
├── vite.config.ts
└── nginx.conf                  # 部署配置
```

## 7. 实施路线图

| 阶段 | 交付 | 依赖 | 预估工作量 |
|------|------|------|-----------|
| 0: 搭建 | Vite + React + Shadcn + WebSocket RPC 客户端 | 无 | 基础 |
| 1: 拓扑 | Agent 拓扑可视化 + 实时状态 | Gateway API 已有 | 中等 |
| 2: 对话 | 直接对话 + Session 查看器 + 实时消息 | Gateway API 已有 | 中等 |
| 3: 配置 | 模型/Provider/Key 管理 UI | Gateway config API 已有 | 中等 |
| 4: 监控 | Token 用量图表 + 健康状态 | Gateway API 已有 | 较少 |
| 5: 文件 | Workspace 文件浏览器 | Gateway API 已有 | 较少 |
| 6: Docker | 容器管理 + 容器内文件浏览 | **需要 broker action 新增** | 较多 |
| 7: Broker | Broker action 管理 + 审批队列 | **需要 broker-proxy plugin** | 较多 |

### 前置工作（阶段 6-7 依赖）

实施阶段 6-7 前需要：
1. **broker 新增 container-* actions** — 封装 `docker ps/exec/cp/stats`
2. **broker-proxy gateway plugin** — 将 broker Unix socket API 暴露为 gateway RPC
3. 或者用方案 B（HTTP proxy sidecar），复杂度更低但需要额外进程

## 8. Gateway API 交互示例

### 连接

```typescript
const ws = new WebSocket("ws://127.0.0.1:17777");
// 认证
ws.send(JSON.stringify({
  jsonrpc: "2.0",
  method: "auth",
  params: { token: GATEWAY_TOKEN },
  id: 1
}));
```

### 获取 Agent 列表

```typescript
ws.send(JSON.stringify({
  jsonrpc: "2.0",
  method: "agents.list",
  params: {},
  id: 2
}));
// Response: { jsonrpc: "2.0", result: { agents: [...] }, id: 2 }
```

### 订阅 Session 消息

```typescript
ws.send(JSON.stringify({
  jsonrpc: "2.0",
  method: "sessions.messages.subscribe",
  params: { key: "session-abc123" },
  id: 3
}));
// Server pushes: { jsonrpc: "2.0", method: "sessions.messages", params: { ... } }
```
