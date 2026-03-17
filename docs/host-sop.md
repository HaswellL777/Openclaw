# OpenClaw Host 状态记录（2026-03-14 Phase 2 broker deployment 完成）

> 适用范围：Ubuntu 24.04 LTS 宿主机裸机安装 OpenClaw（非 Docker），Btrfs 根（subvolid=5），使用 `/.snapshots` + 离线 Vault（`/mnt/vault`, `noauto`）做增量 `send/receive`；OpenClaw 以 systemd **system-level** 服务运行（`User=openclaw`），并严格遵循目录边界：
>
> - 代码：`/opt/openclaw`（`root:root`，`755`，仅 root 可写）
> - 配置：`/etc/openclaw`（`root:openclaw`，`750`；敏感 env 为 `0640 root:openclaw`）
> - 数据：`/var/lib/openclaw`（btrfs 独立子卷，`openclaw:openclaw`，`700`）
> - 日志：`/var/log/openclaw`（`openclaw:openclaw`）
>
> 当前宿主机状态不再是纯 Phase 0，而是 **Phase 1（Phase 1A + Phase 1B）已完成**：`main` agent 已上线、`workspace-main` 已发布、工具集 fix-forward 已完成、默认主模型已切换为 `motchat-gpt-max/gpt-5.4`；**Phase 1B 控制面收口已完成**（2026-03-11 首次现网脚本化发布通过，`check-workspace-main.sh` 校验通过）；**Phase 2 broker deployment 已完成**（2026-03-14）：broker daemon 运行中、8 个 wrapper 已安装（production 逻辑）、host-ops-tool plugin 已注册进 openclaw.json 并被 gateway 接受；但 **plugin lifecycle activation 已完成（2026-03-15）**，**agent-facing host_ops 逐项切片推进中（2026-03-15）**（registerTool 版 plugin 已部署、`main.tools.allow` 已追加 `host_ops`、`gateway_health` agent-facing E2E 成功、`validate_openclaw_json_candidate` agent-facing E2E 成功含正例与负例、`deploy_openclaw_json_candidate` live E2E verified 含正例 + 负例含 wrapper 侧 + 回归通过（Route C，2026-03-15）、`snapshot_pre` live E2E verified（2026-03-16）、`snapshot_post` live E2E verified（2026-03-16）、`rollback_prepare` live E2E verified（2026-03-16）、`gateway_restart` live E2E verified（2026-03-16，两段式契约：deferred dispatch via systemd-run + operator 独立检查 + gateway_health 验证）；其余 1 个 action（`vault_sync`）仍需逐项启用和验收）；正式 `task-runner`、Docker 执行面与 `/var/lib/openclaw` 独立控制面备份链仍未落地。

## ⛔ 禁止操作清单（优先阅读）

> 以下操作均已在本机发生过事故，后果严重，任何情况下不允许执行。

### ❌ 禁止：以 nick 用户运行 openclaw onboard / doctor --repair / doctor --fix

原因：这些命令会自动创建 `~/.openclaw/openclaw.json` 并注册 user-level systemd 服务（`~/.config/systemd/user/openclaw-gateway.service`），产生第二个 gateway 进程，与 openclaw 系统用户的 gateway 并存，端口各自独立互不感知，整个配置体系分裂。**本机已实际发生过一次，修复耗时数小时。**

### ❌ 禁止：以 nick 用户直接运行 openclaw gateway

原因：同上，会产生 nick 用户的 gateway 进程，占用不同端口，与 systemd 服务管理的进程并存。

### ❌ 禁止：将业务配置写入 /var/lib/openclaw/.openclaw/openclaw.json

原因：`OPENCLAW_STATE_DIR`（`/var/lib/openclaw/.openclaw`）是运行时状态目录，**不是配置合并源**。gateway 启动时只读取 `OPENCLAW_CONFIG_PATH` 指向的 `/etc/openclaw/openclaw.json`。channels、plugins、models、agents 等所有配置写在 state 目录下完全不生效。**本机已实际验证。**

### ❌ 禁止：修改 /opt/openclaw 的归属为 openclaw

原因：`/opt/openclaw` 必须保持 root:root 755，openclaw 用户只需读取权限，不得拥有写权限。

### ❌ 禁止：不经快照直接变更

原因：任何变更必须有变更前快照 + 入库，否则无法回滚。

### ❌ 禁止：使用 openclaw config set 修改配置

原因：会写入 `~/.openclaw/openclaw.json`，产生用户级配置文件，与系统配置冲突。

### ❌ 禁止：在 X2Go Client 中复用旧的 KDE / 自定义 session 配置连接本机 XFCE 远程桌面

原因：若客户端 session type 误为 KDE（实际观测到 `unix-kde-depth_32`），会导致 X2Go 会话虽已建立，但只出现背景、面板与完整桌面组件不启动，造成"似乎连上但桌面不完整"的假象。**本机已于 2026-03-06 20:19 实际踩过此坑。**

处理：新建干净会话，`Session type` 明确选择 **XFCE**，不要复用历史 KDE 会话配置。

### ❌ 禁止：在 extensions 目录放入缺少 openclaw.plugin.json 的目录

原因：OpenClaw 启动时会自动扫描 `/var/lib/openclaw/.openclaw/extensions/` 下所有子目录。如果某个子目录缺少 `openclaw.plugin.json` manifest 文件，gateway 会拒绝启动（`Config invalid: plugin manifest not found`），进入 crash loop。**本机已于 2026-03-05 13:47 实际踩过此坑，gateway 连续崩溃 100+ 次。**

处理：删除有问题的目录后 `sudo systemctl restart openclaw-gateway.service`。

### ❌ 禁止：将 plugin 备份目录（.bak）留在 extensions 目录内

原因：`extensions/` 下所有子目录都会被自动扫描。备份目录（如 `tool-audit-plugin.bak-2026-03-05-1533/`）也会被当作 plugin 加载，产生 `duplicate plugin id detected` 警告，且可能导致正式版本被覆盖，行为不可预期。**本机已于 2026-03-05 15:34 实际踩过此坑。**

处理：备份目录必须移到 extensions 目录之外：
```bash
sudo mv /var/lib/openclaw/.openclaw/extensions/<plugin>.bak-* /var/lib/openclaw/
```

### ❌ 禁止：在 before_tool_call handler 中使用 toolInput 字段名

原因：Plugin SDK 的 `before_tool_call` event 中，工具入参字段名为 **`params`**，不存在 `toolInput` 字段。使用 `toolInput` 会得到 `undefined`，调用任何方法（如 `.slice()`）均抛出 `TypeError`，handler 异常退出，工具被静默放行（无任何拦截效果）。**本机已于 2026-03-05 15:48 实际验证。**

正确字段：`{ toolName, params, toolCallId, runId }`

### ❌ 禁止：在 plugins.entries 中使用 installPath 字段

原因：`plugins.entries.<id>` 只接受 `enabled`、`config` 等已知字段。`installPath` 是非法 key，会导致 Zod schema 校验失败，gateway 拒绝启动（`Unrecognized key: "installPath"`）。插件发现路径由 extensions 目录自动扫描或 `plugins.load.paths` / `plugins.installs` 控制。**本机已于 2026-03-05 14:22 实际验证。**

### ❌ 禁止：在 /etc/openclaw/openclaw.json 中明文写入 API Key 或 appSecret

原因：所有敏感凭证（DeepSeek API Key、飞书 appSecret 等）必须存放于 `/etc/openclaw/openclaw.env`，配置文件中一律使用 `${变量名}` 环境变量引用。明文硬编码存在凭证泄露风险，且违反最小权限原则。**本机已于 2026-03-04 21:24 完成整改。**


### ❌ 禁止：在仍保留全局 `tools.profile` 的情况下，为 `main` 叠加 per-agent `tools.allow`

原因：本机已于 2026-03-07 实际验证，顶层 `tools.profile: "messaging"` 与 per-agent `tools.allow` 并存时，前者会实际压制后者，导致 `main` 最终只拿到 profile 对应的受限工具集，表现为缺少 `read` / `write` / `edit`。

### ❌ 禁止：把 `workspace-main` 描述成“root snapshot 可直接恢复”的持久状态目录

原因：`/var/lib/openclaw` 是独立 btrfs 子卷，根快照不包含该路径；`/var/lib/openclaw/.openclaw/workspace-main` 应视为发布产物，而不是 root snapshot 直接恢复物。

---

## 0. 当前时间、主机与当前阶段

### 0.1 当前时间与主机
- 时区：CST (+0800)
- 日期：2026-03-14（Phase 2 broker deployment 完成）
- 主机：`nick-MS-7D73`（管理用户：`nick`，服务用户：`openclaw`）

### 0.2 当前阶段定位
- 当前宿主机已不再停留在纯 Phase 0。
- **Phase 1A（main bootstrap only）已完成落地**：
  - `main` agent 已加入运行态配置；
  - `workspace-main` 已发布到 `/var/lib/openclaw/.openclaw/workspace-main`；
  - 已完成 gateway 重启、health 验证与 Feishu 黑盒实测；
  - `main` 当前可读取其 workspace 内控制文件，并具备最小 file tools + session tools；
  - 默认主模型已切换为 `motchat-gpt-max/gpt-5.4`。
- **Phase 1B（控制面收口）已完成**：
  - `workspace-main-template/` 目录已建立并提交至 `~/projects/openclaw-dev/`；
  - `scripts/publish-workspace-main.sh`、`scripts/publish-sop.sh`、`scripts/check-workspace-main.sh` 已实现并提交；
  - `docs/runtime-allowlist-backup-draft.md` 已升级为设计定稿候选（design candidate）——分类模型、恢复语义、恢复优先级、实施约束已结构化，但尚未转化为可执行脚本，也未在生产中启用；
  - 以上均为开发仓库内的候选产物，**脚本化发布链已于 2026-03-11 首次用于 live target 并校验通过**（workspace-main 本身最初在 Phase 1A 手动部署，本次通过 publish 脚本完成首次脚本化覆写发布）。
- **Phase 2 broker deployment 已完成（2026-03-14）**：
  - host-ops broker daemon 运行中（`openclaw-broker.service`，active + enabled）；
  - 8 个 wrapper 已安装（production 逻辑，`BROKER_DRY_RUN=false`）；
  - Unix socket `/run/openclaw/broker.sock`（`root:openclaw 660`）；
  - host-ops-tool plugin 已注册进 `openclaw.json`，gateway 已接受该配置并健康运行；
  - **plugin lifecycle activation 已完成（2026-03-15）**：`register(api)` export 已部署，gateway 无 warning；
  - **registerTool 版 `index.js` 已部署到 live（2026-03-15）**，agent-facing `gateway_health` E2E 成功；
  - **`main.tools.allow` 已包含 `host_ops`（2026-03-15）**，agent 可见 `host_ops` 工具；
  - **agent-facing 切片已完成七项**：`gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` + `snapshot_pre` + `snapshot_post` + `rollback_prepare` + `gateway_restart`（均 live E2E verified）；其余 1 个 action（`vault_sync`）仍需逐项启用和验收；
  - **Phase 2 的后续工作（task-runner、Docker 隔离等）尚未开始**。
- 当前是 **Phase 2 agent-facing 切片推进中**（七项已 live E2E verified，其余 1 个仍未开放）：
  - **broker backend 已部署并通过验收**
  - **plugin lifecycle activation 已完成**
  - **registerTool 版 plugin 已部署到 live，`gateway_health` + `validate_openclaw_json_candidate` agent-facing E2E 成功**
  - **`deploy_openclaw_json_candidate` live E2E verified（Route C，2026-03-15：正例 + 负例含 wrapper 侧 + 回归通过；restart/snapshot/health 仍由 operator-mediated checklist 承担）**
  - **`snapshot_pre` live E2E verified（2026-03-16）：正例（btrfs 快照创建成功）+ 负例（label 非法 / 缺失 reason / 非 object inputs / 多余参数 / 非 enabled action 全部正确拒绝）+ 回归（gateway_health 通过）**
  - **`snapshot_post` live E2E verified（2026-03-16）：正例（btrfs 快照创建成功）+ 负例（label 非法 / 缺失 reason / 非 object inputs / 多余参数 / 非 enabled action 全部正确拒绝）+ 回归（gateway_health + snapshot_pre 通过）**
  - **`rollback_prepare` live E2E verified（2026-03-16）：正例（snapshot 存在性验证成功，prepare_only metadata 返回正确）+ 负例（缺失 target_snapshot / 不存在 snapshot 返回 E_FILE_NOT_FOUND / 非 enabled action schema reject）+ 回归（gateway_health + snapshot_pre + snapshot_post 通过）。rollback_prepare 是纯只读 action，只验证 snapshot 存在性并返回 prepare-only metadata（prepare_only: true / rollback_executed: false / scope: root-filesystem-only / excluded_paths: [/var/lib/openclaw] / operator_action_required: true），不执行实际 rollback。实际 rollback 仍需 LiveUSB/救援环境。**
  - **`gateway_restart` live E2E verified（2026-03-16）：两段式契约（deferred dispatch via systemd-run transient timer + operator 独立 systemctl 检查 + agent gateway_health 验证），12/12 PASS（含正例 + 正例后续 operator 检查 + 7 个负例 + 3 个回归）。经历三次 live activation：(1) --no-block 方案失败（SIGTERM 竞态），(2) systemd-run deferred dispatch 部分失败（stderr 污染 + reason 输入验证不足），(3) input hardening 后成功。`ok: true` / `restart_scheduled: true` 仅表示 restart 已 scheduled，不表示 restart 已完成——完成判据是 operator `systemctl is-active` 双服务 active + agent `gateway_health` ok。**
  - **其余 1 个 action（`vault_sync`）仍需逐项 agent-facing 开放与验收**
  - **deploy 的成功不代表其余 action 已安全开放；deploy 写入成功 ≠ 配置生效成功（纪律约束不变）**

### 0.3 `/var/lib/openclaw` 与根快照的边界
- `/var/lib/openclaw` 是独立 btrfs 子卷；
- 根 `/` 的只读快照 **不包含** `/var/lib/openclaw`；
- 任何“回滚根系统”的表述，**都不得再写成会同时恢复 OpenClaw 运行态**；
- 因此 `workspace-main`、extensions、session state、cron state、未来 task-runner 任务目录，默认都不属于 root snapshot 的直接恢复对象。

### 0.4 `workspace-main` 的语义
- `/var/lib/openclaw/.openclaw/workspace-main` 应视为：
  - **由开发仓库发布出来的可重建 artifact**
  - **运行态发布副本**
  - **不是根快照恢复对象**
  - **不是长期手工漂移的真相源目录**
- 其中真正需要长期保留的，不是整个 `workspace-main` 的全部静态模板文件，而是其中少数控制面状态与运行元数据。

### 0.5 当前最重要的未决问题
1. **飞书卡住 / 超慢回复问题尚未根治。**
   - 现象早在本轮修改前一天就出现过；
   - 日志中可见 `embedded run timeout ... timeoutMs=600000`；
   - 切换默认模型到 `g54` 后目前恢复良好；
   - 但尚不能断言根因一定是 Claude 4.6。
2. **`session-memory` 日志路径显示为 `~/.openclaw/workspace-main/memory/...`。**
   - 这说明日志展示层存在 `~` 形式路径；
   - 后续仍需核实其实际解析路径是否仍指向 `/var/lib/openclaw/.openclaw/...`，并确认不会引回 `nick` 用户空间。
3. **agent-facing `host_ops` 切片推进中（2026-03-15）。**
   - broker backend 已于 2026-03-14 部署完成（`openclaw-broker.service` active + enabled）；
   - host-ops-tool plugin 已注册进 `openclaw.json`；
   - plugin lifecycle activation 已完成（2026-03-15，`register(api)` export 部署，warning 消失）；
   - registerTool 版 `index.js` 已部署到 live（2026-03-15）；
   - `main.tools.allow` 已包含 `host_ops`（2026-03-15）；
   - `gateway_health` agent-facing E2E 成功；
   - `validate_openclaw_json_candidate` agent-facing E2E 成功（正例 + 负例）；
   - `deploy_openclaw_json_candidate` live E2E verified（Route C，2026-03-15：正例 + 负例含 wrapper 侧 + 回归通过，见 `docs/records/phase2-hostops-deploy-candidate-activation-2026-03-15.md`）；
   - `snapshot_pre` live E2E verified（2026-03-16：正例 + 负例 + 回归通过，见 `docs/records/phase2-hostops-snapshot-pre-activation-2026-03-15.md`）；
   - `snapshot_post` live E2E verified（2026-03-16：正例 + 负例 + 回归通过，见 `docs/records/phase2-hostops-snapshot-post-activation-2026-03-16.md`）；
   - `rollback_prepare` live E2E verified（2026-03-16：正例 + 负例含 wrapper 侧 E_FILE_NOT_FOUND + 回归通过，见 `docs/records/phase2-hostops-rollback-prepare-activation-2026-03-16.md`）；
   - `gateway_restart` live E2E verified（2026-03-16：两段式契约 deferred dispatch，12/12 PASS，见 `docs/records/phase2-hostops-gateway-restart-activation-2026-03-16.md`）；
   - 其余 1 个 action（`vault_sync`）仍需逐项开放与验收。
4. ~~Phase 1B 发布 / 校验脚本已在开发仓就绪，但尚未在现网执行首次正式发布。~~ ✅ 已完成（2026-03-11）。

## 1. 磁盘与分区布局（lsblk 摘要）
### 1.1 系统盘（System）
- Disk: /dev/nvme0n1  931.5G  (KIOXIA-EXCERIA PRO SSD, serial 43LA20RJKMW6)
  - /dev/nvme0n1p1  1G   vfat  挂载：/boot/efi
  - /dev/nvme0n1p2  837.3G  btrfs 挂载：/

说明：
- 根文件系统 `/` 为 btrfs
- 当前根挂载为顶层子卷 subvolid=5（尚未迁移到 @/@home/@snapshots 布局）

### 1.2 金库盘（Vault）
- Disk: /dev/nvme1n1  931.5G  (KIOXIA-EXCERIA PRO SSD, serial 43LA20RHKMW6)
- 已清空并重建为 GPT 单分区：
  - /dev/nvme1n1p1  931.5G  btrfs  LABEL=vault  UUID=38267f78-bbcb-49ad-96c3-b97e8286308d
- 作为"离线金库盘"使用：默认不自动挂载，仅在备份窗口挂载接收增量流。

## 2. Btrfs 快照与子卷（System 盘）
### 2.1 /.snapshots
- `/.snapshots` 已创建为 btrfs 子卷（Subvolume ID: 256，Parent ID: 5）
- 已创建只读快照（readonly snapshots）：
  - `/.snapshots/root-baseline-pre-openclaw-2026-03-04-1516`（Subvol ID: 257）
  - `/.snapshots/root-pre-openclaw-install-2026-03-04-1528`（开始安装 OpenClaw 前的里程碑）
  - `/.snapshots/root-auto-2026-03-04-1536`（由自动备份脚本生成）
  - `/.snapshots/root-post-openclaw-working-2026-03-04-1624`（OpenClaw 安装验证可用后的里程碑）
  - `/.snapshots/root-auto-2026-03-04-1624`（由自动备份脚本生成）
  - `/.snapshots/root-post-config-fixed-2026-03-04-2047`（配置修正完成、飞书与 DeepSeek 验证可用后的里程碑）
  - `/.snapshots/root-pre-fix-2026-03-04-2121`（SOP 合规审计修复前里程碑）
  - `/.snapshots/root-post-fix-2026-03-04-2124`（SOP 合规审计修复后里程碑）
  - `/.snapshots/root-auto-2026-03-05-0340`（由自动备份脚本生成）
  - `/.snapshots/root-pre-motchat-models-2026-03-05-1141`（接入 MotChat 中转模型前里程碑）
  - `/.snapshots/root-auto-2026-03-05-1141`（由自动备份脚本生成）
  - `/.snapshots/root-post-motchat-models-2026-03-05-1158`（接入 MotChat 中转模型后里程碑）
  - `/.snapshots/root-auto-2026-03-05-1158`（由自动备份脚本生成）
  - `/.snapshots/root-pre-hook-test-2026-03-05-1347`（before_tool_call hook 可用性测试前里程碑）
  - `/.snapshots/root-auto-2026-03-05-1347`（由自动备份脚本生成）
  - `/.snapshots/root-post-hook-test-2026-03-05-1436`（before_tool_call hook 验证完成后里程碑）
  - `/.snapshots/root-auto-2026-03-06-1353`（每日定时备份）
  - `/.snapshots/root-pre-x2go-2026-03-06-2007`（安装 X2Go / XFCE 前里程碑）
  - `/.snapshots/root-auto-2026-03-06-2007`（由自动备份脚本生成）
  - `/.snapshots/root-post-x2go-working-2026-03-06-2030`（X2Go 远程桌面验证可用后的里程碑）
  - `/.snapshots/root-auto-2026-03-06-2031`（由自动备份脚本生成）
  - `/.snapshots/root-pre-gpt54-2026-03-06-2051`（替换 MotChat GPT-5.1 系列为 GPT-5.2 / 5.3 / 5.4 前里程碑）
  - `/.snapshots/root-auto-2026-03-06-2051`（由自动备份脚本生成）
  - `/.snapshots/root-post-gpt54-2026-03-06-2233`（GPT 5.x 模型切换完成后里程碑）
  - `/.snapshots/root-auto-2026-03-06-2233`（由自动备份脚本生成）
  - `/.snapshots/root-pre-main-agent-2026-03-07-1804`（Phase 1A `main` bootstrap 前里程碑）
  - `/.snapshots/root-auto-2026-03-07-1804`（由自动备份脚本生成）
  - `/.snapshots/root-pre-toolfix-2026-03-07-1830`（移除全局 `tools.profile` 修复前里程碑）
  - `/.snapshots/root-auto-2026-03-07-1830`（由自动备份脚本生成）
  - `/.snapshots/root-post-phase1a-2026-03-07-1911`（Phase 1A 完成后的收尾里程碑）
  - `/.snapshots/root-auto-2026-03-07-1911`（由自动备份脚本生成）

### 2.2 OpenClaw 数据目录子卷隔离
- `/var/lib/openclaw` 已迁移为独立 btrfs 子卷：
  - Subvolume ID: 260
  - 权限：700，owner/group：openclaw:openclaw
- 目的：将运行期数据与根系统快照隔离，控制快照膨胀，便于单独备份与恢复。
- 说明：对根 `/`（subvolid=5）打快照时，`/var/lib/openclaw` 不被包含在内（btrfs 快照不递归包含其他子卷）。回滚根系统不会影响运行数据。

## 3. Vault 金库盘接收结构（Vault 盘）
- 挂载点：/mnt/vault（默认 noauto）
- 子卷结构（在 Vault 文件系统内部）：
  - /mnt/vault/recv                  （subvol）
  - /mnt/vault/recv/system           （目录，用于接收系统盘快照流）
- 已接收的快照（Vault 内部子卷）：
  - system/root-baseline-pre-openclaw-2026-03-04-1516
  - system/root-pre-openclaw-install-2026-03-04-1528
  - system/root-auto-2026-03-04-1536
  - system/root-auto-2026-03-04-1624
  - system/root-auto-2026-03-04-2047（配置修正后入库）
  - system/root-auto-2026-03-04-2121（SOP 合规审计修复前入库）
  - system/root-auto-2026-03-04-2124
  - system/root-auto-2026-03-05-0340（每日定时备份）
  - system/root-auto-2026-03-05-1141（接入 MotChat 中转模型前入库）
  - system/root-auto-2026-03-05-1158（接入 MotChat 中转模型后入库）（SOP 合规审计修复后入库）
  - system/root-auto-2026-03-05-1347（hook 可用性测试前入库）
  - system/root-auto-2026-03-05-1436（hook 验证完成后入库）
  - system/root-auto-2026-03-06-1353（每日定时备份）
  - system/root-auto-2026-03-06-2007（安装 X2Go / XFCE 前入库）
  - system/root-auto-2026-03-06-2031（X2Go 远程桌面验证可用后入库）
  - system/root-auto-2026-03-06-2051（GPT 5.x 模型切换前入库）
  - system/root-auto-2026-03-06-2233（GPT 5.x 模型切换后入库）
  - system/root-auto-2026-03-07-1804（Phase 1A `main` bootstrap 前入库）
  - system/root-auto-2026-03-07-1830（工具集 fix-forward 前入库）
  - system/root-auto-2026-03-07-1911（Phase 1A 收尾入库）
  - system/root-auto-2026-03-11-1324（Phase 1B 发布后入库）
  - system/root-auto-2026-03-14-1454（Phase 2 broker deployment 后入库，parent: root-auto-2026-03-14-0340）

## 4. 离线挂载策略（/etc/fstab）
已追加一条（仅一条）：
- `LABEL=vault  /mnt/vault  btrfs  noauto,nofail,x-systemd.device-timeout=1,noatime,compress=zstd  0  0`

说明：
- noauto：默认不自动挂载，降低在线暴露与误操作风险
- compress=zstd：Vault 盘挂载使用 zstd 压缩

## 5. 增量备份脚本与状态
### 5.1 脚本
- 路径：`/usr/local/sbin/vault-backup-root-btrfs`
- 行为：
  1) 创建新的只读快照 `/.snapshots/root-auto-YYYY-MM-DD-HHMM`
  2) 挂载 /mnt/vault
  3) 读取 last_sent 作为父快照（若父快照同时存在于源与 Vault 目的地，则走增量 `btrfs send -p`；否则全量）
  4) `btrfs receive` 到 `/mnt/vault/recv/system`
  5) 更新 last_sent
  6) 卸载 /mnt/vault
  7) 若 openclaw-gateway.service 存在，会在备份窗口自动 stop/start

### 5.2 状态文件
- `/var/lib/openclaw/backup/last_sent`
  - 当前值：`root-auto-2026-03-14-1454`

## 6. systemd 定时器（Vault 备份）
- Service:
  - `/etc/systemd/system/vault-backup-root-btrfs.service`
  - ExecStart=/usr/local/sbin/vault-backup-root-btrfs
- Timer:
  - `/etc/systemd/system/vault-backup-root-btrfs.timer`
  - `OnCalendar=*-*-* 03:40:00`
  - `Persistent=true`
- 已启用：`vault-backup-root-btrfs.timer`（每天 03:40:00 CST 触发）

## 7. OpenClaw 目录与权限基线（宿主机）
- 程序目录：
  - `/opt/openclaw`  owner root:root, mode 755（所有用户可读/进入，仅 root 可写）
  - `/opt/openclaw/broker/`  owner root:root, mode 755（broker daemon + wrappers，2026-03-14 部署）
  - `/opt/openclaw/broker/wrappers/`  owner root:root, mode 755（8 个 action wrapper）
  - `/opt/openclaw/broker/wrappers/lib/`  owner root:root, mode 755（共享验证库 common.sh）
  - `/opt/openclaw/broker/lib/`  owner root:root, mode 755（socket-listener.py）
- 配置目录：
  - `/etc/openclaw`  owner root:openclaw, mode 750
  - `/etc/openclaw/openclaw.json`  owner root:openclaw, mode 640
  - `/etc/openclaw/openclaw.env`  owner root:openclaw, mode 640（强制）
- 数据目录（已为子卷）：
  - `/var/lib/openclaw` owner openclaw:openclaw, mode 700（仅服务账号读写）
  - `/var/lib/openclaw/broker/`  owner root:openclaw, mode 750（broker 状态，minimal）
  - `/var/lib/openclaw/approvals/candidates/`  owner openclaw:openclaw, mode 700（config candidate 暂存区）
- 日志目录：
  - `/var/log/openclaw` owner openclaw:openclaw
  - `/var/log/openclaw/broker/`  owner root:openclaw, mode 750（broker 审计日志）
- 插件目录：
  - `/var/lib/openclaw/.openclaw/extensions` owner openclaw:openclaw, mode 700
- 运行时：
  - `/run/openclaw/broker.sock`  owner root:openclaw, mode 660（broker Unix socket，systemd RuntimeDirectory）

## 8. OpenClaw 运行账号
- 用户：openclaw（system user）
- uid：997，gid：984
- home：/var/lib/openclaw
- shell：/usr/sbin/nologin（不可交互登录）
- 用途：systemd 服务以该用户运行，最小权限原则

## 9. 里程碑快照备忘
- 每次完成重要变更后（必须执行）：
  1) 创建只读快照：`sudo btrfs subvolume snapshot -r / "/.snapshots/root-post-<描述>-$(date +%F-%H%M)"`
  2) 运行入库脚本：`sudo /usr/local/sbin/vault-backup-root-btrfs`

## 10. 关键验证命令（备忘）
- 查看系统盘根的 btrfs 状态：
  - `sudo btrfs subvolume show /`
- 查看快照：
  - `sudo btrfs subvolume list /.snapshots`
- 验证 Vault 是否离线：
  - `findmnt /mnt/vault && echo "WARNING: vault is mounted" || echo "OK: vault is unmounted"`
- 手动触发一次备份：
  - `sudo /usr/local/sbin/vault-backup-root-btrfs`
- 查看 timer：
  - `systemctl list-timers | grep vault-backup-root-btrfs`

---

## 10A. 远程桌面（X2Go over SSH，追加于 2026-03-06）

> 目标：在**不新增公网 RDP / VNC 暴露面**的前提下，为 Ubuntu 24.04 宿主机提供可回连、可验证、可复现的图形远程桌面能力。

### 10A.1 结论（当前权威状态）
- 方案：**X2Go over SSH**
- 远程登录账号：`nick`
- **禁止**使用 `openclaw` 账号登录图形会话；该账号为 system user，shell=`/usr/sbin/nologin`，仅用于 systemd 服务。
- 公网暴露面：仍仅需 **SSH 22**；**不要**新增 RDP / VNC 监听端口。
- 桌面环境：**XFCE**
- 客户端会话类型：**XFCE**
- 当前状态：**已于 2026-03-06 20:19~20:30 实机验证通过**

### 10A.2 已安装软件包
```bash
sudo apt update
sudo apt install -y x2goserver x2goserver-xsession xfce4 xfce4-goodies dbus-x11 xterm
```

补充说明：
- 安装过程中提示选择 display manager 时，本机选择 **lightdm**。
- `lightdm` 在服务器场景下可保持 `inactive`，**不影响 X2Go 正常工作**；X2Go 的关键依赖是 `ssh + x2goserver + 可启动的 XFCE session`。

### 10A.3 服务端会话配置（当前生效版本）
**`~/.xsession`**
```bash
startxfce4
```

**`~/.xsessionrc`**
```bash
export XDG_SESSION_DESKTOP=xfce
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
```

权限：
```bash
chmod 644 ~/.xsession ~/.xsessionrc
```

### 10A.4 客户端连接参数（Windows / Linux X2Go Client）
- Host：本机可达地址（本次验证使用 IPv6）
- Login：`nick`
- SSH Port：`22`
- Session type：**XFCE**

### 10A.5 首次排障与最终修正（本机已验证）
#### 现象 1：客户端已建立图形会话，但只有背景，没有 panel / 完整桌面
根因：客户端历史会话误用了 KDE / 自定义 session type，日志出现：
```
Warning: Unrecognized session type 'unix-kde-depth_32'. Assuming agent session.
```

处理：
1. 删除旧 X2Go session 或新建干净 session
2. 客户端 `Session type` 明确改为 **XFCE**
3. 服务端 `~/.xsession` 使用 `startxfce4`，不要继续仅写 `xfce4-session`
4. 清理旧缓存：
```bash
rm -rf ~/.cache/sessions/*
```

#### 现象 2：尝试启用 `x2gocleansessions.service` 失败
表现：
```
Failed to enable unit: Unit file x2gocleansessions.service does not exist.
```

结论：**不是故障**。Ubuntu 24.04 当前包形态下仅有 `x2goserver.service` 也可正常工作。

#### 现象 3：`lightdm` 显示为 inactive
结论：**不是故障**。服务器不以本地图形登录为主时，`lightdm inactive` 可接受，不影响 X2Go。

### 10A.6 已验证的服务端状态
```bash
systemctl is-active ssh         # active
systemctl is-active x2goserver  # active
which xfce4-session             # /usr/bin/xfce4-session
ls -l ~/.xsession               # 存在
```

成功连入后，服务端进程验证：
```bash
pgrep -a xfce4-session
pgrep -a xfce4-panel
pgrep -a xfdesktop
```

本机实测结果：`xfce4-session`、`xfce4-panel`、`xfdesktop` 均已启动，判定桌面会话完整可用。

### 10A.7 已执行的里程碑快照与入库
变更前：
```bash
sudo btrfs subvolume snapshot -r / "/.snapshots/root-pre-x2go-$(date +%F-%H%M)"
sudo /usr/local/sbin/vault-backup-root-btrfs
```

验证成功后：
```bash
sudo btrfs subvolume snapshot -r / "/.snapshots/root-post-x2go-working-$(date +%F-%H%M)"
sudo /usr/local/sbin/vault-backup-root-btrfs
```

本机已落地：
- `/.snapshots/root-pre-x2go-2026-03-06-2007`
- `/.snapshots/root-post-x2go-working-2026-03-06-2030`
- `/.snapshots/root-auto-2026-03-06-2007`
- `/.snapshots/root-auto-2026-03-06-2031`
- Vault 已接收：`system/root-auto-2026-03-06-2007`、`system/root-auto-2026-03-06-2031`

### 10A.8 推荐收尾优化
为降低远程渲染闪烁/黑屏概率，已执行：
```bash
xfconf-query -c xfwm4 -p /general/use_compositing -s false
```

建议：后续若出现图形异常，优先检查该项是否被重新开启。

### 10A.9 远程桌面运维规则
- **必须**通过 `nick` 登录 X2Go，会话内需要 sudo 时再提权。
- **不要**尝试让 `openclaw` 账号承担图形登录；该账号只用于后台服务。
- **不要**为了图形远程桌面额外开放 RDP / VNC 公网端口。
- **不要**复用历史错误的 KDE session 配置。
- 远程桌面出现异常时，优先“终止旧会话 + 清缓存 + 新建 XFCE 会话”，不要在坏会话上反复恢复。


---

## 11. 部署结果（当前权威状态）

### 11.1 运行时版本（验收时）
- Node.js：`v22.22.0`（NodeSource apt）
- npm：`10.9.4`
- git：`2.43.0`
- OpenClaw：`2026.3.2`（`85377a2`）
- systemd 服务：`openclaw-gateway.service`（system-level，`User=openclaw`）

### 11.2 监听端口（默认仅 localhost）
- Gateway WebSocket：`127.0.0.1:17777`（同时监听 `::1:17777`）
- Browser control（HTTP）：`127.0.0.1:17779`（auth=token）
- 内部端口：`127.0.0.1:17780`
- Dashboard（本机访问）：`http://127.0.0.1:17777/`

> ⚠️ 如果发现 `18789` 端口在监听，说明 `nick` 用户的 user-level gateway 被意外启动，见第 **13.6.8** 节清理步骤。

### 11.3 当前阶段标签
- **Phase 1A / main bootstrap only — 已完成落地**
- **Phase 1B / 控制面收口 — 已完成（2026-03-11 首次现网脚本化发布通过）**
- **Phase 2 / broker deployment — 已完成（2026-03-14）**
- `main` agent 已正式上线；
- `workspace-main` 已落地；
- `main` 的 file tools 已修正；
- 默认主模型已切到 `motchat-gpt-max/gpt-5.4`；
- 开发仓已提交 `workspace-main-template/` 目录与 publish/check 脚本；
- `docs/runtime-allowlist-backup-draft.md` 已升级为设计定稿候选（design candidate）；
- host-ops broker daemon 已部署（`openclaw-broker.service`，active + enabled）；
- 8 个 wrapper 已安装（production 逻辑，`BROKER_DRY_RUN=false`）；
- host-ops-tool plugin 已注册进 `openclaw.json`（gateway 接受，健康运行）；
- **plugin lifecycle activation 已完成（2026-03-15）**；registerTool 版 plugin 已部署到 live（2026-03-15）；**agent-facing 切片已完成七项**（`gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` + `snapshot_pre` + `snapshot_post` + `rollback_prepare` + `gateway_restart`，均 live E2E verified）；其余 1 个 action（`vault_sync`）仍需逐项开放与验收；
- `task-runner` / Docker 执行面仍未进入生产落地。

#### 11.3.1 Phase 1B 退出条件（摘要）

Phase 1B 完成收口需要满足以下剩余条件：
1. ~~publish 脚本增加 live target 支持（`--allow-live-target` 或等效机制）~~ ✅ 已实现；
2. ~~首次通过脚本化发布链完成现网 workspace-main 发布~~ ✅ 已完成（2026-03-11）；
3. ~~发布后通过 `check-workspace-main.sh` 校验通过~~ ✅ 已完成（2026-03-11）。

控制面备份脚本实现不作为 Phase 1B 退出条件（设计已完成，实现归 Phase 6）。

完整退出条件、阶段交付物与 Phase 2 进入门槛见 `docs/design-v3.md` §7 Phase 1B / Phase 2。

#### 11.3.2 Phase 2 broker deployment 退出条件（摘要）

Phase 2 broker deployment 于 2026-03-14 完成，退出条件满足情况：

1. ~~broker daemon 部署并运行（`openclaw-broker.service` active + enabled）~~ ✅
2. ~~Unix socket 已创建且权限正确（`/run/openclaw/broker.sock`，`root:openclaw 660`）~~ ✅
3. ~~8 个 wrapper 安装为 production 版本（`BROKER_DRY_RUN=false`）~~ ✅
4. ~~`gateway_health` 正向测试通过~~ ✅
5. ~~negative cases 测试通过（invalid action → error，bad path → denied，path traversal → denied）~~ ✅
6. ~~host-ops-tool plugin 注册进 `openclaw.json`，gateway 健康接受~~ ✅
7. ~~pre/post change snapshot + Vault 入库~~ ✅
8. ~~plugin activation（`index.js` register/activate export）~~ ✅ 已完成（2026-03-15）
9. ~~agent-facing `host_ops` tool access（registerTool 版 plugin 部署 + `main.tools.allow` 更新）~~ ✅ 七项已完成（`gateway_health` + `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` + `snapshot_pre` + `snapshot_post` + `rollback_prepare` + `gateway_restart`，均 live E2E verified）；其余 1 个 action（`vault_sync`）仍需逐项开放

详细现场记录见 `docs/records/phase2-broker-deployment-2026-03-14.md`。

### 11.4 里程碑快照与入库（已执行）
- 最近关键本地只读里程碑快照：
  - `/.snapshots/root-post-openclaw-working-2026-03-04-1624`
  - `/.snapshots/root-post-x2go-working-2026-03-06-2030`
  - `/.snapshots/root-post-gpt54-2026-03-06-2233`
  - `/.snapshots/root-post-phase1a-2026-03-07-1911`
  - `/.snapshots/root-pre-phase1b-publish-2026-03-11-1308`（Phase 1B 首次现网发布前）
  - `/.snapshots/root-post-phase1b-publish-2026-03-11-1319`（Phase 1B 首次现网发布后）
  - `/.snapshots/root-pre-phase2-broker-20260314`（ID 309，Phase 2 broker 部署前）
  - `/.snapshots/root-post-phase2-broker-20260314`（ID 310，Phase 2 broker 部署后）
- 最近自动备份快照（由 `vault-backup-root-btrfs` 生成）：
  - `/.snapshots/root-auto-2026-03-06-2031`
  - `/.snapshots/root-auto-2026-03-06-2051`
  - `/.snapshots/root-auto-2026-03-06-2233`
  - `/.snapshots/root-auto-2026-03-07-1804`
  - `/.snapshots/root-auto-2026-03-07-1830`
  - `/.snapshots/root-auto-2026-03-07-1911`
  - `/.snapshots/root-auto-2026-03-11-1324`（Phase 1B 发布后 Vault 入库时自动创建）
  - `/.snapshots/root-auto-2026-03-14-1454`（Phase 2 broker 部署后 Vault 入库时自动创建）
- Vault 已接收（`/mnt/vault/recv/system`）的最新条目：
  - `system/root-auto-2026-03-06-2031`
  - `system/root-auto-2026-03-06-2051`
  - `system/root-auto-2026-03-06-2233`
  - `system/root-auto-2026-03-07-1804`
  - `system/root-auto-2026-03-07-1830`
  - `system/root-auto-2026-03-07-1911`
  - `system/root-auto-2026-03-11-1324`（parent: `root-auto-2026-03-11-0340`）
  - `system/root-auto-2026-03-14-1454`（parent: `root-auto-2026-03-14-0340`）
- `last_sent`：`/var/lib/openclaw/backup/last_sent = root-auto-2026-03-14-1454`
- Vault 备份后状态：Vault 不常驻挂载（`findmnt /mnt/vault -> unmounted`）

### 11.5 审计记录（已生成）
- `/var/lib/openclaw/backup/openclaw-host-audit-2026-03-04-1625.txt`

### 11.6 飞书插件（已验证可用）
- 插件：`@openclaw/feishu v2026.3.2`
- 安装路径：`/var/lib/openclaw/.openclaw/extensions/feishu/node_modules/@openclaw/feishu`
  - ⚠️ `installPath` 必须指向 `node_modules/@openclaw/feishu` 这一层，不能指向 npm prefix 目录。
- 连接模式：websocket
- Bot `open_id`：`ou_85701f4531d56c7de0fc1fb845fcebfe`
- 启动日志确认已注册：`feishu_doc`、`feishu_app_scopes`、`feishu_chat`、`feishu_wiki`、`feishu_drive`、`feishu_bitable`

## 12. 关键配置与 systemd 单元（权威落地版本）

### 12.1 配置文件说明（`/etc/openclaw/openclaw.json`）

> ⚠️ **所有配置（gateway、models、agents、channels、plugins）必须集中写在此文件。**  
> `/var/lib/openclaw/.openclaw/` 下即使存在 `openclaw.json` 也不会被读取——那是运行时状态目录，不是配置合并源，本机已实际踩过此坑。

当前配置文件包含以下部分（使用 JSON5 格式）：
- `gateway`
  - 端口 `17777`
  - `bind=loopback`
  - token 通过 `${OPENCLAW_GATEWAY_TOKEN}` 从环境变量注入
- `models`
  - DeepSeek 自定义 provider（`contextWindow: 128000`）
  - MotChat 中转 Claude 4.6（provider：`motchat-claude-4-6`，`baseUrl: https://new.motchat.com/v1`，5 个模型：`opus-4-6 / opus-4-6-1m / opus-4-6-thinking / sonnet-4-6 / sonnet-4-6-thinking`）
  - MotChat 中转 GPT 5.x（provider：`motchat-gpt-max`，`baseUrl: https://new.motchat.com/v1`，7 个模型：`gpt-5.2-codex / gpt-5.2-codex-high / gpt-5.2-codex-xhigh / gpt-5.2-high / gpt-5.2-xhigh / gpt-5.3-codex / gpt-5.4`）
    - `gpt-5.2-*` 与 `gpt-5.3-codex`：`contextWindow=400000`，`maxTokens=128000`
    - `gpt-5.4`：`contextWindow=1050000`，`maxTokens=128000`
- `agents`
  - 当前默认主模型为 `motchat-gpt-max/gpt-5.4`
  - 保留 `motchat-claude-4-6/*` 与 `motchat-gpt-max/*` 模型矩阵，可通过 alias 或显式 model 路径切换
  - 当前 alias：`opus / opus1m / opusthink / sonnet / sonnetthink / g52codex / g52codexhigh / g52codexxhigh / g52high / g52xhigh / g53codex / g54 / deepchat / deepresoner`
  - Phase 1A 已新增 `agents.list[main]`，其 `workspace` 指向 `/var/lib/openclaw/.openclaw/workspace-main`
  - `main.subagents.allowAgents = ["task-runner"]`
  - `agents.defaults.subagents` 当前包含：
    - `maxSpawnDepth = 2`
    - `maxChildrenPerAgent = 3`
    - `runTimeoutSeconds = 3600`
    - `archiveAfterMinutes = 120`
- `channels`
  - 飞书（websocket 模式）
  - `appSecret` 通过 `${FEISHU_APP_SECRET}` 从环境变量注入
- `plugins`
  - `feishu`
  - `tool-audit-plugin`（诊断用）
- `hooks`
  - 内部 hooks 已启用
  - `tool-audit-probe` 已注册（诊断用）
- `logging`
  - `file=/var/log/openclaw/openclaw.log`

当前配置层面的关键修订：
- **顶层 `tools: { profile: "messaging" }` 已移除。**
  - 原因：本机已实测验证，该 profile 与 per-agent `tools.allow` 并存时，会压制 `main` 的显式 allowlist，导致 `read/write/edit` 缺失。
- `main` 当前最小工具集为：
  - `read`
  - `write`
  - `edit`
  - `sessions_list`
  - `sessions_history`
  - `sessions_send`
  - `session_status`
  - `sessions_spawn`
- `main` 当前显式 deny：
  - `exec`
  - `process`
  - `apply_patch`
  - `elevated`
- `main.tools.elevated.enabled = false`

> ⚠️ **凭证注入规则（2026-03-04 整改后）：**
> - DeepSeek `apiKey` 在 json 中写 `${DEEPSEEK_API_KEY}`，实际值在 `openclaw.env` 中
> - 飞书 `appSecret` 在 json 中写 `${FEISHU_APP_SECRET}`，实际值在 `openclaw.env` 中
> - MotChat 中转 `apiKey` 在 json 中写 `${MOTCHAT_API_KEY}`，实际值在 `openclaw.env` 中
> - **禁止在 json 中明文写任何 API Key 或 Secret**

### 12.1.1 当前 MotChat GPT 5.x 模型矩阵（2026-03-07 权威落地版本）

| Provider 路径 | Alias | 说明 | contextWindow | maxTokens |
|---|---|---|---:|---:|
| `motchat-gpt-max/gpt-5.2-codex` | `g52codex` | GPT-5.2 Codex | 400000 | 128000 |
| `motchat-gpt-max/gpt-5.2-codex-high` | `g52codexhigh` | GPT-5.2 Codex High | 400000 | 128000 |
| `motchat-gpt-max/gpt-5.2-codex-xhigh` | `g52codexxhigh` | GPT-5.2 Codex XHigh | 400000 | 128000 |
| `motchat-gpt-max/gpt-5.2-high` | `g52high` | GPT-5.2 High | 400000 | 128000 |
| `motchat-gpt-max/gpt-5.2-xhigh` | `g52xhigh` | GPT-5.2 XHigh | 400000 | 128000 |
| `motchat-gpt-max/gpt-5.3-codex` | `g53codex` | GPT-5.3 Codex | 400000 | 128000 |
| `motchat-gpt-max/gpt-5.4` | `g54` | GPT-5.4 | 1050000 | 128000 |

说明：
- 为降低变更爆炸半径，provider 键名 **仍保留** `motchat-gpt-max`，但其 `models` 数组已完全替换，不再保留任何 GPT-5.1 Codex Max 条目。
- 旧 alias `max / maxhigh / maxlow / maxmed / maxxhigh` 已全部移除，避免语义漂移与后续误用。
- 截至 2026-03-07 Phase 1A 落地完成后，默认主模型已从 `motchat-claude-4-6/claude-opus-4-6` 切换为 `motchat-gpt-max/gpt-5.4`。
- 变更原因不是“统一偏好 GPT”，而是本机在飞书主控制面实际观测到 Claude Opus 4.6 会出现长时间卡住 / 超时后才回复的现象；该问题在本轮修改前一天已出现过，因此当前只把“切到 g54 并恢复稳定响应”记录为**经验性处置结果**，不把“Claude 4.6 一定是根因”写成已证事实。
- `motchat-claude-4-6/*` 与 `motchat-gpt-max/*` 仍保留在模型矩阵中，可通过显式 model 路径或 alias 切换；默认值仅代表当前最稳妥运行选择。

### 12.1.2 Phase 1A `main` agent 当前 live config 要点
- `main.workspace = /var/lib/openclaw/.openclaw/workspace-main`
- `main.subagents.allowAgents = ["task-runner"]`
- `main.tools.allow = ["read","write","edit","sessions_list","sessions_history","sessions_send","sessions_spawn","session_status"]`
- `main.tools.deny = ["exec","process","apply_patch","elevated"]`
- `main.tools.elevated.enabled = false`
- 当前 `main` 可以作为 Feishu 主会话入口正常对话、读取 workspace 内文件、列出工具、回答自身角色与 worker allowlist、拒绝直接宿主机 shell 请求，但 **仍不具备受控 host-side action 能力**。

### 12.2 环境文件（`/etc/openclaw/openclaw.env`）
- 权限：`0640 root:openclaw`，`nick` 用户不可直接读取
- 当前包含：
  - `OPENCLAW_GATEWAY_TOKEN=`（随机强 token）
  - `DEEPSEEK_API_KEY=`（DeepSeek API Key）
  - `FEISHU_APP_SECRET=`（飞书应用 appSecret，2026-03-04 21:24 迁入）
  - `MOTCHAT_API_KEY=`（MotChat 中转站 API Key，2026-03-05 11:41 新增，用于 Claude 4.6 + GPT 5.x 系列）

### 12.3 systemd 主 unit（`/etc/systemd/system/openclaw-gateway.service`）

```ini
[Unit]
Description=OpenClaw Gateway (system service, non-root)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/var/lib/openclaw

Environment="HOME=/var/lib/openclaw"
Environment="OPENCLAW_HOME=/var/lib/openclaw"
Environment="OPENCLAW_STATE_DIR=/var/lib/openclaw/.openclaw"
Environment="OPENCLAW_CONFIG_PATH=/etc/openclaw/openclaw.json"
EnvironmentFile=/etc/openclaw/openclaw.env

ExecStartPre=/usr/bin/install -d -m 0700 -o openclaw -g openclaw /var/lib/openclaw/.openclaw
ExecStartPre=/usr/bin/install -d -m 0700 -o openclaw -g openclaw /var/lib/openclaw/.openclaw/workspace
ExecStartPre=/usr/bin/install -d -m 0700 -o openclaw -g openclaw /var/lib/openclaw/.openclaw/credentials
ExecStartPre=/usr/bin/install -d -m 0755 -o openclaw -g openclaw /var/log/openclaw

ExecStart=/opt/openclaw/node_modules/.bin/openclaw gateway

Restart=on-failure
RestartSec=2s
TimeoutStopSec=30s

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/openclaw /var/log/openclaw
ReadOnlyPaths=/opt/openclaw /etc/openclaw
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
CapabilityBoundingSet=
AmbientCapabilities=

[Install]
WantedBy=multi-user.target
```

补充说明：
- 该 unit 当前仍只确保基础运行目录与默认 `workspace` 存在。
- `workspace-main` 目前由 **受控发布流程** 在 host-side 创建并 rsync 发布，不依赖该 unit 的 `ExecStartPre` 自动生成。
- 因为 `/var/lib/openclaw` 是独立子卷，任何首次创建 `workspace-main` 的动作都属于 **host-side write**，必须纳入变更前快照纪律。

### 12.4 Drop-in：允许 AF_NETLINK（修复 `error 97`）
路径：`/etc/systemd/system/openclaw-gateway.service.d/10-address-families.conf`

```ini
[Service]
# Node/libuv 枚举网卡需要 AF_NETLINK；否则可能报 uv_interface_addresses ... error 97
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
```

### 12.5 Drop-in：最小 PATH + UMask
路径：`/etc/systemd/system/openclaw-gateway.service.d/20-path-umask.conf`

```ini
[Service]
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
UMask=0077
```

> 注：OpenClaw CLI 的 `doctor/status --deep` 会持续提示：
> - `Service: systemd (disabled)`
> - `~/.openclaw/openclaw.json missing`
> - `systemctl --user unavailable`
>
> 这是预期行为，**不要使用 `openclaw doctor --repair` 去”修复”**，否则会引入 user-level daemon，破坏当前目录边界策略。

### 12.6 Broker systemd unit（`/etc/systemd/system/openclaw-broker.service`）

> 2026-03-14 Phase 2 broker deployment 落地。

```ini
[Unit]
Description=OpenClaw Host-Ops Broker
After=network.target openclaw-gateway.service
Requires=openclaw-gateway.service

[Service]
Type=simple
ExecStart=/opt/openclaw/broker/openclaw-broker --listen --log-file /var/log/openclaw/broker/broker.log
RuntimeDirectory=openclaw
RuntimeDirectoryMode=0755
User=root
Group=root
Environment=BROKER_DRY_RUN=false
ProtectHome=yes
PrivateTmp=yes
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-broker

[Install]
WantedBy=multi-user.target
```

**运行时注意**：因 `Requires=openclaw-gateway.service`，当 gateway 被重启时 broker 也会被 SIGTERM 并由 systemd 重启。通过 broker 发送 `gateway_restart` 请求时，broker 自身的请求返回值可能为 `E_BROKER_INTERNAL`，此时应以 gateway + broker 的 post-restart 状态作为成功判据，而非 broker 请求返回值。

## 13. 运维 SOP（日常 / 变更 / 备份 / 回滚 / 排障 / 发布）

### 13.1 日常操作（systemd）
```bash
# 状态
sudo systemctl status --no-pager openclaw-gateway.service

# 启动 / 停止 / 重启
sudo systemctl start openclaw-gateway.service
sudo systemctl stop openclaw-gateway.service
sudo systemctl restart openclaw-gateway.service

# 查看日志（推荐）
sudo journalctl -u openclaw-gateway.service -n 200 --no-pager
sudo journalctl -u openclaw-gateway.service -f --no-pager
```

### 13.2 健康检查
> 注意：`/etc/openclaw/openclaw.env` 为 `0640 root:openclaw`，普通用户（`nick`）默认无权读取。  
> 若在交互 shell 中启用了 `set -e`，health 失败会导致 shell 退出（表象像 SSH 断线）。推荐使用下面带重试的模板。  
> 刚执行 `systemctl restart openclaw-gateway.service` 后，**立即**做单次 health 可能命中启动窗口期，返回 `gateway closed (1006 abnormal closure)`；这不等同于配置已损坏。应按下述模板重试，并同时查看 `journalctl -u openclaw-gateway.service`。  
> 注：`openclaw gateway health` 输出中的 `Config: /var/lib/openclaw/.openclaw/openclaw.json` 可能只是 CLI 的默认路径提示；本机 systemd 部署的权威配置仍以 `/etc/openclaw/openclaw.json` 为准。若怀疑 state 目录残留旧文件，应执行 `sudo diff -u /var/lib/openclaw/.openclaw/openclaw.json /etc/openclaw/openclaw.json || true` 交叉核对。

```bash
set +e

for i in $(seq 1 20); do
  sudo -u openclaw -H bash -c '
    set -euo pipefail
    source /etc/openclaw/openclaw.env
    /opt/openclaw/node_modules/.bin/openclaw gateway health --url ws://127.0.0.1:17777 --token "$OPENCLAW_GATEWAY_TOKEN"
  ' >/dev/null 2>&1

  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "Gateway health: OK"
    break
  fi

  echo "health attempt $i failed (rc=$rc); last logs:"
  sudo journalctl -u openclaw-gateway.service -n 12 -o cat --no-pager
  sleep 1
done

# 可见输出的 health + status
sudo -u openclaw -H bash -c '
  set -euo pipefail
  source /etc/openclaw/openclaw.env
  /opt/openclaw/node_modules/.bin/openclaw gateway health --url ws://127.0.0.1:17777 --token "$OPENCLAW_GATEWAY_TOKEN"
  /opt/openclaw/node_modules/.bin/openclaw gateway status --url ws://127.0.0.1:17777 --token "$OPENCLAW_GATEWAY_TOKEN" --deep
'

set -e
```

### 13.3 监听与本机访问（默认仅 loopback）
```bash
sudo ss -tlnp | grep openclaw
```

#### 13.3.1 Windows / 远端浏览器访问（SSH 隧道）
在 Windows PowerShell：
```powershell
ssh -f -N -L 17777:127.0.0.1:17777 -L 17779:127.0.0.1:17779 nick@<HOST_IP>
```

然后在浏览器访问：
- `http://127.0.0.1:17777/`（Dashboard，输入 `OPENCLAW_GATEWAY_TOKEN` 连接）
- `http://127.0.0.1:17779/`（Browser control，token auth）

### 13.4 修改配置
当前**默认做法**不再是“直接手改 `/etc/openclaw/openclaw.json`”，而是：

1. 在开发仓库生成候选文件；
2. 抓 live baseline；
3. 做 pre-change snapshot；
4. 部署候选到 `/etc/openclaw/openclaw.json`；
5. 重启 gateway；
6. 执行带重试 health；
7. 做 post snapshot；
8. Vault 入库；
9. 把 post-state 再抓回开发仓。

紧急修复时可以临时直接编辑 `/etc/openclaw/openclaw.json`，但**事后必须立即回补**：
- 候选文件；
- delta / validation 文档；
- 变更记录；
- post-state 抓取。

> ⚠️ 修改配置时若涉及凭证，应将凭证写入 `/etc/openclaw/openclaw.env`，json 中使用 `${变量名}` 引用，禁止明文写入 json。  
> ⚠️ 若本次修改涉及 `models.providers` 或 `agents.defaults.model / agents.list / tools`：
> - 修改后至少执行一次带重试的 `gateway health`
> - 至少对新增 provider / model 做一次**真实调用验证**，不要仅以网关启动成功代替上游模型可用性验证
> - 若使用第三方中转站，面板展示名不一定等于真实 API model id；health 通过但真实调用失败时，应优先怀疑 model id 映射问题

### 13.5 变更流程（升级 OpenClaw / 修改配置 / 发布 runtime artifact）
**原则：任何 host-affecting 变更都必须可回滚。**

#### 13.5.1 总原则
- **pre-change snapshot 必须发生在第一笔 host-side write 之前。**
- 这里的“第一笔 host-side write”不仅包括编辑 `/etc/openclaw/openclaw.json`，也包括：
  - 创建 `/var/lib/openclaw/.openclaw/workspace-main`
  - 发布 runtime workspace
  - 部署 plugin / wrapper / broker
  - 修改 systemd unit / timer / host-side 脚本
- 由于 `/var/lib/openclaw` 是独立子卷，root snapshot **不会**保护其内部内容；因此发布到该子卷的任何内容，都必须被视为单独的 host-side 变更动作。

#### 13.5.2 变更前（强制）
```bash
set -euo pipefail

# 可选：先抓 live baseline 到开发仓
# 例如：cp /etc/openclaw/openclaw.json ~/projects/openclaw-dev/candidates/openclaw.live.json

sudo btrfs subvolume snapshot -r / "/.snapshots/root-pre-change-$(date +%F-%H%M)"
sudo /usr/local/sbin/vault-backup-root-btrfs
```

#### 13.5.3 升级 OpenClaw（`/opt/openclaw`）
> 推荐：避免 `openclaw@latest`；使用明确版本号并记录。
```bash
set -euo pipefail
sudo systemctl stop openclaw-gateway.service
cd /opt/openclaw
sudo npm install --omit=dev openclaw@<PINNED_VERSION>
sudo systemctl start openclaw-gateway.service
```

#### 13.5.4 配置 / workspace 发布（推荐流程）
A. 配置发布：
- 在开发仓生成 candidate；
- 与 live baseline 做 diff；
- pre snapshot；
- 部署到 `/etc/openclaw/openclaw.json`；
- gateway restart；
- health；
- post snapshot；
- Vault 入库；
- post-state 抓回开发仓。

B. workspace 发布：
- `workspace-main/` 模板在开发仓维护；
- 以受控方式发布到 `/var/lib/openclaw/.openclaw/workspace-main/`；
- 发布后 runtime workspace 只做运行，不作为权威源长期手工维护。

C. 文档发布：
- 权威 SOP 源先更新；
- 再同步到开发仓；
- 最后发布到 `workspace-main/control/SOP.md`；
- 不靠 runtime 目录反向回写权威源。

#### 13.5.5 变更后（强制：验收 + 快照 + 入库）
```bash
# 健康检查（建议用 13.2 的模板）
sudo -u openclaw -H bash -c '
  set -euo pipefail
  source /etc/openclaw/openclaw.env
  /opt/openclaw/node_modules/.bin/openclaw gateway health --url ws://127.0.0.1:17777 --token "$OPENCLAW_GATEWAY_TOKEN"
'

# 里程碑快照 + 入库
sudo btrfs subvolume snapshot -r / "/.snapshots/root-post-change-$(date +%F-%H%M)"
sudo /usr/local/sbin/vault-backup-root-btrfs
```

### 13.6 故障排查（常见问题与处理）

#### 13.6.1 OpenClaw 启动崩溃：`uv_interface_addresses ... error 97`
症状：journal 中出现 `uv_interface_addresses returned Unknown system error 97`  
原因：systemd 沙箱 `RestrictAddressFamilies` 未允许 `AF_NETLINK`  
处理：确认 drop-in `10-address-families.conf` 存在并包含 `AF_NETLINK`，然后重启服务：
```bash
sudo systemctl cat openclaw-gateway.service
sudo systemctl daemon-reload
sudo systemctl restart openclaw-gateway.service
```

#### 13.6.2 health 报 `1006 abnormal closure`（但端口在 listen）
原因：重启后的启动窗口，WS 端口已监听但内部尚未 ready（约需 12 秒）  
处理：使用 13.2 的重试模板；或等待后重试。

#### 13.6.3 读取 `/etc/openclaw/openclaw.env` “权限不够”
原因：文件为 `0640 root:openclaw`，`nick` 默认不可读。  
处理：用 `sudo -u openclaw ... source /etc/openclaw/openclaw.env` 运行；不要把 token 打印到终端 / 历史。

#### 13.6.4 `npm install` 报 `spawn git ENOENT`
原因：系统缺 git，但依赖链需要 git 拉取。  
处理：`sudo apt install -y git`

#### 13.6.5 “复制命令带 UI 引用”导致 `set` 报错
现象：终端出现 `set: pipe:contentReference...: 无效的选项名`  
原因：从聊天界面复制时带入引用标记。  
处理：只复制代码块内内容；或先粘贴到纯文本编辑器清洗后再执行。

#### 13.6.6 飞书不加载 / 启动日志无 feishu
原因：最常见原因是配置写在了 `/var/lib/openclaw/.openclaw/openclaw.json` 而非 `/etc/openclaw/openclaw.json`。  
处理：
```bash
sudo grep -i feishu /etc/openclaw/openclaw.json  # 确认配置在正确位置
sudo systemctl restart openclaw-gateway.service
```

#### 13.6.7 `low context window` 警告
症状：日志出现 `low context window: ... ctx=16000 (warn<32000)`  
处理：将 `/etc/openclaw/openclaw.json` 中对应模型的 `contextWindow` 改为 `65536` 或更大，重启服务。

#### 13.6.8 发现 `18789` 端口在监听（双 gateway 问题）
原因：`nick` 用户的 user-level gateway 被意外启动（通常由 onboard 引起）。  
处理：
```bash
systemctl --user stop openclaw-gateway.service
systemctl --user disable openclaw-gateway.service
rm -f ~/.config/systemd/user/openclaw-gateway.service
systemctl --user daemon-reload
# 确认清理：应只剩 17777/17779/17780
sudo ss -tlnp | grep openclaw
```

#### 13.6.9 登录提示 `~/.openclaw/completions/openclaw.bash` 不存在
原因：onboard 写入了 `.bashrc` 引用。  
处理：
```bash
sed -i '/openclaw.*completions/d' ~/.bashrc
source ~/.bashrc
```

#### 13.6.10 Gateway 崩溃：`plugin manifest not found`
症状：journal 中出现 `plugin manifest not found: .../openclaw.plugin.json`  
原因：`/var/lib/openclaw/.openclaw/extensions/` 下存在缺少 `openclaw.plugin.json` 的目录；OpenClaw 自动扫描此目录，发现无效 plugin 会拒绝启动。  
处理：
```bash
# 删除有问题的 plugin 目录
sudo rm -rf /var/lib/openclaw/.openclaw/extensions/<问题目录>
sudo systemctl restart openclaw-gateway.service
```

#### 13.6.11 Gateway 崩溃：`Unrecognized key in plugins.entries`
症状：journal 中出现 `Unrecognized key: "installPath"` 或其他未知 key。  
原因：`plugins.entries.<id>` 使用 Zod strict schema，只接受已知字段（`enabled`、`config`）。  
处理：
```bash
# 从配置中移除非法字段，只保留 enabled 和 config
sudo nano /etc/openclaw/openclaw.json
# 将 "plugin-id": { enabled: true, installPath: "..." }
# 改为 "plugin-id": { enabled: true }
sudo systemctl restart openclaw-gateway.service
```

#### 13.6.12 `main` 只有 session 工具、不能读 SOP
优先排查：
1. `/etc/openclaw/openclaw.json` 中是否仍存在全局 `tools: { profile: "messaging" }`
2. `agents.list[main].tools.allow` 是否已正确包含 `read / write / edit`
3. gateway 重启后是否真正加载了更新后的配置
4. 用飞书直接让 bot 列工具名进行黑盒验证

#### 13.6.13 飞书消息长时间无回复，但最终很久后才补发
优先排查：
1. `journalctl -u openclaw-gateway.service -f --no-pager`
2. 是否出现 `embedded run timeout ... timeoutMs=600000`
3. 是否出现 `typing TTL reached (2m)` 但未及时完成回复
4. 当前默认模型是否仍为 Claude 4.6 路径
5. 先切到 `g54` 做 A/B 验证，再决定是否继续深挖模型路径根因

### 13.7 备份策略（root 系统层 + 运行态控制面层）

#### 13.7.1 根系统层（现有）
- 自动备份：`OnCalendar=*-*-* 03:40:00`
- 手动触发：
```bash
sudo /usr/local/sbin/vault-backup-root-btrfs
```
- 验证 Vault 离线：
```bash
findmnt /mnt/vault && echo "WARNING: vault is mounted" || echo "OK: vault is unmounted"
```

根系统层当前持续保护：
- `/.snapshots/*`
- Vault 中 `recv/system/*`
- `/etc/openclaw/*`
- `/opt/openclaw`
- systemd unit / drop-in
- `/usr/local/sbin/vault-backup-root-btrfs`
- 与 broker / wrapper / 备份脚本 / Docker 权限边界相关的 host 侧代码

#### 13.7.2 运行态控制面层（新增设计目标，尚未实施）
从现在开始，不再把 `/var/lib/openclaw` 整体简单视为”完全不值得备份”的黑盒。
建议后续新增单独备份 / 导出策略，优先覆盖：
- `/var/lib/openclaw/.openclaw/workspace-main/control/state/`
  - `pending-approvals.json`
  - `last-health.md`
  - `last-sop-hash.txt`
  - `last-task-index.json`
- `/var/lib/openclaw/.openclaw/extensions/`
  - 尤其是已部署、未在系统包管理器中声明、且带本地修改的 plugin
- `/var/lib/openclaw/.openclaw/cron/`（若启用）
- `/var/lib/openclaw/backup/`
  - 尤其 `last_sent` 与可能新增的运行时备份元数据
- 后续 broker 状态目录、request log 索引与 wrapper 审计索引

> **2026-03-09 补充，2026-03-10 修订**：开发仓 `docs/runtime-allowlist-backup-draft.md` 已从草案升级为**设计定稿候选（design candidate）**——将 `/var/lib/openclaw` 内容分为三类（A: 必须备份的控制面状态、B: 可由 publish 重建的内容、C: 高 churn 排除项），定义了各类的恢复语义与恢复优先级（P0–P5），并增加了实施约束（权限、路径白名单、原子性、Vault 操作、幂等性、与 publish 脚本的关系、验收条件）。该设计稿为结构化设计参考，**尚未转化为可执行的备份脚本，也未在生产中启用**。

#### 13.7.3 运行态噪声层（默认不做强恢复）
默认不纳入严格里程碑恢复的对象：
- 临时 session memory
- 临时 canvas
- 可完全由 repo 重新发布的 `workspace-main` 静态模板文件
- 大体积临时任务输出
- 高频变动但恢复价值较低的调试日志全文

> 结论：
> - **根快照链继续保留；**
> - **但不应再把 `/var/lib/openclaw` 整体视为“完全不值得备份”的黑盒。**
> - 下一步应设计“`/var/lib/openclaw` 选择性控制面备份”方案，而不是把所有运行态一股脑重新纳入 root snapshot。

### 13.8 控制仓库、开发仓、运行时副本与任务仓的 Git / 发布模型

#### 13.8.1 四类对象必须严格区分
A. **权威控制仓库（authoritative control repo）**
- 原设计建议路径：`/srv/openclaw-control/`
- **当前实际状态**：权威控制仓库尚未独立运作；当前 SOP 与设计稿的实际编辑入口是开发仓 `~/projects/openclaw-dev/docs/host-sop.md` 与 `docs/design-v3.md`
- 未来目标：当 `/srv/openclaw-control/` 正式启用后，权威源迁移到该仓库；在此之前，开发仓中的文档即为权威源
- 角色：宿主机控制规范、SOP、runbook、控制面文档的**单一真相源**
- 说明：`workspace-main/control/SOP.md` 不得被视为手工主编辑点

B. **开发仓库（development repo）**
- 当前路径：`~/projects/openclaw-dev/`
- 角色：
  - 使用 Claude Code CLI 与人工协作开发
  - 维护 broker / plugin / publish script / workspace 模板 / 候选配置 / 测试 / 设计稿
  - **当前同时承担权威控制文档的编辑入口**（`docs/host-sop.md`、`docs/design-v3.md`）
- 说明：这是日常 Git commit 的主开发仓；不是 system gateway 运行目录

C. **运行时发布副本（runtime published artifact）**
- 当前主路径：`/var/lib/openclaw/.openclaw/workspace-main/`
- 角色：供现网 `main` agent 读取和写入的控制面 workspace
- 说明：这是**发布产物**，不是权威源；应由 publish 流或受控 rsync 生成，不应长期手工直接维护

D. **任务级工程仓（per-task repo）**
- 设计路径：`/var/lib/openclaw/.openclaw/workspace-task-runner/tasks/<task-id>/repo/`
- 角色：未来 `task-runner` / 容器内 Claude Code 执行单次工程任务的项目根
- 说明：这是任务工作仓，可按任务创建、归档、清理；不是长期宿主控制仓

#### 13.8.2 权威源、开发仓、副本之间怎么流动
统一工作原则：
1. 宿主机控制规范（尤其 SOP）当前的权威编辑入口是开发仓：`~/projects/openclaw-dev/docs/host-sop.md`（未来 `/srv/openclaw-control/` 正式启用后迁移）
2. 运行时副本：`/var/lib/openclaw/.openclaw/workspace-main/control/SOP.md`（由 `scripts/publish-sop.sh` 从开发仓 `docs/host-sop.md` 发布）
3. 未来 task-runner 任务仓中的 SOP 副本：`tasks/<task-id>/repo/docs/host-sop.md`
4. 统一原则：
   - **改权威源**（当前即开发仓）
   - **发布到副本**
   - **副本供运行**
   - **不靠 symlink，不靠 runtime 目录手工直改**

#### 13.8.3 日常 Git 使用规则
1. 日常开发提交发生在：`~/projects/openclaw-dev/`
2. 权威控制文档当前也在开发仓编辑和提交（未来迁移到独立控制仓后，此条更新）
3. `workspace-main` 不是 Git 主仓，不要求在运行时 workspace 直接 `git init` / `git commit`
4. `tasks/<task-id>/repo/` 是任务级工程仓，可临时 clone / init，但不承担宿主控制真相管理
5. 配置候选文件必须先进入开发仓版本化，再部署到 `/etc/openclaw/openclaw.json`
6. live config baseline 应在每轮重要配置变更前后抓取入开发仓

#### 13.8.4 发布工作流
A. 文档发布：
- 在开发仓编辑 SOP（`~/projects/openclaw-dev/docs/host-sop.md`）；
- 发布到 runtime：`workspace-main/control/SOP.md`（使用 `scripts/publish-sop.sh`，自动附加 SHA256 + 时间戳头）

B. workspace 发布：
- `workspace-main/` 模板文件在开发仓维护（`workspace-main-template/` 目录）；
- 受控发布到 `/var/lib/openclaw/.openclaw/workspace-main/`
- 开发仓已提供发布与校验脚本：
  - `scripts/publish-workspace-main.sh`：从 `workspace-main-template/` 发布到目标目录，保留 `control/state/`，自动调用 `publish-sop.sh`；默认 dry-run + 拒绝写入生产路径；`--allow-live-target` flag 可解锁唯一指定的 live workspace 路径（需 `--apply` + 交互确认 + TTY 检查）
  - `scripts/publish-sop.sh`：从 `docs/host-sop.md` 发布到 `control/SOP.md`，附加 SHA256 与时间戳头，写入 `last-sop-hash.txt`；无条件拒绝 live path（live 场景由 `publish-workspace-main.sh` inline 处理）
  - `scripts/check-workspace-main.sh`：校验 workspace-main 结构完整性（区分模板模式 vs 发布产物模式），含 SOP hash 交叉校验
  - `scripts/preflight-first-live-publish.sh`：首次 live publish 只读预检脚本，验证开发仓侧所有前置条件（不访问 live path），输出 Go/No-Go 结论
- 首次现网脚本化发布 operator runbook：`docs/runbook-first-live-publish.md`（含 Go/No-Go checklist 与证据采集要求，2026-03-11 首次执行完成）
- 首次现网发布执行包：`docs/execution-pack-first-live-publish.md`（分步命令块 + 人工确认点 + 回退速查卡，2026-03-11 首次执行完成）
- 现场记录模板：`docs/templates/first-live-publish-record-template.md`
- 发布后文档回写模板：`docs/templates/phase1b-live-publish-syncback-template.md`
- 现场执行记录：`docs/records/first-live-publish-2026-03-11.md`

C. 配置发布：
- 在开发仓生成候选配置；
- 用 live baseline 做 diff；
- pre snapshot；
- 部署到 `/etc/openclaw/openclaw.json`；
- restart gateway；
- health；
- post snapshot；
- Vault 入库；
- post-state 抓回开发仓归档

### 13.9 Claude Code CLI 现状、配置与使用边界（截至 2026-03-07）

#### 13.9.1 当前安装状态
Claude Code CLI 当前已由 `nick` 用户安装在用户域：
- 安装位置：`~/.local/bin/claude`
- 已安装版本：`2.1.58`

本机实际安装过程中：
- 直接使用 `socks5h://127.0.0.1:7890` 作为 `ALL_PROXY / HTTP_PROXY / HTTPS_PROXY` 时，bootstrap 取版本失败，报：
  - `UnsupportedProxyProtocol`
- 改为：
  - `HTTP_PROXY=http://127.0.0.1:7890`
  - `HTTPS_PROXY=http://127.0.0.1:7890`
- 并取消 `ALL_PROXY`
- 之后安装成功

因此本机经验规则：
- Claude Code 安装与 bootstrap 阶段，优先使用 `http://127.0.0.1:7890` 形式的 HTTP(S) 代理；
- 不把 `socks5h` 代理写为默认安装路径上的标准做法。

#### 13.9.2 本机当前接入方式
本机当前并非使用 Claude 官方登录态直连，而是通过 MotChat 中转站接入 Claude Code。  
建议会话环境变量：
- `PATH="$HOME/.local/bin:$PATH"`
- `HTTP_PROXY='http://127.0.0.1:7890'`
- `HTTPS_PROXY='http://127.0.0.1:7890'`
- `ANTHROPIC_BASE_URL='https://new.motchat.com'`
- `ANTHROPIC_AUTH_TOKEN='<token>'`
- `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`

说明：
- `ANTHROPIC_AUTH_TOKEN` 用于自定义 Authorization 头；
- `ANTHROPIC_BASE_URL` 用于把请求指向中转 / gateway；
- 当网关采用 Anthropic Messages 兼容路径但对实验性 betas 不完全兼容时，可需要：
  - `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`

#### 13.9.3 Claude Code 在本体系中的双角色
A. **`nick` 用户的开发工具**
- 运行位置：`nick` 用户 shell / SSH / 图形终端
- 工作目录：`~/projects/openclaw-dev/`
- 用途：开发 broker / plugin / publish script / 候选配置 / workspace 模板 / 测试
- 硬边界：
  - 绝不替代 system gateway
  - 绝不以 `openclaw` 用户登录
  - 绝不把它当成宿主后台常驻控制面

B. **未来 `task-runner` 容器内工程执行器**
- 运行位置：OpenClaw sandbox / Docker 任务容器内
- 工作目录：`tasks/<task-id>/repo/`
- 用途：工程任务、代码改动、测试、文档整理、patch 输出
- 硬边界：
  - 不是宿主控制面
  - 不直接接触宿主机 secrets
  - 不直接修改 `/etc/openclaw`、`/opt/openclaw`、systemd、Vault

#### 13.9.4 Claude Code 项目文件与层级
Claude Code 项目级配置文件统一按以下原则理解：
- `CLAUDE.md`
  - 项目级规则文件
- `.claude/settings.json`
  - 项目共享设置，应入库
- `.claude/settings.local.json`
  - 本地私有设置，不共享
- `.claude/agents/`
  - 项目 subagents 官方位置

本机 SOP 规定：
- `~/projects/openclaw-dev/CLAUDE.md` 与 `.claude/settings.json` 用于开发仓开发流程；
- 未来 `tasks/<task-id>/repo/CLAUDE.md` 与 `.claude/agents/` 用于容器内 Claude Code 工程执行流程；
- `workspace-main` 本身不是 Claude Code 项目根，不要求按开发仓方式长期维护 `.claude/`。

### 13.10 今后继续使用 Claude Code 进行开发的标准工作流

#### 13.10.1 开发前准备
每次进入开发前，先确认：
1. 当前所在目录是：`~/projects/openclaw-dev/`
2. 没有任何 `nick` 用户级第二 gateway：
   - `~/.openclaw` 不存在
   - `~/.config/systemd/user/openclaw-gateway.service` 不存在
3. 当前 system gateway 正常：
   - `openclaw-gateway.service` 为 `active`
4. 若需要联网访问 Claude Code 中转：
   - `HTTP_PROXY / HTTPS_PROXY` 正确
   - `ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN` 正确
5. Claude Code 只在开发仓运行，不在宿主运行路径直接写配置

#### 13.10.2 日常开发循环
默认循环如下：
1. 在开发仓确定要改的目标：
   - SOP
   - design
   - candidate config
   - workspace 模板
   - script
   - plugin / broker 代码
2. 在 `~/projects/openclaw-dev/` 中用 Claude Code 进行：
   - 方案草拟
   - 文件改写
   - diff 检查
   - 脚本生成
   - repo-local 测试
3. 先把候选文件入 Git：
   - `git add`
   - `git commit`
4. 若变更涉及现网 host-side write：
   - 先抓 live baseline；
   - 先做 pre snapshot；
   - 再部署候选文件；
   - restart gateway；
   - health check；
   - post snapshot；
   - Vault 入库；
   - 再抓当前配置回仓
5. 若变更只限开发仓，不触碰宿主机运行路径：
   - 不做 host snapshot；
   - 仅走 repo commit + 测试

#### 13.10.3 何时可以让 Claude Code 直接改文件
Claude Code 可以直接改：
- `~/projects/openclaw-dev/**`
- 未来任务容器内 `tasks/<task-id>/repo/**`
- 未来任务容器内 `outputs/**`

Claude Code 不得直接改：
- `/etc/openclaw/**`
- `/opt/openclaw/**`
- `/var/lib/openclaw/.openclaw/extensions/**`
- systemd unit / timer
- `/mnt/vault/**`
- 任意 root-only 关键路径

#### 13.10.4 何时必须转成“候选文件 + 审批 / 发布”
以下事项一律先在仓库中生成候选文件，不得直接热改：
- `/etc/openclaw/openclaw.json`
- 未来 broker / wrapper 正式部署文件
- 未来 plugin 正式部署目录
- 任何会影响 system gateway、快照链、Vault 链的变更

#### 13.10.5 Claude Code 输出应如何沉淀
开发仓阶段应沉淀：
- 候选配置文件
- delta 文档
- validation checklist
- 排错分析文档
- 测试脚本
- 发布脚本
- 变更说明
- Git commit 记录

未来 task-runner 阶段应沉淀：
- `outputs/plan.md`
- `outputs/summary.md`
- `outputs/diff.patch`
- `outputs/test.log`
- `outputs/lint.log`
- `outputs/summary.json`
- 若涉及宿主机：
  - `outputs/host-change-request.json`

### 13.11 回滚与恢复（高级操作，务必谨慎）

> 重要：当前根挂载为 `subvolid=5`（顶层），并非 `@` 布局。  
> `/var/lib/openclaw` 是独立子卷，回滚根系统不会回滚运行态数据（这是设计目标之一）。

#### 13.11.1 从本地 `/.snapshots` 回滚（建议在 LiveUSB / 救援环境操作）
```bash
# 1. 挂载系统盘顶层
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt
# 2. 找到目标快照的 subvol ID
sudo btrfs subvolume list -o /mnt/.snapshots | grep 'root-post' | tail -n 5
# 3. 设置默认子卷
sudo btrfs subvolume set-default <ID> /mnt
# 4. 检查 /etc/fstab 根分区是否显式写了 subvol=
#    若没有显式 subvol=，set-default 通常可生效
#    若显式写了 subvol=/ 或 subvolid=5，需在救援环境编辑 fstab
# 5. reboot
```

#### 13.11.2 从 Vault 恢复快照到系统盘（在救援环境操作）
```bash
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/sys
sudo mount /dev/nvme1n1p1 /mnt/vault
sudo btrfs send "/mnt/vault/recv/system/<SNAPNAME>" | sudo btrfs receive "/mnt/sys/.snapshots"
# 然后按 13.11.1 设置默认子卷并 reboot
```

## 14. Hooks 与 Plugin 扩展体系（2026-03-05 验证）

### 14.1 Hook 类型与可用性（OpenClaw 2026.3.2）

OpenClaw 有两套 hook 体系，经本机实测可用性如下：

| Hook 体系 | 事件名 | 2026.3.2 可用 | 说明 |
|-----------|--------|:---:|------|
| 内部 Hook（HOOK.md） | `agent:bootstrap` | ✅ | 每次 agent 启动时触发 |
| 内部 Hook（HOOK.md） | `command:new` / `command:stop` | ✅ | 命令事件 |
| 内部 Hook（HOOK.md） | `agent:tool:start` / `agent:tool:end` | ❌ | PR #18889 未合并，不可用 |
| 内部 Hook（HOOK.md） | `agent:thinking:*` / `agent:response:*` | ❌ | PR #18889 未合并，不可用 |
| Plugin SDK | `before_tool_call` | ✅ | **已验证可用，每次工具调用前触发** |
| Plugin SDK | `after_tool_call` | ✅ | **已验证可用，每次工具调用后触发** |
| Plugin SDK | `gateway_start` | ✅ | gateway 启动时触发 |

**结论**：如需在工具执行前拦截审计（如接入 vLLM 安全门控），应使用 **Plugin SDK 的 `before_tool_call`**，而非内部 Hook 的 `agent:tool:start`。

### 14.2 当前已部署的 Hook 与 Plugin

#### 内部 Hook：tool-audit-probe（诊断用）
- 路径：`/var/lib/openclaw/.openclaw/hooks/tool-audit-probe/`
- 文件：`HOOK.md` + `handler.ts`
- 日志：`/var/log/openclaw/tool-audit-probe.log`
- 用途：诊断内部 hook 事件触发情况
- 配置：`/etc/openclaw/openclaw.json` → `hooks.internal.entries."tool-audit-probe".enabled: true`

#### Plugin：tool-audit-plugin（诊断用，后续改造为 vLLM 审计）
- 路径：`/var/lib/openclaw/.openclaw/extensions/tool-audit-plugin/`
- 文件：`openclaw.plugin.json` + `package.json` + `index.js`
- 日志：`/var/log/openclaw/tool-audit-plugin.log`
- 用途：验证 Plugin SDK `before_tool_call` / `after_tool_call` 可用性
- 配置：`/etc/openclaw/openclaw.json` → `plugins.allow` 含 `"tool-audit-plugin"` + `plugins.entries."tool-audit-plugin".enabled: true`
- **当前行为**：仅记录日志，**不拦截任何操作**，所有工具调用正常执行

### 14.3 本地 Plugin 开发 SOP

> ⚠️ **extensions 目录是自动扫描的**。任何放入 `/var/lib/openclaw/.openclaw/extensions/` 的子目录都会被 gateway 尝试加载。缺少 `openclaw.plugin.json` 会导致 gateway 崩溃。

#### 必需文件清单（最小化 plugin）

```
extensions/<plugin-name>/
├── openclaw.plugin.json    ← 必需：plugin manifest（缺失则 gateway 崩溃）
├── package.json            ← 必需：npm 包声明
└── index.js                ← 入口文件
```

#### openclaw.plugin.json 最小模板
```json
{
  "id": "<plugin-name>",
  "name": "Plugin Display Name",
  "description": "What this plugin does",
  "configSchema": {
    "type": "object",
    "additionalProperties": false,
    "properties": {}
  }
}
```

#### package.json 最小模板
```json
{
  "name": "@local/<plugin-name>",
  "version": "0.0.1",
  "main": "index.js",
  "openclaw": {
    "extensions": ["./index.js"]
  }
}
```

#### 配置注册（/etc/openclaw/openclaw.json）
```json5
plugins: {
  allow: ["feishu", "<plugin-name>"],  // 加入白名单
  entries: {
    feishu: { enabled: true },
    "<plugin-name>": { enabled: true },  // 只允许 enabled 和 config 字段
  },
  // ... installs 段不变
},
```

#### 关键注意事项
1. `plugins.entries.<id>` **只接受** `enabled` 和 `config` 字段，其他字段（如 `installPath`）会导致 schema 校验失败
2. `configSchema` 即使无配置也必须提供空 schema（`{ "type": "object", "additionalProperties": false, "properties": {} }`）
3. Plugin 的 `register(api)` 中通过 `api.on("before_tool_call", handler)` 注册 hook
4. Plugin 运行在 gateway 进程内，崩溃会影响 gateway，务必做好异常处理
5. **测试新 plugin 前必须打快照**（SOP 13.5.1）

### 14.4 vLLM 安全审计 Plugin 架构（2026-03-05 已实装）

已于 2026-03-05 16:00 完成 `tool-audit-plugin` 改造并验证。

#### 架构

```
Agent 请求执行工具
       ↓
[Gateway exec approval]  ← 第一层：allowlist + 模式匹配（确定性，零延迟）
       ↓ 通过
[before_tool_call hook]  ← 第二层：调用本地 vLLM 审计（语义级，有延迟）
       ↓
   vLLM 判定 SAFE  → 执行
   vLLM 判定 DENY  → 拒绝 + 写审计日志
   vLLM 超时/出错  → 默认拒绝（fail-closed）
```

#### 当前部署

| 项目 | 值 |
|------|----|
| 模型 | Qwen2.5-7B-Instruct-AWQ（AWQ 4-bit） |
| 模型路径 | `/data/models/Qwen2.5-7B-Instruct-AWQ` |
| vLLM 服务 | `vllm-audit.service`，监听 `127.0.0.1:8000` |
| vLLM 版本 | 0.16.0 |
| CUDA | 13.1（驱动 590.48.01） |
| GPU | RTX 5060 Ti 16GB |
| 超时 | 5000ms，超时默认 deny（fail-closed） |
| 审计日志 | `/var/log/openclaw/vllm-audit.log` |

#### 关键踩坑：before_tool_call event 字段名

Plugin SDK 的 `before_tool_call` event 字段名与直觉不符：

| 误以为 | 实际字段名 |
|--------|----------|
| `toolInput` | **`params`** |
| — | `toolName` |
| — | `toolCallId` |
| — | `runId` |

**`toolInput` 不存在**，使用该字段名会得到 `undefined`，调用 `.slice()` 等方法会抛出 `TypeError`，导致 `before_tool_call` 异常退出，工具被静默放行（不拦截）。

#### ⚠️ 已知问题：before_tool_call 为软性门控

**问题描述**：在 OpenClaw 2026.3.2 中，`before_tool_call` 返回 `{ allow: false }` **不能硬性阻断**工具执行。实测日志中 `vllm_error`（fail-closed deny）和 `deny_vllm` 之后，仍然出现了对应的 `after_tool_call`，说明工具实际已执行。

**表现**：
```
before_tool_call → vLLM timeout → deny（fail-closed）  ← 记录了拒绝
after_tool_call  → 工具结果返回                         ← 但工具仍然执行了！
```

**当前状态**：审计日志记录完整，但门控是**软性**的（仅审计，不拦截）。

**待确认与优化**（TODO）：
1. 查阅 OpenClaw Plugin SDK 文档，确认 `before_tool_call` 硬性拦截的正确返回值语义
   - 可能需要抛出异常（`throw new Error(...)`）而非返回 `{ allow: false }`
   - 也可能是该版本尚未支持硬性拦截（需等待 upstream 更新）
2. 升级 OpenClaw 后重新验证拦截行为
3. 考虑在 vLLM 判定 DENY 时，通过飞书通知告警（即便无法阻断也能感知）

#### systemd 服务（vllm-audit.service）

```ini
[Unit]
Description=vLLM Audit Model Server (Qwen2.5-7B-Instruct-AWQ)
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vllm-env
Environment="HF_HOME=/data/models"
Environment="CUDA_VISIBLE_DEVICES=0"
ExecStart=/opt/vllm-env/bin/vllm serve \
  /data/models/Qwen2.5-7B-Instruct-AWQ \
  --host 127.0.0.1 \
  --port 8000 \
  --dtype auto \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.85 \
  --trust-remote-code
Restart=on-failure
RestartSec=10s
TimeoutStartSec=300s

[Install]
WantedBy=multi-user.target
```

#### vLLM 健康检查

```bash
curl -sf http://127.0.0.1:8000/health && echo "✅ vLLM OK"
```

#### 审计日志格式（正常链路）

```json
{"event":"gateway_start","msg":"vllm-audit-plugin loaded"}
{"event":"before_tool_call","toolCallId":"...","toolName":"sessions_list","paramsPreview":"..."}
{"event":"vllm_verdict","toolCallId":"...","toolName":"sessions_list","verdict":"SAFE"}
{"event":"allow","toolCallId":"...","toolName":"sessions_list"}
{"event":"after_tool_call","toolCallId":"...","toolName":"sessions_list","resultPreview":"..."}
```

#### 首次推理冷启动说明

vLLM 启动后首次推理需要编译 CUDA graph，约耗时 5-30 秒，可能触发超时。
第二次起推理延迟正常（`sessions_list` 实测约 33ms）。
**不需要特殊处理**，fail-closed 冷启动超时是预期行为。

---

## 15. Phase 1A 落地记录（`main bootstrap only`，2026-03-07）

### 15.1 本阶段定位
本阶段为 **Phase 1A / main bootstrap only**，目标是让 `main` agent 在现网 OpenClaw 中正式上线，成为默认主控制代理，但**不**把 `host_ops` broker 正式接入生产执行链。

本阶段达成的是：
- 新增 `main` agent；
- 发布并落地 `workspace-main`；
- 让 `main` 具备读取 / 写入 / 编辑其 workspace 内控制文件的能力；
- 保持 `main` 无宿主机任意 shell、无 elevated、无 direct host mutation；
- `main` 仅允许 spawn 已批准 worker：`task-runner`；
- 默认主模型切换为 `motchat-gpt-max/gpt-5.4`；
- 不部署 `host_ops` plugin 正式生产版，不开放经 broker 的宿主机写操作链。

本阶段**未**达成的是：
- `host_ops` broker 正式落地；
- root-owned wrapper 链上线；
- `task-runner` 正式上线；
- Docker sandbox 执行面联调；
- `/var/lib/openclaw` 独立纳入单独备份链。

### 15.2 变更前边界与快照事实
本机根文件系统 `/` 为 btrfs，`/.snapshots` 已独立为 btrfs 子卷；同时 `/var/lib/openclaw` 也已迁移为**独立 btrfs 子卷**。因此：
- 对根 `/` 做只读快照时，**不会递归包含** `/var/lib/openclaw`；
- 根系统快照可保护 `/etc/openclaw/openclaw.json`、systemd unit、`/opt/openclaw` 等根系统内容；
- 但**不能**保护 `/var/lib/openclaw/.openclaw/workspace-main`、extensions、cron state、session state 等运行态数据；
- 因此 `workspace-main` 必须被视为**可重复发布产物**，而不是依赖 root snapshot 恢复的持久真相源；
- 任何首次创建 `/var/lib/openclaw/.openclaw/workspace-main` 的动作，都属于 host-side write，必须发生在 pre-change snapshot 之后。

本阶段实际执行的第一组里程碑快照：
- `/.snapshots/root-pre-main-agent-2026-03-07-1804`
- `/.snapshots/root-auto-2026-03-07-1804`
- Vault 接收端新增：`system/root-auto-2026-03-07-1804`

这组快照覆盖：
- `main` 配置接入前的根系统状态；
- `/etc/openclaw/openclaw.json` 变更前状态；
- 但**不覆盖** `/var/lib/openclaw` 子卷内部内容。

### 15.3 Phase 1A 的实际落地结果
本阶段实际完成了以下动作：

1. 从 live config 抽取基线副本到开发仓库：
   - `candidates/openclaw.live.json`
   - `candidates/openclaw.phase1a.current.json5`
   - `candidates/openclaw.phase1a.g54-current.json5`

2. 在开发仓库内生成并提交候选配置与验证文档：
   - `candidates/openclaw.main.candidate.json5`
   - `candidates/openclaw.main.delta.md`
   - `candidates/openclaw.main.validation.md`
   - `candidates/openclaw.phase1a.fixforward.candidate.json5`
   - `candidates/openclaw.phase1a.fixforward.delta.md`
   - `candidates/openclaw.phase1a.tool-gap.md`
   - `candidates/openclaw.phase1a.g54-default.candidate.json5`

3. 新建 runtime workspace：
   - `/var/lib/openclaw/.openclaw/workspace-main`
   - 初始通过 `install -d` 建立目录，再通过 `rsync` 从开发仓 `workspace-main/` 发布内容

4. 发布进入 runtime workspace 的文件包括（至少已验证）：
   - `AGENTS.md`
   - `TOOLS.md`
   - `IDENTITY.md`
   - `SOUL.md`
   - `USER.md`
   - `HEARTBEAT.md`
   - `control/SOP.md`
   - `control/routing-policy.md`
   - `control/approval-policy.md`
   - `control/allowed-workers.md`
   - `control/host-ops-api.md`
   - `control/runbooks/*`
   - `control/state/*`
   - `skills/*`

5. 实际写入 `/etc/openclaw/openclaw.json` 的 Phase 1A 候选配置包括：
   - 新增 `agents.list[main]`
   - `main.workspace = /var/lib/openclaw/.openclaw/workspace-main`
   - `main.subagents.allowAgents = ["task-runner"]`
   - `main.tools.allow = ["read","write","edit","sessions_list","sessions_history","sessions_send","sessions_spawn","session_status"]`
   - `main.tools.deny = ["exec","process","apply_patch","elevated"]`
   - `main.tools.elevated.enabled = false`
   - `agents.defaults.subagents` 增加：
     - `maxSpawnDepth = 2`
     - `maxChildrenPerAgent = 3`
     - `runTimeoutSeconds = 3600`
     - `archiveAfterMinutes = 120`

6. system gateway 重启与健康检查通过：
   - `openclaw-gateway.service` 重启成功；
   - health check 在启动窗口后恢复正常；
   - 日志显示 `agents.list` 与 `agents.defaults.subagents.*` 动态读取已生效。

7. `workspace-main` 权限在首次 rsync 后一度为 `775`，后已修正为：
   - owner / group：`openclaw:openclaw`
   - mode：`700`

### 15.4 工具集异常与 fix-forward 记录
Phase 1A 首次落地后，`main` 虽已上线，但实际在飞书中表现为：
- 能对话；
- 能拒绝直接宿主机 shell；
- 但无法读取 `control/SOP.md`；
- 自报可用工具仅见 session 类工具，缺失 `read` / `write` / `edit`。

经本轮排查，最可能根因是：
- 顶层配置仍保留 `tools: { profile: "messaging" }`
- 该全局 profile 实际覆盖或替代了 `agents.list[].tools.allow`
- 导致 `main` 实际只拿到 messaging 风格工具集，而没有拿到显式配置的 file tools

因此执行了单行 fix-forward：
- 从现网配置中移除顶层：
  - `tools: { profile: "messaging" }`

该变更前再次执行：
- `/.snapshots/root-pre-toolfix-2026-03-07-1830`
- `/.snapshots/root-auto-2026-03-07-1830`
- Vault 接收端新增：`system/root-auto-2026-03-07-1830`

fix-forward 后结果：
- `main` 可正常列出：
  - `read`
  - `write`
  - `edit`
  - `sessions_list`
  - `sessions_history`
  - `sessions_send`
  - `session_status`
  - `sessions_spawn`
- `main` 在飞书中已能正确回答工具清单；
- `main` 仍保持无 `exec`、无 `elevated`、无 direct host shell。

### 15.5 默认模型切换到 g54 的落地记录
在 Phase 1A 修复工具集后，又观测到以下现象：
- `main` 在飞书中有时会长时间无回复；
- 日志可见：`embedded run timeout ... timeoutMs=600000`
- 该“长时间卡住后才回复”的问题并非本轮修改后首次出现；用户确认在前一天就已经见过；
- 本轮中，重启 gateway 后机器人可立即恢复回复；
- 随后将默认主模型切换为 `motchat-gpt-max/gpt-5.4` 后，飞书侧的 `/reset`、`只回复 OK`、`列出工具名称` 等交互表现稳定。

因此当前 SOP 的结论是：
- **已证事实**
  - 将默认主模型切到 `motchat-gpt-max/gpt-5.4` 后，当前主控制面对话恢复稳定；
  - `/reset` 后飞书明确显示默认模型为 `motchat-gpt-max/gpt-5.4`。
- **未证事实**
  - 不能把“Claude Opus 4.6 一定是根因”写成已证结论；
  - 当前只能记录为“与 Claude 4.6 会话中的卡住现象存在时间相关性，重启 gateway 与切换 g54 后当前恢复正常”。

实际变更内容：
- `agents.defaults.model.primary`
  - 由：`motchat-claude-4-6/claude-opus-4-6`
  - 改为：`motchat-gpt-max/gpt-5.4`

本次改动未单独执行新的 pre snapshot，而是作为 Phase 1A 后续小范围补充变更并入文档记录。

### 15.6 Phase 1A 的 post snapshot 与完成标记
Phase 1A 完成后，已执行 post-change 里程碑快照与 Vault 入库：
- `/.snapshots/root-post-phase1a-2026-03-07-1911`
- `/.snapshots/root-auto-2026-03-07-1911`
- Vault 接收端新增：`system/root-auto-2026-03-07-1911`

执行后确认：
- `root-post-phase1a-2026-03-07-1911` 已存在；
- `/mnt/vault` 当前未保持挂载；
- 表明 Vault 盘仍遵循“备份窗口挂载、备份后立即卸载”的离线策略。

至此，Phase 1A 当前可视为：
- `main` 已正式上线；
- `main` 的 file tools 已修正；
- 默认主模型已切至 `g54`；
- 但 `host-ops` broker / `task-runner` / Docker 执行面尚未进入生产落地。

### 15.7 `workspace-main` 当前事实

#### 15.7.1 当前路径与权限
- 路径：`/var/lib/openclaw/.openclaw/workspace-main`
- 最终权限：`700`
- owner / group：`openclaw:openclaw`

> 注：首次 `rsync --chown=openclaw:openclaw` 后目录权限曾显示为 `775`，随后已手工修正回 `700`。

#### 15.7.2 当前已发布内容（至少已看到）
- `AGENTS.md`
- `SOUL.md`
- `IDENTITY.md`
- `USER.md`
- `HEARTBEAT.md`
- `TOOLS.md`
- `control/SOP.md`
- `control/allowed-workers.md`
- `control/approval-policy.md`
- `control/host-ops-api.md`
- `control/routing-policy.md`
- `control/runbooks/gateway-restart.md`
- `control/runbooks/openclaw-config-change.md`
- `control/runbooks/rollback.md`
- `control/state/last-health.md`
- `control/state/last-sop-hash.txt`
- `control/state/last-task-index.json`
- `control/state/pending-approvals.json`
- `skills/approvals/SKILL.md`
- `skills/broker/SKILL.md`
- `skills/host-sop/SKILL.md`
- `skills/routing/SKILL.md`

#### 15.7.3 重新强调其恢复语义
- `workspace-main` 是 **发布产物**；
- 根快照不恢复它；
- 真正需要恢复的是：
  - 配置 `/etc/openclaw/openclaw.json`
  - 根系统程序与 unit
  - 以及后续单独备份的 `/var/lib/openclaw` 控制面状态

### 15.8 当前运行态 `main` agent 的事实

#### 15.8.1 当前阶段标签
- **Phase 1A / main bootstrap only**

#### 15.8.2 已确认具备的能力
- 在飞书中作为主会话入口正常对话；
- 可以读取 workspace 内文件；
- 可以回答关于自身角色、workspace、worker allowlist 的问题；
- 可以列出当前工具；
- 可以拒绝直接执行 `ls /` 之类宿主机 shell 请求；
- 可以 `sessions_spawn`。

#### 15.8.3 当前工具清单（飞书实测）
- `read`
- `write`
- `edit`
- `sessions_list`
- `sessions_history`
- `sessions_send`
- `session_status`
- `sessions_spawn`

#### 15.8.4 当前尚未具备的能力
- `host_ops` 只读工具 **尚未上线**；
- broker / wrapper **尚未上线**；
- 因此当前 `main` 仍不能直接触发受控 host-side action。

## 16. 变更记录

| 时间 | 内容 |
|------|------|
| 2026-03-04 15:16 | 创建基线快照 root-baseline-pre-openclaw，入库 Vault |
| 2026-03-04 15:28 | 创建安装前快照 root-pre-openclaw-install，入库 Vault |
| 2026-03-04 15:36 | 自动备份快照 root-auto-1536 |
| 2026-03-04 16:03 | 完成 OpenClaw 裸机安装（/opt/openclaw），创建 systemd system-level 服务（User=openclaw），修复 AF_NETLINK 导致的 error 97 |
| 2026-03-04 16:24 | 完成里程碑快照 root-post-openclaw-working-1624，入库 Vault，生成审计记录 openclaw-host-audit-2026-03-04-1625.txt |
| 2026-03-04 ~18:28 | 发现 nick 用户 onboard 产生了 user-level gateway（端口 18789），与 openclaw 用户 gateway（17777）双 gateway 并存 |
| 2026-03-04 19:40 | 清理 nick 用户 onboard 产物：删除 user-level systemd 服务、~/.openclaw 残留、.bashrc 补全引用 |
| 2026-03-04 19:41 | systemd service 唯一接管，端口收敛至 17777/17779/17780 |
| 2026-03-04 19:55 | 将飞书、DeepSeek、插件、模型等所有配置迁移至 /etc/openclaw/openclaw.json |
| 2026-03-04 19:56 | 飞书 WebSocket 连接成功，所有工具注册，DeepSeek Reasoner 生效 |
| 2026-03-04 20:47 | /opt/openclaw 归属修正为 root:root，contextWindow 调整为 65536，完成本次里程碑快照并入库 |
| 2026-03-04 21:21 | SOP 全量合规审计，发现 3 项违规（extensions 权限 755、apiKey/appSecret 明文硬编码）；变更前快照 root-pre-fix-2026-03-04-2121 创建并入库 |
| 2026-03-04 21:24 | 修复全部违规：extensions 权限改为 700；DeepSeek apiKey 改为 `${DEEPSEEK_API_KEY}` 引用；飞书 appSecret 迁入 openclaw.env 并改为 `${FEISHU_APP_SECRET}` 引用；state 目录下含明文凭证的 openclaw.json 已删除；daemon-reload 完成；gateway health 验证 OK，飞书正常；里程碑快照 root-post-fix-2026-03-04-2124 创建并入库 |
| 2026-03-05 03:40 | 每日定时自动备份 root-auto-2026-03-05-0340，入库 Vault |
| 2026-03-05 11:41 | 变更前快照 root-pre-motchat-models-2026-03-05-1141 创建并入库 |
| 2026-03-05 11:54 | 通过 MotChat 中转站（`new.motchat.com`）接入 Claude 4.6 系列（5 模型）+ GPT-5.1 Codex Max 系列（5 模型）；新增 provider `motchat-claude-4-6` 和 `motchat-gpt-max`；API Key 存入 openclaw.env（`MOTCHAT_API_KEY`），json 中使用 `${MOTCHAT_API_KEY}` 环境变量引用；默认 agent 模型改为 `motchat-claude-4-6/claude-opus-4-6`；为全部 12 个模型配置了 alias 别名；gateway health OK，飞书正常 |
| 2026-03-05 11:58 | 里程碑快照 root-post-motchat-models-2026-03-05-1158 创建并入库 |
| 2026-03-05 13:47 | 变更前快照 root-pre-hook-test-2026-03-05-1347 创建并入库；开始 before_tool_call hook 可用性测试 |
| 2026-03-05 13:49 | 创建内部 Hook 探针 tool-audit-probe（`/var/lib/openclaw/.openclaw/hooks/tool-audit-probe/`），在 `/etc/openclaw/openclaw.json` 中启用 `hooks.internal`；重启 gateway 验证 hook 注册成功（5 个 internal hooks loaded） |
| 2026-03-05 14:05 | 内部 Hook 测试结果：`agent:bootstrap` 可触发，`agent:tool:start` / `agent:tool:end` **不可用**（PR #18889 未合并进 2026.3.2） |
| 2026-03-05 14:15 | 开始 Plugin SDK `before_tool_call` 测试；首次尝试因缺少 `openclaw.plugin.json` 导致 gateway 崩溃（踩坑记录：extensions 目录自动扫描机制） |
| 2026-03-05 14:22 | 第二次尝试因 `plugins.entries` 中使用非法字段 `installPath` 导致 Zod schema 校验失败，gateway 再次崩溃 |
| 2026-03-05 14:27 | 从备份恢复配置，创建正确的 plugin manifest（`openclaw.plugin.json` + `package.json` + `index.js`），注册 `before_tool_call` 和 `after_tool_call` hooks |
| 2026-03-05 14:29 | Plugin SDK 测试成功：`before_tool_call` 和 `after_tool_call` 在 2026.3.2 **均可用**，每次工具调用前后均被触发，`toolCallId` 可用于关联配对。结论：Plugin SDK 的 `before_tool_call` 是接入 vLLM 安全审计的正确扩展点 |
| 2026-03-05 14:36 | 里程碑快照 root-post-hook-test-2026-03-05-1436 创建并入库；Hook 可用性测试全部完成，SOP 更新 |
| 2026-03-05 15:02 | 变更前快照 root-pre-vllm-install-2026-03-05-1502 创建并入库；开始 vLLM 安装 |
| 2026-03-05 15:04 | 添加 NVIDIA 官方 CUDA 源（cuda-keyring_1.1-1），安装驱动 590.48.01 + CUDA 13.1；RTX 5060 Ti 16GB 验证可用（nvidia-smi OK） |
| 2026-03-05 15:11 | 安装 vLLM 0.16.0（/opt/vllm-env），安装 python3.12-dev 修复 Python.h 缺失问题 |
| 2026-03-05 15:15 | 下载 Qwen2.5-7B-Instruct-AWQ 至 /data/models/（5.57GB，AWQ 4-bit，hf-mirror.com 加速） |
| 2026-03-05 15:27 | 部署 vllm-audit.service（systemd，root，127.0.0.1:8000）；首次启动因缺少 python3.12-dev 失败；安装后重启成功 |
| 2026-03-05 15:32 | vLLM health OK；变更前快照 root-pre-vllm-plugin-2026-03-05-1532 创建并入库；开始 tool-audit-plugin 改造 |
| 2026-03-05 15:34 | 备份目录（.bak）遗留在 extensions 内导致 duplicate plugin id 警告；移出后 gateway 正常启动 |
| 2026-03-05 15:51 | 发现 before_tool_call event 字段名为 `params` 而非 `toolInput`；修复后 vLLM 审计链路完整跑通 |
| 2026-03-05 15:51 | 首次调用冷启动 vLLM timeout（fail-closed deny）；第二次调用 vllm_verdict=SAFE，33ms 完成，allow 放行，after_tool_call 正常 |
| 2026-03-05 15:51 | 发现 before_tool_call 返回 `{ allow: false }` 为**软性门控**，不能阻断工具执行（after_tool_call 仍触发）；已记录为 TODO 待确认 |
| 2026-03-05 16:00 | 里程碑快照 root-post-vllm-audit-2026-03-05-1600 创建并入库；vLLM 审计部署完成 |
| 2026-03-06 20:51 | 变更前快照 root-pre-gpt54-2026-03-06-2051 创建并入库；开始将 `motchat-gpt-max` provider 下的 GPT-5.1 Codex Max 系列替换为 GPT 5.x 新模型矩阵 |
| 2026-03-06 21:14 | `/etc/openclaw/openclaw.json` 更新完成：删除 `gpt-5.1-codex-max*` 5 个模型与旧 alias `max/maxhigh/maxlow/maxmed/maxxhigh`；新增 `gpt-5.2-codex`、`gpt-5.2-codex-high`、`gpt-5.2-codex-xhigh`、`gpt-5.2-high`、`gpt-5.2-xhigh`、`gpt-5.3-codex`、`gpt-5.4` 及对应 alias `g52codex/g52codexhigh/g52codexxhigh/g52high/g52xhigh/g53codex/g54` |
| 2026-03-06 21:15 | gateway 重启后首次立即单次 health 曾返回 `gateway closed (1006 abnormal closure)`；按重试模板再次探测后 `Gateway Health: OK`，Feishu 正常，17777 监听正常；日志确认 `config hot reload applied (models.providers.motchat-gpt-max.models)`，新配置生效 |
| 2026-03-06 22:33 | 里程碑快照 root-post-gpt54-2026-03-06-2233 创建并入库；自动备份快照 root-auto-2026-03-06-2233 已发送至 Vault；`last_sent` 更新为 `root-auto-2026-03-06-2233` |
| 2026-03-07 18:04 | 创建 `root-pre-main-agent-2026-03-07-1804`，随后执行 Vault sync；作为 Phase 1A `main` bootstrap 前里程碑 |
| 2026-03-07 18:04~18:05 | 创建并发布 `/var/lib/openclaw/.openclaw/workspace-main`；将 `workspace-main/*` 发布为运行态 artifact；初始目录权限一度为 `775`，后续修正为 `700` |
| 2026-03-07 18:04~18:05 | 备份 `/etc/openclaw/openclaw.json`，部署 `openclaw.main.candidate.json5`，重启 gateway，带重试 health 验证通过 |
| 2026-03-07 18:07~18:09 | 飞书黑盒验证发现：`main` 虽已上线，但只能看到 session 工具，不能实际读取 `control/SOP.md`；同时能正确拒绝直接执行宿主机 shell |
| 2026-03-07 18:18 左右 | 在开发仓库中完成工具缺口根因分析：全局 `tools.profile: "messaging"` 压制 per-agent `tools.allow`；生成 `openclaw.phase1a.tool-gap.md`、`openclaw.phase1a.fixforward.delta.md` 与 `openclaw.phase1a.fixforward.candidate.json5` |
| 2026-03-07 18:30 | 创建 `root-pre-toolfix-2026-03-07-1830`，随后执行 Vault sync；部署 fix-forward candidate（移除全局 `tools.profile`），重启 gateway，health OK |
| 2026-03-07 18:31~18:42 | 飞书与日志验证：`main` 已具备 `read/write/edit/sessions_*`；`session-memory` 记录出现 `~/.openclaw/workspace-main/...` 路径展示；同时仍观测到 `embedded run timeout ... timeoutMs=600000` 与长时间无回复现象 |
| 2026-03-07 19:02~19:05 | 生成 `openclaw.phase1a.g54-default.candidate.json5`，将默认主模型从 `motchat-claude-4-6/claude-opus-4-6` 改为 `motchat-gpt-max/gpt-5.4` |
| 2026-03-07 19:11 | 创建 `root-post-phase1a-2026-03-07-1911` 并执行 Vault sync，作为本轮 Phase 1A + g54 默认模型切换的收尾里程碑；`last_sent` 更新为 `root-auto-2026-03-07-1911` |
| 2026-03-07 19:xx | 飞书实测：默认模型显示为 `motchat-gpt-max/gpt-5.4`，`/reset`、简单回复与工具列举均恢复即时可用；当前将 g54 作为默认运营模型保留 |
| 2026-03-09 | 文档收口：在开发仓 `docs/host-sop.md` 中回写 Phase 1B 开发仓候选产物状态（`workspace-main-template/`、publish/check 脚本、`runtime-allowlist-backup-draft.md`）；更新 §0.2 阶段定位、§0.5 未决问题、§11.3 阶段标签、§13.7.2 备份策略、§13.8.4 发布工作流 |
| 2026-03-10 | Phase 1B 收口：正式定义 Phase 1B 退出条件与 Phase 2 进入门槛（`design-v3.md` §7）；将控制面备份脚本实现从 Phase 1B 重新归入 Phase 6；同步更新 SOP §0.2、§11.3（新增 §11.3.1）；同步更新 `runtime-allowlist-backup-draft.md` §8.1 |
| 2026-03-10 | Phase 1B live publish 准备：publish 脚本增加 `--allow-live-target` flag（交互确认 + TTY 检查，默认仍 fail-closed）；check 脚本增加 SOP hash 交叉校验；编写首次现网发布 operator runbook（`docs/runbook-first-live-publish.md`）；文档同步更新 SOP §0.2/§0.5/§11.3/§13.8.4 与 design-v3 §0/§7/§8.2——**均未将现网发布写为已完成** |
| 2026-03-11 | Phase 1B 预检包：新增只读 preflight 脚本（`scripts/preflight-first-live-publish.sh`）；增强 runbook（Go/No-Go checklist、证据采集要求、preflight 集成、check 命令 sudo 修正）；修正 `publish-sop.sh` 描述（无条件拒绝 live path，非"含 --allow-live-target"）；同步更新 SOP §0.2/§11.3/§13.8.4 与 design-v3 §5.3.1/§7/§8.2——**现网发布仍未执行** |
| 2026-03-11 | Phase 1B 执行包：新增首次现网发布执行包（`docs/execution-pack-first-live-publish.md`，含分步命令块、人工确认点、回退速查卡）；新增现场记录模板（`docs/templates/first-live-publish-record-template.md`）与发布后文档回写模板（`docs/templates/phase1b-live-publish-syncback-template.md`）；一致性复核确认 preflight/runbook/publish/check 命令顺序一致、无文档间冲突；更新 SOP §13.8.4 引用新文档——**所有文档均为执行前准备材料，现网发布仍未执行** |
| 2026-03-11 | Phase 1B 首次现网脚本化发布：通过 `publish-workspace-main.sh --apply --allow-live-target` 将 `workspace-main-template/` 发布到 `/var/lib/openclaw/.openclaw/workspace-main/`（使用 runbook §1.5 方案 A staging 路径 `/tmp/openclaw-publish-staging-20260311-130932`）；`check-workspace-main.sh` 校验通过（published artifact 模式）；gateway health 复验 OK（0ms）；飞书可达性验证通过；pre snapshot `root-pre-phase1b-publish-2026-03-11-1308`，post snapshot `root-post-phase1b-publish-2026-03-11-1319`，Vault 入库完成（auto snapshot `root-auto-2026-03-11-1324`，parent `root-auto-2026-03-11-0340`）；**Phase 1B 退出条件全部满足** |
| 2026-03-11 | Phase 2 开发仓准备（不涉及现网部署）：创建 broker per-action 输入 schema（`broker/schemas/actions/` 8 文件）、wrapper stub（`broker/wrappers/ocw-*.sh` 8 文件，仅验证+echo，不执行 live 操作）、broker 测试 fixture（`examples/broker/` 18 文件，含 negative test）、schema 交叉验证脚本（`scripts/validate-broker-schemas.sh` 192 checks pass）、wrapper 运行时测试（`tests/test_broker_schemas.sh` 62 checks pass）；对齐 `workspace-main-template/control/host-ops-api.md` 与 design-v3 §5.6.2 请求契约（消除 operation/parameters/approval_id 与 action/inputs/requested_by 漂移）；修正全仓 "Phase 1B+"/"Phase 0" 残留为准确阶段标号；升级 plugin skeleton 为 phase2-prep；更新 design-v3 §7 Phase 2 状态与 §8.3 TODO——**所有产物仅在开发仓内，Phase 2 现网部署尚未启动** |
| 2026-03-11 | Phase 2 开发仓准备续（不涉及现网部署）：创建 wrapper 共享验证库（`broker/wrappers/lib/common.sh`），重构 8 个 wrapper stub 消除代码重复；创建协议规格文档（`docs/specs/host-ops-broker-protocol-v1.md`）；增强 plugin skeleton（`index.js` 增加 buildRequest/validateRequest/validateResult，新增 `lib/build-request.sh` 和 `lib/validate-request.sh`）；创建聚合验证脚本（`scripts/validate-phase2-prep.sh`）和集成测试（`tests/test_phase2_integration.sh`，含 plugin→wrapper pipeline、negative tests、contract drift detection）；修正 `workspace-main-template/skills/broker/SKILL.md` 契约漂移（operation/parameters/approval_id → action/inputs/requested_by）——**所有产物仅在开发仓内，Phase 2 现网部署尚未启动** |
| 2026-03-11 | Phase 2 开发仓准备第三轮（不涉及现网部署）：创建错误分类规格文档（`docs/specs/error-taxonomy-v1.md`，定义 E_*/D_* 错误码与 error/denied 语义）；创建 9 组负面测试 fixture + 1 missing-file result（`examples/broker/negative/`，覆盖全部 error/denied 类别）；创建协议契约冻结测试（`tests/test_contract_freeze.sh`，109 checks，冻结 action enum / required fields / ok-status 不变量 / 跨层一致性 / 无废弃字段名）；修正 `host-ops-api.md` SHA256 占位符（abc123→正确 64 hex）并增加 error/denied 区分文档；增强 `validate-phase2-prep.sh` 新增 5 个验证段（负面 fixture、错误分类、契约冻结、SHA256 一致性、workspace 模板）；更新 `host-ops-broker-protocol-v1.md` 引用错误分类和负面 fixture——**所有产物仅在开发仓内，Phase 2 现网部署尚未启动** |
| 2026-03-11 | Phase 2 开发仓准备第四轮（不涉及现网部署）：扩充负面 fixture 覆盖至 17 场景（新增 empty-reason / empty-label / empty-sha256 / missing-snapshot-name / missing-target-snapshot / missing-label / type-error-reason / empty-action）；在 common.sh / index.js / validate-request.sh 三层同步 maxLength=128 校验；扩展 builder→wrapper pipeline 集成测试覆盖全部 8 个 action；增强 contract freeze 测试（per-action property types / wrapper stub existence / fixture deprecated field check / expanded negative fixture list）；增强 validate-phase2-prep.sh（builder action 覆盖 / negative fixture rejection / maxLength consistency）；修正 protocol spec 字段描述 "alphanumeric" → "alphanumeric, dots, hyphens, underscores; max 128 chars"；更新 error taxonomy negative fixture index 至 19 条——**所有产物仅在开发仓内，Phase 2 现网部署尚未启动** |
| 2026-03-11 | Phase 2 开发仓准备第五轮（不涉及现网部署）：强化 result schema（`additionalProperties: false` / required string `minLength: 1` / `if/then/else` ok-status 不变量 / reserved `error_code` 字段）；创建跨层契约矩阵（`docs/specs/contract-matrix-v1.md`）；扩充负面 fixture 至 22 组 + 2 特殊场景（extra-fields / null-action / null-inputs / array-inputs / numeric-action / ok-status-mismatch）；三层同步 extra-fields 拒绝和 inputs type 校验（common.sh / validate-request.sh / index.js 新增 additionalProperties 对等检查）；冻结 result envelope property types / minLength / invariant 约束；修正 SKILL.md SHA256 占位符；更新 error taxonomy fixture index 至 25 条——**所有产物仅在开发仓内，Phase 2 现网部署尚未启动** |
| 2026-03-11 | Phase 2 开发仓准备第六轮——收口型加固（不涉及现网部署）：创建单一来源 action inventory（`broker/schemas/action-inventory.json`，frozen=true，映射 schema/wrapper/fixture/required_inputs）；创建 fixture registry（`examples/broker/fixture-registry.json`，24 negative + 8 happy-path + 1 special，含 action/error_type/expected_status）；创建 prep 入口门控文档（`docs/specs/phase2-repo-prep-gate.md`，定义 21 条退出标准、10 条明确 deferred 事项、3 条残留低优先级项）；在 host-ops-api.md 补充 error_code 可选字段文档；在 contract-matrix-v1.md §7 添加验证脚本实现状态与单一来源引用；增强 test_contract_freeze.sh（action inventory 冻结验证 + fixture registry 一致性验证）；增强 validate-phase2-prep.sh（新增 §12-15：inventory / registry / gate / validator parity freeze）——**所有产物仅在开发仓内，Phase 2 现网部署尚未启动** |
| 2026-03-11 | Phase 2 部署设计包（不涉及现网部署）：创建部署布局规格文档（`docs/specs/phase2-broker-deployment-layout.md`，定义 broker daemon / socket / wrappers / logs / state / systemd unit 的目标路径、权限与归属模型）；创建部署 runbook（`docs/runbook-phase2-broker-deployment.md`，含 10 项进入条件、7 项禁止条件、Go/No-Go checklist、10 阶段部署序列、8 项最终验证、回滚规程与快照纪律）；创建分步执行包（`docs/execution-pack-phase2-broker-deployment.md`，15 步命令块 + 人工确认点 + 回退速查卡）；创建现场记录模板（`docs/templates/phase2-broker-deployment-record-template.md`）；创建文档回写模板（`docs/templates/phase2-broker-deployment-syncback-template.md`）；创建只读预检脚本（`scripts/preflight-phase2-broker-deployment.sh`，10 段验证 + GO/NO-GO 结论，不访问 live path）；更新 design-v3 §7 Phase 2 状态与 §8.3 TODO——**所有产物均为部署设计材料，broker 未部署，Phase 2 现网部署尚未启动** |
| 2026-03-14 | Phase 2 broker live deployment（现网部署）：operator-led 手动执行，按 runbook 全流程完成；broker daemon 部署到 `/opt/openclaw/broker/openclaw-broker`（bash + Python3 socket listener）；8 个 wrapper 安装为 production 版本（`BROKER_DRY_RUN=false`）；systemd unit `openclaw-broker.service` 安装并 enabled；Unix socket `/run/openclaw/broker.sock`（`root:openclaw 660`）已创建；`gateway_health` 正向测试通过；invalid action、bad path、path traversal 三类负面测试通过；host-ops-tool plugin 安装到 extensions 目录并注册进 `openclaw.json`（`plugins.allow` + `plugins.entries`）；gateway 重启后健康；pre snapshot `root-pre-phase2-broker-20260314`（ID 309），post snapshot `root-post-phase2-broker-20260314`（ID 310），Vault 入库完成（auto snapshot `root-auto-2026-03-14-1454`，parent `root-auto-2026-03-14-0340`）；`last_sent` 更新为 `root-auto-2026-03-14-1454`；**部署结论：PASS**；plugin activation（`index.js` register/activate export）和 agent-facing `host_ops` tool access 仍 pending；详见 `docs/records/phase2-broker-deployment-2026-03-14.md` |
