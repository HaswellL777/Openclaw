# OpenClaw 对话交接提示词

> 生成日期：2026-03-31
> 上一轮：Phase 5J — GUI auth + Docker/Broker 页面 + Cron 修复 + 部署自动化
> 模型：Claude Opus 4.6 (1M context)

---

## 第零部分：必读文档（开始工作前必须读完）

**按此顺序读取，不可跳过**：
1. `CLAUDE.md` — 安全边界、escalation 规则、anti-stall 规则、skill 编写规则
2. `docs/current-boundary.md` — 唯一实时状态文件
3. `docs/map.md` — 文档总地图
4. `docs/host-sop.md` §0 — 当前阶段定位
5. `.claude/handoff/handoff-2026-03-31-phase5j.md` — 本文件

**然后自行探索**：
- `gui/src/` 前端源码
- `gui/vite.config.ts` — auth middleware + Docker API + runs API
- `plugins/gateway-rpc-tool/` — Gateway RPC 插件
- OpenClaw 源码 `/opt/openclaw/node_modules/openclaw/dist/` — 不确定的行为从这里找证据

---

## 第一部分：工作纪律（每轮都适用）

1. **先读后做**：按第零部分顺序读文档。
2. **产出 > 分析**：每个任务有可落盘产物。
3. **不猜测**：不确定的系统行为，从源码找证据。
4. **config 变更走 escalation**：pre-snapshot → backup → apply → verify → rollback plan。
5. **workspace 更新后提醒 publish**：`sudo bash scripts/publish-workspace-all.sh --apply --allow-live-target all`
6. **发布前验证 skill**：`bash scripts/check-workspace-skills.sh`
7. **SKILL.md 必须有 YAML frontmatter**：`name` + `description` 字段。

### 踩过的坑（必须牢记）

| 坑 | 教训 |
|-----|------|
| **Gateway 消息用 `timestamp` 不是 `ts`** | chat.history 返回的消息字段是 `timestamp`（毫秒） |
| **Gateway cron payload 需要 `kind` 字段** | `{ kind: "agentTurn", message: "..." }` 不是 `{ agentTurn: { message: "..." } }` |
| **main session cron 必须用 systemEvent** | `sessionTarget: "main"` 时只允许 `kind: "systemEvent"` |
| **cron RPC 方法名** | `cron.run`（非 trigger）、`cron.remove`（非 delete）、toggle 用 `cron.update` + patch |
| **CronJob enabled 在顶层** | `job.enabled` 不是 `job.state.enabled` |
| **Docker sandbox 容器是 `sleep infinity`** | 没有 stdout 日志，Logs 功能无用，改为 Inspect |
| **容器文件系统 docker exec 权限** | 必须 `-u 0`（root），否则 runner 用户无法读所有目录 |
| **knowledge/ 是 read-only bind mount** | rsync --delete 会失败，必须 --exclude='knowledge/' |
| SKILL.md 无 YAML frontmatter | skill 被 gateway 静默丢弃 |
| sessions.delete 是永久操作 | 用 localStorage 软归档替代 |
| **h-screen 嵌套在 min-h-screen 中** | 子组件用 h-full，父 main 用 h-screen overflow-y-auto |
| 共享 parent session 不能加入 swimlane 列 | 飞书群聊等 shared session 包含所有不相关对话 |
| Gateway device pairing | WebSocket 连接需要 device pairing |

---

## 第二部分：已完成事项（截至 2026-03-31 本轮）

### Commit `fbb0d1f` — Phase 5J

**GUI 安全加固**：
- Token-based auth middleware（Vite plugin）
- Cookie + query param 两种认证方式
- `setup-gui-auth.sh` 生成随机 token
- systemd EnvironmentFile 集成
- 登录页面（OpenClaw 风格暗色主题）

**Docker 页面（全面重写）**：
- 容器列表：实时状态 + Start/Stop/Restart 按钮
- 文件浏览器：`docker exec -u 0` 导航容器文件系统
  - 快捷导航栏：Workspace / Skills / Control / Outputs / Tasks / Knowledge
  - 默认打开到容器 WorkingDir（`/workspace`）
  - 文件预览 + 面包屑导航
- Inspect 弹窗：挂载点、网络、环境变量、资源限制
- 镜像列表、网络列表
- 全部通过 Vite middleware Docker API 实现

**Broker 页面（全面重写）**：
- Gateway 健康仪表板
- 活跃 Session 列表 + Abort 按钮
- Channel 连接状态
- Agent-to-Agent 编排配置

**Cron 页面修复**：
- payload 格式修正（`kind` discriminator）
- 方法名修正（`cron.run`、`cron.remove`、`cron.update`）
- main session 自动选择 systemEvent
- enabled 字段读取修正

**布局修复**：
- `h-screen` → `h-full`（SessionsPage、TaskFlowPage、FilesPage）
- App.tsx main 加 `h-screen overflow-y-auto`
- SessionsPage header 加 `min-h-12`

**部署自动化**：
- `publish-workspace-all.sh` — 统一 4 workspace 发布
- `deploy-phase5j.sh` — 全量部署脚本
- `deploy-phase5j-remaining.sh` — 增量部署脚本

### 已执行的部署

- 全部 4 workspace 已发布到 live
- gateway-rpc-tool 插件已部署到 extensions
- openclaw.json 已 patch（plugin allow + main agent tools.allow）
- Gateway 已重启验证
- GUI auth token 已生成并启用
- nick 已加入 docker 组
- workspace-health-check cron job 已创建（`3 9 * * *`）
- Pre-change snapshot: `/.snapshots/root-pre-phase5j-deploy-20260331-0943`

---

## 第三部分：待做任务

### 任务 A（中优）：Vault Sync
- Phase 5 大量变更以来未执行 Vault 同步
- 需要在维护窗口执行
- 包含所有 workspace 发布 + plugin 部署 + config 变更

### 任务 B（低优）：清理旧 Docker 镜像
- `<none>` tag 镜像可以清理（`docker image prune`）
- GPU 镜像 `2026-03-v3-gpu`（9.79GB）确认是否还需要

### 任务 C（低优）：GUI 生产化
- 当前是 Vite dev server，不是生产构建
- 可选：Nginx 反代 + Vite build + 静态文件服务
- 可选：TLS（Let's Encrypt 或自签名）

### 任务 D（低优）：CronPage 编辑功能完善
- editFormData 回填缺少 payloadKind/sessionTarget 字段
- cron.update patch 格式可能需要进一步验证

---

## 第四部分：技术参考

### GUI Auth 流程
```
Browser → GET /any-page
  → middleware 检查 cookie `openclaw_gui_token`
  → 匹配 → pass through → Vite 正常服务
  → 不匹配 → 302 → /login?next=...
  → 用户输入 token → POST /__auth/verify
  → Set-Cookie → 302 → 原页面
  → query param: ?token=xxx → Set-Cookie → 302（去掉 token）
```

### Docker API 端点（Vite middleware）
| 端点 | 方法 | 功能 |
|------|------|------|
| `/api/docker/containers` | GET | 容器列表（含 workDir from inspect） |
| `/api/docker/images` | GET | 镜像列表 |
| `/api/docker/networks` | GET | 网络列表 |
| `/api/docker/action` | POST | 容器操作（stop/start/restart） |
| `/api/docker/inspect?id=` | GET | 容器详细信息 |
| `/api/docker/files?id=&path=` | GET | 容器内文件列表（`-u 0`） |
| `/api/docker/cat?id=&path=` | GET | 容器内文件内容（`-u 0`，max 1MB） |
| `/api/docker/logs?id=&tail=` | GET | 容器日志（stdout+stderr） |

### Gateway Cron RPC 正确格式
```typescript
// 创建
cron.add({ name, schedule: { cron: "..." }, sessionTarget: "main",
           wakeMode: "now", payload: { kind: "systemEvent", text: "..." } })

// 立即运行
cron.run({ jobId: "..." })

// 删除
cron.remove({ jobId: "..." })

// 启用/禁用
cron.update({ jobId: "...", patch: { enabled: true/false } })
```

### 关键文件
| 文件 | 用途 |
|------|------|
| `gui/vite.config.ts` | Auth middleware + Docker API + runs API + proxy |
| `gui/src/pages/DockerPage.tsx` | Docker 容器管理 + 文件浏览器 |
| `gui/src/pages/BrokerPage.tsx` | Broker 健康 + Session 管理 |
| `gui/src/pages/CronPage.tsx` | Cron 任务管理（修复后） |
| `gui/src/App.tsx` | 布局修复（h-screen） |
| `scripts/publish-workspace-all.sh` | 统一 workspace 发布 |
| `scripts/deploy-phase5j.sh` | 全量部署脚本 |
| `scripts/setup-gui-auth.sh` | GUI auth token 生成 |

---

## 第五部分：启动 checklist

1. 读完第零部分文档
2. 确认 GUI 运行中：`systemctl is-active openclaw-gui.service`
3. 确认 Gateway 运行中：`systemctl is-active openclaw-gateway.service`
4. 访问 GUI 确认 auth 工作（需要 token 或已有 cookie）
5. 检查 Docker 页面能否看到容器和文件
6. 检查 Cron 页面 health-check job 存在
7. 处理第三部分的待做任务
