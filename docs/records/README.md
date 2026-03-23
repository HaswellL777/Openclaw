# Records 证据库索引

> `docs/records/` 是 activation / deployment 的证据层。
> 这些文件记录 live 操作的具体过程与结果。
> 主叙述层是 `docs/host-sop.md`（运行态事实）和 `docs/design-v3.md`（设计规格）。
> 当前状态见 `docs/current-boundary.md`。

---

## Phase 1B

| 文件 | 日期 | 主题 |
|------|------|------|
| `first-live-publish-2026-03-11.md` | 2026-03-11 | 首次 live 脚本化发布 |

## Phase 2 — Broker Deployment

| 文件 | 日期 | 主题 |
|------|------|------|
| `phase2-broker-deployment-2026-03-14.md` | 2026-03-14 | broker daemon + 8 wrappers 部署 |

## Phase 2 — Plugin & Tool Activation

| 文件 | 日期 | 主题 |
|------|------|------|
| `phase2-plugin-activation-2026-03-15.md` | 2026-03-15 | plugin lifecycle activation |
| `phase2-hostops-main-activation-2026-03-15.md` | 2026-03-15 | gateway_health agent-facing E2E |

## Phase 2 — Agent-Facing Action Slices

| 文件 | 日期 | Action | 结果 |
|------|------|--------|------|
| `phase2-hostops-validate-candidate-activation-2026-03-15.md` | 2026-03-15 | `validate_openclaw_json_candidate` | E2E pass |
| `phase2-hostops-deploy-candidate-activation-2026-03-15.md` | 2026-03-15 | `deploy_openclaw_json_candidate` | Route C E2E pass |
| `phase2-hostops-snapshot-pre-activation-2026-03-15.md` | 2026-03-16 | `snapshot_pre` | E2E pass |
| `phase2-hostops-snapshot-post-activation-2026-03-16.md` | 2026-03-16 | `snapshot_post` | E2E pass |
| `phase2-hostops-rollback-prepare-activation-2026-03-16.md` | 2026-03-16 | `rollback_prepare` | E2E pass |
| `phase2-hostops-gateway-restart-activation-2026-03-16.md` | 2026-03-16 | `gateway_restart` | 两段式 E2E pass |
| `phase2-hostops-vault-sync-activation-2026-03-17.md` | 2026-03-17 | `vault_sync` | incremental send E2E pass |

**全部 8/8 action live E2E verified (2026-03-17)。**

## OpenClaw 版本升级

| 文件 | 日期 | 主题 |
|------|------|------|
| `openclaw-2026.3.13-upgrade-activation-2026-03-18.md` | 2026-03-18 | OpenClaw 2026.3.2 → 2026.3.13 升级，P0 19/19 PASS，rollback 未触发 |
| `post-upgrade-capability-probe-execution-2026-03-19.md` | 2026-03-19 | capability probe P5 FAIL（Docker 未安装）；P5 根因已于 2026-03-23 解决 |

## 已归档记录

Mar 19-22 期间的 proxy feasibility 执行记录已归档至 `docs/archive/records/phase3-stall/`：

| 文件 | 日期 | 主题 |
|------|------|------|
| `temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md` | 2026-03-21 | HARD_STOP: hello-world image missing |
| `hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md` | 2026-03-22 | hello-world prerequisite 补齐 |
| `temporary-restricted-proxy-feasibility-execution-hard-stop-...20260322-111033.md` | 2026-03-22 | HARD_STOP: current-run artifact alignment |

这些记录保留为历史参考。proxy 路线已放弃，改用 docker group 方案（2026-03-23 完成）。
