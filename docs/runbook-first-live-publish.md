# Runbook: 首次现网脚本化发布 workspace-main

> 创建日期：2026-03-10
> 适用阶段：Phase 1B 退出收口
> 前提：Phase 1A 已落地，开发仓 publish/check 脚本已在 test path 验证通过
> 状态：**待执行**（本文档是操作指南，不代表操作已完成）

---

## 0. 范围与目的

本 runbook 仅覆盖一件事：**首次通过 `publish-workspace-main.sh --apply --allow-live-target` 将开发仓 `workspace-main-template/` 脚本化发布到现网 live target**。

发布目标路径：`/var/lib/openclaw/.openclaw/workspace-main/`

这次发布不是"首次部署 workspace-main"（那已在 Phase 1A 手动完成），而是**首次使用脚本化发布链覆写已有的 live workspace-main**，验证 publish → check 闭环在现网可用。

---

## 1. 前置检查（operator 必须在执行前逐项确认）

### 1.1 开发仓状态

```bash
cd ~/projects/openclaw-dev
git status          # 工作区 clean，无未提交变更
git log --oneline -5  # 确认当前 HEAD 包含最新 publish 脚本（含 --allow-live-target）
```

### 1.2 现网 gateway 健康

使用 host-sop.md §13.2 的带重试 health check 模板确认 gateway 正常运行。

```bash
set +e
for i in $(seq 1 5); do
  sudo -u openclaw -H bash -c '
    set -euo pipefail
    source /etc/openclaw/openclaw.env
    /opt/openclaw/node_modules/.bin/openclaw gateway health --url ws://127.0.0.1:17777 --token "$OPENCLAW_GATEWAY_TOKEN"
  ' >/dev/null 2>&1 && echo "Gateway health: OK" && break
  echo "health attempt $i failed; retrying..."
  sleep 1
done
set -e
```

**如果 health 不通过，停止。不进行发布。**

### 1.3 确认 live workspace-main 当前存在

```bash
ls -la /var/lib/openclaw/.openclaw/workspace-main/
ls -la /var/lib/openclaw/.openclaw/workspace-main/control/state/
```

确认 `control/state/` 目录存在且包含运行时状态文件（`pending-approvals.json`、`last-health.md`、`last-task-index.json` 等）。这些文件在 publish 过程中会被保留（rsync `--exclude`）。

### 1.4 记录当前 live workspace 的 SOP hash（可选但推荐）

```bash
cat /var/lib/openclaw/.openclaw/workspace-main/control/state/last-sop-hash.txt 2>/dev/null || echo "(no hash file)"
```

### 1.5 确认 openclaw 用户对开发仓的读取权限

publish 脚本以 `openclaw` 用户执行时，需要读取开发仓中的脚本、模板和 `docs/host-sop.md`。
`openclaw` 是 `nologin` 系统用户，**不保证对 `/home/nick/projects/openclaw-dev/` 有读取和执行权限**。

在执行发布前必须检查：

```bash
# 以 openclaw 用户身份测试关键路径是否可读
sudo -u openclaw test -r /home/nick/projects/openclaw-dev/scripts/publish-workspace-main.sh && echo "script: readable" || echo "script: NOT readable"
sudo -u openclaw test -r /home/nick/projects/openclaw-dev/workspace-main-template/AGENTS.md && echo "template: readable" || echo "template: NOT readable"
sudo -u openclaw test -r /home/nick/projects/openclaw-dev/docs/host-sop.md && echo "sop: readable" || echo "sop: NOT readable"
sudo -u openclaw test -x /home/nick/projects/openclaw-dev/scripts/ && echo "scripts dir: executable" || echo "scripts dir: NOT executable"
```

**如果任一项显示 NOT readable / NOT executable，必须先解决权限问题再继续。**

可选方案（按优先级）：

**方案 A：创建 staging 导出**（推荐，权限隔离最干净）
```bash
STAGING=/tmp/openclaw-publish-staging-$(date +%s)
mkdir -p "$STAGING/docs"
cp -a /home/nick/projects/openclaw-dev/scripts/ "$STAGING/scripts/"
cp -a /home/nick/projects/openclaw-dev/workspace-main-template/ "$STAGING/workspace-main-template/"
cp /home/nick/projects/openclaw-dev/docs/host-sop.md "$STAGING/docs/host-sop.md"
chown -R openclaw:openclaw "$STAGING"
# 然后从 $STAGING 执行 publish（需调整脚本中的 REPO_ROOT 或 cd 到 staging）
```
注意：方案 A 需要确保脚本内的 `REPO_ROOT` 解析指向 staging 目录——最简单的做法是将整个开发仓复制到 staging。发布完成后删除 staging 目录：`rm -rf "$STAGING"`

**方案 B：POSIX ACL 最小只读授权**（次选，仅授权 openclaw 用户）
```bash
# 给 openclaw 用户对路径链上每个目录的遍历权限（仅 execute，不含 read）
sudo setfacl -m u:openclaw:x /home/nick
sudo setfacl -m u:openclaw:x /home/nick/projects
sudo setfacl -m u:openclaw:x /home/nick/projects/openclaw-dev
# 给 openclaw 对开发仓内容的只读权限
sudo setfacl -R -m u:openclaw:rX /home/nick/projects/openclaw-dev/
```
发布完成后收回 ACL：
```bash
sudo setfacl -R -b /home/nick/projects/openclaw-dev/
sudo setfacl -b /home/nick/projects/openclaw-dev
sudo setfacl -b /home/nick/projects
sudo setfacl -b /home/nick
```
注意：需确认文件系统已启用 ACL（ext4/btrfs 默认支持）。

**方案 C：临时放宽 other 权限**（不推荐——仅作为紧急权宜手段）

⚠️ **风险**：`chmod o+x /home/nick` 将 home 目录对系统上所有用户和进程开放遍历权限，不仅限于 openclaw。在多用户或多服务的系统上，这可能暴露 home 目录下的其他内容。
```bash
chmod o+x /home/nick /home/nick/projects /home/nick/projects/openclaw-dev
chmod -R o+rX /home/nick/projects/openclaw-dev/
```
如果使用此方案，发布完成后**必须立即收回**：
```bash
chmod o-x /home/nick
```

---

## 2. 变更前快照

**这是硬性要求。** 遵循 host-sop.md 变更纪律：pre-change snapshot → change → health → post-change snapshot → Vault sync。

```bash
# 创建根只读快照
sudo btrfs subvolume snapshot -r / "/.snapshots/root-pre-phase1b-publish-$(date +%Y-%m-%d-%H%M)"
```

记录快照名：`root-pre-phase1b-publish-YYYY-MM-DD-HHMM`

注意：`/var/lib/openclaw` 是独立子卷，不在此根快照保护范围内。但此处的根快照仍然保护 `/etc/openclaw`、`/opt/openclaw`、systemd 等系统组件——如果发布后发现需要回滚系统层配置，此快照可用。

对于 `/var/lib/openclaw/.openclaw/workspace-main/` 本身，回退策略是：**workspace-main 是可重复发布产物**——如果新发布有问题，可以再次执行 publish 回到上一个已知良好状态。`control/state/` 在 publish 过程中不会被覆写。

---

## 3. 执行发布

```bash
cd ~/projects/openclaw-dev

# 执行 live publish（需要交互终端确认）
sudo -u openclaw bash scripts/publish-workspace-main.sh \
    --apply --allow-live-target \
    /var/lib/openclaw/.openclaw/workspace-main
```

脚本会：
1. 显示安全警告框
2. 要求输入 `yes-publish-live` 确认
3. 使用 rsync 将 `workspace-main-template/` 同步到目标，保留 `control/state/`
4. 内联发布 `docs/host-sop.md` 到 `control/SOP.md`（live 模式下不调用 `publish-sop.sh`，而是由父脚本直接完成）

**关于执行身份的说明：**
- publish 脚本需要写入 `/var/lib/openclaw/.openclaw/workspace-main/`，该目录属于 `openclaw:openclaw 700`
- 因此需要以 `openclaw` 用户执行（通过 `sudo -u openclaw`）
- `nick` 用户直接执行会因权限不足而失败
- 如果 `openclaw` 用户因 `nologin` shell 无法执行 bash 脚本，可改用：
  ```bash
  sudo -u openclaw -s /bin/bash -c 'cd /home/nick/projects/openclaw-dev && bash scripts/publish-workspace-main.sh --apply --allow-live-target /var/lib/openclaw/.openclaw/workspace-main'
  ```
- 或临时将开发仓内 script 复制到 openclaw 用户可执行的路径

**如果脚本报错退出，停止。分析错误原因后决定是否重试。**

---

## 4. 发布后校验

### 4.1 结构校验

```bash
bash scripts/check-workspace-main.sh /var/lib/openclaw/.openclaw/workspace-main
```

期望输出：`All checks passed`

check 脚本在 published artifact 模式下会验证：
- 所有核心文件存在（AGENTS.md、IDENTITY.md、SOUL.md 等）
- 所有控制文件存在（SOP.md、routing-policy.md 等）
- 所有状态文件存在且格式有效（JSON 可解析、hash 为 64 字符 SHA256）
- SOP.md 不是 placeholder，包含 publication header 和 SHA256
- 无明显密钥泄露
- Skill 定义结构完整

**如果 check 失败，记录失败项，进入 §6 回退判断。**

### 4.2 gateway 健康复验

```bash
# 使用与 §1.2 相同的 health check 模板
set +e
for i in $(seq 1 5); do
  sudo -u openclaw -H bash -c '
    set -euo pipefail
    source /etc/openclaw/openclaw.env
    /opt/openclaw/node_modules/.bin/openclaw gateway health --url ws://127.0.0.1:17777 --token "$OPENCLAW_GATEWAY_TOKEN"
  ' >/dev/null 2>&1 && echo "Gateway health: OK" && break
  echo "health attempt $i failed; retrying..."
  sleep 1
done
set -e
```

注意：publish workspace-main 不涉及 gateway restart（workspace-main 是文件系统层的文档，不是 gateway 配置），因此 gateway 应保持健康。如果此时 health 失败，原因很可能与 publish 无关，但仍需排查。

### 4.3 飞书可达性验证

通过飞书向 `main` agent 发送一条简单消息，确认 agent 仍可正常对话。

---

## 5. 变更后快照与 Vault 入库

```bash
# Post-change 里程碑快照
sudo btrfs subvolume snapshot -r / "/.snapshots/root-post-phase1b-publish-$(date +%Y-%m-%d-%H%M)"

# Vault 入库（挂载 → send → 卸载）
sudo mount /mnt/vault
sudo /usr/local/sbin/vault-backup-root-btrfs
sudo umount /mnt/vault
```

记录快照名与 Vault sync 结果。

---

## 6. 失败回退判断

### 6.1 什么算失败

| 情况 | 严重度 | 处理 |
|------|--------|------|
| publish 脚本报错退出，未写入任何文件 | 低 | 分析错误，修复后重试 |
| publish 部分完成，check 失败 | 中 | 见 §6.2 |
| publish 完成，check 通过，但 gateway health 失败 | 高 | 但很可能与 publish 无关——排查 gateway 本身 |
| publish 完成，check 通过，但 main agent 飞书不可达 | 中 | 可能需要 gateway restart；排查后决定 |

### 6.2 回退方式

workspace-main 的回退不依赖根快照回滚。回退方式是**重新 publish**：

**方案 A：重新 publish 修复后的模板**（首选）
如果 check 失败是因为模板问题，在开发仓修复模板后重新执行 publish。

**方案 B：手动恢复特定文件**
如果 publish 的 rsync `--delete` 意外删除了 `control/state/` 中的文件（这不应该发生，因为有 `--exclude`），从 Phase 1A 的手动部署状态判断：
- `control/state/` 中的文件如果是 gateway 运行时产生的（`pending-approvals.json`、`last-health.md`、`last-task-index.json`），丢失后无法从开发仓恢复，需从备份（如果有）或重新初始化
- 如果仅是模板初始值文件丢失，可从 `workspace-main-template/control/state/` 复制初始值

**方案 C：根快照回滚**（最后手段，且注意限制）
根快照回滚只恢复根文件系统，**不恢复 `/var/lib/openclaw`**（独立子卷）。因此根快照回滚不能直接恢复 workspace-main 内容。根快照回滚的作用是恢复 `/etc/openclaw`、`/opt/openclaw` 等系统组件——但本次 publish 操作不修改这些路径。

### 6.3 回退前提

执行回退前必须：
1. 记录当前失败状态（截屏或复制 check 输出）
2. 确认根快照已创建（§2）
3. 确认回退方案不会丢失 `control/state/` 中的运行时状态

---

## 7. 完成后记录

发布完成且校验通过后，需要：

1. 在 `docs/host-sop.md` 的操作时间线（§16）追加一条记录
2. 在 `docs/design-v3.md` Phase 1B 交付物表更新状态
3. 提交开发仓变更

**注意：以上文档更新应在现网操作实际完成后执行，不应提前写成已完成。**

---

## 8. 本 runbook 的局限

- 本 runbook 假设 operator 有 `sudo` 权限
- 本 runbook 不覆盖 gateway restart（publish workspace-main 不需要 restart）
- 本 runbook 不覆盖 `/etc/openclaw/openclaw.json` 的任何变更
- 本 runbook 的 Vault 入库步骤依赖 `/usr/local/sbin/vault-backup-root-btrfs` 已就绪
- 执行身份问题（`openclaw` 用户的 `nologin` shell）可能需要在实际操作时调整方案
