# 现场记录：首次现网脚本化发布 workspace-main

> 本文档是现场记录模板。Operator 在执行发布时逐项填写。
> 对应执行包：`docs/execution-pack-first-live-publish.md`
> 对应 runbook：`docs/runbook-first-live-publish.md`

---

## 基本信息

| 项目 | 值 |
|------|----|
| Operator | _(nick / 其他)_ |
| 执行日期（本地） | _YYYY-MM-DD_ |
| 执行时间（UTC） | _YYYY-MM-DD HH:MM:SS UTC_ |
| 开发仓分支 | _(例：feat/phase1b-workspace-foundation 或 main)_ |
| Git commit (full SHA) | _(git rev-parse HEAD 输出)_ |
| Git commit 摘要 | _(git log --oneline -1 输出)_ |

---

## Preflight 结果

| 项目 | 值 |
|------|----|
| Preflight 结论 | _GO / NO-GO_ |
| PASS 数量 | ___ |
| WARN 数量 | ___ |
| FAIL 数量 | ___ |
| 输出文件路径 | _/tmp/preflight-YYYYMMDD-HHMMSS.txt_ |
| 备注（如有 WARN） | _(留空或记录)_ |

---

## 现网前置检查

| 检查项 | 结果 |
|--------|------|
| Gateway health check | _OK / FAIL_ |
| Live workspace-main 存在 | _是 / 否_ |
| control/state/ 包含运行时文件 | _是 / 否_ |
| openclaw 用户读取权限 | _全部 readable / 需要方案 A/B/C_ |
| 如使用权限方案，具体方案 | _(A: staging / B: ACL / C: chmod / 不需要)_ |
| Go/No-Go 检查表全部通过 | _是 / 否_ |

---

## 变更前快照

| 项目 | 值 |
|------|----|
| Pre-change snapshot 名称 | _root-pre-phase1b-publish-YYYY-MM-DD-HHMM_ |
| 快照创建时间 | _YYYY-MM-DD HH:MM_ |

---

## 发布执行

| 项目 | 值 |
|------|----|
| 实际执行命令 | _(复制实际执行的完整命令)_ |
| 交互确认输入 | _yes-publish-live_ |
| 脚本输出结论 | _PUBLISH COMPLETE / 报错退出_ |
| 如报错，错误信息 | _(留空或记录)_ |

---

## 发布后校验

| 项目 | 值 |
|------|----|
| check-workspace-main.sh 结论 | _All checks passed / 有失败项_ |
| check 输出文件路径 | _/tmp/check-post-publish-YYYYMMDD-HHMMSS.txt_ |
| 如有失败，失败项列表 | _(留空或记录)_ |

---

## 健康复验

| 项目 | 值 |
|------|----|
| Gateway health 复验 | _OK / FAIL_ |
| 飞书可达性验证 | _main 正常响应 / 不可达_ |
| 飞书验证方式 | _(截屏 / 文字记录)_ |

---

## 变更后快照与 Vault

| 项目 | 值 |
|------|----|
| Post-change snapshot 名称 | _root-post-phase1b-publish-YYYY-MM-DD-HHMM_ |
| Vault 挂载 | _成功 / 失败_ |
| vault-backup-root-btrfs 执行 | _成功 / 失败_ |
| Vault 卸载 | _成功 / 失败_ |

---

## 最终结论

| 项目 | 值 |
|------|----|
| 发布是否成功 | _是 / 否_ |
| Phase 1B 退出条件是否满足 | _是 / 否_ |

---

## 异常与备注

_(记录任何非预期情况、偏差、额外操作。如无异常则写"无"。)_

---

## 文档回写确认

| 回写项 | 已完成 |
|--------|--------|
| host-sop.md §16 追加时间线条目 | ☐ |
| host-sop.md §0.2 / §11.3 更新阶段表述 | ☐ |
| design-v3.md §7 交付物表 `⬚ 待执行` → `✅ 已完成` | ☐ |
| design-v3.md §0 更新文档结论 | ☐ |
| 开发仓 git commit 提交 | ☐ |
| 回写 commit SHA | _(填写)_ |

---

> 本记录填写完毕后，建议保存到开发仓的合适位置（如 `docs/records/` 目录），或作为 commit message 的补充附件。
