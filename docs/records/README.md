# Records 证据库索引

> `docs/records/` 是 activation / deployment 的证据层。
> 这些文件记录 live 操作的具体过程与结果，不是主叙述层。
> 主叙述层是 `docs/host-sop.md`（运行态事实）和 `docs/design-v3.md`（设计规格）。

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

**全部 8/8 action live E2E verified (2026-03-17)。** `vault_sync` 已收口。

## OpenClaw 版本升级

| 文件 | 日期 | 主题 |
|------|------|------|
| `openclaw-2026.3.13-upgrade-activation-2026-03-18.md` | 2026-03-18 | OpenClaw 2026.3.2 → 2026.3.13 升级，P0 19/19 PASS，rollback 未触发 |
| `post-upgrade-capability-probe-execution-2026-03-19.md` | 2026-03-19 | capability probe execution attempted，P5 hard gate FAIL 后中止，结果 = NO-GO |

`post-upgrade-capability-probe-execution-2026-03-19.md` 是执行证据文件，不是 Docker prerequisite establishment 的实施记录。
