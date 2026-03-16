# snapshot_post — 下一安全切片实施设计

> 文档类型：**设计 / planning note**
> 创建日期：2026-03-16
> 作者：nick + ClaudeCode
> 前置完成：`gateway_health` E2E live verified, `validate_openclaw_json_candidate` E2E live verified, `deploy_openclaw_json_candidate` live E2E verified (Route C), `snapshot_pre` live E2E verified
> 目标：为 `snapshot_post` 的 agent-facing 开放建立严谨的实施方案
> 状态：**repo-side 实施完成（2026-03-16）— 待 live activation**
>
> - repo-side：plugin 代码已提交，activation/rollback 脚本已就绪
> - live-side：待 operator 执行 plugin sync + gateway restart + E2E 验收
> - 其余 3 个 action（`gateway_restart`, `vault_sync`, `rollback_prepare`）仍未 agent-facing 开放
> - snapshot_post 的成功不代表 snapshot workflow 完整闭环，也不代表 host_ops 全量开放

---

## 1. 当前真实边界

### 1.1 已 live verified（4 个）

| Action | 类型 | 验证日期 | Evidence |
|--------|------|----------|----------|
| `gateway_health` | 只读 | 2026-03-15 | E2E 成功 |
| `validate_openclaw_json_candidate` | 只读 | 2026-03-15 | E2E 成功（正例 + 负例） |
| `deploy_openclaw_json_candidate` | 写操作 | 2026-03-15 | Route C live E2E verified（正例 + 负例含 wrapper 侧 + 回归通过） |
| `snapshot_pre` | 写操作（创建只读快照） | 2026-03-16 | live E2E verified（正例 + 负例 + 回归通过） |

### 1.2 仍未开放（4 个）

| Action | 类型 | 当前状态 |
|--------|------|----------|
| `gateway_restart` | 写操作 | **未开放** — 返回语义不稳，依赖链根因待独立复核 |
| `snapshot_post` | 写操作（创建只读快照） | **本轮 repo-side ready，待 live activation** |
| `vault_sync` | 写操作 | 未开放 — 权威文档的 Vault receive 路径与 wrapper 代码存在漂移；`incremental` 目前是接口层宣称存在，但实现层未体现真正 incremental send 机制 |
| `rollback_prepare` | 写操作 | 未开放 — 当前返回的 `rollback_steps` 语义过强，容易被误读为已验证的完整恢复计划，但当前系统边界下 root snapshot 不等于 OpenClaw 全运行态恢复（`/var/lib/openclaw` 为独立 btrfs 子卷） |

---

## 2. 为什么下一 slice 是 snapshot_post

### 2.1 snapshot_post 的优势

1. **与 snapshot_pre 代码结构高度对称**：wrapper（`ocw-snapshot-post.sh`）、schema（`snapshot-post.schema.json`）、plugin 校验逻辑（共用 `case` 分支）均与 snapshot_pre 同构
2. **副作用最小**：创建只读 btrfs 快照，不修改任何现有状态，不删除任何内容
3. **成功定义最清晰**：wrapper 返回 `ok: true` + operator 确认 `/.snapshots/root-post-{label}` 存在且为只读
4. **代码改动最小**：仅需加入 `ENABLED_ACTIONS` + 更新描述文案，无逻辑变更
5. **不修改 `/etc/openclaw/openclaw.json`**：启用由 plugin 代码 `ENABLED_ACTIONS` 控制
6. **rollback 最简单**：恢复 plugin 备份 + restart gateway 即可

### 2.2 snapshot_post 与 snapshot_pre 的关系

- `snapshot_post` 因结构对称、改动面小、风险低，适合作为下一 slice
- 但 snapshot_pre 的成功**不代表** snapshot_post 已被间接验证，snapshot_post 必须独立完成 live E2E
- 两者共用 `validateActionInputs()` 的 `case` 分支，但 wrapper 执行路径独立（`ocw-snapshot-post.sh` vs `ocw-snapshot-pre.sh`），snapshot 命名前缀不同（`root-post-` vs `root-pre-`）

### 2.3 为什么不是其他 3 个

| Action | 不选原因 |
|--------|----------|
| `gateway_restart` | 返回语义不稳，依赖链根因待独立复核。需先解决其契约语义问题，不适合作为当前最稳妥的下一 slice |
| `vault_sync` | 权威文档的 Vault receive 路径（`/mnt/vault/recv/system`）与 wrapper 代码存在漂移；`incremental` 在接口层宣称存在但实现层未体现真正 incremental send 机制；依赖 Vault 挂载（`/mnt/vault`, `noauto`），运行时条件更复杂 |
| `rollback_prepare` | 当前返回的 `rollback_steps` 语义过强，容易被误读为已验证的完整恢复计划；当前系统边界下 root snapshot 不等于 OpenClaw 全运行态恢复（`/var/lib/openclaw` 为独立 btrfs 子卷） |

---

## 3. 三层边界定义

### 3.1 repo-side 边界

- `ENABLED_ACTIONS` 从 4 个扩展为 5 个：加入 `snapshot_post`
- Tool description / action description / enum / inputs 描述文案同步
- `vault_sync`, `rollback_prepare`, `gateway_restart` 仍不在 `ENABLED_ACTIONS`
- `openclaw.live.json` 未进入版本控制

### 3.2 live-side 边界（待 operator 执行）

- 当前 live plugin 仍为 snapshot_pre slice 版本（ENABLED_ACTIONS = 4 个）
- 需 operator 执行 plugin sync + gateway restart
- 需 fresh session 获取新 tool schema（enum 从 4 扩展为 5）
- broker daemon 和 8 个 wrapper 无需变更（wrapper 已部署为 production 版本）

### 3.3 agent-facing 边界（待 live E2E 验证）

- agent 调用 `host_ops(action: "snapshot_post", inputs: { label: "...", reason: "..." })` 应返回结构化 success
- 非 enabled action 仍应被 `status: "denied"` 拒绝
- 已有 4 个 action 的回归必须通过

---

## 4. 验收口径

### 4.1 repo-side 验收（本轮完成）

- [x] `snapshot_post` 已加入 `ENABLED_ACTIONS`
- [x] 其余 3 个 action 仍未加入
- [x] description / enum / inputs 文案同步
- [x] activation / rollback 脚本已创建
- [x] planning 文档已创建
- [x] `openclaw.live.json` 未进入版本控制

### 4.2 live-side 验收（模板）

- [ ] live plugin 已备份
- [ ] 新版 plugin 已同步到 live 路径
- [ ] `chown openclaw:openclaw` + `chmod 644` 已执行
- [ ] `systemctl restart openclaw-gateway.service` 已执行
- [ ] `systemctl is-active openclaw-gateway.service` → `active`
- [ ] `systemctl is-active openclaw-broker.service` → `active`
- [ ] gateway journal 无 plugin/tool 注册错误
- [ ] agent 新 session 后可见 `snapshot_post` 在 schema enum 中

### 4.3 agent-facing 验收（模板）

**正例**：
```
host_ops(action: "snapshot_post", inputs: {
  label: "e2e-snapshot-post-20260316",
  reason: "E2E verification of snapshot_post agent slice"
})
```
- 返回 `ok: true`, `status: "ok"`
- operator 独立确认 `/.snapshots/root-post-e2e-snapshot-post-20260316` 存在且为只读

**负例**（预期均被拒绝/校验失败，正式 record 以实际返回值为准）：
- 非法 label（如 `"bad label!"`）
- 缺失 reason
- inputs 非 object（如 `inputs: "string"`）
- 顶层多余参数
- 非 enabled action（如 `vault_sync`）→ 预期 denied

**回归**：
- `gateway_health` 返回 `ok: true`
- `snapshot_pre` 返回 `ok: true`

**验收表述纪律**：
- 不得将 `snapshot_post` 成功写成 "host_ops 已完整开放"
- 不得将 `snapshot_post` 成功写成 "snapshot workflow 已完整闭环"
- 只能写：`snapshot_post` 已 live E2E verified；`vault_sync` / `gateway_restart` / `rollback_prepare` 仍未开放

---

## 5. Rollback 口径

### 5.1 首要 rollback：plugin 文件回滚

使用 rollback 脚本：
```bash
sudo bash scripts/rollback-snapshot-post-slice.sh <artifacts-dir>
```

或手动：
```bash
sudo cp <backup-file> /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chown openclaw:openclaw /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo chmod 644 /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js
sudo systemctl restart openclaw-gateway.service
```

效果：回到 `gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` + `snapshot_pre` 可用的基线。

### 5.2 plugin 文件不在 root snapshot 保护范围内

plugin 文件位于 `/var/lib/openclaw`（独立 btrfs 子卷），**不在** root snapshot 保护范围内。plugin 文件级备份是首要 rollback anchor，root snapshot 不能作为 plugin 状态恢复的充分手段。

### 5.3 测试 snapshot 的处理

测试生成的 snapshot 应作为审计痕迹保留，不把"删除测试 snapshot"写进成功定义。

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
8. 负例 E2E（至少 5 个）
9. 回归 E2E（gateway_health + snapshot_pre）
10. post-change root snapshot
11. 可选 vault sync
12. 更新 activation record

或使用一键脚本：`sudo bash scripts/activate-snapshot-post-slice.sh`（完成步骤 1-5 + 10）

---

## 7. 文档更新面

| 文档 | 更新内容 |
|------|----------|
| `plugins/host-ops-tool/index.js` | `ENABLED_ACTIONS` + description 文案 |
| `scripts/activate-snapshot-post-slice.sh` | Activation 脚本（新增） |
| `scripts/rollback-snapshot-post-slice.sh` | Rollback 脚本（新增） |
| `docs/planning/snapshot-post-slice-design-2026-03-16.md` | 本文件（新增） |
| `docs/records/phase2-hostops-snapshot-post-activation-2026-03-16.md` | Activation record（待 E2E 后新增） |
| `docs/host-sop.md` | 边界声明同步（待 E2E 后） |
| `docs/design-v3.md` | 边界声明同步（待 E2E 后） |
| `workspace-main-template/control/host-ops-api.md` | ENABLED_ACTIONS 列表 + Phase 1 workaround 更新（待 E2E 后） |

---

## 8. Commit 计划

1. `feat(host-ops-tool): enable snapshot_post agent slice`
   - `plugins/host-ops-tool/index.js`
   - `scripts/activate-snapshot-post-slice.sh`
   - `scripts/rollback-snapshot-post-slice.sh`
   - `docs/planning/snapshot-post-slice-design-2026-03-16.md`

2. `docs: complete snapshot_post live E2E verified and sync boundary`（待 E2E 后）
   - activation record
   - `docs/host-sop.md`
   - `docs/design-v3.md`
   - `workspace-main-template/control/host-ops-api.md`

Planning 文档与代码+脚本合并为一个 commit 的原因：planning 是 repo-side 实施阶段的交付物，与代码和脚本属于同一实施窗口，分拆没有独立的审计意义。

---

## 9. 未验证事项

- [ ] live plugin sync 尚未执行
- [ ] live E2E 尚未执行
- [ ] snapshot_post 创建的 snapshot 路径是否正确可访问尚未在 live 验证
- [ ] `broker/wrappers/lib/common.sh` 已针对 snapshot_post 用途复核，但未做全量逐行审计
- [ ] `gateway_restart` 返回语义不稳问题仍待独立复核
- [ ] `vault_sync` Vault receive 路径漂移 + incremental 机制问题未处理
- [ ] `rollback_prepare` rollback_steps 语义过强问题未处理
- [ ] snapshot workflow 闭环（pre → change → post → vault）尚未完整实现
- [ ] `openclaw.live.json` 未加入 `.gitignore`（本轮不扩 scope）
