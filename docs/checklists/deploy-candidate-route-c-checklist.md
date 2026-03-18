# Route C — deploy_openclaw_json_candidate Operator-Mediated Checklist

> 文档类型：**操作清单（每次 deploy 操作窗口必须完成全部步骤）**
> 路线：Route C（deploy + operator-mediated checklist）
> 创建日期：2026-03-15
> 设计来源：`docs/archive/planning/phase2/deploy-candidate-slice-design-2026-03-15.md`

---

## 核心约束

- **deploy 写入成功 ≠ 配置生效成功 ≠ 变更窗口关闭**
- agent 可自主调用 `validate`、`deploy`、`snapshot_pre`、`snapshot_post`、`gateway_restart`、`vault_sync`——这些 action 在能力层面均已 agent-facing 可用（8/8 live E2E verified，2026-03-17）
- 在当前 Route C 操作纪律中，restart / snapshot / vault_sync 的 closeout 步骤**仍由 operator-mediated checklist 承担**——这是纪律选择，不是能力缺失
- 本 checklist 是纪律约束，不由 plugin 或 wrapper 自动执行
- 每次 deploy 操作必须在一个操作窗口内完成所有步骤

---

## Preconditions

- [ ] 候选文件已存在于 `/var/lib/openclaw/approvals/candidates/`
- [ ] 候选文件 SHA256 已计算并记录
- [ ] operator 确认当前系统健康（gateway + broker active）
- [ ] operator 确认当前不在另一个未关闭的变更窗口中

## Phase 1: Pre-snapshot

> `snapshot_pre` action 已 agent-facing 可用，但 Route C 纪律要求 operator 确认快照已创建。

- [ ] agent 或 operator: 创建 pre-change snapshot
  - agent 可调用 `host_ops(action: "snapshot_pre", inputs: { label: "pre-deploy-YYYYMMDD-HHMM", reason: "..." })`
  - 或 operator 手动：
  ```bash
  sudo btrfs subvolume snapshot -r / /.snapshots/root-pre-deploy-YYYYMMDD-HHMM
  ```

## Phase 2: Validate

- [ ] agent: `host_ops(action: "validate_openclaw_json_candidate", inputs: { candidate_path: "...", expected_sha256: "..." })`
- [ ] 确认返回 `ok: true`，`sha256_match: true`，`json_valid: true`

## Phase 3: Deploy

- [ ] agent: `host_ops(action: "deploy_openclaw_json_candidate", inputs: { candidate_path: "...", expected_sha256: "..." })`
- [ ] 确认返回 `ok: true`
- [ ] operator 确认：此时**文件已写入**，但**配置尚未生效**（gateway 仍运行旧配置）

## Phase 4: Restart (operator-mediated)

> `gateway_restart` action 已 agent-facing 可用（两段式契约），但 Route C 纪律要求 operator 独立确认 restart 完成。

- [ ] agent 或 operator: 触发 restart（agent 可调用 `host_ops(action: "gateway_restart", inputs: { reason: "..." })`，或 operator 手动 `sudo systemctl restart openclaw-gateway.service`）
- [ ] operator: `systemctl is-active openclaw-gateway.service` → `active`
- [ ] operator: `systemctl is-active openclaw-broker.service` → `active`

## Phase 5: Health Gate

- [ ] agent: `host_ops(action: "gateway_health")` → 确认 `ok: true`
- [ ] operator: 检查 gateway journal 无 config validation errors
  ```bash
  sudo journalctl -u openclaw-gateway.service -n 30 --no-pager
  ```

## Phase 6: Post-snapshot & Close

> `snapshot_post` 和 `vault_sync` action 均已 agent-facing 可用，但 Route C 纪律要求 operator 确认变更窗口关闭。

- [ ] agent 或 operator: 创建 post-change snapshot
  - agent 可调用 `host_ops(action: "snapshot_post", inputs: { label: "post-deploy-YYYYMMDD-HHMM", reason: "..." })`
  - 或 operator 手动：
  ```bash
  sudo btrfs subvolume snapshot -r / /.snapshots/root-post-deploy-YYYYMMDD-HHMM
  ```
- [ ] agent 或 operator: vault_sync
  - agent 可调用 `host_ops(action: "vault_sync", inputs: { snapshot_name: "root-post-deploy-YYYYMMDD-HHMM" })`
  - 或 operator 手动：
  ```bash
  sudo /usr/local/sbin/vault-backup-root-btrfs
  ```
- [ ] operator: 确认变更窗口关闭

## Rollback

如果 Phase 4 或 Phase 5 失败：

### 首选：.bak 回滚
```bash
sudo cp /etc/openclaw/openclaw.json.bak /etc/openclaw/openclaw.json
sudo systemctl restart openclaw-gateway.service
```

### 备选：root snapshot 回滚
使用 Phase 1 创建的 pre-change snapshot。

### Plugin 回滚（取消 deploy action 可用性）
```bash
sudo cp /var/lib/openclaw/host-ops-tool-backups/index.js.bak-pre-deploy-slice \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo systemctl restart openclaw-gateway.service
```

## Records

- [ ] 操作完成后更新 `docs/records/phase2-hostops-deploy-candidate-activation-2026-03-15.md`
- [ ] 如有异常，记录 anomalies 和 lessons learned
