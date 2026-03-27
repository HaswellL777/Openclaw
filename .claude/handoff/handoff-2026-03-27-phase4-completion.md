# OpenClaw 对话交接提示词

> 生成日期：2026-03-27
> 上一轮对话完成的工作：Phase 4 完成（ACP + GPU + Agent 扩展 + Skills），暴露多阶段编排结构性问题
> 模型：Claude Opus 4.6 (1M context)

---

你是 OpenClaw 宿主机开发仓库的工程执行者。你拥有 1M 上下文窗口。

## 工作纪律

1. **先读后做**：开始工作前，必须读以下文档：
   - `CLAUDE.md` — 项目规则、安全边界、anti-stall 规则
   - `docs/current-boundary.md` — 当前系统真实状态（**唯一实时状态源**）
   - `docs/map.md` — 文档地图
   - `docs/design-v3.md` §0 结论先行、§5.3.2（ACP 修正）、§8.5（Phase 4 TODO）
   - 然后**自行探索** workspace 模板、candidates、planning、scripts 等目录

2. **不碰 live 除非有 escalation plan**：不执行 sudo、docker build、systemctl。只生成文件和 operator 命令。

3. **不允许猜测**：遇到不确定的系统行为，必须从仓库文档、OpenClaw 源码（`/opt/openclaw/node_modules/openclaw/dist/`）、git 历史中找证据。不要靠推理"应该是这样"。

4. **慎用 subagent**：可以使用 Opus 4.6 (1M) 模型的 agent。不要大量并行 spawn——每次最多 2-3 个，确保质量。

---

## 当前系统状态（详见 docs/current-boundary.md）

- **OpenClaw**: 2026.3.23-2
- **Gateway**: active，port 17777
- **Agents**: main (deepseek-chat), task-runner (shared scope, GPU image), research-coordinator (deepseek-chat), auditor (coding profile+deny), ACP claude (one-shot)
- **GPU**: RTX 5060 Ti 16GB, nvidia default-runtime, container 内 torch.cuda=True
- **ACP**: verified ✅ via acpx-wrapper.sh (one-shot mode only)
- **agentToAgent**: enabled for ["main", "auditor"]
- **maxSpawnDepth**: 2 (main → coordinator → task-runner)

---

## 关键陷阱（上两轮踩过的坑）

### 配置文件保护
- `/etc/openclaw/openclaw.json` 变更走 **escalation rule**：pre-snapshot → backup → apply → verify → rollback plan
- 使用 `scripts/apply-agents-expansion.py` 式的结构化 apply 脚本，**禁止 `sudo nano` 直接编辑**
- config schema 是 `.strict()`，未知字段会导致 gateway crash loop
- `per-agent subagents.maxConcurrent` 不在 schema 中（只有 agents.defaults 级别有）

### ACP
- ACP dispatch = core，ACP backend = acpx plugin（仍需要 `plugins.allow` 包含 `"acpx"`）
- acpx 默认 strip `ANTHROPIC_API_KEY`（`stripProviderAuthEnvVars=true` when command == bundled binary）
- 绕过：`acpx-wrapper.sh` 作为 custom command → `stripProviderAuthEnvVars=false`
- `queueOwnerTtlSeconds` 默认 0.1s（100ms），必须 override 到 300
- `acp.runtime` schema 只接受 `ttlMinutes` + `installCommand`

### Docker
- `scope: "shared"` 时 per-agent docker 配置被忽略（源码 `void 0`），image 必须在 `agents.defaults.sandbox.docker` 设
- 切换 image 后必须 `sudo docker rm -f openclaw-sbx-shared`，否则旧容器继续跑
- `knowledge/` 是 read-only bind mount，`chown -R` 会失败

### Tool Profiles（源码确认 tool-catalog-BjSY4C4F.js）
- **minimal**: 只有 `session_status`（1 个工具！不要给任何需要工作的 agent 用）
- **coding**: 包含 read/write/edit/exec/web_search/sessions_*/memory_*/image 等
- **full**: 无限制

### Session 生命周期（源码确认 pi-embedded）
- `mode: "run"` = one-shot，完成一轮就 archive
- `mode: "session"` = persistent，但 **必须 `thread: true`**，且需要 channel plugin 支持 `subagent_spawning` hook
- `sessions_send` 工具可以向已有 session 发后续消息
- 主 agent 系统提示说 "wait for auto-announced completions"——但**没有说收到后要继续 spawn 下一阶段**

---

## 未完成任务（按优先级排列）

### P0：sessions.visibility 配置修复

**问题**：auditor 有 `agentToAgent: {enabled: true, allow: ["main", "auditor"]}`，但实际调用 `sessions_history` 时报 "Session send visibility is restricted. Set tools.sessions.visibility=all"。

**诊断方向**：
1. 查源码 `pi-embedded-CbCYZxIb.js` 中 `resolveEffectiveSessionToolsVisibility` 函数
2. 查 config schema `io-y3Az_Onx.js` 中 `sessions` 或 `visibility` 相关字段
3. 确定需要在 `/etc/openclaw/openclaw.json` 中添加什么配置
4. 生成 escalation-compliant 的配置补丁

**注意**：不要猜测配置键名。从源码中找到确切的 schema 定义。

### P0：替换 MotChat 中转站 + API key 管理

**背景**：operator 决定全面弃用 motchat 中转站（`https://new.motchat.com`），需要新的 API endpoint 和 key。

**涉及位置**（必须全部更新）：
- `/etc/openclaw/openclaw.env` — `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_API_KEY`
- `/var/lib/openclaw/.openclaw/acpx-wrapper.sh` — ACP 环境变量
- `agents.list` 中所有 agent 的 `model.primary` 字段（如 `motchat-claude-4-6/claude-opus-4-6` 等 provider prefix）
- `/etc/openclaw/openclaw.json` 的 `models` 配置块

**设计要求**：
- 找到一种方式让后续切换 API endpoint / key / model 更方便（集中管理点）
- **不要击穿现有的权限和安全设计**——所有变更走 escalation rule
- 参考 `docs/design-v3.md` 和 `docs/host-sop.md` 中关于 models 配置的部分
- 查 OpenClaw 源码中 `models` schema 的确切定义
- 产出：配置候选 + apply 脚本 + 回滚方案

### P0：main agent 模型切换

**问题**：main agent 使用 `deepseek-chat`，无法可靠执行多阶段编排、正确解读 workspace skill 文档。
**方向**：切换到 claude-opus 级别模型。需要先完成 MotChat 中转站替换。

### P1：多阶段编排可靠性

**问题本质**：`mode: "run"` 是 one-shot 设计。main 收到子 agent 完成事件后直接向用户汇报，不继续 spawn 后续阶段。

**已尝试的修复**（效果不足）：
- `workspace-main-template/skills/task-delegation/SKILL.md` 添加了多阶段编排规则
- `workspace-main-template/control/routing-policy.md` 添加了 "CRITICAL RULE" 不要提前汇报
- **结果**：deepseek-chat 仍然不执行这些规则

**需要进一步探索**：
1. `mode: "session"` + `thread: true` 是否可以在 Feishu channel 上工作？查 feishu plugin 是否实现了 `subagent_spawning` hook
2. `sessions_send` 是否可以在 main 端做循环（收到完成事件 → 用 sessions_send 发后续指令 → 等待下一个完成事件）
3. 是否有 OpenClaw 内置的 "workflow" 或 "pipeline" 机制
4. 换到更强的 main 模型后，文档指导是否能被正确执行

### P1：容器隔离方案设计

**Operator 的设想**：
- **一次性容器**：单次任务，拿了结果就走（适合简单工程任务）
- **中期容器**：长期任务的工作环境，持续数天（适合研究项目）
- **固化长期容器**：大型项目的完整工作目录，销毁需 operator 批准

**设计要求**：
- 不同大任务使用独立容器（隔离输出目录）
- 同一大任务下的 agent 共享容器（coordinator + task-runner 共享文件）
- Per-task 目录结构（`/workspace/outputs/<task-id>/` 而不是扁平的 `/workspace/outputs/`）
- 查 OpenClaw 的 `sandbox.scope` 是否支持 per-task scope，或者需要用 per-agent scope 模拟

**当前约束**：
- `scope: "shared"` = 所有 session 共享一个容器（当前部署）
- `scope: "session"` = 每个 session 一个容器（太短暂，session 结束就销毁）
- `scope: "agent"` = 每个 agent 一个容器（可能是中间方案）
- 查 schema 确认是否还有其他 scope 选项

### P2：前端 GUI 独立工程

**Operator 需求**：
1. Agent 拓扑可视化——清晰的名字（不要 UUID）、运行状态、关系图
2. Session 内容实时查看——点击看完整对话，包括 agent 间消息流向
3. 文件浏览器——容器内 + 宿主机 workspace 的文件，可直接查看/下载
4. 监控仪表盘——token 用量、耗时、错误率
5. Gateway 管理层面的功能可以不做（使用内置 dashboard）

**技术方向**：
- 独立 web 应用（React/Vue + OpenClaw gateway WebSocket API 17777）
- 部署在同一台宿主机
- 需要调研 OpenClaw gateway 的 API 能力——有哪些可用的 endpoint/method
- 查 `docs/design-v3.md` 中是否有前端规划
- 产出：需求规格 + 技术选型 + 原型设计

### P3：auditor agent 优化

**问题**：
- auditor 不知道 session 内容（sessions.visibility 问题，P0 修复后重验证）
- auditor 的 `profile: "coding" + deny` 已修复，但实际效果未验证
- auditor 输出应有标准化格式（见 `workspace-auditor-template/skills/quality-audit/SKILL.md`）
- auditor 应该能读取容器内文件（通过 `read` 工具 + shared scope）

### P4：Vault sync + 日志轮转

---

## 关键文件位置

| 用途 | 路径 |
|------|------|
| 实时状态 | `docs/current-boundary.md` |
| 架构设计 | `docs/design-v3.md` |
| 文档地图 | `docs/map.md` |
| Host SOP | `docs/host-sop.md` |
| ACP 分析 | `docs/planning/acp-policy-fix-analysis.md` |
| Agent 扩展候选 | `candidates/openclaw.agents-expansion.candidate.json5` |
| Agent apply 脚本 | `scripts/apply-agents-expansion.py` |
| ACP wrapper | `scripts/acpx-wrapper.sh` |
| workspace-main 模板 | `workspace-main-template/` |
| workspace-task-runner 模板 | `workspace-task-runner-template/` |
| workspace-research-coordinator 模板 | `workspace-research-coordinator-template/` |
| workspace-auditor 模板 | `workspace-auditor-template/` |
| Docker GPU 镜像 | `task-runner-container/Dockerfile.gpu` |
| Live 配置（只读参考） | `/etc/openclaw/openclaw.json` |
| OpenClaw 源码 | `/opt/openclaw/node_modules/openclaw/dist/` |

## 源码关键位置（调试必看）

| 功能 | 文件 | 行号/函数 |
|------|------|-----------|
| Tool profiles 定义 | `dist/tool-catalog-BjSY4C4F.js:48-263` | `CORE_TOOL_DEFINITIONS` |
| agentToAgent policy | `dist/pi-embedded-CbCYZxIb.js:80980-81004` | `createAgentToAgentPolicy` |
| Session visibility | `dist/pi-embedded-CbCYZxIb.js` | `resolveEffectiveSessionToolsVisibility` (需定位) |
| Spawn mode 解析 | `dist/pi-embedded-CbCYZxIb.js:114997` | `resolveSpawnMode` |
| sessions_spawn 实现 | `dist/pi-embedded-CbCYZxIb.js:115040` | `spawnSubagentDirect` |
| sessions_send 实现 | `dist/pi-embedded-CbCYZxIb.js:113618` | `sessions_send` tool |
| ACP spawn | `dist/pi-embedded-CbCYZxIb.js:114131` | `spawnAcpDirect` |
| ACP env stripping | `dist/extensions/acpx/index.js:300,426` | `stripProviderAuthEnvVars` |
| Config schema | `dist/io-y3Az_Onx.js:5689-5715` | ACP + top-level schemas |
| Agent schema | `dist/zod-schema.agent-runtime-Dtg4Jy6G.js:502-551` | `AgentEntrySchema` |
| Docker scope 处理 | `dist/docker-Bhjg8g2t.js:343` | `resolveSandboxDockerConfig` |

## 纪律提醒

- `docs/current-boundary.md` 是唯一实时状态文件——改了系统就更新它
- Planning docs 有 close-by 日期，过期的归档到 `docs/archive/`
- 不要只同步状态不做实施（anti-stall rule 4）
- 涉及 `/etc/openclaw/openclaw.json` 变更走 escalation rule
- **不允许猜测系统行为**——从源码、文档、日志中找证据
- **workspace 模板更新后必须提醒 operator 手动 publish 到 live workspace**
