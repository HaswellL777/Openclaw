# OpenClaw 2026.3.13 升级 Activation Record

> 日期：2026-03-18
> 操作者：nick（operator）
> 升级前版本：OpenClaw 2026.3.2
> 升级后版本：OpenClaw 2026.3.13
> 结果：**升级成功，rollback 未触发**

---

## 时间线

| 时间（CST） | 事件 |
|-------------|------|
| ~15:30 | Pre-change root snapshot 创建 |
| ~15:30 | Pre-change vault_sync 完成 |
| ~15:30 | Plugin 文件级备份完成（tar.gz） |
| ~15:30–15:45 | Gateway 停止、npm install openclaw@2026.3.13 执行、gateway 启动 |
| ~15:45 | Gateway 确认运行在 2026.3.13 |
| ~15:45 | 发现 broker 未随 gateway 自动启动，手动 `systemctl start openclaw-broker.service` |
| ~15:45–16:00 | P0 focused regression 19/19 PASS |
| ~16:00 | Phase 2 host_ops 8/8 升级后正例回归全部通过 |
| ~16:15 | Post-change root snapshot 创建 |
| ~16:15 | Post-change vault_sync 完成 |

## Snapshots

| 类型 | 名称 |
|------|------|
| Pre-change | `root-pre-upgrade-2026.3.13-20260318-1530` |
| Post-change | `root-post-upgrade-2026.3.13-20260318-1615` |

## Vault Sync

- Pre-change vault_sync：已完成
- Post-change vault_sync：已完成

## Plugin 备份

- 路径：`/var/lib/openclaw/host-ops-tool-backups/host-ops-tool-pre-upgrade-20260318-1530.tar.gz`
- 类型：升级前完整 plugin 文件备份（tar.gz）
- 说明：`/var/lib/openclaw` 是独立 btrfs 子卷，不在 root snapshot 保护范围内，plugin 文件必须独立备份

## Gateway / Broker 状态恢复

- Gateway：升级后 `systemctl start openclaw-gateway.service` 正常启动，确认运行在 2026.3.13
- Broker：**未随 gateway 自动启动**，需要 operator 手动执行 `systemctl start openclaw-broker.service`
  - 这是本次升级窗口发现的操作观察项
  - 手动启动后 broker 正常运行
  - 已写入权威文档作为已知操作要点

## P0 Focused Regression 结果

**19/19 PASS**

### Phase 2 host_ops 8/8 升级后回归

| Action | 结果 |
|--------|------|
| `gateway_health` | PASS |
| `validate_openclaw_json_candidate` | PASS |
| `deploy_openclaw_json_candidate` | PASS |
| `snapshot_pre` | PASS |
| `snapshot_post` | PASS |
| `rollback_prepare` | PASS |
| `gateway_restart` | PASS |
| `vault_sync` | PASS |

全部 8/8 action 在 2026.3.13 上通过正例回归。

## Rollback

未触发。升级成功完成，无需 rollback。

## 非阻塞观察项

| # | 观察 | 严重程度 | 说明 |
|---|------|----------|------|
| 1 | Broker 未随 gateway 自动启动 | 非阻塞 | 需要 operator 手动 `systemctl start openclaw-broker.service`。手动启动后功能正常。已写入 SOP 作为操作要点 |
| 2 | Plugin provenance 警告出现 | 非阻塞（P1） | 警告出现但不阻塞 plugin 功能，registerTool 正常工作，全部 8 action 通过 |
| 3 | OpenClaw log file size cap reached | 非阻塞（P1） | 日志文件大小上限触达，不影响运行，后续可评估日志轮转策略 |

## 验收标准核对

| 判据 | 状态 |
|------|------|
| Gateway 健康运行在 2026.3.13 | ✅ |
| Broker 健康运行 | ✅（手动启动后） |
| host-ops-tool plugin 无 registration error | ✅ |
| 全部 8 action focused regression PASS | ✅ 8/8 |
| gateway_restart 两段式契约成立 | ✅ |
| vault_sync incremental 路径成立 | ✅ |
| Post-change snapshot + vault_sync 完成 | ✅ |
| 文档 syncback 完成 | ✅（本次 syncback） |

## 结论

OpenClaw 2026.3.13 升级窗口已成功关闭。Live baseline 正式从 2026.3.2 切换到 2026.3.13。下一步应为升级后 capability probe（在 2026.3.13 上），而不是直接进入 Phase 3 实现。
