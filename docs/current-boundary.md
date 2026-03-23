# OpenClaw 当前真实边界

> 冻结日期：2026-03-22
> 基线版本：OpenClaw 2026.3.13（2026-03-18 从 2026.3.2 升级完成）
> 阶段：Phase 2 全部完成 + OpenClaw 2026.3.13 升级完成；升级后 capability probe 已执行到 P5，并因 hard gate FAIL 中止；Phase 3 当前为 NO-GO

---

## 已完成

| 阶段 | 状态 | 完成日期 |
|------|------|----------|
| Phase 0 (dev skeleton) | 完成 | 2026-03-07 |
| Phase 1A (main bootstrap) | 完成 | 2026-03-07 |
| Phase 1B (控制面收口 + 首次 live publish) | 完成 | 2026-03-11 |
| Phase 2 broker deployment | 完成 | 2026-03-14 |
| Phase 2 plugin activation | 完成 | 2026-03-15 |
| Phase 2 agent-facing host_ops **8/8** | 完成 | 2026-03-17 |
| OpenClaw 版本升级 (2026.3.2 → 2026.3.13) | 完成 | 2026-03-18 |

### 已验证的 8 个 host_ops action

| Action | 验证日期 | 类型 |
|--------|----------|------|
| `gateway_health` | 2026-03-15 | 只读 |
| `validate_openclaw_json_candidate` | 2026-03-15 | 只读 |
| `deploy_openclaw_json_candidate` | 2026-03-15 | 写（Route C） |
| `snapshot_pre` | 2026-03-16 | 写 |
| `snapshot_post` | 2026-03-16 | 写 |
| `rollback_prepare` | 2026-03-16 | 只读（prepare-only） |
| `gateway_restart` | 2026-03-16 | 写（两段式） |
| `vault_sync` | 2026-03-17 | 写（incremental send） |

`vault_sync` 已收口，不 reopen。全部 8 action 证据见 `docs/records/`。

### 2026.3.13 升级窗口事实

- Pre snapshot：`root-pre-upgrade-2026.3.13-20260318-1530`
- Post snapshot：`root-post-upgrade-2026.3.13-20260318-1615`
- Pre / post vault_sync：均已完成
- Plugin 文件级备份：`/var/lib/openclaw/host-ops-tool-backups/host-ops-tool-pre-upgrade-20260318-1530.tar.gz`
- P0 focused regression：19/19 PASS
- Phase 2 host_ops 升级后回归：8/8 PASS
- Rollback：未触发
- 升级记录：`docs/records/openclaw-2026.3.13-upgrade-activation-2026-03-18.md`

## 当前真实边界

| 事项 | 状态 |
|------|------|
| 升级后 capability probe（在 2026.3.13 上） | **已执行到 P5，并因 hard gate FAIL 中止** — `P5 FAIL`，Phase 3 当前为 **NO-GO**，`P2 / P1 / P4 / P3` 为 **deferred / not executed** |
| `2026-03-21` temporary restricted proxy feasibility window | **HARD_STOP before proxy start** — 唯一 hard-stop reason = `hello-world image missing`；`proxy not started`；`audit jsonl not created`；`gateway remained active`；`broker remained active` |
| `2026-03-22` hello-world image prerequisite remediation 微窗口 | **PASS / prerequisite-only 收口** — `/etc/docker/daemon.json` 起初不存在；仅通过 `registry-mirrors` + `docker.service` restart 完成最小 registry reachability remediation；`sudo docker pull hello-world` 成功；`hello-world` image 已形成直接存在证据；`docker.service` / `docker.socket` / gateway / broker 前后均保持 `active`；`proxy not started`；`audit jsonl not created`；`proxy execution not validated` |
| Phase 3 (Docker sandbox / task-runner) | **未开始** — 当前仍不放行；`docker.service` / `docker.socket` 的 dated evidence 不等于 `Phase 3 = GO` |
| Phase 4 (容器内 Claude Code 执行链) | **未开始** |
| Phase 5 (LLM gateway / token 最小化) | **未开始** |
| Phase 6 (备份扩展 / 长期收口) | **未开始** |
| Scrapling 接入 | **未开始** |

## 当前下一步：operator-side / future execution seam prep for first live pilot

`2026-03-19` 的 capability probe 已在 `P5 Docker / task-runner prerequisites` 处 hard gate FAIL，结论仍是 `Phase 3 = NO-GO`。

`2026-03-21` 的 temporary restricted proxy feasibility window execution evidence 又进一步收口为：

- `WINDOW_RESULT=HARD_STOP`
- `HARD_STOP_REASON=hello-world image missing`
- `PROXY_NOT_STARTED=yes`
- `AUDIT_JSONL_PRESENT=no`

对应 evidence 见：

- `docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md`

同一 bundle 还直接显示：

- `docker.service` pre-proxy = `active`
- `docker.socket` pre-proxy = `active`
- `openclaw` 直接访问 Docker daemon = `permission denied`
- `hello-world` image 缺失

`2026-03-22` 的 remediation 微窗口随后补齐了该唯一 blocker：

- `/etc/docker/daemon.json` 起初不存在；
- 仅通过 `registry-mirrors` 配置 + `docker.service` restart 做最小 remediation；
- `sudo docker pull hello-world` 成功；
- `sudo docker image inspect hello-world` / `sudo docker image ls hello-world` 已形成直接存在证据；
- `docker.service` / `docker.socket` / gateway / broker 在 remediation 前后均保持 `active`；
- `proxy not started`；
- `audit jsonl not created`；
- `proxy execution not validated`。

这些 dated facts 只说明 `hello-world` prerequisite 已补齐，不构成 `Phase 3 = GO`，也不构成 temporary restricted proxy execution 已开始。

在此之后，`2026-03-22` 的 blocked-check authoritative 状态又进一步收口为：

- `RESULT=BLOCKED_BEFORE_HOST_SIDE_CHANGE`
- `GATE0_3=GREEN`
- `PREPARED_STATE_PASS=YES`
- `READONLY_EVIDENCE_GREEN=YES`
- `APPROVED_PROXY_EXEC_CMD=NO`

这意味着 repo-side prepare / precheck 与 readonly evidence 已经收口，但当前仍**没有**可进入 live-side 的 future execution seam exact input。

因此当前 direct next work 已从“继续扩 repo-side source closure”切换为：

- `operator-side / future execution seam prep for first live pilot`

其收口原则固定为：

1. `first-live-pilot candidate pack` 已 ready，当前 repo-side 资产视为已收口。
2. remaining blocker 只剩 `future execution seam / operator input`，不再是 repo-side asset gap。
3. 当前唯一最小 first live pilot case 固定为 `task-intake-host-affecting`，而不是继续停留在 readonly dry-run。
4. Gate 0-3 green 不等于可进入 pre-snapshot；future first live pilot 仍必须另行满足 `快照 -> 变更 -> 健康检查 -> post 快照 -> Vault 入库`。
5. 当前 direct next 主文档改为 `docs/planning/phase3-first-live-pilot-execution-seam-prep-pack-2026-03-23.md`。
6. 不触碰 `/etc/openclaw/openclaw.json`、`openclaw.live.json` 或 `openclaw` 用户组归属。

- 执行记录：`docs/records/post-upgrade-capability-probe-execution-2026-03-19.md`
- 本次 HARD_STOP evidence record：`docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md`
- prerequisite remediation record：`docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md`
- blocked-state hard-stop record：`docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md`
- 设计文档：`docs/planning/post-upgrade-capability-probe-2026.3.13-slice-design-2026-03-18.md`
- Probe matrix：`docs/checklists/post-upgrade-capability-probe-matrix-2026.3.13.md`
- next-window runbook：`docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md`
- 父切片 planning：`docs/planning/docker-prerequisite-establishment-for-phase3-2026-03-19.md`
- 当前 direct-next merged prep pack：`docs/planning/phase3-first-live-pilot-execution-seam-prep-pack-2026-03-23.md`
- 前一轮 repo-side source closure：`docs/planning/approved-direct-proxy-execution-block-source-closure-2026-03-22.md`
- repo-side artifact preparation pack：`docs/execution-pack-temporary-restricted-proxy-feasibility-artifact-preparation-2026-03-22.md`
- 已形成 green 的 preflight checklist：`docs/checklists/temporary-restricted-proxy-feasibility-execution-preflight-2026-03-22.md`
- 已形成 green 的 readonly evidence pack：`docs/checklists/temporary-restricted-proxy-feasibility-execution-readonly-evidence-pack-2026-03-22.md`
- feasibility definition：`docs/planning/docker-access-model-feasibility-experiment-for-openclaw-2026.3.13-2026-03-21.md`

## 当前 repo-side 执行器状态

- Codex 当前已可作为 **repo-side 主执行者** 使用，但这只代表开发仓文档/脚本/候选产物层可接手，不代表 live-side 执行器已切换。
- Claude Code **未被替代**；当前应视为与 Codex **双栈共存**：
  - Claude Code：已有既有 SOP、项目规则与开发使用路径。
  - Codex：当前已可在 `~/projects/openclaw-dev/` 内承担 repo-side 主执行工作。
- `CLAUDE.md` 当前仍是 repo 级协作规则入口。
- `.codex/config.toml` 是 repo-local 配置层；`~/.codex/config.toml` 是用户级接入层，不属于仓库事实源。
- 本轮文档收口仅覆盖 repo-side 文档与 repo-local 配置，不涉及任何 live-side 配置、凭据或运行态文件。

## 已知非阻塞观察项

- 权威脚本 `vault-backup-root-btrfs` 检查的是 `openclaw.service`，而历史文档中曾写 `openclaw-gateway.service`。属于脚本/文档命名漂移，不影响 vault_sync 已收口的结论。
- Broker 不会随 gateway 自动启动，需 operator 手动 `systemctl start openclaw-broker.service`（2026-03-18 升级窗口发现）。
- Plugin provenance 警告出现但不阻塞功能（P1）。
- OpenClaw log file size cap reached（P1）。

## 关键参考

- 权威 SOP：`docs/host-sop.md`
- 架构设计：`docs/design-v3.md`
- 文档地图：`docs/map.md`
- 证据索引：`docs/records/README.md`
