# OpenClaw 对话交接提示词

> 生成日期：2026-04-01
> 上一轮：Phase 6 推进 — outputs schema + task-init + hotfixes + 文档全量同步
> 模型：Claude Opus 4.6 (1M context)

---

## 第零部分：必读文档（开始工作前必须读完）

**按此顺序读取，不可跳过**：
1. `CLAUDE.md` — 安全边界、escalation 规则、anti-stall 规则、skill 编写规则
2. `docs/current-boundary.md` — 唯一实时状态文件
3. `docs/map.md` — 文档总地图
4. `docs/host-sop.md` §0 — 当前阶段定位
5. `.claude/handoff/handoff-2026-04-01-phase6-hotfixes.md` — 本文件

**然后自行探索**：
- `gui/src/` 前端源码
- `gui/vite.config.ts` — auth middleware + Docker API + runs API
- `workspace-main-template/skills/` — 6 个 main agent skill
- `workspace-task-runner-template/` — 12 skills + schemas/ + outputs/
- `task-project-template/` — ACP Claude Code 容器内项目模板
- `scripts/hotfix-*.sh` — 3 个 live-side hotfix 脚本

---

## 第一部分：工作纪律（每轮都适用）

1. **先读后做**：按第零部分顺序读文档。
2. **产出 > 分析**：每个任务有可落盘产物。
3. **不猜测**：不确定的系统行为，从源码找证据。
4. **config 变更走 escalation**：pre-snapshot → backup → apply → verify → rollback plan。
5. **workspace 更新后提醒 publish**：`sudo bash scripts/publish-workspace-all.sh --apply --allow-live-target all`
6. **发布前验证 skill**：`bash scripts/check-workspace-skills.sh`
7. **SKILL.md 必须有 YAML frontmatter**：`name` + `description` 字段。
8. **gateway 重启后修复权限**：`sudo chmod 0750 /var/lib/openclaw/.openclaw /var/lib/openclaw/.openclaw/subagents`

### 踩过的坑（必须牢记）

| 坑 | 教训 |
|-----|------|
| **GPT-5.4 填 streamTo: "parent"** | Tool schema 泄漏 — 模型看到 optional 参数就填。skill 禁令无效。必须源码 hotfix |
| **GPT-5.4 填 cleanup: "delete"** | 同上 — subagent session + run 被自动删除。必须源码 hotfix 强制 keep |
| **saveJsonFile chmod 0600** | 每次写入都清掉 ACL/group 权限。hotfix 改为 0640 |
| **`.openclaw/` 目录权限 700** | gateway 重启后目录权限回到 700，nick 读不到 runs.json |
| **Gateway 消息用 `timestamp` 不是 `ts`** | chat.history 返回的消息字段是 `timestamp`（毫秒） |
| **shared container 并发冲突** | 两个 spawn 同时到达，第二个报 container name conflict。避免并行 spawn |
| **main session cron 必须用 systemEvent** | `sessionTarget: "main"` 时只允许 `kind: "systemEvent"` |
| **knowledge/ 是 read-only bind mount** | rsync --delete 会失败，必须 --exclude='knowledge/' |
| SKILL.md 无 YAML frontmatter | skill 被 gateway 静默丢弃 |
| SKILL.md CRLF 换行符 | 检查脚本报 frontmatter 缺失，实际是 CRLF 问题 |

---

## 第二部分：已完成事项（截至 2026-04-01 本轮）

### GUI 修复

- **DockerPage**: outputs 路径错误处理 + "Go to parent" 按钮 + 快捷导航排序
- **CronPage**: editFormData 完全重写（scheduleType/sessionTarget/payloadKind/message 正确回填）
- **ChatPage**: URL session 持久化（`?session=xxx`）+ streaming final 后 refetch 完整 history
- **MessageRenderer**: CollapsibleContent（>500 字符自动折叠）+ ToolResultCard（JSON 折叠卡片）+ tool role 消息不再隐藏

### Workspace 模板

- **task-runner**: `outputs/` 目录 + README + `schemas/task-runner-summary.schema.json` + `schemas/host-change-request.schema.json` + `skills/task-init/SKILL.md`（12 skills 总计）
- **main**: `skills/host-change-review/SKILL.md` + `skills/task-delegation/SKILL.md` 更新（streamTo 禁用规则 + cleanup: keep + sessions_spawn 参数规则）
- **task-project-template/**: 新建，含 `CLAUDE.md` + `.claude/settings.json` + `.claude/agents/{coder,tester,reviewer,doc-writer}.md`

### 文档同步

- **host-sop.md**: §0 日期/阶段 → 2026-04-01；§0.5 四个未决问题标记已解决；§12 MotChat→DuckCoding
- **design-v3.md**: Phase 3 全部 21 项勾选；Phase 4 勾选 6 项；Phase 5 标注原设计废弃；Phase 6 勾选 5 项
- **current-boundary.md**: 完整更新含 hotfix 记录
- **map.md**: 加入 task-project-template + container-isolation 归档
- **planning/README.md**: container-isolation 归档

### 文档归档

- `docs/planning/container-isolation-design.md` → `archive/planning/container-isolation/`
- `docs/records/post-upgrade-capability-probe-execution-2026-03-19.md` → `archive/records/phase3-stall/`

### 脚本

- `scripts/publish-workspace-all.sh`: rsync `--exclude='knowledge/'`
- `scripts/hotfix-streamto-noop.sh`: streamTo guard 静默忽略
- `scripts/hotfix-json-file-chmod.sh`: saveJsonFile chmod 0600→0640
- `scripts/hotfix-cleanup-keep.sh`: sessions_spawn cleanup 强制 keep

### Live 部署

- 全部 4 workspace 已发布到 live（多次）
- 3 个 hotfix 已应用到 `/opt/openclaw/node_modules/openclaw/dist/`
- nick 已加入 openclaw group
- Docker `<none>` 镜像已清理

---

## 第三部分：待做任务

### 任务 A（高优）：Chat session spawn 消息不可见
- sessions_spawn 的 tool_use/tool_result 在 Chat 页面不显示
- MessageRenderer 的 ToolCallCard 已有折叠功能，但 spawn 结果的渲染路径可能被跳过
- 需要对比官方 control-ui 的 tool streaming 机制

### 任务 B（高优）：outputs/task-init-test 权限问题
- 容器内 `ls /workspace/outputs/task-init-test: Permission denied`
- 原因：main agent 绕过 task-runner 直接用 write 工具写入，ownership 可能不对
- 需要 `docker exec -u 0 openclaw-sbx-shared chmod -R 755 /workspace/outputs/task-init-test`

### 任务 C（中优）：runs.json 权限持久化
- 每次 gateway 重启后 `.openclaw/` 目录权限回到 700
- 方案：在 openclaw-gateway.service 加 ExecStartPost 或创建 tmpfiles.d 规则
- 当前需手动：`sudo chmod 0750 /var/lib/openclaw/.openclaw /var/lib/openclaw/.openclaw/subagents`

### 任务 D（低优）：GUI 生产化
- 当前 Vite dev server，可选 Nginx + build + TLS

### 任务 E（低优）：Phase 6 剩余
- backup/recovery 脚本（3 项）

---

## 第四部分：技术参考

### Live Hotfixes

| 脚本 | 目标文件 | 改动 |
|------|----------|------|
| `hotfix-streamto-noop.sh` | `pi-embedded-CbCYZxIb.js:115534` | `if (false && streamTo ...)` |
| `hotfix-json-file-chmod.sh` | `json-file-Dl3Z1jL1.js:20` | `chmodSync(416)` |
| `hotfix-cleanup-keep.sh` | `pi-embedded-CbCYZxIb.js:115060,115527` | `const cleanup = "keep"` |

Pre-hotfix snapshot: `/.snapshots/root-pre-streamto-hotfix-20260401-1230`

### 关键文件

| 文件 | 用途 |
|------|------|
| `gui/src/pages/ChatPage.tsx` | Chat 页面（URL 持久化 + streaming refetch） |
| `gui/src/pages/DockerPage.tsx` | Docker 容器管理 + 文件浏览器 |
| `gui/src/pages/CronPage.tsx` | Cron 任务管理 |
| `gui/src/components/MessageRenderer.tsx` | 消息渲染（CollapsibleContent + ToolResultCard） |
| `workspace-main-template/skills/task-delegation/SKILL.md` | spawn 参数规则 |
| `workspace-main-template/skills/host-change-review/SKILL.md` | host-change-request 审批流 |
| `workspace-task-runner-template/skills/task-init/SKILL.md` | 任务初始化 skill |
| `workspace-task-runner-template/schemas/` | summary.json + host-change-request.json schema |
| `task-project-template/` | ACP Claude Code 容器内项目模板 |
| `scripts/hotfix-*.sh` | 3 个 hotfix 脚本 |

### GPT-5.4 Tool Schema 问题

根因：`sessions_spawn` 的 `SessionsSpawnToolSchema` 暴露了 `streamTo` 和 `cleanup` 参数给所有 runtime。GPT-5.4 作为强 schema-following 模型，会自动填入这些参数。skill/prompt 指令无法覆盖。

修复层级（按可靠性排序）：
1. **最佳**：上游动态 schema（按 runtime 隐藏不适用参数）
2. **最小**：后端兼容（非 ACP 路径静默忽略 streamTo；强制 cleanup=keep）← 当前已做
3. **不推荐**：换模型（概率性降低问题，不是根治）

---

## 第五部分：启动 checklist

1. 读完第零部分文档
2. 确认 GUI 运行中：`systemctl is-active openclaw-gui.service`
3. 确认 Gateway 运行中：`systemctl is-active openclaw-gateway.service`
4. 确认 runs.json 可读：`python3 -c "import json; print(len(json.load(open('/var/lib/openclaw/.openclaw/subagents/runs.json')).get('runs',{})))"`
5. 如果 runs.json 不可读：`sudo chmod 0750 /var/lib/openclaw/.openclaw /var/lib/openclaw/.openclaw/subagents`
6. 确认 hotfix 生效：`grep '\[hotfix\]' /opt/openclaw/node_modules/openclaw/dist/pi-embedded-CbCYZxIb.js | wc -l`（应该 ≥ 3）
7. 处理第三部分的待做任务
