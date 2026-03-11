# 执行包：首次现网脚本化发布 workspace-main

> 创建日期：2026-03-11
> 适用阶段：Phase 1B 退出收口
> 前提：Phase 1A 已落地，开发仓 publish/check/preflight 脚本已验证通过
> 状态：**待执行**

**本文档是执行包，不代表操作已执行。**
**本文档是 `docs/runbook-first-live-publish.md` 的操作伴侣，不替代 runbook。**

---

## 0. 使用说明

本执行包提供 operator 可直接复制执行的分步命令块。每一步都有人工确认点。

- 每个命令块独立执行，不要合并成一行
- 看到 `⏸ STOP` 标记时必须停下来人工确认
- 看到 `📋 RECORD` 标记时需要记录信息到现场记录模板
- 遇到失败时参考底部「回退速查卡」
- 现场记录模板：`docs/templates/first-live-publish-record-template.md`
- 发布后文档回写模板：`docs/templates/phase1b-live-publish-syncback-template.md`

---

## 步骤 1：开发仓 preflight 预检

```bash
cd ~/projects/openclaw-dev
```

```bash
bash scripts/preflight-first-live-publish.sh 2>&1 | tee /tmp/preflight-$(date +%Y%m%d-%H%M%S).txt
```

> `📋 RECORD` 记录 preflight 输出文件路径。

> `⏸ STOP` 检查 preflight 结论：
> - 如果输出 `RESULT: NO-GO` → **停止。先解决所有 FAIL 项。**
> - 如果输出 `RESULT: GO` → 继续下一步。

---

## 步骤 2：记录开发仓证据

```bash
git rev-parse HEAD
```

```bash
git log --oneline -1
```

```bash
date -u
```

> `📋 RECORD` 将 git commit full SHA、commit 摘要、UTC 时间记录到现场记录模板。

---

## 步骤 3：现网 gateway 健康检查

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

> `⏸ STOP` 检查 gateway 健康结果：
> - 如果输出 `Gateway health: OK` → 继续。
> - 如果 5 次全部失败 → **停止。不进行发布。排查 gateway 问题。**

---

## 步骤 4：确认 live workspace-main 存在

```bash
ls -la /var/lib/openclaw/.openclaw/workspace-main/
```

```bash
ls -la /var/lib/openclaw/.openclaw/workspace-main/control/state/
```

> `⏸ STOP` 确认 `control/state/` 目录存在且包含运行时状态文件。

---

## 步骤 5：检查 openclaw 用户读取权限

```bash
sudo -u openclaw test -r /home/nick/projects/openclaw-dev/scripts/publish-workspace-main.sh && echo "script: readable" || echo "script: NOT readable"
sudo -u openclaw test -r /home/nick/projects/openclaw-dev/workspace-main-template/AGENTS.md && echo "template: readable" || echo "template: NOT readable"
sudo -u openclaw test -r /home/nick/projects/openclaw-dev/docs/host-sop.md && echo "sop: readable" || echo "sop: NOT readable"
sudo -u openclaw test -x /home/nick/projects/openclaw-dev/scripts/ && echo "scripts dir: executable" || echo "scripts dir: NOT executable"
```

> `⏸ STOP` 检查权限结果：
> - 如果全部 `readable` / `executable` → 继续步骤 6。
> - 如果任一项 NOT → **必须先解决权限问题**，参见 runbook §1.5 的三种方案。
>   - 如果使用方案 A（staging），后续步骤 7 的命令需要调整 `cd` 目标。

---

## 步骤 6：Go/No-Go 最终确认

> `⏸ STOP` 逐项确认 runbook §1.6 的 Go/No-Go 检查表（12 项）。
> 全部"必需"项满足后方可继续。

---

## 步骤 7：创建变更前快照

```bash
sudo btrfs subvolume snapshot -r / "/.snapshots/root-pre-phase1b-publish-$(date +%Y-%m-%d-%H%M)"
```

> `📋 RECORD` 记录快照名称（格式：`root-pre-phase1b-publish-YYYY-MM-DD-HHMM`）。

> 注意：此根快照不包含 `/var/lib/openclaw`（独立子卷）。workspace-main 的回退策略是重新 publish，不依赖根快照。

---

## 步骤 8：执行发布

```bash
cd ~/projects/openclaw-dev
```

```bash
sudo -u openclaw bash scripts/publish-workspace-main.sh \
    --apply --allow-live-target \
    /var/lib/openclaw/.openclaw/workspace-main
```

> 脚本会显示安全警告框，要求输入 `yes-publish-live` 确认。

> 如果 `openclaw` 用户因 `nologin` shell 无法执行 bash，改用：
> ```bash
> sudo -u openclaw -s /bin/bash -c 'cd /home/nick/projects/openclaw-dev && bash scripts/publish-workspace-main.sh --apply --allow-live-target /var/lib/openclaw/.openclaw/workspace-main'
> ```

> `⏸ STOP` 检查脚本输出：
> - 如果输出 `PUBLISH COMPLETE` → 继续步骤 9。
> - 如果脚本报错退出 → **停止。** 分析错误原因。参考底部「回退速查卡」。

> `📋 RECORD` 记录实际执行的命令与脚本输出摘要。

---

## 步骤 9：发布后结构校验

```bash
sudo bash scripts/check-workspace-main.sh /var/lib/openclaw/.openclaw/workspace-main 2>&1 | tee /tmp/check-post-publish-$(date +%Y%m%d-%H%M%S).txt
```

> `⏸ STOP` 检查校验结果：
> - 如果输出 `All checks passed` → 继续步骤 10。
> - 如果有 `✗` 失败项 → **停止。** 参考底部「回退速查卡」。

> `📋 RECORD` 记录 check 输出文件路径与通过/失败结论。

---

## 步骤 10：gateway 健康复验

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

> `📋 RECORD` 记录 health check 结果。

> 注意：publish workspace-main 不涉及 gateway restart，gateway 应保持健康。如果此时 health 失败，原因很可能与 publish 无关。

---

## 步骤 11：飞书可达性验证

通过飞书向 `main` agent 发送一条简单消息，确认 agent 仍可正常对话。

> `📋 RECORD` 记录飞书验证结果（截屏或文字）。

---

## 步骤 12：变更后快照与 Vault 入库

```bash
sudo btrfs subvolume snapshot -r / "/.snapshots/root-post-phase1b-publish-$(date +%Y-%m-%d-%H%M)"
```

```bash
sudo mount /mnt/vault
```

```bash
sudo /usr/local/sbin/vault-backup-root-btrfs
```

```bash
sudo umount /mnt/vault
```

> `📋 RECORD` 记录 post-change 快照名称与 Vault sync 结果。

---

## 步骤 13：完成现场记录

> 使用 `docs/templates/first-live-publish-record-template.md` 模板，填写所有 `📋 RECORD` 标记收集的信息。

---

## 步骤 14：文档回写（在开发仓内操作）

> 使用 `docs/templates/phase1b-live-publish-syncback-template.md` 中的模板文字：

1. 在 `docs/host-sop.md` §16 变更记录末尾追加时间线条目
2. 在 `docs/host-sop.md` §0.2 和 §11.3 更新阶段表述
3. 在 `docs/design-v3.md` §7 Phase 1B 交付物表将 `⬚ 待执行` 改为 `✅ 已完成`
4. 在 `docs/design-v3.md` §0 更新文档结论

> `⏸ STOP` 在提交前 review 所有变更，确保不夸大为 Phase 2 已开始。

```bash
cd ~/projects/openclaw-dev
git add docs/host-sop.md docs/design-v3.md
git commit -m "phase1b: record first live scripted publish completion

- Update host-sop.md timeline, phase status, and exit criteria
- Update design-v3.md Phase 1B deliverables table
- Phase 1B exit criteria now fully met
- Phase 2 has NOT started"
```

---

## 回退速查卡

### 如果步骤 8 脚本报错退出（未写入文件）

- **严重度**：低
- **动作**：分析错误原因（权限？路径？模板缺文件？）
- **不要做**：不要手动 rsync 或 cp 绕过脚本
- **修复后**：可直接重新执行步骤 8

### 如果步骤 8 完成但步骤 9 check 失败

- **严重度**：中
- **先看**：check 的哪些项失败？
- **如果是 SOP 相关**：`control/SOP.md` 缺少 header 或 hash 不匹配 → 在开发仓修复后重新 publish
- **如果是模板文件缺失**：检查 `workspace-main-template/` 是否完整 → 修复后重新 publish
- **不要做**：不要手动编辑 live workspace-main 中的文件
- **关键确认**：`control/state/` 是否完好？如果状态文件被意外删除（不应该发生），需评估影响

### 如果步骤 9 通过但步骤 10 gateway health 失败

- **严重度**：高（但很可能与 publish 无关）
- **先看**：`sudo journalctl -u openclaw-gateway.service --since '5 minutes ago'`
- **不要做**：不要因为 gateway 问题回滚 workspace-main — publish 不影响 gateway 进程
- **如果需要 gateway restart**：按 host-sop.md §13 的标准流程操作

### 如果步骤 11 飞书不可达

- **严重度**：中
- **先看**：gateway health 是否通过？如果 health 通过但飞书不可达，可能是飞书插件问题
- **不要做**：不要因此回滚 workspace-main

### 通用原则

- workspace-main 是可重复发布产物 — 回退方式是重新 publish，不是根快照回滚
- 根快照只保护 `/etc/openclaw`、`/opt/openclaw` 等系统组件 — 本次操作不修改这些
- 任何回退前先记录当前失败状态
- `control/state/` 在 publish 过程中被 rsync `--exclude` 保护，不会被覆写

---

## 本文档不包含

- Phase 2 的任何内容
- broker / wrapper / task-runner / Docker 的任何操作
- `/etc/openclaw/openclaw.json` 的任何变更
- gateway restart 操作
- Vault 子卷级别的操作（仅使用现有 `vault-backup-root-btrfs` 脚本）
