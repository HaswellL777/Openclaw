# OpenClaw 对话交接提示词

> 生成日期：2026-03-29
> 上一轮：P0 全部修复 + Task Flow 页面 + MessageRenderer 增强 + 运维配置
> 模型：Claude Opus 4.6 (1M context)

---

## 第零部分：必读文档（开始工作前必须读完）

**按此顺序读取，不可跳过**：
1. `CLAUDE.md` — 安全边界、escalation 规则、anti-stall 规则
2. `docs/current-boundary.md` — 唯一实时状态文件
3. `docs/map.md` — 文档总地图
4. `docs/design-v3.md` §0/§5.3.2/§8.5 — 架构设计核心章节
5. `docs/planning/frontend-gui-design.md` — GUI 需求规格 v2（含 MCP、会话增强需求）
6. `.claude/handoff/handoff-2026-03-29-task-flow.md` — 本文件

**然后自行探索**：
- `gui/src/` 前端源码（特别是 `pages/TaskFlowPage.tsx` 和 `components/MessageRenderer.tsx`）
- `gui/src/api/rpc-client.ts` — Gateway WebSocket 协议实现
- `gui/vite.config.ts` — Vite 配置 + `/api/runs` middleware
- OpenClaw 源码 `/opt/openclaw/node_modules/openclaw/dist/` — 不确定的行为从这里找证据
- `/var/lib/openclaw/.openclaw/subagents/runs.json` — subagent 运行注册表（nick 已有 ACL 读权限）

---

## 第一部分：工作纪律（长期规则，每轮都适用）

1. **先读后做**：按第零部分顺序读文档。**这不是完整列表**——必须根据任务需要主动搜索仓库。
2. **产出 > 分析**：每个任务有可落盘产物（文件、脚本、配置候选）。
3. **不猜测**：不确定的系统行为，从源码和文档找证据。找不到标注 `[UNVERIFIED]`。
4. **config 变更走 escalation**：pre-snapshot → backup → apply 脚本 → verify → rollback plan。
5. **workspace 更新后提醒 publish**：task-runner/research-coordinator/auditor 无 publish 脚本，必须手动 rsync + 精确 chown（`knowledge/` 是 ro mount，`chown -R` 会失败）。
6. **自行测试**：所有 RPC 调用先用 Node.js WebSocket 脚本验证参数格式，不让用户当测试员。
7. **使用 Opus 4.6 subagent**：复杂任务用 `model: "opus"` 的 subagent 并行执行，最多 2-3 个，确保质量。
8. **使用 frontend-design skill**：前端 UI 改进时调用 `Skill` tool 使用 `frontend-design:frontend-design`。

### 踩过的坑（必须牢记，本轮新增标 🆕）

| 坑 | 教训 |
|-----|------|
| Gateway 响应数据在 `msg.payload` 不是 `msg.result` | 所有 RPC 都用 OpenClaw 协议不是 JSON-RPC |
| `chat.history` 用 `sessionKey` 不是 `key` | sessions.abort/reset/delete 用 `key`，chat.* 用 `sessionKey` |
| 🆕 `chat.send` 用 `message` 不是 `text` | schema `additionalProperties: false`，多余字段直接报错 |
| 🆕 Chat streaming event 名是 `"chat"` | **不是** `chat.message` 或 `chat.chunk`，payload 有 `state: "delta"\|"final"\|"error"` |
| 🆕 `chat.history` 返回的 content 始终是 array | `[{type:"text", text:"..."}]`，即使是 user 消息也是 array，不是 string |
| 🆕 `chat.history` 不返回 tool_use 块 | 不是因为过滤，是因为 session reset/compact 后旧 transcript 被 archived。Gateway handler 本身不过滤 tool_use |
| 🆕 `crypto.randomUUID()` 在 HTTP 上下文（非 HTTPS）的 Firefox 中不可用 | 必须加 fallback |
| 🆕 `runs.json` 结构是 `{version:2, runs:{<runId>:{...}}}` | 不是数组，需要 `data.runs` 才能拿到记录 |
| 🆕 `config.agents` 是 `{defaults:{...}, list:[{id,model,...}]}` | 不是 `{agentId:{...}}` 的 keyed object |
| `sessions.list` 筛选用 `agentId` 不是 `agent` | 参数名严格，多一个字段会被 schema 拒绝 |
| Health channels 的 `running` 可能 false 但 `probe.ok` 为 true | 判断健康状态要 `ch.running \|\| ch.probe?.ok` |
| `config.set/patch` 返回 EROFS | Gateway 进程无 config 文件写权限 |
| `openclaw-control-ui` client 触发 origin 检查 | 需要 Vite proxy 重写 Origin header 到 localhost |
| `scope: "shared"` 时 per-agent docker 配置被忽略 | image 必须在 defaults 级别设 |
| config schema `.strict()` | 未知字段导致 gateway crash loop |
| 切换 image 后旧容器继续跑 | 必须 `docker rm -f openclaw-sbx-shared` |
| `queueOwnerTtlSeconds` 默认 0.1s | 必须 override 到 300+ |

### 关于 React Flow（@xyflow/react）

| 问题 | 解决 |
|------|------|
| 节点不可拖拽 | 必须用 `useNodesState` + `onNodesChange`，不能只传静态 nodes array |
| Edge 报 "handle id null" | 自定义节点必须包含 `<Handle type="target" position={Position.Top}/>` 和 `<Handle type="source" position={Position.Bottom}/>` |
| 节点重叠 | 静态布局时必须手动计算每行高度，不能用固定 ROW_H |

---

## 第二部分：已完成事项（截至 2026-03-29）

### 配置部署（全部已验证 ✅）
- sessions.visibility = "all" + sandbox.sessionToolsVisibility = "all"
- main → duckcoding-gpt/gpt-5.4, RC/auditor/claude-engineer → duckcoding-claude/claude-opus-4-6
- 模型上下文窗口：claude-opus-4-6 = **500k ctx / 128k max**, gpt-5.4 = **1.05M ctx / 128k max**
- 日志轮转：`/etc/logrotate.d/openclaw`（size 500M, rotate 7, copytruncate）
- ACL：nick 可读 `/var/lib/openclaw/.openclaw/subagents/runs.json`

### 前端 GUI P0（全部完成 ✅）
- Chat 续接 session：`?session=` 参数 + SessionPicker 下拉
- `chat.send` 参数修复（text → message）
- Chat streaming 修复（event "chat" + state: delta/final/error）
- `crypto.randomUUID` fallback（HTTP context Firefox）
- User 消息 array content 正确渲染为 user bubble
- Sessions: "Reset" → "Clear History" + 确认对话框 + "Open in Chat" 按钮
- Sessions: ?agent= URL 参数 + spawn tree view (List/Tree toggle)
- Settings 全部只读 + amber info banner + agent model 从 config.agents.list 正确解析

### 前端 GUI P1（大部分完成 ✅）
- **Task Flow 页面**（`gui/src/pages/TaskFlowPage.tsx`）
  - Vite middleware `/api/runs` 直接读 runs.json（ACL 已设置）
  - 按时间聚类分 task group（10min gap），过滤心跳检查 spawn
  - 二级 spawn 正确连线（RC → sub-RC 通过 `requesterSessionKey`）
  - `useNodesState` 可拖拽节点，点击查看对话
- **MessageRenderer 增强**（`gui/src/components/MessageRenderer.tsx`）
  - `[Subagent Context]` / `OpenClaw runtime context` 自动折叠为可展开小条
  - `[Internal task completion event]` 解析为结构化卡片（agent badge + status + 可点击 session key）
  - Provenance 标记（→ from [agent]）用于 inter-session 消息
  - Spawn result JSON (`{status:"accepted",childSessionKey:...}`) 渲染为 "Spawned [agent]" 蓝色卡片
  - `<<<EXTERNAL_UNTRUSTED_CONTENT>>>` 折叠为 "External: source" 块
  - 可点击 agent badge 跳转到该 agent 的 session 列表
  - 改进 tool result 配对（处理 flat string content 的 tool messages）
- **UI 美化**：IBM Plex Sans/Mono 字体，自定义滚动条，页面淡入动画，sidebar indigo 高亮

---

## 第三部分：本轮待完成任务

### 任务 A（主要）：Task 内部消息流程图

**需求**：用户点击 Task Flow 中的某个 Task，进入一个专门的详细视图，以流程图形式展示该 task 内所有 session 间的消息流动。

**用户原话**：
> "例如专门的 task 视图，这个 task 点开以后整个视图就是整个 task 的内部，例如以消息一个块，然后区分不同的消息是哪个 agent 的，这些关键消息如何传递的，方向起点终点是什么，就像完整的流程一样"

**交互设计需要 plan**：
- Swimlane（每个 agent 一列，消息按时间向下排列）vs 时间线流程图？
- 哪些消息默认展开（spawn、completion event、user 指令），哪些折叠（runtime context、重复消息）？
- 一个 task 可能有 5-10 个 session × 100+ 条消息，如何分页/虚拟化？

**技术基础（已验证）**：
1. `runs.json`（已可读，Vite `/api/runs` middleware）：每个 run 有 `requesterSessionKey` → `childSessionKey` + `task` + 时间
2. `chat.history`：返回每个 session 的完整消息（content 始终是 array 格式）
3. `msg.provenance`：`{ kind: "inter_session", sourceSessionKey, sourceTool }` — 标识消息来源 session
4. 消息文本中 `[Internal task completion event]` 包含 `session_key` + `status` + `task`
5. Spawn result JSON `{status:"accepted", childSessionKey}` 标识 spawn 去向

**实现思路**：
1. 用户点击 Task card → 获取该 task 所有 session keys（从 runs data）
2. 并行调用 `chat.history` 获取所有 session 的消息
3. 构建 swimlane 视图：
   - 每个 session/agent 一列
   - 消息按时间向下排列
   - inter-session 消息（provenance 或 completion event）绘制跨列箭头
   - Spawn 事件绘制为分叉箭头
4. 用 React Flow 或自定义 SVG/Canvas 渲染

**注意事项**：
- `chat.history` 不返回 tool_use 块（因 session reset/compact 导致旧 transcript 被 archived）
- 需要从消息文本内容解析 provenance（`[Internal task completion event]` 块、spawn result JSON）
- delta streaming messages 中 content 是 accumulated text，不是增量
- `useNodesState` 必须用于可拖拽节点

### 任务 B（次要）：Observability 改进

**问题**：用户反映很难随时全面检查 OpenClaw control plane 状态。根本原因是权限隔离 + 缺少统一视图。

**已解决**：
- Settings 页面显示 config（通过 gateway `config.get` API）
- `/api/runs` middleware 读取 subagent 运行数据
- ACL 设置 nick 可读 `runs.json`（`scripts/setup-runs-access.sh`）

**待做**：
1. **扩展 Vite middleware**：
   - `/api/config` — 读取 `/etc/openclaw/openclaw.json`（需设置 ACL 或用 gateway API）
   - `/api/transcript?key=xxx` — 读取 session transcript JSONL
   - `/api/sessions-store` — 读取 session store 原始数据
2. **GUI "System Inspector" 页面**：
   - Config 原文显示（带语法高亮 + 与上次的 diff）
   - Session store 浏览（比 `sessions.list` 更原始的数据）
   - Subagent runs 表格（可排序、过滤）
   - Transcript 原始 JSONL 查看器
3. **ACL 扩展**：在 `scripts/setup-runs-access.sh` 中增加对 `/etc/openclaw/openclaw.json` 和 session store 路径的 ACL

### 任务 C（后续）：其他待做项

| 优先级 | 项目 | 阻塞情况 |
|--------|------|----------|
| P1 | 代码块语法高亮 | 需加 `react-syntax-highlighter`，纯前端 |
| P1 | Task Flow 自动布局 | 当前静态网格，考虑 dagre/elk 算法 |
| P2 | Docker/Broker/File 页面功能 | 需 broker actions（container-list/stats/lifecycle） |
| P2 | Heartbeat 管理 UI | API 已有（set-heartbeats, last-heartbeat） |
| P2 | MCP 管理 UI | 设计文档在 `frontend-gui-design.md`，config.patch 不可用只能只读 |
| P2 | Workspace 文件浏览 | agents.files.list/get/set API 已有 |
| P3 | 安全加固 | IPv6 + auth |
| P3 | Vault sync | 运维任务 |

---

## 第四部分：技术参考

### Gateway WebSocket 协议
```
Server → { type: "event", event: "connect.challenge", payload: { nonce, ts } }
Client → { type: "req", method: "connect", id: "1", params: { client: { id: "openclaw-control-ui", mode: "ui", platform: "...", version: "0.1.0" }, minProtocol: 3, maxProtocol: 3, role: "operator", scopes: ["operator.read","operator.write","operator.admin"], auth: { token: "..." } } }
Server → { type: "res", id: "1", ok: true, payload: { type: "hello-ok", ... } }
```

### Chat streaming event（🆕 已验证）
```
Event name: "chat" (NOT chat.message / chat.chunk)
Payload: { sessionKey, state: "delta"|"final"|"error", message?, errorMessage?, runId, seq }
delta message: { role: "assistant", content: [{type:"text", text:"<accumulated_full_text>"}], timestamp }
final message: same structure, or message=undefined if suppressed
```

### API 参数速查（🆕 已修正）
| Method | 参数 | 注意 |
|--------|------|------|
| sessions.list | `agentId`, limit, includeLastMessage | 不是 `agent` |
| chat.history | `sessionKey`, limit(max 1000) | 无 includeTools 参数，schema `additionalProperties: false` |
| **chat.send** | `sessionKey`, `idempotencyKey`, **`message`** | ~~text~~ 错的！字段名必须是 `message` |
| sessions.abort/reset/delete | `key` | 不是 `sessionKey` |
| sessions.create | agentId, label → `{ key, sessionId }` | |
| config.get | → `{ path, raw, parsed, resolved, hash }` | raw 是 JSONC 字符串 |

### chat.history 消息格式（🆕 已验证）
```
User message:   { role: "user", content: [{type:"text", text:"..."}], timestamp, __openclaw, senderLabel?, provenance? }
Assist message: { role: "assistant", content: [{type:"text", text:"..."}], api, provider, model, usage, stopReason, timestamp, responseId, __openclaw }
```
- content 始终是 array，不是 string
- provenance: `{ kind: "inter_session"|"external_user"|"internal_system", sourceSessionKey?, sourceTool? }`
- user 消息可能包含 `[Subagent Context]`、`OpenClaw runtime context`、`[Internal task completion event]` 文本块

### runs.json 结构（🆕 已验证）
```json
{
  "version": 2,
  "runs": {
    "<runId-uuid>": {
      "runId": "...",
      "childSessionKey": "agent:task-runner:subagent:...",
      "requesterSessionKey": "agent:main:feishu:group:...",
      "task": "任务描述文本",
      "label": "可选标签",
      "createdAt": 1774...,
      "startedAt": 1774...,
      "endedAt": 1774...,
      "outcome": { "status": "ok"|"timeout"|"error" },
      "cleanup": "keep"|"delete",
      "spawnMode": "run"|"session"
    }
  }
}
```
路径：`/var/lib/openclaw/.openclaw/subagents/runs.json`（nick ACL 可读）

### OpenClaw session 生命周期（🆕 源码验证）
- 无正式状态机：session entry 无 status 字段（仅 subagent 有 running/done/killed/failed/timeout）
- `sessions.reset` 保留 key，生成新 sessionId，archive 旧 transcript，零化 token 计数
- `sessions.compact` 保留最后 N 行 JSONL，不做摘要
- maintenance mode 默认 "warn"（不自动删除），pruneAfterMs = 30 天，maxEntries = 500
- `archiveAfterMinutes`（默认 60）仅影响 subagent session，到期后自动 delete
- 100+ session 是正常现象：每个 channel conversation 创建独立 session entry，从不自动清理

### 关键文件
| 文件 | 用途 |
|------|------|
| `gui/.env` | VITE_GATEWAY_TOKEN（gitignored） |
| `gui/vite.config.ts` | Vite 配置 + WS proxy + `/api/runs` middleware |
| `gui/src/api/rpc-client.ts` | OpenClaw WS 协议实现 |
| `gui/src/api/hooks.ts` | Zustand store + React Query hooks |
| `gui/src/api/types.ts` | TypeScript 类型（Session, ChatMessage 等） |
| `gui/src/components/MessageRenderer.tsx` | 消息渲染器（含 runtime context 折叠、provenance 标记、spawn card） |
| `gui/src/components/shared.tsx` | 共享组件（Badge, StatusDot, Spinner 等） |
| `gui/src/pages/TaskFlowPage.tsx` | Task Flow 节点图（React Flow + runs.json） |
| `gui/src/pages/ChatPage.tsx` | Chat 页面（session 续接 + streaming） |
| `gui/src/pages/SessionsPage.tsx` | Sessions 页面（Tree view + 确认对话框） |
| `gui/src/pages/SettingsPage.tsx` | Settings 页面（只读） |
| `gui/src/App.tsx` | 路由 + sidebar |
| `scripts/setup-runs-access.sh` | ACL 设置（nick 读 runs.json） |
| `scripts/apply-logrotate.sh` | 安装日志轮转 |
| `scripts/apply-model-context-windows.sh` | 更新模型上下文窗口 |

### 陷阱速查（继承 + 新增）
| 陷阱 | 说明 |
|------|------|
| config schema `.strict()` | 未知字段导致 gateway crash loop |
| `scope: "shared"` 忽略 per-agent docker | image 必须在 defaults 设 |
| 切换 image 后旧容器继续跑 | 必须 `docker rm -f openclaw-sbx-shared` |
| `minimal` profile 只有 1 个工具 | 不给需要工作的 agent 用 |
| acpx 默认 strip API key | 用 wrapper 脚本绕过 |
| `queueOwnerTtlSeconds` 默认 0.1s | 必须 override 到 300+ |
| Vite dev server 端口 3000 | `gui/` 目录下运行 `npx vite --port 3000`，访问 `http://10.129.40.88:3000` |
| Vite proxy 重写 Origin | 必须重写到 `localhost:17777` 否则 gateway 拒绝 origin |

---

## 第五部分：启动 dev server

```bash
cd ~/projects/openclaw-dev/gui
npx vite --port 3000
```

访问 `http://10.129.40.88:3000`，主要页面：
- `/overview` — Agent 拓扑 + 健康状态
- `/chat` — 对话（支持续接 session）
- `/sessions` — Session 列表/Tree view + 对话查看
- `/tasks` — Task Flow 节点图（spawn chain）
- `/settings` — 只读配置
- `/monitor`, `/logs`, `/cron`, `/skills` — 监控/日志/定时任务/技能
