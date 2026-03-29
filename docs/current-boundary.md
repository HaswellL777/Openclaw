# OpenClaw 当前真实边界

> 更新日期：2026-03-29（Task Flow 详细视图 + 语法高亮 + Overview 仪表板 + 安全审计）
> 基线版本：**OpenClaw 2026.3.23-2**
> 阶段：**Phase 5 operational — 多 agent 编排 + GUI 管理前端**

---

## 已完成

| 阶段 | 状态 | 完成日期 |
|------|------|----------|
| Phase 0–2 | 完成 | 2026-03-07 ~ 2026-03-17 |
| Phase 3 (task-runner + Docker sandbox) | 完成 | 2026-03-24 |
| Phase 3+ (image upgrade + Scrapling) | 完成 | 2026-03-25 |
| OpenClaw 升级 → 2026.3.23-2 | 完成 | 2026-03-25 |
| Phase 4 (ACP + Agent 扩展) | 完成 | 2026-03-26 |
| Phase 5A–5F (visibility, models, DuckCoding, providers, GUI, workspace) | 完成 | 2026-03-28 |
| **Phase 5G: GUI P0/P1 修复 + Task Flow + MessageRenderer** | **完成 ✅** | **2026-03-29** |
| **Phase 5H: Task Detail Swimlane + 语法高亮 + Overview 改版** | **完成 ✅** | **2026-03-29** |

## 当前真实边界

| 事项 | 状态 |
|------|------|
| OpenClaw 版本 | **2026.3.23-2** |
| Gateway | **active (running)** — ws://127.0.0.1:17777 |
| **API Endpoint** | **api.duckcoding.ai** |
| Providers | `duckcoding-claude` (opus-4-6), `duckcoding-gpt` (gpt-5.4), `custom-api-deepseek-com` (deepseek-chat), `duckcoding-claude-backup` |
| main model | **duckcoding-gpt/gpt-5.4** |
| RC/auditor model | **duckcoding-claude/claude-opus-4-6** |
| task-runner model | defaults → deepseek-chat |
| sessions.visibility | **all** ✅ |
| sandbox.sessionToolsVisibility | **all** ✅ |
| agentToAgent | enabled for ["main", "auditor"] ✅ |
| ACP | **verified** via acpx-wrapper.sh → DuckCoding |
| Broker | **active (running)** — Unix socket |
| 飞书 | **连接正常** — WebSocket, bundled feishu plugin |
| **GUI 前端** | **运行中** — Vite dev server :3000, 12 页面 |
| **日志轮转** | ✅ `/etc/logrotate.d/openclaw` (size 500M, rotate 7) |

## GUI 前端状态

| 页面 | 功能 | 状态 |
|------|------|------|
| Overview | Agent 卡片仪表板 + 快速统计 + 最近任务 + 健康 + Presence | ✅ 改版完成 |
| Chat | 新建/续接 session + streaming + idempotencyKey | ✅ 完成 |
| Sessions | Session 列表/Tree view + 对话查看 + Abort/Clear History | ✅ 完成（Delete 已隐藏） |
| **Task Flow** | **spawn chain 图 + 筛选/重命名/软归档 + 点击进入详细视图** | **✅ 完成** |
| **Task Detail** | **Swimlane 消息流程图 + 跨列箭头 + 消息折叠/展开 + 详情面板** | **✅ 新增** |
| Monitor | Token 用量 + 健康 + Session 统计 | ✅ 可用 |
| Logs | Gateway 日志查看器 | ✅ 可用 |
| Cron | 定时任务管理 | ✅ 可用 |
| Skills | Skills + Tools 目录 | ✅ 可用 |
| Settings | 配置只读展示 + agent 模型解析 | ✅ 完成 |
| Files / Docker / Broker | 占位 | 待 broker actions |

## GUI 技术栈

- React 19 + TypeScript + Vite 8 + Tailwind 4
- @xyflow/react (React Flow) — spawn chain 图
- react-syntax-highlighter (PrismLight + one-dark) — 代码块语法高亮
- react-markdown — Markdown 渲染
- @tanstack/react-query — 数据查询
- zustand — 全局状态
- recharts — 图表
- 字体：IBM Plex Sans + IBM Plex Mono

## 待解决

- **Task Flow 自动布局**：当前静态网格，考虑 dagre/elk 算法
- **Observability 扩展**：Vite middleware 扩展 (transcript/session-store), System Inspector 页面
- **Docker/Broker/File 页面功能**：需 broker actions（container-list/stats/lifecycle）
- **Heartbeat 管理 UI**：API 已有（set-heartbeats, last-heartbeat）
- **MCP 管理 UI**：设计文档在 `frontend-gui-design.md`，config.patch 不可用只能只读
- **Workspace 文件浏览**：agents.files.list/get/set API 已有
- **安全加固**：IPv6 + auth
- **Vault sync**：维护窗口后尚未执行

## 当前下一步

1. Task Flow 自动布局 (dagre)
2. Observability: 扩展 Vite middleware + System Inspector 页面
3. Workspace 文件浏览（agents.files API 已有）
4. Docker/Broker 页面（需 broker actions 开发）
