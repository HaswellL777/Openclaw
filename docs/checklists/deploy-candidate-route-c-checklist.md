# Route C — deploy_openclaw_json_candidate Operator-Mediated Checklist

> 文档类型：**操作清单（每次 deploy 操作窗口必须完成全部步骤）**
> 路线：Route C（deploy + operator-mediated checklist）
> 创建日期：2026-03-15
> 设计来源：`docs/planning/deploy-candidate-slice-design-2026-03-15.md`

---

## 核心约束

- **deploy 写入成功 ≠ 配置生效成功 ≠ 变更窗口关闭**
- agent 可自主调用 `validate` 和 `deploy`，但 `restart` / `snapshot` / `vault_sync` 仍由 operator 手动执行
- 本 checklist 是纪律约束，不由 plugin 或 wrapper 自动执行
- 每次 deploy 操作必须在一个操作窗口内完成所有步骤

---

## Preconditions

- [ ] 候选文件已存在于 `/var/lib/openclaw/approvals/candidates/`
- [ ] 候选文件 SHA256 已计算并记录
- [ ] operator 确认当前系统健康（gateway + broker active）
- [ ] operator 确认当前不在另一个未关闭的变更窗口中

## Phase 1: Pre-snapshot

- [ ] operator: 创建 pre-change snapshot
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

- [ ] operator: `sudo systemctl restart openclaw-gateway.service`
- [ ] operator: `systemctl is-active openclaw-gateway.service` → `active`
- [ ] operator: `systemctl is-active openclaw-broker.service` → `active`

## Phase 5: Health Gate

- [ ] agent: `host_ops(action: "gateway_health")` → 确认 `ok: true`
- [ ] operator: 检查 gateway journal 无 config validation errors
  ```bash
  sudo journalctl -u openclaw-gateway.service -n 30 --no-pager
  ```

## Phase 6: Post-snapshot & Close

- [ ] operator: 创建 post-change snapshot
  ```bash
  sudo btrfs subvolume snapshot -r / /.snapshots/root-post-deploy-YYYYMMDD-HHMM
  ```
- [ ] operator: vault_sync（可选，手动）
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
