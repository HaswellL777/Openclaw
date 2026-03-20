# OpenClaw 当前真实边界

> 冻结日期：2026-03-19
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
| Phase 3 (Docker sandbox / task-runner) | **未开始** — 当前不放行，待 `docker-prerequisite-establishment-for-phase3` 完成后再评估 |
| Phase 4 (容器内 Claude Code 执行链) | **未开始** |
| Phase 5 (LLM gateway / token 最小化) | **未开始** |
| Phase 6 (备份扩展 / 长期收口) | **未开始** |
| Scrapling 接入 | **未开始** |

## 当前下一步：docker-prerequisite-establishment-for-phase3

本次 capability probe 已在 `2026.3.13` live baseline 上执行到 `P5 Docker / task-runner prerequisites`，并因 Docker prerequisite 缺失而在 hard gate 处中止。

当前下一步不是继续 capability probe 主流程，不是直接进入 `phase3-docker-sandbox-foundation`，而是先完成：

- `docker-prerequisite-establishment-for-phase3`

其目标应聚焦于：

1. 安装并启用 Docker Engine
2. 明确 `docker.service` / `docker.socket` 的目标形态
3. 为 `openclaw` 用户建立安全访问路径
4. 定义后续 Phase 3 所需的最小 Docker prerequisite
5. 为 capability probe 的 `P5 / P4 / P3` 重试建立入口

capability probe 的结论仍然是进入 Phase 3 实现的 Go/No-Go gate；本次执行窗口的正式结果是：**P5 FAIL，Phase 3 = NO-GO**。

- 执行记录：`docs/records/post-upgrade-capability-probe-execution-2026-03-19.md`
- 设计文档：`docs/planning/post-upgrade-capability-probe-2026.3.13-slice-design-2026-03-18.md`
- Probe matrix：`docs/checklists/post-upgrade-capability-probe-matrix-2026.3.13.md`
- Operator runbook：`docs/runbook-post-upgrade-capability-probe-2026.3.13.md`
- 下一刀 planning：`docs/planning/docker-prerequisite-establishment-for-phase3-2026-03-19.md`

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
