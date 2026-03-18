# OpenClaw 当前真实边界

> 冻结日期：2026-03-18
> 基线版本：OpenClaw 2026.3.2 / commit 85377a2
> 阶段：Phase 2 agent-facing host_ops 全部完成，pre-Phase 3 baseline rebase 中

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

## 未开始

| 事项 | 状态 |
|------|------|
| Phase 3 (Docker sandbox / task-runner) | **未开始** |
| Phase 4 (容器内 Claude Code 执行链) | **未开始** |
| Phase 5 (LLM gateway / token 最小化) | **未开始** |
| Phase 6 (备份扩展 / 长期收口) | **未开始** |
| OpenClaw 版本升级 (2026.3.2 → 2026.3.13) | **未开始** |
| Scrapling 接入 | **未开始** |

## 当前不应直接进入 Phase 3

原因：

1. **版本落后**：当前 live 基线仍是 2026.3.2，上游已到 2026.3.13。2026.3.7 引入 ContextEngine plugin slot，2026.3.12 带来 sessions_yield 和 workspace plugin trust 变更（implicit auto-load 禁用），且可能涉及进一步 sandbox 相关变化——这些影响 Phase 3 设计假设，具体范围待升级后验证
2. **在旧版本上做 Phase 3 capability probe 没有意义**：结论可能在升级后失效
3. **安全债务**：2026.3.11 包含安全修复，长期停留在 2026.3.2 不合理

后续优先路线：**baseline rebase → 升级准备 → 升级执行 → 升级后 capability probe → Phase 3 实现**

详见 `docs/planning/openclaw-upgrade-readiness-2026-03-18.md`。

## 已知漂移（非阻塞）

- 权威脚本 `vault-backup-root-btrfs` 检查的是 `openclaw.service`，而历史文档中曾写 `openclaw-gateway.service`。属于脚本/文档命名漂移，不影响 vault_sync 已收口的结论。

## 关键参考

- 权威 SOP：`docs/host-sop.md`
- 架构设计：`docs/design-v3.md`
- 文档地图：`docs/map.md`
- 证据索引：`docs/records/README.md`
