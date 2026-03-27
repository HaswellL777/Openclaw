# OpenClaw 对话交接提示词

> 生成日期：2026-03-27
> 上一轮：Phase 4 完成（ACP + GPU + Agent 扩展），暴露多阶段编排结构性问题
> 模型：Claude Opus 4.6 (1M context)

---

## 第一部分：工作纪律（长期规则，每轮都适用）

1. **先读后做**：`CLAUDE.md` → `docs/current-boundary.md` → `docs/map.md` → `docs/design-v3.md` §0/§5.3.2/§8.5 → 自行探索 workspace 模板、candidates、scripts。**这不是完整列表**——你必须根据任务需要主动搜索仓库中的其他文档（`docs/planning/`、`docs/host-sop.md`、`docs/specs/`、git log）和 OpenClaw 官方源码。遇到不确定的行为，先 grep 源码再动手。
2. **产出 > 分析**：纯文字分析不算完成。每个任务必须有可落盘的产物（文件、脚本、配置候选）。
3. **不猜测**：不确定的系统行为，从源码 `/opt/openclaw/node_modules/openclaw/dist/`、仓库文档、git log 中找证据。找不到就标注 `[UNVERIFIED]` 并说明需要 operator 验证什么。
4. **config 变更走 escalation**：pre-snapshot → backup（确定性文件名）→ apply 脚本 → verify → rollback plan。禁止 `sudo nano` 直接编辑。产出结构化 apply 脚本和 operator 命令块。
5. **workspace 更新后提醒 publish**：task-runner/research-coordinator/auditor 无 publish 脚本，必须在 commit message 或输出中包含 rsync + 精确 chown 命令。`knowledge/` 是 ro mount，`chown -R` 会失败。
6. **优化 operator 设想**：operator 方案是方向，不是最终设计。基于源码/文档事实提出更优解，但不发散——所有优化必须直接服务于当前任务。格式："方案 X → 源码显示 Y → 建议 Z，因为..."
7. **慎用 subagent**：最多 2-3 个并行，用 Opus 4.6 (1M)，确保质量。

---

## 第二部分：本轮任务（严格按顺序执行）

### 阶段 A：sessions.visibility 修复（阻塞后续所有 agent 交互验证）

**目标**：让 auditor 能通过 `sessions_history` 读取其他 agent 的会话内容。

**当前状态**：
- `tools.agentToAgent: {enabled: true, allow: ["main", "auditor"]}` 已部署
- 但 auditor 调用 `sessions_history` 时报 "Session send visibility is restricted. Set tools.sessions.visibility=all"

**执行步骤**：
1. 在源码中定位 `resolveEffectiveSessionToolsVisibility` 函数（`pi-embedded-CbCYZxIb.js`，grep 关键字）
2. 在 config schema 中找 `sessions.visibility` 或等效字段（`io-y3Az_Onx.js`）
3. 确定需要在 openclaw.json 中添加的确切配置
4. 产出：配置候选文件 + apply 脚本 + operator 命令块

**完成标准**：
- [ ] 候选配置文件已写入 `candidates/`
- [ ] apply 脚本已写入 `scripts/`
- [ ] operator 命令块已输出（snapshot → backup → apply → restart → verify）
- [ ] 文档中标注了确切的 schema 来源（文件:行号）

**卡住协议**：如果源码中找不到 `sessions.visibility` 的 schema 定义，输出你搜索过的所有文件和关键词，标注 `[BLOCKED: schema not found]`，建议 operator 在 OpenClaw 官方文档或 GitHub issues 中搜索，或检查更高版本是否支持该功能。不要运行 `openclaw doctor` 或任何 openclaw CLI 诊断命令（`CLAUDE.md` 安全边界禁止在 nick 用户下运行）。

---

### 阶段 B：API endpoint 和 key 管理重构（阻塞模型切换）

**目标**：替换 MotChat 中转站，建立可维护的 API endpoint/key/model 管理方案。

**当前状态**：
- MotChat: `ANTHROPIC_BASE_URL=https://new.motchat.com`, `ANTHROPIC_API_KEY=sk-iqC...`
- 分散在：`/etc/openclaw/openclaw.env`、`acpx-wrapper.sh`、openclaw.json `models` 块、agent `model.primary` 字段

**执行步骤**：
1. 查 openclaw.json 中 `models` 配置块的 schema（`io-y3Az_Onx.js` 中 `ModelsConfigSchema`）
2. 查 agent `model.primary` 的 provider prefix 如何解析（`model-selection-BnFtDmP7.js` 或相关文件）
3. 理清所有需要修改的位置（列清单，不要遗漏）
4. 设计集中管理方案：理想情况下一处改 endpoint/key，所有 agent 和 ACP 自动生效
5. 产出：
   - 管理方案设计文档（放 `docs/planning/`，含 close-by）
   - 配置候选（`candidates/openclaw.api-migration.candidate.json5`）
   - apply 脚本
   - `acpx-wrapper.sh` 的更新版
   - operator 命令块

**完成标准**：
- [ ] 所有涉及 API endpoint/key 的位置已列出（文件:行号）
- [ ] 集中管理方案已设计（说明 operator 未来改 key 只需改一处）
- [ ] 配置候选 + apply 脚本已产出
- [ ] acpx-wrapper.sh 已更新（endpoint 改为从 openclaw.env 继承或新地址）
- [ ] operator 命令块包含新 endpoint 和 key 的占位符（operator 填入实际值）

**卡住协议**：如果 models schema 不支持集中的 provider 定义，输出 schema 的实际结构，提出"最近似集中管理"的方案（可能是 env 文件 + wrapper 脚本的组合）。

**Operator 需提供**：新的 API base URL 和 API key。在 apply 脚本中用 `${NEW_ANTHROPIC_BASE_URL}` 和 `${NEW_ANTHROPIC_API_KEY}` 占位。

---

### 阶段 C：main agent 模型切换（依赖阶段 B）

**目标**：将 main agent 从 deepseek-chat 切换到 claude-opus 级模型。

**执行步骤**：
1. 基于阶段 B 的 models 理解，确定 main agent 的 `model.primary` 新值
2. 同时评估 research-coordinator 是否也需要换模型（当前也是 deepseek-chat，orchestration 不可靠）
3. 产出：更新到阶段 B 的 apply 脚本中（合并为一次部署）

**完成标准**：
- [ ] main agent model.primary 新值已确定（基于 schema 事实，不是猜测）
- [ ] research-coordinator 模型建议已给出（附理由）
- [ ] 合并到阶段 B 的候选配置中

---

### 阶段 D：容器隔离方案设计（repo-side only，不部署）

**目标**：设计 per-task 目录结构 + 容器生命周期管理方案。

**Operator 设想**（允许优化，但保留核心意图）：
- 不同大任务用独立容器，同一任务下的 agent 共享容器
- 三档生命周期：一次性（单次任务）、中期（数天研究项目）、固化（大型项目，销毁需批准）
- Per-task 目录：`/workspace/outputs/<task-id>/` 而不是扁平的 `/workspace/outputs/`

**执行步骤**：
1. 查 OpenClaw `sandbox.scope` 完整选项（schema + 源码 `docker-Bhjg8g2t.js`）
2. 查是否支持 per-task 或 per-label 的容器命名
3. 评估 operator 的三档方案在 OpenClaw 中是否可实现，如果不能，提出最近似替代
4. 设计目录结构规范（task-runner 和 coordinator 的 workspace skill 中强制执行）
5. 产出：设计文档（`docs/planning/container-isolation-design.md`，含 close-by、3 个方案 + 推荐）

**完成标准**：
- [ ] `sandbox.scope` 完整选项已列出（源码证据）
- [ ] 设计文档已产出，含方案对比和推荐
- [ ] 目录结构规范已写入 workspace skill 或 policy 文档

**卡住协议**：如果 OpenClaw 的 scope 选项无法满足三档需求，明确说明限制，提出基于现有 scope 的 workaround（如用 agent ID 模拟 task 隔离）。

---

### 阶段 E：前端 GUI 需求规格（设计阶段，不实现）

**目标**：产出前端 GUI 的需求规格和技术选型文档，作为独立工程的启动输入。

**Operator 核心需求**：
1. Agent 拓扑可视化——人类友好名字、运行状态、父子关系图
2. Session 内容查看——点击进入完整对话，看到 agent 间消息内容和流向
3. 文件浏览器——容器内 + 宿主机 workspace，可查看/下载
4. 监控仪表盘——token 用量、耗时、错误率
5. Gateway 管理用内置 dashboard（17777 端口），不重复

**执行步骤**：
1. 调研 OpenClaw gateway 的 WebSocket/HTTP API（查源码 `gateway-cli-Dsd9gHBa.js` 或相关文件，找可用 method）
2. 评估内置 dashboard 已有的功能（避免重复造轮子）
3. 设计前端架构（技术选型、部署方式、与 gateway API 的交互）
4. 产出：`docs/planning/frontend-gui-design.md`（含 close-by、需求规格、技术选型、API 依赖清单、原型线框图描述）

**完成标准**：
- [ ] Gateway API 可用 method 已列出（从源码，不是猜测）
- [ ] 设计文档已产出，含需求规格 + 技术选型 + 部署方案
- [ ] 明确了哪些功能 gateway API 已支持、哪些需要额外开发

**卡住协议**：如果 gateway API 不够（例如没有 session transcript 的 API），标注 `[API GAP]`，提出替代方案（如直接读 session store 文件）。

---

## 第三部分：技术参考（按需查阅，不用通读）

### 关键陷阱速查

| 陷阱 | 说明 |
|------|------|
| config schema `.strict()` | 未知字段导致 gateway crash loop（已发生过：`subagents.maxConcurrent` at agent level） |
| `scope: "shared"` 忽略 per-agent docker | image 必须在 `agents.defaults.sandbox.docker` 设 |
| 切换 image 后旧容器继续跑 | 必须 `docker rm -f openclaw-sbx-shared` |
| `minimal` profile 只有 1 个工具 | 不要给需要工作的 agent 用 |
| acpx 默认 strip API key | 用 wrapper 脚本绕过 |
| `queueOwnerTtlSeconds` 默认 0.1s | 必须 override 到 300+ |
| `mode: "run"` 是 one-shot | 完成一轮就 archive，不会自动继续 |

### 源码关键位置

| 功能 | 文件 | 位置 |
|------|------|------|
| Tool profiles | `dist/tool-catalog-BjSY4C4F.js:48-263` | `CORE_TOOL_DEFINITIONS` |
| agentToAgent policy | `dist/pi-embedded-CbCYZxIb.js:80980` | `createAgentToAgentPolicy` |
| Session visibility | `dist/pi-embedded-CbCYZxIb.js` | grep `resolveEffectiveSessionToolsVisibility` |
| Spawn mode | `dist/pi-embedded-CbCYZxIb.js:114997` | `resolveSpawnMode` |
| sessions_spawn | `dist/pi-embedded-CbCYZxIb.js:115040` | `spawnSubagentDirect` |
| sessions_send | `dist/pi-embedded-CbCYZxIb.js:113618` | tool execute |
| ACP env strip | `dist/extensions/acpx/index.js:300,426` | `stripProviderAuthEnvVars` |
| Config schema | `dist/io-y3Az_Onx.js:5689-5715` | top-level schemas |
| Agent schema | `dist/zod-schema.agent-runtime-Dtg4Jy6G.js:502-551` | `AgentEntrySchema` |
| Docker scope | `dist/docker-Bhjg8g2t.js:343` | `resolveSandboxDockerConfig` |
| Models schema | `dist/io-y3Az_Onx.js` | grep `ModelsConfigSchema` |

### 文件位置速查

| 用途 | 路径 |
|------|------|
| 实时状态 | `docs/current-boundary.md` |
| 架构设计 | `docs/design-v3.md` |
| 文档地图 | `docs/map.md` |
| Agent 扩展候选 | `candidates/openclaw.agents-expansion.candidate.json5` |
| Apply 脚本 | `scripts/apply-agents-expansion.py` |
| ACP wrapper | `scripts/acpx-wrapper.sh` |
| Live 配置 | `/etc/openclaw/openclaw.json`（只读参考） |
| OpenClaw 源码 | `/opt/openclaw/node_modules/openclaw/dist/` |
