# OpenClaw Dev Repo 文档地图

> 更新日期：2026-03-25

---

## 权威文档 `[authority]`

修改必须谨慎。

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
| `docs/planning/phase4-acp-claude-code-research.md` | Phase 4 ACP Claude Code 集成研究报告（close-by: 2026-03-30） |
| `docs/planning/skills-extension-design.md` | Skills 体系扩展设计（close-by: 2026-04-01） |
| `docs/planning/long-running-tasks-design.md` | 长期任务支持方案设计（close-by: 2026-04-01） |

## 架构决策记录 `[active]`

| 文件 | 描述 |
|------|------|
| `docs/adr/adr-scrapling-placement.md` | Scrapling 系统定位决策 |

## 冻结规格 `[frozen]`

Phase 2 交付的协议/契约规格，处于冻结状态。

| 文件 | 描述 |
|------|------|
| `docs/specs/host-ops-broker-protocol-v1.md` | broker 协议规格 v1 |
| `docs/specs/error-taxonomy-v1.md` | 错误分类与错误码 |
| `docs/specs/contract-matrix-v1.md` | 跨层契约矩阵 |
| `docs/specs/phase2-repo-prep-gate.md` | Phase 2 prep 退出标准 |
| `docs/specs/phase2-broker-deployment-layout.md` | Phase 2 部署文件系统布局 |

## 证据库 `[evidence]`

| 目录 | 描述 |
|------|------|
| `docs/records/` | Phase 1B–2 + upgrade + probe 的执行证据记录 |
| `docs/checklists/` | 操作清单 |

### 活跃 checklists

| 文件 | 描述 |
|------|------|
| `docs/checklists/deploy-candidate-route-c-checklist.md` | Route C deploy 操作清单 |
| `docs/checklists/openclaw-upgrade-focused-regression-2026.3.13.md` | 2026.3.13 升级 focused regression checklist |
| `docs/checklists/post-upgrade-capability-probe-matrix-2026.3.13.md` | 升级后 capability probe matrix |

## Runbook `[active]`

| 文件 | 描述 |
|------|------|
| `docs/runbooks/runbook-post-upgrade-capability-probe-2026.3.13.md` | 升级后 capability probe runbook — 下一步使用 |

## 已用 Runbook `[archived]`

| 文件 | 描述 |
|------|------|
| `docs/runbooks/runbook-openclaw-upgrade-2026.3.13.md` | 2026.3.13 升级 runbook（已完成） |
| `docs/runbooks/runbook-first-live-publish.md` | Phase 1B live publish runbook |
| `docs/runbooks/runbook-phase2-broker-deployment.md` | Phase 2 broker 部署 runbook |

## 执行包 `[archived]`

| 文件 | 描述 |
|------|------|
| `docs/execution-packs/execution-pack-first-live-publish.md` | Phase 1B 执行包 |
| `docs/execution-packs/execution-pack-phase2-broker-deployment.md` | Phase 2 执行包 |

## 参考文档 `[active]`

| 文件 | 描述 |
|------|------|
| `docs/when-to-snapshot.md` | 快照时机指南 |
| `docs/acceptance-tests.md` | 验收测试 |
| `docs/runtime-allowlist-backup-draft.md` | Phase 6 输入：运行态备份 allowlist 设计 |
| `.codex/config.toml` | repo-local Codex 配置层（当前主执行者为 Claude Code） |

## 历史里程碑 `[archived]`

| 文件 | 描述 |
|------|------|
| `docs/milestones/phase0-baseline.md` | Phase 0 基线记录 |

## 模板 `[reference]`

| 文件 | 描述 |
|------|------|
| `docs/templates/post-upgrade-capability-probe-record-template.md` | capability probe record 模板 |
| `docs/templates/first-live-publish-record-template.md` | Phase 1B live publish 记录模板 |
| `docs/templates/phase1b-live-publish-syncback-template.md` | Phase 1B syncback 模板 |
| `docs/templates/phase2-broker-deployment-record-template.md` | Phase 2 部署记录模板 |
| `docs/templates/phase2-broker-deployment-syncback-template.md` | Phase 2 syncback 模板 |

## 已归档 `[archived]`

| 目录 | 描述 |
|------|------|
| `docs/archive/planning/phase2/` | Phase 2 slice 设计（8 个文件） |
| `docs/archive/planning/phase3-upgrade/` | Phase 3 upgrade/probe 设计（4 个文件） |
| `docs/archive/planning/phase3-stall/` | Phase 3 stall-period 文档（5 个文件，Mar 19-23 proxy 路线探索产物） |
| `docs/archive/checklists/` | 已归档 checklists（3 个文件） |
| `docs/archive/runbooks/` | 已归档 runbooks（1 个文件） |
| `docs/archive/execution-packs/` | 已归档 execution packs（2 个文件） |
| `docs/archive/records/phase3-stall/` | Phase 3 stall-period 执行记录（3 个文件） |
