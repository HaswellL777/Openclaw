# OpenClaw 对话交接提示词

> 生成日期：2026-03-25 17:30
> 上一轮对话完成的工作：Phase 4 维护窗口（升级 + vLLM + ACP + 飞书 + 镜像 + 知识库 + 文档）

---

你是 OpenClaw 宿主机开发仓库的工程执行者。你拥有 1M 上下文窗口。

## 工作纪律

1. **先读后做**：开始工作前，必须读以下文档，不要跳过，读完再动手：
   - `CLAUDE.md` — 项目规则、安全边界、anti-stall 规则
   - `docs/current-boundary.md` — 当前系统真实状态（**唯一实时状态源**）
   - `docs/map.md` — 文档地图
   - `docs/design-v3.md` §0 结论先行、§5.3.2（ACP 修正）、§5.5（gate ABANDONED）、§8.5（Phase 4 TODO）
   - 然后**自行探索** workspace 模板、candidates、planning 等目录，建立完整理解

2. **不碰 live**：不执行 sudo、docker build、systemctl。只生成文件和 operator 命令。

3. **关键陷阱（上一轮踩过的坑）**：
   - **升级路径**：OpenClaw 在 `/opt/openclaw/`，升级用 `cd /opt/openclaw && sudo npm install --omit=dev openclaw@<version>`。**禁止 `sudo npm i -g`**（装到错误位置）
   - **shared scope**：`scope=shared` 时 per-agent docker 配置被忽略（源码 `void 0`），镜像必须在 `agents.defaults.sandbox.docker` 设置
   - **vLLM 服务名**：`vllm-audit.service`（不是 `vllm.service`）
   - **doctor 命令**：CLAUDE.md 禁止 `openclaw doctor --fix/--repair`，只能只读诊断
   - **飞书插件**：官方 `@larksuiteoapi/feishu-openclaw-plugin` 因 SDK 解析失败，当前用 bundled feishu（从备份恢复）

---

## 当前系统状态（详见 docs/current-boundary.md）

- **OpenClaw**: 2026.3.23-2（从 2026.3.13 升级，2026-03-25）
- **Gateway**: active，port 17777，飞书 WebSocket 正常
- **Broker**: active，8/8 action verified
- **Task-runner**: scope=shared，image=`openclaw-task-claude:2026-03-v3-full`
  - Ubuntu 24.04, Python 3.12, Node.js 22, Scrapling 0.4.2, git, rg, jq, curl, pip, npm
  - Knowledge repos：`/workspace/knowledge/LabClaw/` + `/workspace/knowledge/autoresearch/`（read-only mount）
  - Skills：coding, testing, research, report, scrapling, autoresearch
- **GPU**: RTX 5060 Ti 16GB 可用（vLLM stopped + disabled，SecureBoot disabled）
- **ACP**: **配置已部署但未通过验证**（"not allowed by ACP policy"）

---

## 未完成任务（按优先级）

### P0：ACP claude-engineer 调通
这是 operator 下一个大任务的**前置**。

- 当前错误："claude-engineer 不在允许的 ACP 代理列表中"
- 已做：acp block 部署、claude-engineer agent 定义、ANTHROPIC env 设置、.claude/settings.json 创建、allowed-workers.md 已更新
- 需要调查：2026.3.22+ ACP core 的正确配置方式。查 gateway 日志 `grep -i acp`。参考 `docs/planning/phase4-acp-claude-code-research.md`
- 注意：config schema 拒绝了 `acp.runtime.permissionMode`（已移除），approve-all 可能需要通过其他方式配置

### P1：GPU Docker 透传
- `sandbox.docker.gpus` 被 schema 拒绝。需要替代方案。
- `Dockerfile.gpu` 已就绪（`task-runner-container/Dockerfile.gpu`）

### P2：飞书官方插件
- `@larksuiteoapi/feishu-openclaw-plugin` 的 `openclaw/plugin-sdk` 解析失败
- 可能需要 symlink 或不同安装方式

### P3：Memory 系统
- Agent 把信息写到 health state 而非 MEMORY.md
- 需要调查 memory-core plugin 行为

### P4：Vault sync + 日志轮转

---

## Operator 的下一个大任务

**调研多模型路由和多智能体协同最新进展。** 这是复杂的长期研究任务：

- 在 task-runner shared container 中建立工作目录
- 用 Scrapling 搜索抓取学术文献
- 用 /workspace/knowledge/ 中的 LabClaw 和 autoresearch 作为参考
- 找代码库并复现
- 用 Claude Code（ACP）做复杂推理和代码工作 — **需要 ACP 先调通**
- 产出研究报告

**没有 ACP 时**：task-runner + deepseek-chat 可以做基础搜索、数据收集、初步分析。不能做深度代码工作。

---

## 关键文件位置

| 用途 | 路径 |
|------|------|
| 实时状态 | `docs/current-boundary.md` |
| 架构设计 | `docs/design-v3.md` |
| 文档地图 | `docs/map.md` |
| ACP 研究报告 | `docs/planning/phase4-acp-claude-code-research.md` |
| ACP 候选配置 | `candidates/openclaw.acp-spike.candidate.json5` |
| 升级评估 | `docs/planning/openclaw-upgrade-3.23-evaluation.md` |
| 维护窗口执行包 | `docs/execution-packs/execution-pack-phase4-maintenance.md` |
| LabClaw 集成方案 | `docs/planning/labclaw-autoresearch-integration.md` |
| workspace-main 模板 | `workspace-main-template/` |
| workspace-task-runner 模板 | `workspace-task-runner-template/` |
| live 配置（只读参考） | `candidates/openclaw.live.json`（旧快照，当前 live 已变） |

## 纪律提醒

- `docs/current-boundary.md` 是唯一实时状态文件——改了系统就更新它
- Planning docs 有 close-by 日期，过期的归档到 `docs/archive/`
- 不要只同步状态不做实施（anti-stall rule 4）
- 不要建没有 live target 的 scaffolding（anti-stall rule 5）
- 涉及 `/etc/openclaw/openclaw.json` 变更走 escalation rule
