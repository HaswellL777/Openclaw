# `/var/lib/openclaw` 选择性控制面备份设计稿

> 初稿日期：2026-03-09
> 本次修订日期：2026-03-10
> 上游参考：`docs/host-sop.md`（2026-03-09 Phase 1A+1B(dev) 修订版）、`docs/design-v3.md`（v3.1）
> 状态：**设计定稿候选（design candidate）**——分类模型、恢复语义、实施约束已结构化，但尚未转化为可执行脚本，也未在生产中启用
> 前提：Phase 1A 已落地，Phase 1B workspace-main 模板/发布/校验链已形成候选闭环

---

## 0. 文档定位与范围

### 0.1 文档定位

本文档是 `/var/lib/openclaw` 运行态控制面备份方案的**设计定稿候选**。

它不是：
- 生产就绪的备份脚本或 runbook
- 已在现网验证的实施方案
- 根快照链的替代方案

它是：
- 分类模型、恢复语义、实施约束的结构化设计参考
- 后续将 backup draft 转化为可执行脚本时的设计输入
- 在整个 Phase 1B → Phase 6 过程中持续演进的活文档

### 0.2 范围声明

本文档**仅讨论** `/var/lib/openclaw` 子卷内运行态控制面的选择性备份策略。

**在范围内：**
- `/var/lib/openclaw/.openclaw/` 下的控制面状态、已部署插件、备份元数据
- 上述内容的分类、恢复语义、恢复优先级
- 后续实现约束与验收条件

**不在范围内：**
- 根 `/` 快照链（已有 `vault-backup-root-btrfs` 覆盖，见 `host-sop.md` §5 / §13.7.1）
- `/etc/openclaw`、`/opt/openclaw`、systemd unit/drop-in（由根快照链保护）
- Vault 盘本身的冗余或异地备份
- broker / wrapper / task-runner / Docker 执行面的实现（这些是后续 Phase 的工作）

---

## 1. 核心前提

1. `/var/lib/openclaw` 是独立 Btrfs 子卷（Subvolume ID: 260），**不被根 `/` 快照递归覆盖**。
2. 根快照链（`/.snapshots/root-*` → Vault `recv/system/`）保护 `/etc/openclaw`、`/opt/openclaw`、systemd unit/drop-in、备份脚本等根系统组件，但**不保护** `/var/lib/openclaw` 内的任何内容。
3. `workspace-main` 是由开发仓库发布出来的**可重建 artifact**，不是根快照可恢复的长期真相源。
4. 因此需要一套独立于根快照的、面向 `/var/lib/openclaw` 的选择性备份策略。

---

## 2. 三类分类模型

### 类别 A：必须备份的控制面状态

这些是运行过程中由 `main` agent 或 gateway 产生的、**无法通过 publish 重建**的状态数据。丢失后意味着审批链断裂、健康基线丢失、或任务索引不可恢复。

| 路径 | 说明 | 分类理由 | 恢复方式 | 恢复时注意事项 |
|------|------|----------|----------|----------------|
| `.openclaw/workspace-main/control/state/pending-approvals.json` | 待审批队列 | 记录不可重演的运行时审批决策 | 从备份还原 | 还原后需核实队列中引用的 task-id 是否仍有效；若 gateway 已跨越还原点运行过新审批，可能产生冲突 |
| `.openclaw/workspace-main/control/state/last-health.md` | 最近一次健康检查结果 | 唯一的健康基线快照 | 从备份还原 | 还原后应立即执行一次新的 health check 以刷新基线 |
| `.openclaw/workspace-main/control/state/last-sop-hash.txt` | SOP 哈希校验值 | 判断 SOP 是否漂移的唯一依据 | 从备份还原；或重新执行 `publish-sop.sh` 以重算 | 若选择重算而非还原，需确认开发仓 `docs/host-sop.md` 是当前权威版本 |
| `.openclaw/workspace-main/control/state/last-task-index.json` | 任务索引 | 记录已创建任务的历史索引 | 从备份还原 | 丢失后任务追踪中断；无法从其他源自动重建已完成任务的记录 |
| `.openclaw/extensions/` | 已部署插件（含 `openclaw.plugin.json` 与 `node_modules`） | 非系统包管理器管理，可能含本地修改 | 优先从备份还原整个目录；还原后验证每个子目录均含有效 `openclaw.plugin.json` | 若备份不可用，需要从开发仓 plugin 源码重新 build + deploy；还原后必须 restart gateway 并验证 plugin 加载 |
| `backup/last_sent` | 根快照增量备份的父快照指针 | 增量 send/receive 依赖此文件 | 从备份还原 | 丢失后下次 `vault-backup-root-btrfs` 退化为全量 `btrfs send`（不会丢数据，但耗时和空间显著增加） |
| `backup/openclaw-host-audit-*.txt` | 审计快照文件 | 审计链完整性依赖 | 从备份还原 | 丢失后审计链不完整，但不影响系统运行 |

**分类共性**：这些文件要么记录不可重演的运行时决策（审批、健康、任务索引），要么记录无法从其他源自动重建的已部署状态。丢失后不存在一条从开发仓 `publish` 就能完全恢复的路径。

### 类别 B：可由发布/重建恢复的内容

这些是 `workspace-main` 中的静态模板文件和控制面文档。它们的权威源在开发仓库（`~/projects/openclaw-dev/`），可以通过 publish 脚本重新发布到运行态目录。

| 路径 | 恢复方式 | 恢复时注意事项 |
|------|----------|----------------|
| `.openclaw/workspace-main/AGENTS.md` | `publish-workspace-main.sh` 从开发仓模板重新 publish | 确认开发仓 `workspace-main-template/` 为最新版本 |
| `.openclaw/workspace-main/TOOLS.md` | 同上 | 同上 |
| `.openclaw/workspace-main/SOUL.md` | 同上 | 同上 |
| `.openclaw/workspace-main/IDENTITY.md` | 同上 | 同上 |
| `.openclaw/workspace-main/USER.md` | 同上 | 同上 |
| `.openclaw/workspace-main/HEARTBEAT.md` | 同上 | 同上 |
| `.openclaw/workspace-main/README.md` | 同上 | 同上 |
| `.openclaw/workspace-main/skills/**` | 同上 | 同上 |
| `.openclaw/workspace-main/control/SOP.md` | `publish-sop.sh` 从 `docs/host-sop.md` 发布 | 发布后 `last-sop-hash.txt` 自动更新 |
| `.openclaw/workspace-main/control/routing-policy.md` | `publish-workspace-main.sh` 从开发仓模板 publish | 确认开发仓模板为最新 |
| `.openclaw/workspace-main/control/approval-policy.md` | 同上 | 同上 |
| `.openclaw/workspace-main/control/allowed-workers.md` | 同上 | 同上 |
| `.openclaw/workspace-main/control/host-ops-api.md` | 同上 | 同上 |
| `.openclaw/workspace-main/control/runbooks/**` | 同上 | 同上 |

**分类理由**：这些文件在开发仓库中有版本化的权威源副本。运行态目录中的版本只是发布产物。恢复时应重新执行 publish 流程而不是从备份还原——这样能确保恢复后的内容与权威源一致，避免恢复出过时版本。

**恢复注意事项**：`publish-workspace-main.sh` 会保留 `control/state/` 目录（rsync `--exclude`），因此类别 B 的重新 publish 不会覆盖类别 A 的状态文件。这是设计上的关键保证。

### 类别 C：高 churn、应排除的运行态内容

这些是高频变动、体积可能较大、且恢复价值较低的临时运行态数据。将它们纳入频繁备份会浪费空间且增加快照差异噪声。

| 路径 | 排除理由 | 全丢后的影响 |
|------|----------|--------------|
| `.openclaw/workspace-main/memory/**` | 临时 session memory；高 churn | agent 会在后续对话中自然积累新记忆 |
| `.openclaw/workspace-main/MEMORY.md` | 同上 | 同上；若需保留关键记忆，应提升到 `control/state/` |
| `.openclaw/workspace/` | gateway 默认 workspace 目录 | 由 systemd `ExecStartPre` 自动创建 |
| `.openclaw/credentials/` | 运行时凭证缓存 | 由 systemd `ExecStartPre` 自动创建，凭证源在 `/etc/openclaw/openclaw.env` |
| `.openclaw/workspace-task-runner/tasks/*/` | 未来 task-runner 临时任务目录 | 按设计为可丢弃；完成的任务结果应已提交到外部仓库 |
| 未来可能出现的 canvas / 临时 session 产物 | 临时 UI 产物 | 不承载长期控制面价值 |
| `.openclaw/cron/` 中的执行日志全文（若启用） | 高频运行日志 | 索引/元数据属于类别 A，全文日志属于此类 |

**分类理由**：这些文件的共同特征是**高频写入 + 低恢复价值**。即使全部丢失，系统可以通过重启 gateway、重新执行 publish、重新运行 agent 对话来恢复到可用状态。

---

## 3. 恢复语义

### 3.1 workspace-main 静态模板文件（类别 B）

恢复方式：**通过开发仓 publish 脚本重新发布**

```
开发仓 ~/projects/openclaw-dev/workspace-main-template/
  → publish-workspace-main.sh --apply TARGET_DIR
  → /var/lib/openclaw/.openclaw/workspace-main/
```

不依赖从备份还原。publish 脚本确保目标目录与开发仓模板一致，同时保留 `control/state/`。

### 3.2 control/SOP.md（类别 B）

恢复方式：**从开发仓发布**

```
~/projects/openclaw-dev/docs/host-sop.md
  → publish-sop.sh --apply TARGET_DIR
  → workspace-main/control/SOP.md
  → workspace-main/control/state/last-sop-hash.txt（自动更新）
```

SOP 的权威编辑入口在开发仓 `~/projects/openclaw-dev/docs/host-sop.md`，不在运行时目录。publish-sop.sh 会自动附加发布头（authoritative source / 时间戳 / SHA256）。

### 3.3 control/state/* 控制面状态（类别 A）

恢复方式：**从备份还原**

这些文件记录 `main` agent 运行期间产生的决策与状态，没有外部权威源可以重建。若丢失，应从最近一次控制面备份还原。

特例：`last-sop-hash.txt` 虽然归属类别 A，但可以通过重新执行 `publish-sop.sh` 来重算。这使得它在备份不可用时有降级恢复路径。其他 `control/state/` 文件没有此降级路径。

### 3.4 extensions/ 已部署插件（类别 A）

恢复方式：**优先从备份还原 + 验证 manifest**

已部署插件可能包含本地修改或本地 `npm install` 生成的 `node_modules`。若丢失：
1. 优先从备份还原整个 `extensions/` 目录；
2. 还原后验证每个子目录均含有效 `openclaw.plugin.json`（否则 gateway 会拒绝启动——本机已实际踩过此坑，见 host-sop.md 禁止清单）；
3. 若备份不可用，则需要从开发仓的 plugin 源码重新 build + deploy；
4. 恢复后必须 restart gateway 并验证 plugin 注册日志。

### 3.5 backup/ 备份元数据（类别 A）

恢复方式：**从备份还原 `last_sent`**

`last_sent` 丢失后，下次 `vault-backup-root-btrfs` 将退化为全量 `btrfs send`（非增量）。这不会导致数据丢失，但会显著增加 Vault 入库耗时和空间占用。

### 3.6 根系统组件（不在本文档范围）

`/etc/openclaw/openclaw.json`、`/opt/openclaw`、systemd unit/drop-in、`/usr/local/sbin/vault-backup-root-btrfs` 等由根快照链保护，恢复方式是回滚根快照或从 Vault 恢复。本文档不覆盖此类恢复。

---

## 4. 失败恢复顺序与恢复优先级

当 `/var/lib/openclaw` 发生数据丢失或损坏时，应按以下优先级顺序恢复：

### 4.1 恢复优先级（从高到低）

| 优先级 | 恢复对象 | 恢复动作 | 理由 |
|--------|----------|----------|------|
| P0 | `.openclaw/extensions/` | 从备份还原 + 验证 manifest + restart gateway | 缺少有效 plugin 会导致 gateway 拒绝启动或功能缺失 |
| P1 | `backup/last_sent` | 从备份还原 | 避免下次根快照入库退化为全量 send |
| P2 | `.openclaw/workspace-main/` 静态模板 | 执行 `publish-workspace-main.sh --apply` | 恢复 main agent 的 workspace 可读性 |
| P3 | `.openclaw/workspace-main/control/SOP.md` | 执行 `publish-sop.sh --apply` | 恢复 main 对 SOP 的可读性 |
| P4 | `.openclaw/workspace-main/control/state/*` | 从备份还原 | 恢复审批链、健康基线、任务索引 |
| P5 | `backup/openclaw-host-audit-*.txt` | 从备份还原（若可用） | 恢复审计链完整性（非功能性阻断） |

### 4.2 恢复顺序说明

1. **P0（extensions）最优先**：因为 gateway 启动依赖有效 plugin manifest。如果 extensions 缺失或损坏，gateway 会进入 crash loop，其他恢复动作无法验证。
2. **P1（last_sent）次优先**：虽然不影响功能，但若不尽快恢复，下次定时备份窗口会显著延长。
3. **P2-P3（publish 恢复）不依赖备份**：这是基于开发仓的确定性恢复，只要开发仓可用即可执行。应在 extensions 恢复 + gateway 启动成功之后执行。
4. **P4（control/state）在 publish 之后**：因为 `publish-workspace-main.sh` 的 rsync 会跳过 `control/state/`，不会覆盖从备份还原的状态文件。但应确保 publish 先完成（以确保 workspace 结构完整），再还原 state（以避免 rsync 意外行为）。
5. **P5（审计文件）最后**：审计文件不影响运行，优先级最低。

### 4.3 恢复完成后的验证

恢复完成后，必须执行以下验证：

1. `sudo systemctl restart openclaw-gateway.service`
2. 使用 host-sop.md §13.2 的带重试 health check 模板验证 gateway 健康
3. 验证 plugin 加载日志（`sudo journalctl -u openclaw-gateway.service -n 50`）
4. 验证 `main` agent 可通过飞书正常对话
5. 执行 `scripts/check-workspace-main.sh TARGET_DIR` 校验 workspace 结构

---

## 5. 备份策略概要（设计目标，非实施方案）

### 5.1 备份范围

仅备份**类别 A**中列出的路径。类别 B 通过 publish 恢复，类别 C 默认不备份。

### 5.2 备份方法候选

| 方法 | 优点 | 缺点 |
|------|------|------|
| 对 `/var/lib/openclaw` 子卷做 btrfs 只读快照 + 选择性 send | 与根快照链机制统一；可增量 | 粒度粗（整个子卷），包含类别 C 噪声 |
| 基于路径白名单的 rsync/tar 导出到 Vault | 精确控制备份范围；排除噪声 | 需要额外脚本维护路径列表；非原子性 |
| 混合方案：子卷快照做兜底 + 白名单导出做精确恢复源 | 兼具原子性和精确性 | 复杂度最高 |

### 5.3 建议优先顺序

1. **短期**：先实现基于路径白名单的 tar/rsync 导出，覆盖类别 A 所有路径；
2. **中期**：评估是否需要对 `/var/lib/openclaw` 子卷做独立的 btrfs 快照链；
3. **长期**：若 task-runner 上线后 `/var/lib/openclaw` 增长显著，考虑进一步子卷拆分。

### 5.4 触发时机

- 每次 publish workspace-main 之后；
- 每次 gateway restart 验证成功之后；
- 每日定时（与根快照定时对齐或错开）；
- 每次手动触发里程碑快照时。

### 5.5 存储位置

候选：
- Vault 盘（`/mnt/vault/recv/openclaw-state/`）——与根快照入库共用 Vault 盘，但使用独立接收目录
- 注意：Vault 盘为 noauto 离线策略，备份脚本需要在窗口期挂载/卸载

---

## 6. 未来实现约束

当本设计稿转化为可执行备份脚本时，必须满足以下约束：

### 6.1 权限约束

- 备份脚本必须以 `root` 执行（因为 `/var/lib/openclaw` 权限为 `openclaw:openclaw 700`，且涉及 Vault 挂载/卸载）
- 不得要求 `nick` 用户直接执行备份脚本（避免权限泄露）
- 不得将 Vault 挂载权限下放给非 root 用户

### 6.2 路径约束

- 备份源路径必须以白名单方式枚举，不得使用通配符递归整个 `/var/lib/openclaw`
- 白名单必须与本文档第 2 节类别 A 保持一致；任何新增路径必须先更新本文档
- 排除路径必须显式列出类别 C 中的高 churn 目录

### 6.3 原子性约束

- 路径白名单导出（rsync/tar）本质上不是原子操作；若在导出期间 `main` agent 正在写入 `control/state/`，可能产生不一致快照
- 可接受的缓解方案：在导出前短暂停止 gateway → 导出 → 重启 gateway；或接受少量不一致风险（对于低频写入的 control/state 文件，风险较低）
- 若采用子卷快照方案，则天然原子

### 6.4 Vault 操作约束

- 备份脚本的 Vault 挂载/卸载逻辑应与现有 `vault-backup-root-btrfs` 保持一致的操作模式
- 两个备份脚本不应同时挂载 Vault（避免竞争）
- Vault 操作必须有明确的超时和错误处理

### 6.5 幂等性约束

- 备份脚本应支持重复执行而不产生副作用
- 若备份目标路径已存在相同内容（hash 相同），应跳过写入

### 6.6 与 publish 脚本的关系约束

- 备份脚本不得依赖 publish 脚本的执行结果
- 备份脚本不得修改 `workspace-main/` 中的任何内容
- publish 脚本执行后，应由外部编排（手动或 cron）触发备份脚本，而不是 publish 脚本内部调用备份

### 6.7 验收条件

备份脚本进入生产使用前，必须完成以下验收：
- [ ] 在测试路径（如 `/tmp/openclaw-backup-test/`）完成完整的备份→清空→恢复→验证循环
- [ ] 确认恢复后 gateway 可正常启动并通过 health check
- [ ] 确认恢复后 plugin 正常加载
- [ ] 确认恢复后 `publish-workspace-main.sh` 可正常执行（不覆盖 state）
- [ ] 确认备份脚本的 Vault 挂载/卸载逻辑不与 `vault-backup-root-btrfs` 冲突

---

## 7. 明确不在本稿范围内的内容

为避免设计外溢，以下内容**明确不在本文档范围内**：

### 7.1 broker / wrapper 相关

- `host-ops broker` 的实现、部署、状态管理
- root-owned wrapper 链的设计与实现
- broker 状态目录（`broker/request-log/`、`broker/audit-index/`）的备份策略——待 Phase 2 broker 上线后，以本文档为模板扩展类别 A

### 7.2 task-runner / Docker 相关

- `task-runner` agent 的配置与上线
- Docker sandbox 的容器镜像、网络、挂载策略
- `workspace-task-runner/tasks/` 的生命周期管理
- 容器内 Claude Code 执行链

### 7.3 根系统层备份

- 根快照链（`/.snapshots/root-*` → Vault）的任何变更
- `vault-backup-root-btrfs` 脚本的修改
- systemd timer 的调整

### 7.4 Vault 自身

- Vault 盘的冗余、异地备份、健康检查
- Vault 盘容量规划与轮转策略

### 7.5 配置管理

- `/etc/openclaw/openclaw.json` 的候选配置生成与部署流程
- `/etc/openclaw/openclaw.env` 的凭证管理

---

## 8. 当前仍待后续 Phase 完成的事项

### 8.1 Phase 1B 剩余

- [ ] publish 脚本（`scripts/publish-workspace-main.sh`）已形成候选闭环但尚未在现网执行首次发布
- [ ] 基于本设计稿的控制面备份脚本尚未编写
- [ ] `last-sop-hash.txt` 的自动更新机制尚未实施（当前为模板初始值）

### 8.2 Phase 2 依赖

- [ ] `host-ops broker` 上线后将新增 broker 状态目录（如 `broker/request-log/`、`broker/audit-index/`），需要纳入类别 A
- [ ] wrapper 链上线后将新增 wrapper 审计索引，需要纳入类别 A
- [ ] `cron/` 元数据（若启用）需要区分索引（类别 A）和执行日志全文（类别 C）

### 8.3 Phase 3+ 依赖

- [ ] `task-runner` 上线后，`workspace-task-runner/tasks/` 目录的生命周期管理（创建 → 归档 → 清理）需要独立设计，不应纳入本备份方案
- [ ] Docker sandbox 若涉及持久化 volume，其备份策略独立于本文档

### 8.4 尚未决定

- [ ] 是否对 `/var/lib/openclaw` 子卷做独立 btrfs 快照链（区别于路径白名单导出）
- [ ] 备份保留策略（保留多少份、何时轮转）
- [ ] 控制面备份脚本是否复用现有 `vault-backup-root-btrfs` 的 Vault 挂载/卸载逻辑，还是独立实现

---

## 9. 与现有备份链的关系

```
现有根快照链（不变）：
  /.snapshots/root-* → Vault recv/system/
  保护：/etc/openclaw、/opt/openclaw、systemd、备份脚本

本设计稿新增（待实施）：
  /var/lib/openclaw 选择性导出 → Vault recv/openclaw-state/
  保护：control/state/*、extensions/、backup/last_sent、审计文件

不需要备份（靠 publish 恢复）：
  workspace-main 静态模板、SOP 副本、skills、runbooks

不需要备份（临时运行态）：
  memory/、临时 session、task-runner 任务目录、credentials 缓存
```

两条备份链并行，互不干扰。根快照链继续保护根系统组件；选择性导出链保护 `/var/lib/openclaw` 中的控制面状态。
