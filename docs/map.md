# OpenClaw Dev Repo 文档地图

> 更新日期：2026-03-18

---

## 权威文档 `[authority]`

这些文档是系统事实的唯一权威来源，修改必须谨慎。

| 文件 | 描述 |
|------|------|
| `docs/host-sop.md` | 宿主机状态记录——运行态事实的权威源 |
| `docs/design-v3.md` | 架构设计规格 v3.1——实施目标与规格的权威源 |
| `CLAUDE.md` | AI 协作规则与安全边界 |
| `workspace-main-template/control/host-ops-api.md` | host-ops broker API 契约（agent-facing 参考） |

## 边界与导航 `[active]`

| 文件 | 描述 |
|------|------|
| `docs/current-boundary.md` | 当前真实边界冻结（1–3 屏速览） |
| `docs/map.md` | 本文件——文档总地图 |

## 活跃规划 `[active]`

| 文件 | 描述 |
|------|------|
| `docs/planning/README.md` | planning 目录索引 |
| `docs/planning/openclaw-upgrade-readiness-2026-03-18.md` | OpenClaw 升级就绪评估 |

## 架构决策记录 `[active]`

| 文件 | 描述 |
|------|------|
| `docs/adr/adr-scrapling-placement.md` | Scrapling 系统定位决策 |

## 冻结规格 `[frozen]`

这些文档是 Phase 2 交付的协议/契约规格，处于冻结状态。

| 文件 | 描述 |
|------|------|
| `docs/specs/host-ops-broker-protocol-v1.md` | broker 协议规格 v1 |
| `docs/specs/error-taxonomy-v1.md` | 错误分类与错误码 |
| `docs/specs/contract-matrix-v1.md` | 跨层契约矩阵 |
| `docs/specs/phase2-repo-prep-gate.md` | Phase 2 prep 退出标准 |
| `docs/specs/phase2-broker-deployment-layout.md` | Phase 2 部署文件系统布局 |

## 证据库 `[evidence]`

证据文件保留在主树中，不做归档。

| 目录 | 描述 |
|------|------|
| `docs/records/` | Phase 1B–2 激活记录（11 files），见 `docs/records/README.md` |
| `docs/checklists/` | 操作清单 |

### 证据文件明细

| 文件 | 描述 |
|------|------|
| `docs/checklists/deploy-candidate-route-c-checklist.md` | Route C deploy 操作清单 |
| `docs/records/README.md` | records 目录索引 |

## 活跃参考 `[active]`

| 文件 | 描述 |
|------|------|
| `docs/when-to-snapshot.md` | 快照时机指南 |
| `docs/acceptance-tests.md` | 验收测试 |
| `docs/runtime-allowlist-backup-draft.md` | Phase 6 输入：运行态备份 allowlist 设计 |

## 历史里程碑 `[archived]`

| 文件 | 描述 |
|------|------|
| `docs/milestones/phase0-baseline.md` | Phase 0 基线记录 |

## 已用模板 `[archived]`

| 文件 | 描述 |
|------|------|
| `docs/templates/first-live-publish-record-template.md` | Phase 1B live publish 记录模板 |
| `docs/templates/phase1b-live-publish-syncback-template.md` | Phase 1B syncback 模板 |
| `docs/templates/phase2-broker-deployment-record-template.md` | Phase 2 部署记录模板 |
| `docs/templates/phase2-broker-deployment-syncback-template.md` | Phase 2 syncback 模板 |

## 已用 Runbook 与执行包 `[archived]`

| 文件 | 描述 |
|------|------|
| `docs/runbook-first-live-publish.md` | Phase 1B 首次 live publish runbook |
| `docs/execution-pack-first-live-publish.md` | Phase 1B 执行包 |
| `docs/runbook-phase2-broker-deployment.md` | Phase 2 broker 部署 runbook |
| `docs/execution-pack-phase2-broker-deployment.md` | Phase 2 执行包 |

## 已归档规划 `[archived]`

已完成的 Phase 2 slice 设计文档，移至 `docs/archive/planning/phase2/`。

| 文件 | 描述 |
|------|------|
| `docs/archive/planning/phase2/deploy-candidate-slice-design-2026-03-15.md` | deploy_candidate 切片设计 |
| `docs/archive/planning/phase2/snapshot-pre-slice-design-2026-03-15.md` | snapshot_pre 切片设计 |
| `docs/archive/planning/phase2/snapshot-post-slice-design-2026-03-16.md` | snapshot_post 切片设计 |
| `docs/archive/planning/phase2/rollback-prepare-slice-design-2026-03-16.md` | rollback_prepare 切片设计 |
| `docs/archive/planning/phase2/gateway-restart-slice-design-2026-03-16.md` | gateway_restart 切片设计 |
| `docs/archive/planning/phase2/gateway-restart-deferred-dispatch-design-2026-03-16.md` | gateway_restart deferred dispatch 修复 |
| `docs/archive/planning/phase2/gateway-restart-validation-hardening-2026-03-16.md` | gateway_restart input 强化 |
| `docs/archive/planning/phase2/vault-sync-slice-design-2026-03-17.md` | vault_sync 切片设计 |
