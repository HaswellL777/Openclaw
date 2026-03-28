# OpenClaw 对话交接提示词

> 生成日期：2026-03-28
> 上一轮：Phase 5 完成 + GUI 前端开发 + DuckCoding API 迁移
> 模型：Claude Opus 4.6 (1M context)

---

## 第一部分：工作纪律（长期规则，每轮都适用）

1. **先读后做**：`CLAUDE.md` → `docs/current-boundary.md` → `docs/map.md` → `docs/design-v3.md` → 自行探索
2. **产出 > 分析**：每个任务有可落盘产物
3. **不猜测**：从源码 `/opt/openclaw/node_modules/openclaw/dist/` 找证据
4. **config 变更走 escalation**：snapshot → backup → apply → verify → rollback
5. **workspace 更新后提醒 publish**
6. **自行测试**：所有 RPC 调用先用 `/tmp/test-*.mjs` 验证参数格式，不让用户当测试员

---

## 第二部分：已完成事项

### 配置部署（全部已验证 ✅）
- sessions.visibility = "all" + sandbox.sessionToolsVisibility = "all"
- main model → duckcoding-gpt/gpt-5.4
- research-coordinator/auditor/claude-engineer → duckcoding-claude/claude-opus-4-6
- task-runner → defaults (deepseek-chat)
- API 迁移：MotChat → DuckCoding (api.duckcoding.ai)
- Provider 清理：只保留 gpt-5.4, claude-opus-4-6, deepseek-chat
- Provider ID 重命名：motchat-* → duckcoding-*
- Auditor cross-agent 验证通过

### 前端 GUI（gui/ 目录）
- 框架：React + TypeScript + Vite + Tailwind + React Flow + Recharts
- 连接：WebSocket 通过 Vite proxy → Gateway loopback，OpenClaw 协议握手 + token auth
- 11 个页面，8 个有实际功能，3 个占位（Docker/Broker/File）
- 共享组件：PageHeader, Card, StatusDot, Spinner, ErrorBox, Badge, EmptyState
- 代码审查完成（/simplify 三 agent 审查 + 修复）

### Workspace 模板
- main AGENTS.md + task-delegation skill：完整 agent 拓扑 + 多阶段编排
- research-coordinator：模型选择 + per-task 目录 + task-state.json
- task-runner：task-state skill
- auditor：per-task 目录感知

### 设计文档
- `docs/planning/frontend-gui-design.md`：完整 GUI 需求规格 v2（含 MCP）
- `docs/planning/api-migration-model-switch.md`
- `docs/planning/container-isolation-design.md`

---

## 第三部分：本轮待修复问题（按优先级）

### P0 — 必须修复

#### 1. Settings 页面 — config 写入不可用
**现状**：Gateway 进程（openclaw 用户）对 `/etc/openclaw/openclaw.json` 没有写权限（EROFS）。
`config.set` 和 `config.patch` 都返回 `EROFS` 错误。

**影响**：前端无法修改任何配置（模型、provider、agent 设置等）。

**解决方案**：
- Settings 页面改为**只读展示**（当前配置一览）
- 如果需要支持前端写 config，需要通过 broker action 代理（broker 以 root 运行可以写文件）
- 或者给 openclaw 用户赋予 config 文件写权限（`chown openclaw /etc/openclaw/openclaw.json`）

#### 2. Sessions Reset 行为不符合预期
**现状**：`sessions.reset` 清空了 session 的全部对话历史。
**用户预期**：应该像飞书的 `/reset` 一样，新开一个 session，旧记录保留。
**解决方案**：
- 移除或重命名 Reset 按钮
- 改为"New Session"（创建新 session，旧的不删）
- 或者在 reset 前弹确认对话框，明确说明"将清除此 session 的全部对话历史"

#### 3. Chat 页面 — 无法继续已有 session
**现状**：只能 New Session，不能选择一个已有 session 继续对话。
**解决方案**：
- 在 Chat 页面添加 session 列表侧栏（类似 Sessions 页面的左栏）
- 或者在 Sessions 页面的对话视图底部加消息输入框
- 点击 session → 加载历史 → 底部输入框直接发消息

#### 4. chat.send 参数格式
**确认**：需要 `{ sessionKey, idempotencyKey, text }` — 已在代码中修复但未实际验证是否能发消息
**需要验证**：用 test script 实际发一条消息到 session 看返回格式

### P1 — 重要改进

#### 5. Session 生命周期理解
**现状**：显示 100+ "active" sessions，用户认为太多。
**需要研究**：
- 从源码中找 session 的状态定义（active/idle/archived/deleted）
- 理解 `archiveAfterMinutes`（当前 1440 = 24h）的行为
- 理解 heartbeat session 是否计入
- 确定哪些 session 应该在 overview/topology 中显示

#### 6. Session 关系可视化（spawn chain）
**用户需求**：以 task 为视角看完整拓扑——main spawn research-coordinator spawn task-runner 的链路，信息流向，关联的 Docker 文件
**实现方向**：
- sessions.list 返回 `childSessions` 字段可以构建 spawn tree
- session key 格式 `agent:AGENT_ID:subagent:UUID` 可以解析父子关系
- 需要新组件 SpawnTreeView

#### 7. 使用 frontend-design skill 美化 UI
**现状**：skill 已安装（`frontend-design:frontend-design`），但之前没有正确使用。
**需要**：用 `Skill` tool 调用 `frontend-design:frontend-design` 来改进 UI 设计质量。

#### 8. 消息渲染增强
- Tool call 展开/折叠（MessageRenderer 已创建但未验证）
- 代码块语法高亮 + 复制按钮
- Agent badge 来源/目标 + 点击跳转
- sessions_spawn 显示为特殊卡片

### P2 — 后续

#### 9. Docker/Broker/File 实际功能
需要实现 broker actions（container-list, container-files-*, broker-proxy plugin）

#### 10. Heartbeat 管理 UI
`set-heartbeats` + `last-heartbeat` API 已确认可用

#### 11. MCP 管理 UI
设计文档已写，config 中加 mcp.servers 块（需要通过 broker 或 sudo）

#### 12. 安全加固
IPv6 only 绑定 + 登录鉴权（开发完成后实施）

---

## 第四部分：技术参考

### Gateway WebSocket 协议
- 握手：server 发 `connect.challenge` → client 发 `connect` 请求（需 client.id, mode, platform, scopes, auth.token）
- 响应格式：`{ type: "res", id, ok, payload }` — 数据在 `payload` 不是 `result`
- 事件格式：`{ type: "event", event: "name", payload: {...} }`
- Client ID 必须是 `GATEWAY_CLIENT_IDS` 中的值（control-ui, cli, gateway-client 等）
- Scopes: `operator.read`, `operator.write`, `operator.admin`
- `openclaw-control-ui` + token + localhost + `allowInsecureAuth` = 完整 scopes

### API 参数速查（已验证）
| Method | 关键参数 |
|--------|---------|
| sessions.list | `agentId`（不是 agent）, limit, includeLastMessage |
| chat.history | `sessionKey`（不是 key） |
| chat.send | `sessionKey`, `idempotencyKey`, text |
| sessions.abort/reset/delete | `key` |
| sessions.create | agentId, label → 返回 `{ key, sessionId }` |
| config.get | 无参数 → 返回 `{ raw(string), parsed, resolved, hash }` |
| config.set | `raw`(string), `baseHash` — Gateway 无写权限（EROFS） |
| health channels | `ch.running` 可能 false 但 `ch.probe.ok` 为 true |

### 关键文件位置
| 文件 | 用途 |
|------|------|
| `gui/src/api/rpc-client.ts` | WebSocket RPC 客户端 |
| `gui/src/api/hooks.ts` | React hooks + Zustand store |
| `gui/src/api/types.ts` | TypeScript 类型定义 |
| `gui/src/components/shared.tsx` | 共享 UI 组件 |
| `gui/src/components/MessageRenderer.tsx` | 消息渲染器 |
| `gui/.env` | Gateway token（gitignored） |
| `/tmp/test-all-params.mjs` | API 参数测试脚本 |
| `scripts/apply-provider-cleanup.py` | Provider 清理脚本 |
| `scripts/apply-duckcoding-migration.py` | DuckCoding 迁移脚本 |
