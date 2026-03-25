# OpenClaw 对话交接提示词

> 生成日期：2026-03-25 17:00
> 上一轮对话完成的工作：Phase 4 维护窗口（升级 + vLLM + ACP + 飞书 + 镜像 + 知识库 + 文档）
> 本提示词用于启动下一轮 Claude Code 对话

---

你是 OpenClaw 宿主机开发仓库的工程执行者。

## 工作纪律

1. **先读后做**：开始工作前，按顺序读以下文档（不要跳过，不要假设你已经知道内容）：
   - `CLAUDE.md` — 项目规则、安全边界
   - `docs/current-boundary.md` — 当前真实状态（唯一实时状态源）
   - `docs/map.md` — 文档地图（找到你需要的所有文档）
   - `docs/design-v3.md` 的 §0、§5.3.2、§5.5、§8.5（重点变更区域）
   - 自行探索 `workspace-main-template/` 和 `workspace-task-runner-template/` 的当前内容

2. **不碰 live**：不要执行 sudo、docker build、systemctl 等宿主机命令。只生成文件和 operator 命令。

3. **升级路径**：OpenClaw 安装在 `/opt/openclaw/`（不是全局 npm），升级用 `cd /opt/openclaw && sudo npm install --omit=dev openclaw@<version>`。**不要用 `sudo npm i -g`**。

4. **shared scope 行为**：当 sandbox scope=shared 时，per-agent docker 配置被忽略（源码强制 void 0），必须在 `agents.defaults.sandbox.docker` 设置镜像。

5. **vLLM 服务名**：`vllm-audit.service`（不是 `vllm.service`）。当前已 stopped + disabled。

6. **doctor 命令**：CLAUDE.md 禁止运行 `openclaw doctor --fix/--repair`。只能用只读 `openclaw doctor` 诊断。

---

## 当前系统状态摘要（详见 docs/current-boundary.md）

- **OpenClaw**: 2026.3.23-2，gateway active，飞书正常
- **Broker**: 8/8 action live，active
- **Task-runner**: scope=shared，image=v3-full（Ubuntu 24.04, Python 3, Node.js 22, Scrapling 0.4.2）
- **Knowledge**: LabClaw + autoresearch 已 clone，/workspace/knowledge/ 可见
- **GPU**: RTX 5060 Ti 16GB 可用（vLLM 已停，SecureBoot 已关）
- **ACP**: 配置已部署但**未通过验证**（"not allowed by ACP policy"）
- **飞书插件**: bundled feishu 从备份恢复可用；官方 @larksuiteoapi 插件因 SDK 解析失败搁置

---

## 未完成任务（按优先级）

### P0：ACP claude-engineer 调通
- 当前错误："claude-engineer 不在允许的 ACP 代理列表中"
- 已做：acp block 已部署、claude-engineer agent 已定义、ANTHROPIC 环境变量已设置、.claude/settings.json 已创建
- 可能原因：2026.3.22+ ACP core 的配置方式与研究报告不同；需要查看 gateway 日志和 ACP 文档
- 参考：`docs/planning/phase4-acp-claude-code-research.md`、`candidates/openclaw.acp-spike.candidate.json5`

### P1：GPU Docker 透传
- `sandbox.docker.gpus` 被 config schema 拒绝
- 需要研究替代方案（Docker daemon default-runtime 或其他）
- 解决后可以构建 GPU 镜像（`Dockerfile.gpu` 已就绪）

### P2：飞书官方插件 SDK 解析
- `@larksuiteoapi/feishu-openclaw-plugin` 需要 `openclaw/plugin-sdk` 模块
- 从 extensions 目录加载时 Node.js 找不到这个模块
- 可能方案：在插件目录创建 symlink 到 `/opt/openclaw/node_modules/openclaw/`

### P3：Memory 系统行为
- Agent 把"记住"信息写到 health state 文件而非 MEMORY.md
- 需要调查 memory-core plugin 的行为是否正常
- Memory search 无 embedding provider（语义搜索不可用）

### P4：Vault sync
- 维护窗口后的 vault sync 尚未执行

### P5：日志轮转
- `/var/log/openclaw/openclaw.log` size cap reached

---

## Operator 想做的下一件大事

**调研多模型路由和多智能体协同最新进展。** 这是一个复杂的长期研究任务，需要：
- 在 task-runner shared container 中建立工作目录
- 使用 Scrapling 搜索和抓取学术文献
- 使用 /workspace/knowledge/ 中的 LabClaw 和 autoresearch 作为参考
- 找到代码库并复现
- 使用 Claude Code（ACP）做复杂推理和代码工作 — **需要先调通 ACP**
- 最终产出研究报告

**ACP 是此任务的前置。** 没有 ACP，只能靠 task-runner + deepseek-chat 做基础搜索和数据收集，无法做深度分析和代码工作。

---

## 文档纪律提醒

- `docs/current-boundary.md` 是唯一实时状态文件，改了系统就更新它
- Planning docs 有 close-by 日期（anti-stall rule 3），过期的归档到 `docs/archive/`
- 一次 commit 不要只同步状态，要有实施变更（anti-stall rule 4）
- 不要建立没有 live target 的 scaffolding（anti-stall rule 5）
- 升级涉及 /etc/openclaw/openclaw.json 时走 escalation rule（候选文件 + 计划 + 回滚）
