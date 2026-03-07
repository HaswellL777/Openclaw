# OpenClaw Host 状态记录（2026-03-06 更新）

> 目标：为后续裸机安装 OpenClaw 做好"可回滚快照 + 离线 Vault 金库 + 增量备份 + 权限隔离"的宿主机基线。

---

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

---

## 0. 当前时间与主机
- 时区：CST (+0800)
- 日期：2026-03-06（上次更新：2026-03-06 22:33）
- 主机：nick-MS-7D73（管理用户：nick，服务用户：openclaw）

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
  - 当前值：`root-auto-2026-03-06-2233`

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
- 配置目录：
  - `/etc/openclaw`  owner root:openclaw, mode 750
  - `/etc/openclaw/openclaw.json`  owner root:openclaw, mode 640
  - `/etc/openclaw/openclaw.env`  owner root:openclaw, mode 640（强制）
- 数据目录（已为子卷）：
  - `/var/lib/openclaw` owner openclaw:openclaw, mode 700（仅服务账号读写）
- 日志目录：
  - `/var/log/openclaw` owner openclaw:openclaw
- 插件目录：
  - `/var/lib/openclaw/.openclaw/extensions` owner openclaw:openclaw, mode 700

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

# OpenClaw 裸机部署与运维 SOP（追加于 2026-03-04）

> 适用范围：Ubuntu 24.04 LTS 宿主机裸机安装 OpenClaw（非 Docker），Btrfs 根（subvolid=5），使用 /.snapshots + 离线 Vault（/mnt/vault, noauto）做增量 send/receive；OpenClaw 以 systemd **system-level** 服务运行（User=openclaw），并严格遵循目录边界：
>
> - 代码：/opt/openclaw（root:root，755，仅 root 可写）
> - 配置：/etc/openclaw（root:openclaw，750；敏感 env 为 0640 root:openclaw）
> - 数据：/var/lib/openclaw（btrfs 子卷，openclaw:openclaw，700）
> - 日志：/var/log/openclaw（openclaw:openclaw）

## 11. 部署结果（已完成）

### 11.1 运行时版本（验收时）
- Node.js：v22.22.0（NodeSource apt）
- npm：10.9.4
- git：2.43.0
- OpenClaw：2026.3.2（85377a2）
- systemd 服务：openclaw-gateway.service（system-level，User=openclaw）

### 11.2 监听端口（默认仅 localhost）
- Gateway WebSocket：127.0.0.1:17777（同时监听 ::1:17777）
- Browser control（HTTP）：127.0.0.1:17779（auth=token）
- 内部端口：127.0.0.1:17780
- Dashboard（本机访问）：http://127.0.0.1:17777/

> ⚠️ 如果发现 18789 端口在监听，说明 nick 用户的 user-level gateway 被意外启动，见第 13.6.6 节清理步骤。

### 11.3 里程碑快照与入库（已执行）
- 最近关键本地只读里程碑快照：
  - `/.snapshots/root-post-openclaw-working-2026-03-04-1624`
  - `/.snapshots/root-post-x2go-working-2026-03-06-2030`
  - `/.snapshots/root-post-gpt54-2026-03-06-2233`
- 最近自动备份快照（由 `vault-backup-root-btrfs` 生成）：
  - `/.snapshots/root-auto-2026-03-06-2031`
  - `/.snapshots/root-auto-2026-03-06-2051`
  - `/.snapshots/root-auto-2026-03-06-2233`
- Vault 已接收（`/mnt/vault/recv/system`）的最新条目：
  - `system/root-auto-2026-03-06-2031`
  - `system/root-auto-2026-03-06-2051`
  - `system/root-auto-2026-03-06-2233`
- `last_sent`：`/var/lib/openclaw/backup/last_sent = root-auto-2026-03-06-2233`
- Vault 备份后状态：Vault 不常驻挂载（`findmnt /mnt/vault -> unmounted`）

### 11.4 审计记录（已生成）
- /var/lib/openclaw/backup/openclaw-host-audit-2026-03-04-1625.txt

### 11.5 飞书插件（已验证可用）
- 插件：@openclaw/feishu v2026.3.2
- 安装路径：`/var/lib/openclaw/.openclaw/extensions/feishu/node_modules/@openclaw/feishu`
  - ⚠️ installPath 必须指向 `node_modules/@openclaw/feishu` 这一层，不能指向 npm prefix 目录。
- 连接模式：websocket
- Bot open_id：ou_85701f4531d56c7de0fc1fb845fcebfe
- 启动日志确认已注册：feishu_doc、feishu_app_scopes、feishu_chat、feishu_wiki、feishu_drive、feishu_bitable

---

## 12. 关键配置与 systemd 单元（权威落地版本）

### 12.1 配置文件说明（/etc/openclaw/openclaw.json）

> ⚠️ **所有配置（gateway、models、agents、channels、plugins）必须集中写在此文件。**
> `/var/lib/openclaw/.openclaw/` 下即使存在 openclaw.json 也不会被读取——那是运行时状态目录，不是配置合并源。本机已实际踩过此坑。

当前配置文件包含以下部分（使用 JSON5 格式）：
- `gateway`：端口 17777，bind=loopback，token 通过 `${OPENCLAW_GATEWAY_TOKEN}` 从环境变量注入
- `models`：三组 provider
  - DeepSeek 自定义 provider（contextWindow: 128000）
  - MotChat 中转 Claude 4.6（provider: `motchat-claude-4-6`，baseUrl: `https://new.motchat.com/v1`，5 个模型：opus-4-6 / opus-4-6-1m / opus-4-6-thinking / sonnet-4-6 / sonnet-4-6-thinking）
  - MotChat 中转 GPT 5.x（provider: `motchat-gpt-max`，baseUrl: `https://new.motchat.com/v1`，7 个模型：gpt-5.2-codex / gpt-5.2-codex-high / gpt-5.2-codex-xhigh / gpt-5.2-high / gpt-5.2-xhigh / gpt-5.3-codex / gpt-5.4）
    - `gpt-5.2-*` 与 `gpt-5.3-codex`：`contextWindow=400000`，`maxTokens=128000`
    - `gpt-5.4`：`contextWindow=1050000`，`maxTokens=128000`
- `agents`：默认模型为 `motchat-claude-4-6/claude-opus-4-6`，workspace 指向 /var/lib/openclaw/.openclaw/workspace
  - 已配置 alias 别名：opus / opus1m / opusthink / sonnet / sonnetthink / g52codex / g52codexhigh / g52codexxhigh / g52high / g52xhigh / g53codex / g54 / deepchat / deepresoner
- `channels`：飞书（websocket 模式，appSecret 通过 `${FEISHU_APP_SECRET}` 从环境变量注入）
- `plugins`：feishu + tool-audit-plugin（诊断用），installPath 指向 node_modules/@openclaw/feishu
- `hooks`：内部 hooks 已启用，tool-audit-probe 已注册（诊断用）
- `logging`：file=/var/log/openclaw/openclaw.log

> ⚠️ **凭证注入规则（2026-03-04 整改后）：**
> - DeepSeek apiKey 在 json 中写 `${DEEPSEEK_API_KEY}`，实际值在 openclaw.env 中
> - 飞书 appSecret 在 json 中写 `${FEISHU_APP_SECRET}`，实际值在 openclaw.env 中
> - MotChat 中转 apiKey 在 json 中写 `${MOTCHAT_API_KEY}`，实际值在 openclaw.env 中（2026-03-05 新增）
> - **禁止在 json 中明文写任何 API Key 或 Secret**

### 12.1.1 当前 MotChat GPT 5.x 模型矩阵（2026-03-06 22:33 权威落地版本）

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
- 默认主模型 **未改动**，仍为 `motchat-claude-4-6/claude-opus-4-6`；GPT 5.x 模型通过 alias 显式选用。

### 12.2 环境文件（/etc/openclaw/openclaw.env）
- 权限：0640 root:openclaw，nick 用户不可直接读取
- 当前包含：
  - `OPENCLAW_GATEWAY_TOKEN=`（随机强 token）
  - `DEEPSEEK_API_KEY=`（DeepSeek API Key）
  - `FEISHU_APP_SECRET=`（飞书应用 appSecret，2026-03-04 21:24 迁入）
  - `MOTCHAT_API_KEY=`（MotChat 中转站 API Key，2026-03-05 11:41 新增，用于 Claude 4.6 + GPT 5.x 系列）

### 12.3 systemd 主 unit（/etc/systemd/system/openclaw-gateway.service）

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

### 12.4 Drop-in：允许 AF_NETLINK（修复 error 97）
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
> - "Service: systemd (disabled)"
> - "~/.openclaw/openclaw.json missing"
> - "systemctl --user unavailable"
>
> 这是预期行为，**不要使用 `openclaw doctor --repair` 去"修复"**，否则会引入 user-level daemon，破坏当前目录边界策略。

---

## 13. 运维 SOP（日常/变更/备份/回滚/排障）

### 13.1 日常操作（systemd）
```bash
# 状态
sudo systemctl status --no-pager openclaw-gateway.service

# 启动/停止/重启
sudo systemctl start openclaw-gateway.service
sudo systemctl stop openclaw-gateway.service
sudo systemctl restart openclaw-gateway.service

# 查看日志（推荐）
sudo journalctl -u openclaw-gateway.service -n 200 --no-pager
sudo journalctl -u openclaw-gateway.service -f --no-pager
```

### 13.2 健康检查
> 注意：/etc/openclaw/openclaw.env 为 0640 root:openclaw，普通用户（nick）默认无权读取。
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

#### 13.3.1 Windows/远端浏览器访问（SSH 隧道）
在 Windows PowerShell：
```powershell
ssh -f -N -L 17777:127.0.0.1:17777 -L 17779:127.0.0.1:17779 nick@<HOST_IP>
```
然后在浏览器访问：
- http://127.0.0.1:17777/   （Dashboard，输入 OPENCLAW_GATEWAY_TOKEN 连接）
- http://127.0.0.1:17779/   （Browser control，token auth）

### 13.4 修改配置
直接编辑 `/etc/openclaw/openclaw.json`，然后重启服务：
```bash
sudo nano /etc/openclaw/openclaw.json
sudo systemctl restart openclaw-gateway.service
```

> ⚠️ 修改配置时若涉及凭证，应将凭证写入 `/etc/openclaw/openclaw.env`，json 中使用 `${变量名}` 引用，禁止明文写入 json。
>
> ⚠️ 若本次修改涉及 `models.providers` 或 `agents.defaults.models`：
> - 修改后至少执行一次带重试的 `gateway health`
> - 至少对新增 provider/model 做一次**真实调用验证**，不要仅以网关启动成功代替上游模型可用性验证
> - 若使用第三方中转站，面板展示名不一定等于真实 API model id；health 通过但真实调用失败时，应优先怀疑 model id 映射问题

### 13.5 变更流程（升级 OpenClaw / 修改配置）
**原则：任何变更都必须可回滚**（变更前/后快照 + 入库）。

#### 13.5.1 变更前（强制）
```bash
set -euo pipefail
sudo btrfs subvolume snapshot -r / "/.snapshots/root-pre-change-$(date +%F-%H%M)"
sudo /usr/local/sbin/vault-backup-root-btrfs
```

#### 13.5.2 升级 OpenClaw（/opt/openclaw）
> 推荐：避免 `openclaw@latest`；使用明确版本号并记录。
```bash
set -euo pipefail
sudo systemctl stop openclaw-gateway.service
cd /opt/openclaw
sudo npm install --omit=dev openclaw@<PINNED_VERSION>
sudo systemctl start openclaw-gateway.service
```

#### 13.5.3 变更后（强制：验收 + 快照 + 入库）
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

#### 13.6.1 OpenClaw 启动崩溃：uv_interface_addresses ... error 97
症状：journal 中出现 `uv_interface_addresses returned Unknown system error 97`
原因：systemd 沙箱 `RestrictAddressFamilies` 未允许 AF_NETLINK
处理：确认 drop-in 10-address-families.conf 存在并包含 AF_NETLINK，然后重启服务：
```bash
sudo systemctl cat openclaw-gateway.service
sudo systemctl daemon-reload
sudo systemctl restart openclaw-gateway.service
```

#### 13.6.2 health 报 1006 abnormal closure（但端口在 listen）
原因：重启后的启动窗口，WS 端口已监听但内部尚未 ready（约需 12 秒）
处理：使用 13.2 的重试模板；或等待后重试。

#### 13.6.3 读取 /etc/openclaw/openclaw.env "权限不够"
原因：文件为 0640 root:openclaw，nick 默认不可读
处理：用 `sudo -u openclaw ... source /etc/openclaw/openclaw.env` 运行；不要把 token 打印到终端/历史。

#### 13.6.4 npm install 报 spawn git ENOENT
原因：系统缺 git，但依赖链需要 git 拉取
处理：`sudo apt install -y git`

#### 13.6.5 "复制命令带 UI 引用"导致 set 报错
现象：终端出现 `set: pipe:contentReference...: 无效的选项名`
原因：从聊天界面复制时带入引用标记
处理：只复制代码块内内容；或先粘贴到纯文本编辑器清洗后再执行。

#### 13.6.6 飞书不加载 / 启动日志无 feishu
原因：最常见原因是配置写在了 `/var/lib/openclaw/.openclaw/openclaw.json` 而非 `/etc/openclaw/openclaw.json`
处理：
```bash
sudo grep -i feishu /etc/openclaw/openclaw.json  # 确认配置在正确位置
sudo systemctl restart openclaw-gateway.service
```

#### 13.6.7 low context window 警告
症状：日志出现 `low context window: ... ctx=16000 (warn<32000)`
处理：将 `/etc/openclaw/openclaw.json` 中对应模型的 `contextWindow` 改为 65536 或更大，重启服务。

#### 13.6.8 发现 18789 端口在监听（双 gateway 问题）
原因：nick 用户的 user-level gateway 被意外启动（通常由 onboard 引起）
处理：
```bash
systemctl --user stop openclaw-gateway.service
systemctl --user disable openclaw-gateway.service
rm -f ~/.config/systemd/user/openclaw-gateway.service
systemctl --user daemon-reload
# 确认清理：应只剩 17777/17779/17780
sudo ss -tlnp | grep openclaw
```

#### 13.6.9 登录提示 ~/.openclaw/completions/openclaw.bash 不存在
原因：onboard 写入了 .bashrc 引用
处理：
```bash
sed -i '/openclaw.*completions/d' ~/.bashrc
source ~/.bashrc
```

#### 13.6.10 Gateway 崩溃：plugin manifest not found
症状：journal 中出现 `plugin manifest not found: .../openclaw.plugin.json`
原因：`/var/lib/openclaw/.openclaw/extensions/` 下存在缺少 `openclaw.plugin.json` 的目录。OpenClaw 自动扫描此目录，发现无效 plugin 会拒绝启动。
处理：
```bash
# 删除有问题的 plugin 目录
sudo rm -rf /var/lib/openclaw/.openclaw/extensions/<问题目录>
sudo systemctl restart openclaw-gateway.service
```

#### 13.6.11 Gateway 崩溃：Unrecognized key in plugins.entries
症状：journal 中出现 `Unrecognized key: "installPath"` 或其他未知 key
原因：`plugins.entries.<id>` 使用 Zod strict schema，只接受已知字段（`enabled`、`config`）。
处理：
```bash
# 从配置中移除非法字段，只保留 enabled 和 config
sudo nano /etc/openclaw/openclaw.json
# 将 "plugin-id": { enabled: true, installPath: "..." } 
# 改为 "plugin-id": { enabled: true }
sudo systemctl restart openclaw-gateway.service
```

### 13.7 备份策略（根系统）
- 自动备份：OnCalendar=*-*-* 03:40:00
- 手动触发：
```bash
sudo /usr/local/sbin/vault-backup-root-btrfs
```
- 验证 Vault 离线：
```bash
findmnt /mnt/vault && echo "WARNING: vault is mounted" || echo "OK: vault is unmounted"
```

### 13.8 回滚与恢复（高级操作，务必谨慎）

> 重要：当前根挂载为 subvolid=5（顶层），并非 @ 布局。
> /var/lib/openclaw 是独立子卷，回滚根系统不会回滚运行态数据（这是设计目标之一）。

#### 13.8.1 从本地 /.snapshots 回滚（建议在 LiveUSB/救援环境操作）
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

#### 13.8.2 从 Vault 恢复快照到系统盘（在救援环境操作）
```bash
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/sys
sudo mount /dev/nvme1n1p1 /mnt/vault
sudo btrfs send "/mnt/vault/recv/system/<SNAPNAME>" | sudo btrfs receive "/mnt/sys/.snapshots"
# 然后按 13.8.1 设置默认子卷并 reboot
```

---

## 14. Hooks 与 Plugin 扩展体系（2026-03-05 验证）

### 15.1 Hook 类型与可用性（OpenClaw 2026.3.2）

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

### 15.2 当前已部署的 Hook 与 Plugin

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

### 15.3 本地 Plugin 开发 SOP

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

### 15.4 vLLM 安全审计 Plugin 架构（2026-03-05 已实装）

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

## 15. 变更记录

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
