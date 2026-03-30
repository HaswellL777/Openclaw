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
| Cron | 定时任务管理（官方 API 格式） | ✅ 完成 |
| **Heartbeat** | **最后心跳 + 开关 + Wake + 实时事件日志** | **✅ 新增** |
| Skills | Skills 列表 + 来源过滤 + 搜索 + Tools 目录 | ✅ 完成 |
| **MCP** | **MCP 服务器列表 + 工具目录 + Raw config** | **✅ 新增（只读）** |
| **Workspace** | **Agent 控制面文件浏览 + 语法高亮 + 编辑/保存** | **✅ 新增** |
| Docker | Sandbox 配置展示 + 无管理 API 提示 | ✅ 信息展示 |
| Broker | Broker 健康 + 配置展示 | ✅ 信息展示 |
| Settings | 配置只读展示 + agent 模型解析 | ✅ 完成 |
| **Help** | **操作参考手册（中文）— 重启/Docker/目录/快照/排障** | **✅ 新增** |

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

- **Docker/Broker 管理操作**：Gateway 无容器/broker lifecycle API，需开发 broker plugin
- **安全加固**：IPv6 + auth
- **Vault sync**：维护窗口后尚未执行
- **常态化健康检查**：skill 验证、workspace 完整性、config 一致性纳入 heartbeat/cron 检查

## 当前下一步

1. 常态化健康检查（workspace 验证 + config 一致性 + 磁盘空间）纳入 cron
2. Docker/Broker 管理需 broker plugin 开发
3. 安全加固（IPv6 + auth）
4. Vault sync
