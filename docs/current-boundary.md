# OpenClaw 当前真实边界

> 更新日期：2026-03-31（Phase 5J — GUI auth + Docker/Broker 功能化 + Cron 修复 + 全量部署）
> 基线版本：**OpenClaw 2026.3.23-2**
> 阶段：**Phase 5 operational — 多 agent 编排 + GUI 管理前端 + 安全加固**

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
| Phase 5G: GUI P0/P1 修复 + Task Flow + MessageRenderer | 完成 | 2026-03-29 |
| Phase 5H: Task Detail Swimlane + 语法高亮 + Overview 改版 | 完成 | 2026-03-29 |
| Phase 5I: Skill frontmatter 修复 + Gateway RPC Plugin + GUI bugfix | 完成 | 2026-03-30 |
| **Phase 5J: GUI auth + Docker/Broker 页面 + Cron 修复 + 部署自动化** | **完成 ✅** | **2026-03-31** |

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
| **GUI 前端** | **运行中** — Vite dev server :3000, token auth 已启用 |
| **Gateway RPC Plugin** | **已部署** — extensions/gateway-rpc-tool, main agent tools.allow |
| **Cron 健康检查** | **已创建** — workspace-health-check, 3 9 * * * |
| **日志轮转** | ✅ `/etc/logrotate.d/openclaw` (size 500M, rotate 7) |

## GUI 前端状态

| 页面 | 功能 | 状态 |
|------|------|------|
| Overview | Agent 卡片仪表板 + 快速统计 + 最近任务 + 健康 + Presence | ✅ 完成 |
| Chat | 新建/续接 session + streaming + idempotencyKey | ✅ 完成 |
| Sessions | Session 列表/Tree view + 对话查看 + Abort/Clear History | ✅ 完成 |
| Task Flow | spawn chain 图 + 筛选/重命名/软归档 + 点击进入详细视图 | ✅ 完成 |
| Task Detail | Swimlane 消息流程图 + 跨列箭头 + 消息折叠/展开 + 详情面板 | ✅ 完成 |
| Monitor | Token 用量 + 健康 + Session 统计 | ✅ 可用 |
| Logs | Gateway 日志查看器 | ✅ 可用 |
| **Cron** | **定时任务管理 + 创建/运行/删除/启禁用（payload 格式已修正）** | **✅ 修复** |
| Heartbeat | 最后心跳 + 开关 + Wake + 实时事件日志 | ✅ 完成 |
| Skills | Skills 列表 + 来源过滤 + 搜索 + Tools 目录 | ✅ 完成 |
| MCP | MCP 服务器列表 + 工具目录 + Raw config | ✅ 只读 |
| Workspace | Agent 控制面文件浏览 + 语法高亮 + 编辑/保存 | ✅ 完成 |
| **Docker** | **容器列表 + Start/Stop/Restart + 文件浏览器 + Inspect + 镜像/网络** | **✅ 功能化** |
| **Broker** | **Gateway 健康 + 活跃 Session 管理 + Abort + Channel 状态 + A2A 配置** | **✅ 功能化** |
| Settings | 配置只读展示 + agent 模型解析 | ✅ 完成 |
| Help | 操作参考手册（中文）— 重启/Docker/目录/快照/排障 | ✅ 完成 |

## 前端安全

- **Token 认证**：Vite middleware，Cookie + query param，HttpOnly
- **登录页面**：`/login`，暗色主题
- **Token 管理**：`scripts/setup-gui-auth.sh` 生成，systemd EnvironmentFile 注入
- 未设置 `GUI_AUTH_TOKEN` 时完全开放（向后兼容）

## 前端进程管理

- **systemd 服务**: `openclaw-gui.service`（已安装并启用）
- 开机自启，崩溃自动重启（5s 延迟）
- 日志：`journalctl -u openclaw-gui.service -f`

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

- **Vault sync**：Phase 5 大量变更以来未执行
- **GUI 生产化**：当前 Vite dev server，可选 Nginx + build + TLS
- **旧 Docker 镜像清理**：`<none>` tag + GPU 镜像确认

## 当前下一步

1. Vault sync（维护窗口）
2. GUI 生产化（可选）
3. 旧镜像清理（可选）
