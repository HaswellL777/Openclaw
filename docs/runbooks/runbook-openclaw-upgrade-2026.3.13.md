# OpenClaw 2026.3.13 升级 Operator Runbook

> 文档类型：**live-side operator 执行步骤**
> 创建日期：2026-03-18
> 当前基线：OpenClaw 2026.3.2 / commit 85377a2
> 目标版本：OpenClaw 2026.3.13
> 设计来源：`docs/planning/openclaw-2026.3.13-upgrade-slice-design-2026-03-18.md`
> Rollback 设计：`docs/planning/openclaw-2026.3.13-upgrade-rollback-design-2026-03-18.md`
> Focused regression：`docs/checklists/openclaw-upgrade-focused-regression-2026.3.13.md`
> **执行状态：已完成（2026-03-18），升级成功，rollback 未触发**
> **升级 activation record：`docs/records/openclaw-2026.3.13-upgrade-activation-2026-03-18.md`**

---

## 重要声明

- 本 runbook 是给 operator 的 live 执行步骤
- 所有步骤必须按顺序逐步执行
- 任何步骤失败时，根据该步骤的失败处理指引决定是否继续或回滚
- 本文档**不是**升级完成记录——升级完成后需要单独写 records

> **实际执行观测（2026-03-18 补充）**：
> - Broker 不会随 gateway 自动启动，需手动 `systemctl start openclaw-broker.service`
> - Plugin provenance 警告出现但不阻塞功能（P1）
> - P0 focused regression 19/19 PASS
> - Log file size cap reached（P1，不影响运行）

---

## B1. 升级前确认

### B1.1 Repo 状态确认

```bash
# 在 ~/projects/openclaw-dev 中
cd ~/projects/openclaw-dev
git branch --show-current
# 预期: feat/phase1b-workspace-foundation

git log --oneline -1
# 记录当前 HEAD commit hash

git status --short
# 预期: 仅 ?? openclaw.live.json（不应有未提交的 tracked 变更）
```

- [ ] 当前分支: `feat/phase1b-workspace-foundation`
- [ ] HEAD commit: ____________________
- [ ] 工作区干净（无未提交的 tracked 变更）

### B1.2 当前文档入口确认

- [ ] `docs/current-boundary.md` 可读且记录当前版本为 2026.3.2
- [ ] `docs/host-sop.md` §0.1 记录当前版本为 2026.3.2
- [ ] `docs/planning/openclaw-upgrade-readiness-2026-03-18.md` 存在
- [ ] 本 runbook 存在并可读

### B1.3 当前 live OpenClaw 版本记录

```bash
sudo -u openclaw /opt/openclaw/node_modules/.bin/openclaw --version 2>/dev/null \
  || (cd /opt/openclaw && sudo node -e "console.log(require('./node_modules/openclaw/package.json').version)")
```

- [ ] 当前 live 版本: ____________________（预期: 2026.3.2）

### B1.4 当前 gateway/broker 服务状态记录

```bash
systemctl is-active openclaw-gateway.service
systemctl is-active openclaw-broker.service
```

- [ ] `openclaw-gateway.service`: ____________（预期: `active`）
- [ ] `openclaw-broker.service`: ____________（预期: `active`）

如果任一服务不是 `active`，**停止升级**，先排查服务状态。

### B1.5 当前 openclaw.json 配置 hash 记录

```bash
sudo sha256sum /etc/openclaw/openclaw.json
```

- [ ] SHA256: ____________________

### B1.6 当前 plugin 文件/version/hash 记录

```bash
# host-ops-tool plugin
sudo sha256sum /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js

# plugin manifest
sudo cat /var/lib/openclaw/.openclaw/extensions/host-ops-tool/openclaw.plugin.json | head -5
```

- [ ] `index.js` SHA256: ____________________
- [ ] plugin id: ____________________（预期: `host-ops-tool`）

### B1.7 当前 broker wrapper 状态记录

```bash
ls -la /opt/openclaw/broker/wrappers/
sha256sum /opt/openclaw/broker/wrappers/ocw-*.sh
```

- [ ] wrapper 文件列表已记录
- [ ] wrapper SHA256 已记录

### B1.8 repo-side preflight（可选）

```bash
cd ~/projects/openclaw-dev
bash scripts/preflight-upgrade-openclaw.sh
```

- [ ] preflight 无 FAIL 项

---

## B2. 升级前保护动作

### B2.1 Pre-change snapshot

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
sudo btrfs subvolume snapshot -r / "/.snapshots/root-pre-upgrade-2026.3.13-${TIMESTAMP}"
```

- [ ] Snapshot 创建成功
- [ ] Snapshot 名称: `root-pre-upgrade-2026.3.13-____________________`

### B2.2 Vault sync

```bash
sudo /usr/local/sbin/vault-backup-root-btrfs
```

- [ ] Vault sync 完成
- [ ] sync 类型: incremental / full

### B2.3 plugin 文件级备份

> `/var/lib/openclaw` 是独立 btrfs 子卷，不在 root snapshot 保护范围内。
> plugin 文件必须独立备份。

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)

# 备份 plugin index.js
sudo cp /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js \
        /var/lib/openclaw/host-ops-tool-backups/index.js.backup-pre-upgrade-${TIMESTAMP}

# 备份 plugin manifest
sudo cp /var/lib/openclaw/.openclaw/extensions/host-ops-tool/openclaw.plugin.json \
        /var/lib/openclaw/host-ops-tool-backups/openclaw.plugin.json.backup-pre-upgrade-${TIMESTAMP}

sudo cp /var/lib/openclaw/.openclaw/extensions/host-ops-tool/package.json \
        /var/lib/openclaw/host-ops-tool-backups/package.json.backup-pre-upgrade-${TIMESTAMP}

# 验证备份
ls -la /var/lib/openclaw/host-ops-tool-backups/*pre-upgrade*
```

- [ ] plugin 文件级备份完成

### B2.4 journal 最小检查点

```bash
# 记录当前 journal 时间戳，用于升级后对比
echo "Pre-upgrade journal checkpoint: $(date --iso-8601=seconds)"
sudo journalctl -u openclaw-gateway.service -n 5 --no-pager
sudo journalctl -u openclaw-broker.service -n 5 --no-pager
```

- [ ] journal 检查点已记录

### B2.5 Go/No-Go 判定

在继续之前，确认以下全部为 YES：

- [ ] pre-change snapshot 已创建
- [ ] vault sync 已完成
- [ ] plugin 文件级备份已完成
- [ ] 当前 gateway + broker 均 active
- [ ] 所有 hash/版本信息已记录

**如果任一项为 NO，停止升级。**

---

## B3. 升级执行

### B3.1 确认升级路径

> 以下升级命令基于 `docs/host-sop.md` §13.5.3 中记录的权威升级路径。
> 如果 operator 知悉更合适的升级方式（如上游文档变更），应优先使用上游指引，
> 并在执行后记录实际使用的方式。

**Operator 检查点**：
- [ ] 确认升级方式为 `npm install`（如 host-sop.md §13.5.3 所述）
- [ ] 如果上游有更新的升级指引，在此记录: ____________________

### B3.2 停止 gateway

```bash
sudo systemctl stop openclaw-gateway.service
```

- [ ] gateway 已停止

确认 broker 也已停止（由于 `Requires=openclaw-gateway.service` 依赖）：

```bash
systemctl is-active openclaw-broker.service
# 预期: inactive（随 gateway 停止而停止）
```

- [ ] broker 已停止

### B3.3 执行升级

```bash
cd /opt/openclaw
sudo npm install --omit=dev openclaw@2026.3.13
```

- [ ] npm install 完成，无错误
- [ ] 如有错误，记录: ____________________

### B3.4 启动 gateway

```bash
sudo systemctl start openclaw-gateway.service
```

- [ ] gateway 启动命令已执行

---

## B4. 升级后立即检查

### B4.1 OpenClaw 版本确认

```bash
sudo -u openclaw /opt/openclaw/node_modules/.bin/openclaw --version 2>/dev/null \
  || (cd /opt/openclaw && sudo node -e "console.log(require('./node_modules/openclaw/package.json').version)")
```

- [ ] 版本确认: ____________________（预期: 2026.3.13）

如果版本不是 2026.3.13，**停止，按 rollback 设计文档处理**。

### B4.2 Gateway + broker 服务状态

```bash
systemctl is-active openclaw-gateway.service
systemctl is-active openclaw-broker.service
```

- [ ] `openclaw-gateway.service`: ____________（预期: `active`）
- [ ] `openclaw-broker.service`: ____________（预期: `active`）

如果 gateway 不是 `active`：
1. 检查 journal：`sudo journalctl -u openclaw-gateway.service -n 50 --no-pager`
2. 如果是 config schema 问题：尝试恢复 `openclaw.json.bak`
3. 如果无法恢复：按 rollback 设计文档处理

如果 gateway active 但 broker 不是 `active`：
1. 检查 journal：`sudo journalctl -u openclaw-broker.service -n 50 --no-pager`
2. 尝试手动 restart：`sudo systemctl restart openclaw-broker.service`
3. 如果仍然失败：记录错误，继续评估（broker 失败不一定需要整体回滚）

### B4.3 Plugin registration 检查

```bash
# 检查 gateway journal 中 plugin 相关日志
sudo journalctl -u openclaw-gateway.service --since "-5 minutes" --no-pager | grep -i -E "plugin|host-ops|register"
```

- [ ] 无 plugin registration error
- [ ] 无 `host-ops-tool missing register/activate export` 警告
- [ ] 如有异常，记录: ____________________

### B4.4 最小 health check

```bash
# 通过 broker socket 做 health check
sudo socat - UNIX-CONNECT:/run/openclaw/broker.sock <<'EOF'
{"action":"gateway_health","request_id":"req-upgrade-health-001","task_id":"task-upgrade-check","requested_by":"operator:nick","inputs":{}}
EOF
```

- [ ] 返回 `ok: true`
- [ ] 如有错误，记录: ____________________

---

## B5. Focused Regression

> 完整矩阵见 `docs/checklists/openclaw-upgrade-focused-regression-2026.3.13.md`。
> 以下是逐 action 最小测试方式，必须在升级当天全部完成。

### B5.1 gateway_health

**测试方式**：agent 调用 `host_ops(action: "gateway_health")`

**成功判据**：`ok: true`, `service_active: "active"`

**失败排查**：
- `sudo journalctl -u openclaw-gateway.service -n 30 --no-pager`
- `sudo journalctl -u openclaw-broker.service -n 30 --no-pager`

- [ ] PASS / FAIL

### B5.2 validate_openclaw_json_candidate

**测试方式**：使用一个已知存在的候选文件（或现场创建测试文件）

```bash
# 创建测试候选
sudo -u openclaw cp /etc/openclaw/openclaw.json \
  /var/lib/openclaw/approvals/candidates/upgrade-test-candidate.json 2>/dev/null \
  || sudo cp /etc/openclaw/openclaw.json \
     /var/lib/openclaw/approvals/candidates/upgrade-test-candidate.json
HASH=$(sha256sum /var/lib/openclaw/approvals/candidates/upgrade-test-candidate.json | awk '{print $1}')
echo "Test candidate hash: $HASH"
```

Agent 调用：
```
host_ops(action: "validate_openclaw_json_candidate", inputs: {
  candidate_path: "/var/lib/openclaw/approvals/candidates/upgrade-test-candidate.json",
  expected_sha256: "<HASH>"
})
```

**成功判据**：`ok: true`, `sha256_match: true`, `json_valid: true`

**失败排查**：
- 检查候选文件是否存在且可读
- 检查 broker journal

- [ ] PASS / FAIL

### B5.3 deploy_openclaw_json_candidate

> 此测试使用当前已生效的配置作为"候选"部署回自身，是安全的 no-change deploy。

**测试方式**：使用 B5.2 中创建的测试候选

Agent 调用：
```
host_ops(action: "deploy_openclaw_json_candidate", inputs: {
  candidate_path: "/var/lib/openclaw/approvals/candidates/upgrade-test-candidate.json",
  expected_sha256: "<HASH>"
})
```

**成功判据**：`ok: true`

**失败排查**：
- 检查 `/etc/openclaw/openclaw.json` 是否仍可读
- 检查 wrapper journal
- 如果 deploy 失败但 gateway 仍 active，可能是 wrapper 权限问题

- [ ] PASS / FAIL

### B5.4 snapshot_pre

**测试方式**：

Agent 调用：
```
host_ops(action: "snapshot_pre", inputs: {
  label: "regress-pre-upgrade-2026.3.13",
  reason: "post-upgrade regression test"
})
```

**成功判据**：`ok: true`, 返回的 `snapshot_name` 包含 label

**失败排查**：
- `sudo btrfs subvolume list /.snapshots/ | tail -5`
- wrapper 可能遇到权限或空间问题

- [ ] PASS / FAIL

### B5.5 snapshot_post

**测试方式**：

Agent 调用：
```
host_ops(action: "snapshot_post", inputs: {
  label: "regress-post-upgrade-2026.3.13",
  reason: "post-upgrade regression test"
})
```

**成功判据**：`ok: true`

**失败排查**：同 B5.4

- [ ] PASS / FAIL

### B5.6 rollback_prepare

**测试方式**：使用 B2.1 中创建的 pre-upgrade snapshot 名

Agent 调用：
```
host_ops(action: "rollback_prepare", inputs: {
  target_snapshot: "root-pre-upgrade-2026.3.13-<TIMESTAMP>",
  reason: "post-upgrade regression test"
})
```

**成功判据**：`ok: true`, `snapshot_verified: true`, `prepare_only: true`

**失败排查**：
- 确认 snapshot 名称拼写正确
- `sudo btrfs subvolume show /.snapshots/root-pre-upgrade-2026.3.13-<TIMESTAMP>`

- [ ] PASS / FAIL

### B5.7 gateway_restart

**测试方式（三段式）**：

**Step 1** — Agent 调用：
```
host_ops(action: "gateway_restart", inputs: {
  reason: "post-upgrade regression test for gateway_restart"
})
```

**Step 1 成功判据**：`ok: true`, `restart_scheduled: true`, `dispatch_method: "systemd-run-transient-timer"`

**Step 2** — 等待约 10 秒，operator 独立确认：
```bash
systemctl is-active openclaw-gateway.service
systemctl is-active openclaw-broker.service
```

**Step 2 成功判据**：双服务均 `active`

**Step 3** — Agent 调用：
```
host_ops(action: "gateway_health")
```

**Step 3 成功判据**：`ok: true`

**失败排查**：
- 如果 Step 1 失败：检查 systemd-run 是否可用，wrapper 日志
- 如果 Step 2 失败（服务未恢复）：等待更长时间，检查 journal
- 如果 Step 3 失败：broker socket 可能未就绪，等待后重试

- [ ] PASS / FAIL

### B5.8 vault_sync

**测试方式**：使用 B5.4 中创建的 regression snapshot

Agent 调用：
```
host_ops(action: "vault_sync", inputs: {
  snapshot_name: "root-pre-regress-pre-upgrade-2026.3.13",
  incremental: true
})
```

**成功判据**：`ok: true`, `actual_mode` 为 `"incremental"` 或 `"full"`

**失败排查**：
- 确认 Vault 可挂载：`sudo mount /mnt/vault && sudo umount /mnt/vault`
- 检查 `last_sent` 文件：`sudo cat /var/lib/openclaw/backup/last_sent`
- wrapper 日志

- [ ] PASS / FAIL

### B5.9 Regression 汇总

| Action | 结果 | 备注 |
|--------|------|------|
| `gateway_health` | | |
| `validate_openclaw_json_candidate` | | |
| `deploy_openclaw_json_candidate` | | |
| `snapshot_pre` | | |
| `snapshot_post` | | |
| `rollback_prepare` | | |
| `gateway_restart` | | |
| `vault_sync` | | |

- [ ] **全部 8/8 PASS**

如果有任何 action FAIL：
1. 如果是 P0 action 的核心功能失败（不是测试环境问题）：考虑回滚
2. 如果可判定为测试数据问题：修正后重测
3. 如果不确定：停止后续操作，记录现象，评估影响

---

## B6. 升级后保护动作

> 仅在 B5 全部 PASS 后执行。

### B6.1 Post-change snapshot

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
sudo btrfs subvolume snapshot -r / "/.snapshots/root-post-upgrade-2026.3.13-${TIMESTAMP}"
```

- [ ] Post-change snapshot 创建成功
- [ ] Snapshot 名称: `root-post-upgrade-2026.3.13-____________________`

### B6.2 Vault sync

```bash
sudo /usr/local/sbin/vault-backup-root-btrfs
```

- [ ] Vault sync 完成

### B6.3 清理测试候选（可选）

```bash
sudo rm -f /var/lib/openclaw/approvals/candidates/upgrade-test-candidate.json
```

### B6.4 Records/doc syncback

升级完成后需要更新的文档（在 `~/projects/openclaw-dev` 中）：

1. `docs/host-sop.md` — §0.1 版本号更新为 2026.3.13
2. `docs/current-boundary.md` — 更新基线版本
3. `docs/records/` — 新增升级记录文件
4. `docs/design-v3.md` — 更新当前基线版本引用

- [ ] 文档 syncback 完成

---

## Appendix: 升级后 preflight 确认清单

| 项目 | 确认方式 | 结果 |
|------|----------|------|
| OpenClaw 版本 | `openclaw --version` | |
| gateway 状态 | `systemctl is-active` | |
| broker 状态 | `systemctl is-active` | |
| plugin 无 error | gateway journal | |
| 8 action regression | 逐 action E2E | |
| pre snapshot 存在 | `btrfs subvolume show` | |
| post snapshot 存在 | `btrfs subvolume show` | |
| vault sync 完成 | `vault-backup-root-btrfs` 输出 | |
