# `/var/lib/openclaw` 选择性控制面备份草案

> 草案日期：2026-03-09
> 上游参考：`docs/host-sop.md`（2026-03-07 Phase 1A 修订版）、`docs/design-v3.md`（v3.1）
> 状态：**草案（draft）**——仅提供分类与恢复语义框架，不含实施脚本
> 前提：Phase 1A 已落地，Phase 1B workspace-main 模板/发布/校验链已形成候选闭环

---

## 0. 核心前提

1. `/var/lib/openclaw` 是独立 Btrfs 子卷（Subvolume ID: 260），**不被根 `/` 快照递归覆盖**。
2. 根快照链（`/.snapshots/root-*` → Vault `recv/system/`）保护 `/etc/openclaw`、`/opt/openclaw`、systemd unit/drop-in、备份脚本等根系统组件，但**不保护** `/var/lib/openclaw` 内的任何内容。
3. `workspace-main` 是由开发仓库发布出来的**可重建 artifact**，不是根快照可恢复的长期真相源。
4. 因此需要一套独立于根快照的、面向 `/var/lib/openclaw` 的选择性备份策略。

---

## 1. 三类分类

### 类别 A：必须备份的控制面状态

这些是运行过程中由 `main` agent 或 gateway 产生的、**无法通过 publish 重建**的状态数据。丢失后意味着审批链断裂、健康基线丢失、或任务索引不可恢复。

| 路径 | 说明 |
|------|------|
| `.openclaw/workspace-main/control/state/pending-approvals.json` | 待审批队列；丢失后审批链断裂 |
| `.openclaw/workspace-main/control/state/last-health.md` | 最近一次健康检查结果；丢失后基线缺失 |
| `.openclaw/workspace-main/control/state/last-sop-hash.txt` | SOP 哈希校验值；丢失后无法判断 SOP 是否漂移 |
| `.openclaw/workspace-main/control/state/last-task-index.json` | 任务索引；丢失后任务追踪中断 |
| `.openclaw/extensions/` | 已部署插件（含 `openclaw.plugin.json` 与 `node_modules`）；非系统包管理器管理，且可能含本地修改 |
| `backup/last_sent` | 根快照增量备份的父快照指针；丢失后下次 Vault 入库退化为全量 send |
| `backup/openclaw-host-audit-*.txt` | 审计快照文件；丢失后审计链不完整 |

**分类理由**：这些文件要么记录不可重演的运行时决策（审批、健康、任务索引），要么记录无法从其他源自动重建的已部署插件状态。它们的共同特征是：**丢失后不存在一条从开发仓 `publish` 就能完全恢复的路径**。

### 类别 B：可由发布/重建恢复的内容

这些是 `workspace-main` 中的静态模板文件和控制面文档。它们的权威源在开发仓库（`~/projects/openclaw-dev/`），可以通过 publish 脚本重新发布到运行态目录。

| 路径 | 恢复方式 |
|------|----------|
| `.openclaw/workspace-main/AGENTS.md` | 从开发仓 `workspace-main/` 模板重新 publish |
| `.openclaw/workspace-main/TOOLS.md` | 同上 |
| `.openclaw/workspace-main/SOUL.md` | 同上 |
| `.openclaw/workspace-main/IDENTITY.md` | 同上 |
| `.openclaw/workspace-main/USER.md` | 同上 |
| `.openclaw/workspace-main/HEARTBEAT.md` | 同上 |
| `.openclaw/workspace-main/skills/**` | 同上 |
| `.openclaw/workspace-main/control/SOP.md` | 从开发仓 `docs/host-sop.md` 经 `publish-sop.sh` 发布 |
| `.openclaw/workspace-main/control/routing-policy.md` | 从开发仓 publish |
| `.openclaw/workspace-main/control/approval-policy.md` | 同上 |
| `.openclaw/workspace-main/control/allowed-workers.md` | 同上 |
| `.openclaw/workspace-main/control/host-ops-api.md` | 同上 |
| `.openclaw/workspace-main/control/runbooks/**` | 同上 |

**分类理由**：这些文件在开发仓库中有版本化的权威源副本。运行态目录中的版本只是发布产物。恢复时应重新执行 publish 流程而不是从备份还原——这样能确保恢复后的内容与权威源一致，避免恢复出过时版本。

### 类别 C：高 churn、应排除的运行态内容

这些是高频变动、体积可能较大、且恢复价值较低的临时运行态数据。将它们纳入频繁备份会浪费空间且增加快照差异噪声。

| 路径 | 排除理由 |
|------|----------|
| `.openclaw/workspace-main/memory/**` | 临时 session memory；高 churn，可在 agent 重新运行中自然积累 |
| `.openclaw/workspace-main/MEMORY.md` | 同上；若需要保留关键记忆，应提升到 control/state |
| `.openclaw/workspace/` | gateway 默认 workspace 目录；由 systemd `ExecStartPre` 自动创建 |
| `.openclaw/credentials/` | 运行时凭证缓存；由 systemd `ExecStartPre` 自动创建，凭证源在 `/etc/openclaw/openclaw.env` |
| `.openclaw/workspace-task-runner/tasks/*/` | 未来 task-runner 的临时任务目录；按设计应为可丢弃 |
| 未来可能出现的 canvas / 临时 session 产物 | 临时 UI 产物；不承载长期控制面价值 |
| `.openclaw/cron/` 中的执行日志全文（若启用） | 高频运行日志；索引/元数据属于类别 A，但全文日志属于此类 |

**分类理由**：这些文件的共同特征是**高频写入 + 低恢复价值**。即使全部丢失，系统可以通过重启 gateway、重新执行 publish、重新运行 agent 对话来恢复到可用状态。将它们纳入备份只会导致快照膨胀和备份窗口延长，收益不匹配。

---

## 2. 恢复语义

### 2.1 workspace-main 静态模板文件

恢复方式：**通过开发仓 publish 脚本重新发布**

```
开发仓 ~/projects/openclaw-dev/workspace-main/
  → publish 脚本（scripts/publish-workspace-main.sh）
  → /var/lib/openclaw/.openclaw/workspace-main/
```

不依赖从备份还原。publish 脚本确保目标目录与开发仓模板一致。

### 2.2 control/SOP.md

恢复方式：**从开发仓发布**

```
~/projects/openclaw-dev/docs/host-sop.md
  → publish-sop.sh
  → workspace-main/control/SOP.md
```

SOP 的权威编辑入口在开发仓 `~/projects/openclaw-dev/docs/host-sop.md`，不在运行时目录。

### 2.3 control/state/* 控制面状态

恢复方式：**从备份还原**

这些文件记录 `main` agent 运行期间产生的决策与状态，没有外部权威源可以重建。若丢失，应从最近一次控制面备份还原。

### 2.4 extensions/ 已部署插件

恢复方式：**优先从备份还原 + 验证 manifest**

已部署插件可能包含本地修改或本地 `npm install` 生成的 `node_modules`。若丢失：
1. 优先从备份还原整个 `extensions/` 目录；
2. 还原后验证每个子目录均含有效 `openclaw.plugin.json`（否则 gateway 会拒绝启动）；
3. 若备份不可用，则需要从开发仓的 plugin 源码重新 build + deploy。

### 2.5 backup/ 备份元数据

恢复方式：**从备份还原 `last_sent`**

`last_sent` 丢失后，下次 `vault-backup-root-btrfs` 将退化为全量 `btrfs send`（非增量）。这不会导致数据丢失，但会显著增加 Vault 入库耗时和空间占用。

### 2.6 根系统组件（不在本文档范围）

`/etc/openclaw/openclaw.json`、`/opt/openclaw`、systemd unit/drop-in、`/usr/local/sbin/vault-backup-root-btrfs` 等由根快照链保护，恢复方式是回滚根快照或从 Vault 恢复。本文档不覆盖此类恢复。

---

## 3. 备份策略概要（设计目标，非实施方案）

### 3.1 备份范围

仅备份**类别 A**中列出的路径。类别 B 通过 publish 恢复，类别 C 默认不备份。

### 3.2 备份方法候选

| 方法 | 优点 | 缺点 |
|------|------|------|
| 对 `/var/lib/openclaw` 子卷做 btrfs 只读快照 + 选择性 send | 与根快照链机制统一；可增量 | 粒度粗（整个子卷），包含类别 C 噪声 |
| 基于路径白名单的 rsync/tar 导出到 Vault | 精确控制备份范围；排除噪声 | 需要额外脚本维护路径列表；非原子性 |
| 混合方案：子卷快照做兜底 + 白名单导出做精确恢复源 | 兼具原子性和精确性 | 复杂度最高 |

### 3.3 建议优先顺序

1. **短期**：先实现基于路径白名单的 tar/rsync 导出，覆盖类别 A 所有路径；
2. **中期**：评估是否需要对 `/var/lib/openclaw` 子卷做独立的 btrfs 快照链；
3. **长期**：若 task-runner 上线后 `/var/lib/openclaw` 增长显著，考虑进一步子卷拆分。

### 3.4 触发时机

- 每次 publish workspace-main 之后；
- 每次 gateway restart 验证成功之后；
- 每日定时（与根快照定时对齐或错开）；
- 每次手动触发里程碑快照时。

### 3.5 存储位置

候选：
- Vault 盘（`/mnt/vault/recv/openclaw-state/`）——与根快照入库共用 Vault 盘，但使用独立接收目录
- 注意：Vault 盘为 noauto 离线策略，备份脚本需要在窗口期挂载/卸载

---

## 4. 当前仍待后续 Phase 完成的事项

### 4.1 Phase 1B 剩余

- [ ] publish 脚本（`scripts/publish-workspace-main.sh`）已形成候选闭环但尚未在现网执行首次发布
- [ ] 基于本草案的控制面备份脚本尚未编写
- [ ] `last-sop-hash.txt` 的自动更新机制尚未实施（当前为模板初始值）

### 4.2 Phase 2 依赖

- [ ] `host-ops broker` 上线后将新增 broker 状态目录（如 `broker/request-log/`、`broker/audit-index/`），需要纳入类别 A
- [ ] wrapper 链上线后将新增 wrapper 审计索引，需要纳入类别 A
- [ ] `cron/` 元数据（若启用）需要区分索引（类别 A）和执行日志全文（类别 C）

### 4.3 Phase 3+ 依赖

- [ ] `task-runner` 上线后，`workspace-task-runner/tasks/` 目录的生命周期管理（创建 → 归档 → 清理）需要独立设计，不应纳入本备份方案
- [ ] Docker sandbox 若涉及持久化 volume，其备份策略独立于本文档

### 4.4 尚未决定

- [ ] 是否对 `/var/lib/openclaw` 子卷做独立 btrfs 快照链（区别于路径白名单导出）
- [ ] 备份保留策略（保留多少份、何时轮转）
- [ ] 控制面备份脚本是否复用现有 `vault-backup-root-btrfs` 的 Vault 挂载/卸载逻辑，还是独立实现

---

## 5. 与现有备份链的关系

```
现有根快照链（不变）：
  /.snapshots/root-* → Vault recv/system/
  保护：/etc/openclaw、/opt/openclaw、systemd、备份脚本

本草案新增（待实施）：
  /var/lib/openclaw 选择性导出 → Vault recv/openclaw-state/
  保护：control/state/*、extensions/、backup/last_sent、审计文件

不需要备份（靠 publish 恢复）：
  workspace-main 静态模板、SOP 副本、skills、runbooks

不需要备份（临时运行态）：
  memory/、临时 session、task-runner 任务目录、credentials 缓存
```

两条备份链并行，互不干扰。根快照链继续保护根系统组件；选择性导出链保护 `/var/lib/openclaw` 中的控制面状态。
