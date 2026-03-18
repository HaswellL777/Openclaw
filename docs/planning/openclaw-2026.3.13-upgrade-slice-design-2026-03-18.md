# OpenClaw 2026.3.13 升级 Slice 设计

> 设计日期：2026-03-18
> 当前基线：OpenClaw 2026.3.2 / commit 85377a2
> 目标版本：OpenClaw 2026.3.13
> 状态：**升级执行包 repo-side 设计文档**
> 前置文档：`docs/planning/openclaw-upgrade-readiness-2026-03-18.md`

---

## 1. 为什么当前应先升级再进入 Phase 3

1. **版本落后 11 个稳定版本**：当前 live 基线 2026.3.2，上游已到 2026.3.13。
2. **Phase 3 设计假设依赖上游新能力**：2026.3.12 的 `sessions_yield`、workspace plugin trust 变更、可能的 sandbox 相关能力变化——在 2026.3.2 上做 capability probe 结论可能在升级后失效。
3. **安全债务**：2026.3.11 包含安全修复，持续运行在 2026.3.2 不合理。
4. **Phase 3 关键修复在 2026.3.13**：cross-agent subagent target workspace 修复、`agents.list[].params` schema 修复——这些直接关系 task-runner 正确性。
5. **升级是独立变更窗口**：有独立的 pre/post snapshot、独立的 rollback 路径。与 Phase 3 合并会导致问题归因困难。

## 2. 为什么目标候选锁定 2026.3.13

- 2026.3.13 是截至 2026-03-18 的最新稳定版。
- 包含从 2026.3.3 到 2026.3.13 所有累积 bugfix 和安全修复。
- 2026.3.13-1 recovery tag 修复了发布路径问题，npm 版本仍为 2026.3.13。
- 跳版本升级的风险可控：OpenClaw 遵循语义化版本（`2026.3.x` 为 patch），接口兼容性预期不变。

## 3. 为什么不能把升级与 Phase 3 合并

1. **变更窗口隔离**：升级本身需要完整的 pre-snapshot → 升级 → health check → focused regression → post-snapshot → vault sync。
2. **独立 rollback 路径**：如果升级引入回归（plugin 不兼容、配置格式变化），必须能独立回滚到 2026.3.2 基线，不受 Phase 3 变更污染。
3. **问题归因**：两个变更合并后如果出问题，无法区分是升级还是 Phase 3 引入的。
4. **Phase 3 前置条件**：capability probe 必须在升级后版本上做，结论才有效。升级是 Phase 3 的前置条件，不是 Phase 3 的一部分。

## 4. 当前已知风险

| 风险 | 严重程度 | 缓解措施 |
|------|----------|----------|
| `agents.list[].params` schema 变严格（2026.3.13），现有 main agent 配置可能被拒绝 | **中** | gateway 启动失败即可检测；openclaw.json.bak 可立即恢复 |
| Implicit workspace plugin auto-load 禁用（2026.3.12），host-ops-tool 注册路径可能受影响 | **低**（host-ops-tool 通过 `plugins.entries` config 注册，不依赖 workspace auto-load） | focused regression 中 plugin registration 验证 |
| npm install 过程网络问题（本机需走代理） | **低** | operator 根据本机已有经验处理代理配置 |
| `/opt/openclaw` 的 node_modules 结构变化导致 broker 依赖路径失效 | **中** | broker 不直接依赖 `/opt/openclaw/node_modules`；wrapper 为独立 bash 脚本 |
| plugin SDK 内部 API 变化导致 `api.registerTool()` 行为变化 | **低**（registerTool 是公开 API） | focused regression 中 plugin registration + 全 8 action E2E |
| gateway_restart wrapper 的 systemd-run 行为在新版本中变化 | **极低** | systemd-run 是 host 工具，不随 OpenClaw 版本变化 |

## 5. Repo-side / Live-side / Rollback-side 边界划分

### 5.1 Repo-side（本轮完成）

| 工作项 | 产出 |
|--------|------|
| 升级 slice 设计 | 本文档 |
| Operator runbook | `docs/runbook-openclaw-upgrade-2026.3.13.md` |
| Focused regression checklist | `docs/checklists/openclaw-upgrade-focused-regression-2026.3.13.md` |
| Rollback 设计 | `docs/planning/openclaw-2026.3.13-upgrade-rollback-design-2026-03-18.md` |
| Preflight 脚本 | `scripts/preflight-upgrade-openclaw.sh` |
| 文档同步 | `docs/map.md`、`docs/planning/README.md`、`docs/design-v3.md`、`docs/current-boundary.md` |

### 5.2 Live-side（由 operator 后续执行）

| 步骤 | 工具 |
|------|------|
| 记录当前版本/配置/hash | `openclaw --version`、`sha256sum` |
| pre-change snapshot | `btrfs subvolume snapshot -r` |
| vault_sync | `/usr/local/sbin/vault-backup-root-btrfs` |
| 升级 OpenClaw | `sudo npm install --omit=dev openclaw@2026.3.13`（在 `/opt/openclaw`） |
| 服务 restart | `systemctl restart openclaw-gateway.service` |
| Health gate | `systemctl is-active` + gateway journal 检查 |
| Focused regression | 全 8 action E2E |
| post-change snapshot + vault_sync | 同上 |

### 5.3 Rollback-side

| 场景 | 策略 |
|------|------|
| gateway 不启动 | openclaw.json.bak 恢复 + `npm install openclaw@2026.3.2` 降级 |
| plugin registration 失败 | plugin 备份恢复 |
| 全面失败 | root snapshot 回滚 + plugin 文件备份恢复 |
| `/var/lib/openclaw` 不在 root snapshot 中 | 必须独立处理 plugin 文件恢复 |

详见 `docs/planning/openclaw-2026.3.13-upgrade-rollback-design-2026-03-18.md`。

## 6. Focused regression 范围

全部 8 个 Phase 2 host_ops action 必须在升级后完整重测：

| Action | 优先级 | 测试方式 |
|--------|--------|----------|
| `gateway_health` | P0 | agent 调用，确认 `ok: true` |
| `validate_openclaw_json_candidate` | P0 | agent 调用（正例） |
| `deploy_openclaw_json_candidate` | P0 | agent 调用（正例，使用测试候选） |
| `snapshot_pre` | P0 | agent 调用 |
| `snapshot_post` | P0 | agent 调用 |
| `rollback_prepare` | P0 | agent 调用（使用已存在的 snapshot） |
| `gateway_restart` | P0 | agent 调用 + operator 独立确认 + gateway_health 三段式 |
| `vault_sync` | P0 | agent 调用（incremental send） |

补充 P1 项目：

| 项目 | 优先级 |
|------|--------|
| workspace-main skills 可见性 | P1 |
| openclaw.json 配置格式兼容 | P1（gateway 启动即验证） |
| gateway journal 无异常日志 | P1 |
| candidate workflow 可用性 | P1 |

详见 `docs/checklists/openclaw-upgrade-focused-regression-2026.3.13.md`。

## 7. 验收标准

升级 slice 完成的判据：

1. **gateway 健康运行在 2026.3.13**：`openclaw --version` 确认 + `systemctl is-active` 确认
2. **broker 健康运行**：`systemctl is-active openclaw-broker.service` 确认
3. **host-ops-tool plugin 无 registration error**：gateway journal 无 plugin 相关错误
4. **全部 8 个 host_ops action focused regression PASS**：每个 action 至少一个正例通过
5. **gateway_restart 两段式契约仍成立**：deferred dispatch + operator 确认 + gateway_health 三段式验证
6. **vault_sync incremental 路径仍成立**：至少一次 incremental send 成功
7. **post-change snapshot + vault_sync 完成**：变更窗口正式关闭
8. **文档 syncback 完成**：host-sop.md 版本号更新、records 新增升级记录

## 8. 退出条件

升级 slice 视为完成当且仅当：

- [ ] 8 个 P0 focused regression 全部 PASS
- [ ] post-change snapshot 已创建
- [ ] vault_sync 已完成
- [ ] host-sop.md 已更新版本号
- [ ] 升级记录已写入 `docs/records/`
- [ ] `docs/current-boundary.md` 已更新

如有 P0 项目未通过，必须先完成 rollback，再分析原因，不可直接进入 Phase 3。

## 9. 当前不需要预先修改实现代码

基于以下判断，当前不需要为兼容 2026.3.13 预先修改 broker/plugin/wrapper 实现代码：

1. **host-ops-tool 通过 `plugins.entries` config 注册**，不依赖 workspace auto-load（2026.3.12 禁用的是 implicit workspace plugin auto-load）。
2. **broker 是独立 daemon**（`openclaw-broker.service`），不直接依赖 OpenClaw 版本。
3. **wrapper 是独立 bash 脚本**，使用 systemd 工具（btrfs、systemctl、systemd-run），不依赖 OpenClaw node_modules。
4. **plugin SDK 的 `api.registerTool()` 是公开 API**，预期向后兼容。

正确策略：**先升级，再看 focused regression 结果**。如果回归发现兼容问题，在升级后版本上修复，而不是在旧版本上猜测性修改。

## 10. 升级后下一步

升级 slice 完成后，下一步应为 **capability probe**（在 2026.3.13 版本上），而不是直接进入 Phase 3 实现：

1. 评估 `sessions_yield` 对 task-runner 设计的影响
2. 评估 sandbox backend 可用性
3. 评估 `openclaw backup create/verify` 作为补充 backup 工具的价值
4. 验证 Docker sandbox 相关能力是否可用
5. 基于 probe 结论更新 Phase 3 设计

capability probe 的结论才是进入 Phase 3 实现的 Go/No-Go gate。
