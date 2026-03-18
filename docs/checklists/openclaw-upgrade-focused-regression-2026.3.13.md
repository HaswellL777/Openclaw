# OpenClaw 2026.3.13 升级 Focused Regression Checklist

> 创建日期：2026-03-18
> 升级基线：2026.3.2 → 2026.3.13
> 依赖文档：`docs/runbook-openclaw-upgrade-2026.3.13.md`
> 设计来源：`docs/planning/openclaw-2026.3.13-upgrade-slice-design-2026-03-18.md`

---

## P0 — 升级当天必须完成

> 以下所有 P0 项目必须在 live upgrade 当天完成。任一 P0 项目 FAIL 且无法现场修复时，
> 必须根据 rollback 设计文档评估是否回滚。

### P0-1. 基础服务健康

| # | 检查项 | 测试方式 | 成功判据 | 结果 | 备注 |
|---|--------|----------|----------|------|------|
| 1 | gateway 启动并 active | `systemctl is-active openclaw-gateway.service` | `active` | | |
| 2 | broker 启动并 active | `systemctl is-active openclaw-broker.service` | `active` | | |
| 3 | OpenClaw 版本正确 | `openclaw --version` 或 `package.json` | `2026.3.13` | | |
| 4 | host-ops-tool plugin 注册成功 | gateway journal 无 registration error | 无 `missing register/activate`、无 `duplicate plugin`、无 `tool name collision` | | |
| 5 | broker socket 可达 | `sudo socat` 调用 `gateway_health` | 返回 `ok: true` | | |

**如果 #1 FAIL**：检查 journal → 尝试 `openclaw.json.bak` 恢复 → 如仍失败则回滚
**如果 #4 FAIL**：检查 plugin SDK API 兼容性 → plugin 备份恢复 → 如仍失败则回滚

### P0-2. 8 个 host_ops action 正例回归

| # | Action | 测试方式 | 成功判据 | 结果 | 备注 |
|---|--------|----------|----------|------|------|
| 6 | `gateway_health` | agent: `host_ops(action: "gateway_health")` | `ok: true`, `service_active: "active"` | | |
| 7 | `validate_openclaw_json_candidate` | agent: `host_ops(action: "validate_...", inputs: {candidate_path, expected_sha256})` | `ok: true`, `sha256_match: true`, `json_valid: true` | | |
| 8 | `deploy_openclaw_json_candidate` | agent: `host_ops(action: "deploy_...", inputs: {candidate_path, expected_sha256})` | `ok: true` | | |
| 9 | `snapshot_pre` | agent: `host_ops(action: "snapshot_pre", inputs: {label, reason})` | `ok: true` | | |
| 10 | `snapshot_post` | agent: `host_ops(action: "snapshot_post", inputs: {label, reason})` | `ok: true` | | |
| 11 | `rollback_prepare` | agent: `host_ops(action: "rollback_prepare", inputs: {target_snapshot, reason})` | `ok: true`, `snapshot_verified: true`, `prepare_only: true` | | |
| 12 | `gateway_restart` | agent: `host_ops(action: "gateway_restart", inputs: {reason})` | `ok: true`, `restart_scheduled: true` | | |
| 13 | `vault_sync` | agent: `host_ops(action: "vault_sync", inputs: {snapshot_name, incremental: true})` | `ok: true` | | |

**每个 action 如果 FAIL**：
- 检查 broker journal + wrapper 日志
- 区分是 plugin/broker/wrapper 层失败
- 如果是 plugin SDK 兼容性问题：全面评估后决定是否回滚

### P0-3. gateway_restart 两段式成功判据

| # | 检查项 | 测试方式 | 成功判据 | 结果 | 备注 |
|---|--------|----------|----------|------|------|
| 14 | dispatch 返回正确 | #12 结果 | `restart_scheduled: true`, `dispatch_method: "systemd-run-transient-timer"` | | |
| 15 | operator 独立确认双服务 active | `systemctl is-active` × 2 | gateway + broker 均 `active` | | |
| 16 | gateway_health 验证通过 | agent: `host_ops(action: "gateway_health")` | `ok: true` | | |

**完整三段式必须全部 PASS 才算 gateway_restart 回归通过。**

### P0-4. vault_sync incremental 路径

| # | 检查项 | 测试方式 | 成功判据 | 结果 | 备注 |
|---|--------|----------|----------|------|------|
| 17 | incremental send 成功 | #13 结果 | `actual_mode: "incremental"` 或 `"full"`（full 也可接受，表示 parent 不可用但 send 本身成功） | | |
| 18 | last_sent 已更新 | `sudo cat /var/lib/openclaw/backup/last_sent` | 包含刚发送的 snapshot 名 | | |
| 19 | Vault 中目标存在 | `sudo mount /mnt/vault && ls /mnt/vault/recv/system/ && sudo umount /mnt/vault` | 目标 snapshot 存在 | | |

---

## P1 — 可在升级后 1-2 天内完成

> P1 项目不阻塞升级 slice 关闭，但应在进入 Phase 3 之前完成。

### P1-1. 工作流与兼容性

| # | 检查项 | 测试方式 | 成功判据 | 结果 | 备注 |
|---|--------|----------|----------|------|------|
| 20 | `main` 基础工作流 | agent 发起任意日常对话/任务 | 正常响应，无异常中断 | | |
| 21 | candidate workflow 可用 | 完整 validate → deploy 流程 | 候选文件从 validate 到 deploy 全程通过 | | |
| 22 | workspace-main skills 可见性 | agent session 中检查可用 skills | workspace-main 中定义的 skills 可见 | | |
| 23 | `openclaw.json` 配置格式兼容 | gateway 启动无 schema error | gateway journal 无 Zod/schema validation error | | |

### P1-2. 日志与审计

| # | 检查项 | 测试方式 | 成功判据 | 结果 | 备注 |
|---|--------|----------|----------|------|------|
| 24 | gateway 日志路径未变 | `ls /var/log/openclaw/` | 日志文件结构与升级前一致 | | |
| 25 | broker 日志路径未变 | `ls /var/log/openclaw/broker/` | `broker.log` 仍在预期路径 | | |
| 26 | tool-audit-plugin 无异常 | gateway journal 检查 | 无 audit plugin 相关错误 | | |

### P1-3. 控制面行为

| # | 检查项 | 测试方式 | 成功判据 | 结果 | 备注 |
|---|--------|----------|----------|------|------|
| 27 | `workspace-main` 控制面正常 | agent 读取 `control/` 下文件 | 文件可读，内容完整 | | |
| 28 | 飞书通道正常 | 通过飞书向 Bot 发消息 | Bot 正常响应 | | |

---

## 汇总

### P0 汇总

| 组别 | 总数 | PASS | FAIL |
|------|------|------|------|
| P0-1 基础服务 | 5 | | |
| P0-2 action 正例 | 8 | | |
| P0-3 gateway_restart 三段式 | 3 | | |
| P0-4 vault_sync incremental | 3 | | |
| **P0 合计** | **19** | | |

### P1 汇总

| 组别 | 总数 | PASS | FAIL |
|------|------|------|------|
| P1-1 工作流 | 4 | | |
| P1-2 日志 | 3 | | |
| P1-3 控制面 | 2 | | |
| **P1 合计** | **9** | | |

---

## 判定规则

- **全部 P0 PASS**：升级 slice 可以关闭，执行 post-change snapshot + vault sync
- **P0 有 FAIL**：
  - 如果是个别 action 的测试数据问题（如 snapshot 名拼写错误）：修正后重测
  - 如果是 plugin/broker/wrapper 核心功能失败：评估 rollback
  - 如果是 gateway 级别失败（启动失败、plugin 注册失败）：立即 rollback
- **P1 有 FAIL**：记录为已知问题，不阻塞升级 slice 关闭，但阻塞进入 Phase 3
