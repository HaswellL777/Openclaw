# OpenClaw 文档地图

> 更新日期：2026-04-02

---

## 使用者指南 `[guide]`

| 文件 | 描述 |
|------|------|
| `docs/guide/README.md` | 系统能力概览——从这里开始 |
| `docs/guide/agents.md` | Agent 编排指南——可用 agent、协作模式、模型选择 |
| `docs/guide/skills.md` | Skill 开发指南——创建、验证、发布 skill |
| `docs/guide/task-delegation.md` | 任务编排指南——多步任务、状态传递、宿主机变更流程 |

## 实时状态 `[status]`

| 文件 | 描述 |
|------|------|
| `docs/current-boundary.md` | 当前真实边界——唯一实时状态文件 |

## Workspace 模板 `[workspace]`

| 目录 | 描述 |
|------|------|
| `workspace-main-template/` | main agent workspace（6 skills + control/） |
| `workspace-task-runner-template/` | task-runner workspace（12 skills + schemas/ + outputs/ + project-template/） |
| `workspace-research-coordinator-template/` | research-coordinator workspace |
| `workspace-auditor-template/` | auditor workspace |
| `task-project-template/` | ACP Claude Code 容器内项目模板（源文件） |

## GUI 前端 `[gui]`

| 目录/文件 | 描述 |
|-----------|------|
| `gui/` | React + TypeScript + Vite 管理前端（16 页面） |
| `gui/vite.config.ts` | Auth middleware + Docker API + runs API + WebSocket proxy |
| `gui/src/pages/` | 页面组件 |
| `gui/src/components/MessageRenderer.tsx` | 消息渲染器（多格式 tool call 支持） |

## 插件 `[plugin]`

| 目录 | 描述 |
|------|------|
| `plugins/gateway-rpc-tool/` | Gateway RPC 插件（14 methods） |

## 运维脚本 `[ops]`

| 文件 | 描述 |
|------|------|
| `scripts/publish-workspace-all.sh` | 统一 workspace 发布 |
| `scripts/backup-openclaw.sh` | 全量备份（snapshot + config） |
| `scripts/restore-openclaw.sh` | 恢复/回滚 |
| `scripts/validate-openclaw.sh` | 端到端验证 |
| `scripts/install-permissions-fix.sh` | 权限持久化安装 |
| `scripts/check-workspace-skills.sh` | Skill frontmatter 验证 |
| `scripts/hotfix-*.sh` | Live hotfix 脚本（3 个） |

## 交接文档 `[handoff]`

| 文件 | 描述 |
|------|------|
| `.claude/handoff/handoff-2026-04-02-infra-complete.md` | 基础设施完成 + 三阶段投资验证路线图 |
| `.claude/handoff/handoff-2026-04-01-phase6-hotfixes.md` | Phase 6 + hotfixes + 文档同步 |
| `.claude/handoff/handoff-2026-03-31-phase5j.md` | Phase 5J — GUI auth + 部署自动化 |

---

## 基础设施参考 `[internal]` — 开发者向

> 以下文档为基础设施开发期间的参考文档，日常使用中一般不需要阅读。

| 文件 | 描述 |
|------|------|
| `CLAUDE.md` | AI 协作规则、安全边界 |
| `docs/internal/design-v3.md` | 架构设计规格 v3.1 |
| `docs/internal/host-sop.md` | 宿主机状态记录（运行态事实权威源） |
| `docs/internal/when-to-snapshot.md` | 快照时机指南 |
| `docs/internal/acceptance-tests.md` | 验收测试 |
| `docs/internal/specs/` | 冻结协议规格（broker protocol, error taxonomy, contract matrix） |
| `docs/internal/records/` | 历史记录 |
| `docs/internal/adr/` | 架构决策记录 |
| `docs/archive/` | 已归档的规划和记录 |
