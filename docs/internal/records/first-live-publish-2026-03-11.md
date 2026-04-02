# 现场记录：首次现网脚本化发布 workspace-main

> 对应执行包：`docs/execution-pack-first-live-publish.md`
> 对应 runbook：`docs/runbook-first-live-publish.md`

---

## 基本信息

| 项目 | 值 |
|------|-----|
| Operator | nick |
| 执行日期（本地） | 2026-03-11 |
| 执行时间（UTC） | 2026-03-11 约 05:08–05:19 UTC |
| 开发仓分支 | feat/phase1b-workspace-foundation |
| Git commit (full SHA) | 4fb7153dc9b95453ff2de4eafcd9488efa62816c |
| Git commit 摘要 | phase1b: fix publish-workspace-main.sh usage text drift |

---

## Preflight 结果

| 项目 | 值 |
|------|-----|
| Preflight 结论 | GO |
| PASS 数量 | 69 |
| WARN 数量 | 0 |
| FAIL 数量 | 0 |
| 备注 | 无 |

---

## 现网前置检查

| 检查项 | 结果 |
|--------|------|
| Gateway health check | OK（0ms） |
| Live workspace-main 存在 | 是 |
| control/state/ 包含运行时文件 | 是 |
| openclaw 用户读取权限 | 使用方案 A（staging） |
| 如使用权限方案，具体方案 | A: staging（`/tmp/openclaw-publish-staging-20260311-130932`） |
| Go/No-Go 检查表全部通过 | 是 |

---

## 变更前快照

| 项目 | 值 |
|------|-----|
| Pre-change snapshot 名称 | root-pre-phase1b-publish-2026-03-11-1308 |
| 快照创建时间 | 2026-03-11 13:08 |

---

## 发布执行

| 项目 | 值 |
|------|-----|
| 实际执行命令 | `sudo -u openclaw bash /tmp/openclaw-publish-staging-20260311-130932/scripts/publish-workspace-main.sh --apply --allow-live-target /var/lib/openclaw/.openclaw/workspace-main` |
| 交互确认输入 | yes-publish-live |
| 脚本输出结论 | PUBLISH COMPLETE |
| SOP SHA256 | 160b1e766e13e7a62010132c957d94e1190722bbaf6db071a0614972b3d66a28 |

---

## 发布后校验

| 项目 | 值 |
|------|-----|
| check-workspace-main.sh 结论 | All checks passed |
| 如有失败，失败项列表 | 无 |

---

## 健康复验

| 项目 | 值 |
|------|-----|
| Gateway health 复验 | OK（0ms） |
| 飞书可达性验证 | main 正常响应（Feishu ok） |

---

## 变更后快照与 Vault

| 项目 | 值 |
|------|-----|
| Post-change snapshot 名称 | root-post-phase1b-publish-2026-03-11-1319 |
| Vault 挂载 | 成功 |
| vault-backup-root-btrfs 执行 | 成功（auto snapshot: root-auto-2026-03-11-1324，parent: root-auto-2026-03-11-0340） |
| Vault 卸载 | 成功 |

> 注意：Vault 入库时 `vault-backup-root-btrfs` 自动创建的 `root-auto-2026-03-11-1324` 与手动创建的 post-change snapshot `root-post-phase1b-publish-2026-03-11-1319` 是不同快照。Vault 发送的是 auto snapshot，不是 post-change snapshot 本身。

---

## 最终结论

| 项目 | 值 |
|------|-----|
| 发布是否成功 | 是 |
| Phase 1B 退出条件是否满足 | 是 |

---

## 异常与备注

- Staging 方案 A 使用原因：`openclaw` 用户（nologin shell）无法 traverse `/home/nick`，因此将开发仓复制到 `/tmp/openclaw-publish-staging-20260311-130932` 并 chown 给 openclaw 执行
- 本次为"首次现网脚本化发布"，不是"首次 workspace-main 部署"——workspace-main 最初在 Phase 1A 手动部署（2026-03-07）

---

## 文档回写确认

| 回写项 | 已完成 |
|--------|--------|
| host-sop.md §16 追加时间线条目 | ✅ |
| host-sop.md §0.2 / §11.3 更新阶段表述 | ✅ |
| design-v3.md §7 交付物表 `⬚ 待执行` → `✅ 已完成` | ✅ |
| design-v3.md §0 更新文档结论 | ✅ |
| 开发仓 git commit 提交 | ☐（待 operator 审阅 diff 后提交） |
| 回写 commit SHA | （待提交后填写） |
