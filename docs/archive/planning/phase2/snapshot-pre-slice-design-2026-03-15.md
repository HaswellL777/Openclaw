# snapshot_pre — 下一安全切片实施设计

> 文档类型：**设计 / planning note**
> 创建日期：2026-03-15
> 作者：nick + ClaudeCode
> 前置完成：`gateway_health` E2E live verified, `validate_openclaw_json_candidate` E2E live verified, `deploy_openclaw_json_candidate` live E2E verified (Route C)
> 目标：为 `snapshot_pre` 的 agent-facing 开放建立严谨的实施方案
> 状态：**repo-side 实施完成（2026-03-15）— 待 live activation**
>
> - repo-side：plugin 代码已提交，docs/scaffold 已同步
> - live-side：待 operator 执行 plugin sync + gateway restart + E2E 验收
> - 其余 4 个 action（`gateway_restart`, `snapshot_post`, `vault_sync`, `rollback_prepare`）仍未 agent-facing 开放
> - snapshot_pre 的成功不代表 snapshot workflow 闭环

---

## 1. 当前真实边界

### 1.1 已 live verified（3 个）

| Action | 类型 | 验证日期 | Evidence |
|--------|------|----------|----------|
| `gateway_health` | 只读 | 2026-03-15 | E2E 成功 |
| `validate_openclaw_json_candidate` | 只读 | 2026-03-15 | E2E 成功（正例 + 负例） |
| `deploy_openclaw_json_candidate` | 写操作 | 2026-03-15 | Route C live E2E verified（正例 + 负例含 wrapper 侧 + 回归通过） |

### 1.2 仍未开放（5 个）

| Action | 类型 | 当前状态 |
|--------|------|----------|
| `gateway_restart` | 写操作 | **未开放** — 当前文档已记录返回值/契约语义不稳问题（见下文 §2.2） |
| `snapshot_pre` | 写操作（创建只读快照） | **本轮 repo-side ready，待 live activation** |
| `snapshot_post` | 写操作（创建只读快照） | 未开放 |
| `vault_sync` | 写操作 | 未开放 |
| `rollback_prepare` | 写操作 | 未开放 |

---

## 2. 为什么下一 slice 是 snapshot_pre

### 2.1 snapshot_pre 的优势

1. **副作用最小**：创建只读 btrfs 快照，不修改任何现有状态，不删除任何内容
2. **成功定义最清晰**：wrapper 返回 `ok: true` + operator 确认 `/.snapshots/root-pre-{label}` 存在且为只读
3. **验收路径最干净**：正例（创建快照）+ 负例（label 非法、缺失 reason）+ 回归（已有 3 个 action 仍正常）
4. **rollback 最简单**：如果 snapshot 本身不需要，`btrfs subvolume delete` 即可清理（但测试生成的 snapshot 应作为审计痕迹保留）
5. **不修改 `/etc/openclaw/openclaw.json`**：启用由 plugin 代码 `ENABLED_ACTIONS` 控制，不涉及 config 字段变更
6. **不需要 candidate workflow**：与 validate/deploy slice 激活模式完全一致
7. **代码改动最小**：`validateActionInputs()` 已实现、wrapper 已就绪、schema 已冻结，仅需加入 `ENABLED_ACTIONS` + 更新文案

### 2.2 为什么不是 gateway_restart

`gateway_restart` 虽然业务价值高（deploy 后需要 restart 使配置生效），但当前权威文档已记录其契约语义不稳问题：

> **`docs/host-sop.md` 第 765 行**：因 `Requires=openclaw-gateway.service`，当 gateway 被重启时 broker 也会被 SIGTERM 并由 systemd 重启。通过 broker 发送 `gateway_restart` 请求时，broker 自身的请求返回值可能为 `E_BROKER_INTERNAL`，此时应以 gateway + broker 的 post-restart 状态作为成功判据，而非 broker 请求返回值。

这意味着：
- `gateway_restart` 的成功判定不能仅依赖 broker 返回值
- 需要额外设计"broker 重启后的健康探测"机制
- 这超出了"最小切片"的复杂度预算

**结论**：`gateway_restart` 不是无价值，而是需要先单独解决其返回值契约问题，不适合作为本轮的"最稳妥下一 slice"。

### 2.3 为什么不是其他 3 个

| Action | 排除原因 |
|--------|----------|
| `snapshot_post` | 与 `snapshot_pre` 技术实现几乎相同，但在 pre 尚未验证时开放 post 没有独立意义 |
| `vault_sync` | 依赖 Vault 挂载（`/mnt/vault`, `noauto`），运行时条件更复杂，副作用更大 |
| `rollback_prepare` | 依赖已存在的 snapshot，且涉及恢复操作的风险评估，不适合作为第一个 snapshot 类 action |

---

## 3. 三层边界定义

### 3.1 repo-side 边界

- `ENABLED_ACTIONS` 从 3 个扩展为 4 个：加入 `snapshot_pre`
- Tool description / action description / enum 文案同步
- `snapshot_post`, `vault_sync`, `rollback_prepare`, `gateway_restart` 仍不在 `ENABLED_ACTIONS`
- 文档与 scaffold 已同步
- `openclaw.live.json` 未进入版本控制

### 3.2 live-side 边界（待 operator 执行）

- 当前 live plugin 仍为 deploy slice 版本（ENABLED_ACTIONS = 3 个）
- 需 operator 执行 plugin sync + gateway restart
- 需 fresh session 获取新 tool schema（enum 从 3 扩展为 4）
- broker daemon 和 8 个 wrapper 无需变更（wrapper 已部署为 production 版本）

### 3.3 agent-facing 边界（待 live E2E 验证）

- agent 调用 `host_ops(action: "snapshot_pre", inputs: { label: "...", reason: "..." })` 应返回结构化 success
- 非 enabled action 仍应被 `status: "denied"` 拒绝
- 已有 3 个 action 的回归必须通过

---

## 4. 验收口径

### 4.1 repo-side 验收（本轮完成）

- [x] `snapshot_pre` 已加入 `ENABLED_ACTIONS`
- [x] 其余 4 个 action 仍未加入
- [x] description / enum / action 文案同步
- [x] planning 文档已创建
- [x] activation record scaffold 已创建
- [x] 文档同步（host-sop, design-v3, host-ops-api）
- [x] `openclaw.live.json` 未进入版本控制

### 4.2 live-side 验收（模板）

- [ ] live plugin 已备份（`/var/lib/openclaw/host-ops-tool-backups/index.js.bak-pre-snapshot-pre-slice`）
- [ ] 新版 plugin 已同步到 `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js`
- [ ] `chown openclaw:openclaw` + `chmod 644` 已执行
- [ ] `systemctl restart openclaw-gateway.service` 已执行
- [ ] `systemctl is-active openclaw-gateway.service` → `active`
- [ ] `systemctl is-active openclaw-broker.service` → `active`
- [ ] gateway journal 无 plugin/tool 注册错误
- [ ] agent 新 session 后可见 `snapshot_pre` 在 schema enum 中

### 4.3 agent-facing 验收（模板）

**正例**：
```
host_ops(action: "snapshot_pre", inputs: {
  label: "test-snapshot-pre-20260315",
  reason: "E2E verification of snapshot_pre agent slice"
})
```
- 返回 `ok: true`, `status: "ok"`
- `artifacts` 包含 `snapshot_name`, `snapshot_path`, `label`, `reason`
- operator 独立确认 `/.snapshots/root-pre-test-snapshot-pre-20260315` 存在且为只读

**负例**：
- label 非法字符（如 `"bad label!"`）→ plugin 侧拒绝
- 缺失 reason → plugin 侧拒绝
- inputs 非 object（如 `inputs: "string"`）→ execute 侧拒绝
- 顶层多余参数 → execute 侧拒绝
- 非 enabled action（如 `snapshot_post`）→ `status: "denied"`

**回归**：
- `gateway_health` 返回 `ok: true`
- `validate_openclaw_json_candidate` 正例仍正常
- `deploy_openclaw_json_candidate` 正例仍正常（如需，使用测试候选）

**边界声明**：
- 本轮即使 `snapshot_pre` 最终 live verified，也**不代表** snapshot workflow 闭环
- `snapshot_post` / `vault_sync` / `rollback_prepare` 仍未开放
- `gateway_restart` 仍未开放（待返回值契约问题独立收口）

---

## 5. Rollback 口径

### 5.1 首要 rollback：plugin 文件回滚

```bash
sudo cp /var/lib/openclaw/host-ops-tool-backups/index.js.bak-pre-snapshot-pre-slice \
        /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo systemctl restart openclaw-gateway.service
```

效果：回到仅 `gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` 可用的基线。

### 5.2 plugin 文件不在 root snapshot 保护范围内

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），**不在** root snapshot 保护范围内。因此 plugin 文件级备份是首要 rollback anchor，而非根快照。

### 5.3 测试 snapshot 的处理

测试生成的 snapshot 应作为审计痕迹保留，不把"删除测试 snapshot"写进成功定义。如确需清理，使用 `btrfs subvolume delete` 即可。

### 5.4 root snapshot 作为额外锚点

root snapshot 可作为 host 层额外锚点（保护 `/etc/openclaw/` 等），但不是 plugin rollback 的首要手段。

---

## 6. Operator checklist 要点

1. pre-change root snapshot（保护 host 层状态）
2. 备份当前 live plugin（到 `/var/lib/openclaw/host-ops-tool-backups/`）
3. 复制新版 index.js 到 live + chown/chmod
4. `systemctl restart openclaw-gateway.service`
5. 验证 gateway + broker 健康
6. fresh session / `/reset`
7. 正例 E2E
8. 负例 E2E
9. 回归 E2E（3 个已有 action）
10. post-change root snapshot
11. 可选 vault sync
12. 更新 activation record

---

## 7. 文档更新面

| 文档 | 更新内容 |
|------|----------|
| `plugins/host-ops-tool/index.js` | `ENABLED_ACTIONS` + description 文案 |
| `docs/planning/snapshot-pre-slice-design-2026-03-15.md` | 本文件（新增） |
| `docs/records/phase2-hostops-snapshot-pre-activation-2026-03-15.md` | Activation record scaffold（新增） |
| `docs/host-sop.md` | 边界声明同步 |
| `docs/design-v3.md` | 边界声明同步 |
| `workspace-main-template/control/host-ops-api.md` | ENABLED_ACTIONS 列表 + Phase 1 workaround 更新 |

---

## 8. Commit 计划

1. `docs(planning): add snapshot_pre slice design and pre-implementation boundary`
2. `feat(host-ops-tool): enable snapshot_pre agent slice`
3. `docs(records): add snapshot_pre activation scaffold`
4. `docs: sync snapshot_pre boundary across authority docs`

---

## 9. 未验证事项

- [ ] live plugin sync 尚未执行
- [ ] live E2E 尚未执行
- [ ] 测试 snapshot 的实际创建尚未验证
- [ ] snapshot_pre 返回的 snapshot_path 是否正确可访问尚未在 live 验证
- [ ] gateway_restart 的返回值契约问题尚未独立收口
- [ ] snapshot workflow 闭环（pre → change → post → vault）尚未实现
- [ ] `openclaw.live.json` 未加入 `.gitignore`（本轮不扩 scope，仅报告）

---

## 10. Rejected Alternatives

### 10.1 先开放 gateway_restart

**被拒绝**：当前 `docs/host-sop.md` 已明确记录 gateway_restart 通过 broker 调用时返回值可能为 `E_BROKER_INTERNAL`（因 broker 与 gateway 的 systemd `Requires` 依赖导致 broker 也会被重启）。在该契约语义问题未独立收口前，不作为下一最稳妥 slice。

### 10.2 同时开放 snapshot_pre + snapshot_post

**被拒绝**：一次开放两个 action 违反了"最少一次性扩大 action 暴露面"的原则。snapshot_pre 应先独立验证，确认 wrapper 输出、label 生成、只读快照创建等在 live 环境下的行为符合预期后，再考虑 snapshot_post。

### 10.3 跳过 snapshot 直接开放 vault_sync

**被拒绝**：vault_sync 依赖 Vault 挂载（`/mnt/vault`, `noauto`），运行时条件更复杂。snapshot_pre 更简单、副作用更小。
