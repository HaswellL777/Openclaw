# OpenClaw 当前真实边界

> 冻结日期：2026-03-18
> 基线版本：OpenClaw 2026.3.13（2026-03-18 从 2026.3.2 升级完成）
> 阶段：Phase 2 全部完成 + OpenClaw 2026.3.13 升级完成，升级后 capability probe 尚未开始

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

## 未开始

| 事项 | 状态 |
|------|------|
| 升级后 capability probe（在 2026.3.13 上） | **未开始** — 这是当前下一步 |
| Phase 3 (Docker sandbox / task-runner) | **未开始** |
| Phase 4 (容器内 Claude Code 执行链) | **未开始** |
| Phase 5 (LLM gateway / token 最小化) | **未开始** |
| Phase 6 (备份扩展 / 长期收口) | **未开始** |
| Scrapling 接入 | **未开始** |

## 当前下一步：升级后 capability probe

升级已完成，当前下一步应为在 2026.3.13 上进行 capability probe：

1. 评估 `sessions_yield` 对 task-runner 设计的影响
2. 评估 sandbox backend 可用性
3. 评估 `openclaw backup create/verify` 作为补充 backup 工具的价值
4. 验证 Docker sandbox 相关能力是否可用
5. 基于 probe 结论更新 Phase 3 设计

capability probe 的结论是进入 Phase 3 实现的 Go/No-Go gate。

**capability probe 尚未开始。**

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
