# OpenClaw 当前真实边界

> 更新日期：2026-03-28（DuckCoding 迁移 + GUI 前端 + 全量文档更新）
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
| **Phase 5A: sessions.visibility 部署** | **完成 ✅** | **2026-03-27** |
| **Phase 5B: 模型切换 (main→gpt-5.4, RC/auditor→opus)** | **完成 ✅** | **2026-03-27** |
| **Phase 5C: DuckCoding API 迁移** | **完成 ✅** | **2026-03-28** |
| **Phase 5D: Provider 清理** | **完成 ✅** | **2026-03-28** |
| **Phase 5E: GUI 前端开发** | **基础功能完成** | **2026-03-28** |
| **Phase 5F: Workspace 模板全量更新** | **完成 ✅** | **2026-03-28** |

## 当前真实边界

| 事项 | 状态 |
|------|------|
| OpenClaw 版本 | **2026.3.23-2** |
| Gateway | **active (running)** — ws://127.0.0.1:17777 |
| **API Endpoint** | **api.duckcoding.ai**（从 MotChat 迁移完成） |
| Providers | `duckcoding-claude` (opus-4-6), `duckcoding-gpt` (gpt-5.4), `custom-api-deepseek-com` (deepseek-chat), `duckcoding-claude-backup` |
| **main model** | **duckcoding-gpt/gpt-5.4** |
| **research-coordinator model** | **duckcoding-claude/claude-opus-4-6** |
| **auditor model** | **duckcoding-claude/claude-opus-4-6** |
| task-runner model | defaults → deepseek-chat |
| sessions.visibility | **all** ✅ |
| sandbox.sessionToolsVisibility | **all** ✅ |
| agentToAgent | enabled for ["main", "auditor"] ✅ |
| ACP | **verified** via acpx-wrapper.sh → DuckCoding |
| Broker | **active (running)** — Unix socket |
| 飞书 | **连接正常** — WebSocket, bundled feishu plugin |
| GPU | **可用** — RTX 5060 Ti 16GB |
| **GUI 前端** | **运行中** — Vite dev server :3000, 11 页面 |

## GUI 前端状态

| 页面 | 功能 | 状态 |
|------|------|------|
| Overview | Agent 拓扑图 + 健康 + Presence | ✅ 基本可用 |
| Chat | 新建 session 对话 | ⚠ 不能续接已有 session |
| Sessions | Session 列表 + 对话查看 | ⚠ Reset 行为待修正 |
| Monitor | Token 用量 + 健康 + Session 统计 | ✅ 可用 |
| Logs | Gateway 日志查看器 | ✅ 可用 |
| Cron | 定时任务管理 | ✅ 可用（当前无 job） |
| Skills | Skills + Tools 目录 | ✅ 可用 |
| Settings | 配置只读展示 | ⚠ Gateway 无 config 写权限 |
| Files / Docker / Broker | 占位 | 待 broker actions |

## 待解决

- **Chat 续接已有 session**：当前只能 new session，不能继续对话
- **Sessions Reset 行为**：reset 清空历史，应改为"新建 session，保留旧记录"
- **Settings 只读**：Gateway 进程无 `/etc/openclaw/openclaw.json` 写权限（EROFS）
- **Session 生命周期**：100+ "active" sessions，需理解 archive/prune 机制
- **Session spawn chain 可视化**：以 task 为视角的完整拓扑关系
- **消息渲染增强**：tool call 展开、代码高亮、agent badge 跳转
- **Docker/Broker/File 页面**：需要 broker actions 实现
- **Heartbeat 管理 UI**
- **MCP 管理 UI**
- **UI 美化**：使用 `frontend-design:frontend-design` skill
- **安全加固**：IPv6 only + 登录鉴权
- **日志轮转**：`/var/log/openclaw/openclaw.log` ~500MB cap 已达
- **Vault sync**：维护窗口后尚未执行

## 当前下一步

1. 修复 GUI 关键问题（Chat 续接、Reset 行为、Settings 只读展示）
2. 用 frontend-design skill 美化 UI
3. 实现消息渲染增强（tool call、代码块、agent badge）
4. 研究 session 生命周期，实现 spawn chain 可视化
5. 日志轮转 + Vault sync
