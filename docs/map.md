# OpenClaw Dev Repo 文档地图

> 更新日期：2026-03-31

---

## 权威文档 `[authority]`

| 文件 | 描述 |
|------|------|
| `docs/host-sop.md` | 宿主机状态记录——运行态事实的权威源 |
| `docs/design-v3.md` | 架构设计规格 v3.1——实施目标与规格的权威源 |
| `CLAUDE.md` | AI 协作规则、安全边界与 anti-stall 规则 |
| `docs/current-boundary.md` | 当前真实边界——唯一实时状态文件 |

## 导航

| 文件 | 描述 |
|------|------|
| `docs/map.md` | 本文件——文档总地图 |
| `docs/planning/README.md` | planning 目录索引 |
| `docs/records/README.md` | records 目录索引 |

## 活跃规划 `[active]`

| 文件 | 描述 |
|------|------|
| `docs/planning/container-isolation-design.md` | 容器隔离方案设计（close-by: 2026-04-01）— 推荐方案 A |
| `docs/planning/frontend-gui-design.md` | 前端 GUI 需求规格 v2（close-by: 2026-04-05）— P0/P1 全部已实现 |

## GUI 前端 `[active]`

| 目录/文件 | 描述 |
|-----------|------|
| `gui/` | React + TypeScript + Vite 管理前端（16 页面） |
| `gui/vite.config.ts` | Auth middleware + Docker API + runs API + WebSocket proxy |
| `gui/src/api/rpc-client.ts` | Gateway WebSocket 协议客户端 |
| `gui/src/api/hooks.ts` | Zustand store + React Query hooks |
| `gui/src/api/types.ts` | TypeScript 类型（含 RunRecord, TaskGroup, CronJob） |
| `gui/src/api/agent-colors.ts` | 共享 agent 颜色配置 |
| `gui/src/pages/` | 页面组件（16 个） |
| `gui/src/components/TaskDetailView.tsx` | Task 内部 swimlane 消息流程图 |
| `gui/src/components/MessageRenderer.tsx` | 消息渲染器（语法高亮 + tool call + provenance） |
| `gui/src/components/shared.tsx` | 共享 UI 组件 |

## 部署脚本 `[active]`

| 文件 | 描述 |
|------|------|
| `scripts/publish-workspace-main.sh` | main workspace publish 脚本 |
| `scripts/publish-workspace-all.sh` | 统一 4 workspace 发布脚本 |
| `scripts/deploy-phase5j.sh` | Phase 5J 全量部署（snapshot + workspace + plugin + config + restart） |
| `scripts/deploy-phase5j-remaining.sh` | Phase 5J 增量部署（main workspace + plugin + config） |
| `scripts/setup-gui-auth.sh` | GUI auth token 生成 |
| `scripts/check-workspace-skills.sh` | 验证 SKILL.md YAML frontmatter |
| `scripts/openclaw-gui.service` | GUI systemd unit 文件 |
| `scripts/apply-api-migration.py` | API 迁移 apply 脚本（Phase 5B） |
| `scripts/apply-sessions-visibility.py` | sessions.visibility apply 脚本（Phase 5A） |
| `scripts/apply-agents-expansion.py` | Agent 扩展 apply 脚本（Phase 4） |
| `scripts/apply-provider-cleanup.py` | Provider 清理脚本（motchat→duckcoding） |
| `scripts/apply-duckcoding-migration.py` | DuckCoding 迁移脚本 |
| `scripts/acpx-wrapper.sh` | ACP 环境配置 wrapper |
| `scripts/setup-runs-access.sh` | ACL 设置 nick 读 runs.json |
| `scripts/apply-logrotate.sh` | 安装日志轮转 |

## 交接文档 `[handoff]`

| 文件 | 描述 |
|------|------|
| `.claude/handoff/handoff-2026-03-31-phase5j.md` | Phase 5J — GUI auth + Docker/Broker + Cron 修复 + 部署 |
| `.claude/handoff/handoff-2026-03-30-swimlane-fix.md` | Swimlane timestamp 修复 + Skill frontmatter + Gateway RPC Plugin |
| `.claude/handoff/handoff-2026-03-30-gui-complete.md` | GUI 全量完成 + 文档同步 |
| `.claude/handoff/handoff-2026-03-29-task-flow.md` | Task Flow + 消息渲染 + 观测性 |
| `.claude/handoff/handoff-2026-03-28-gui-development.md` | Phase 5 + GUI 开发 |
| `.claude/handoff/handoff-2026-03-27-phase4-completion.md` | Phase 4 完成 |
| `.claude/handoff/handoff-2026-03-25-phase4-maintenance.md` | Phase 4 维护 |

## Workspace 模板 `[active]`

| 目录 | 描述 |
|------|------|
| `workspace-main-template/` | main agent workspace（含 control/、skills/） |
| `workspace-task-runner-template/` | task-runner workspace（11 skills） |
| `workspace-research-coordinator-template/` | research-coordinator workspace |
| `workspace-auditor-template/` | auditor workspace |

## 插件 `[active]`

| 目录 | 描述 |
|------|------|
| `plugins/gateway-rpc-tool/` | Gateway RPC 插件（14 methods，已部署到 live extensions） |

## 冻结规格 `[frozen]`

| 文件 | 描述 |
|------|------|
| `docs/specs/host-ops-broker-protocol-v1.md` | broker 协议规格 v1 |
| `docs/specs/error-taxonomy-v1.md` | 错误分类与错误码 |
| `docs/specs/contract-matrix-v1.md` | 跨层契约矩阵 |

## 已归档 `[archived]`

| 目录 | 描述 |
|------|------|
| `docs/archive/planning/phase2/` | Phase 2 设计（8 个文件） |
| `docs/archive/planning/phase3-upgrade/` | Phase 3 upgrade/probe 设计 |
| `docs/archive/planning/phase3-stall/` | Phase 3 stall-period 文档 |
| `docs/archive/planning/phase4-acp/` | Phase 4 ACP 研究 + 策略修复 + LabClaw 集成 |
| `docs/archive/planning/phase5/` | Phase 5 升级评估 + Skills 扩展 + 长期任务设计 |
| `docs/archive/planning/api-migration/` | API 迁移方案（已完成归档） |
| `candidates/archive/` | 已部署/已过期的配置候选 |

## 参考文档 `[reference]`

| 文件 | 描述 |
|------|------|
| `docs/when-to-snapshot.md` | 快照时机指南 |
| `docs/acceptance-tests.md` | 验收测试 |
| `docs/adr/adr-scrapling-placement.md` | Scrapling 系统定位决策 |
