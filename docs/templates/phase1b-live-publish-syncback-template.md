# 发布后文档回写模板：Phase 1B 首次现网脚本化发布

> 本文档提供首次现网脚本化发布成功后，应如何更新 `docs/host-sop.md` 和 `docs/design-v3.md` 的具体文字模板。
> **只有在现网发布实际执行并校验通过后，才可使用本模板进行回写。**
> **不得提前回写。不得夸大为 Phase 2 已开始。**

---

## 1. host-sop.md §16 变更记录：追加时间线条目

在 `## 16. 变更记录` 表格末尾追加一行：

```markdown
| YYYY-MM-DD | Phase 1B 首次现网脚本化发布：通过 `publish-workspace-main.sh --apply --allow-live-target` 将 `workspace-main-template/` 发布到 `/var/lib/openclaw/.openclaw/workspace-main/`；`check-workspace-main.sh` 校验通过（published artifact 模式）；gateway health 复验 OK；飞书可达性验证通过；pre snapshot `root-pre-phase1b-publish-YYYY-MM-DD-HHMM`，post snapshot `root-post-phase1b-publish-YYYY-MM-DD-HHMM`，Vault 入库完成；**Phase 1B 退出条件全部满足** |
```

> 替换所有 `YYYY-MM-DD` 和 `HHMM` 为实际值。如有异常则在末尾追加备注。

---

## 2. host-sop.md §0.2 当前阶段定位：更新表述

### 将原文中的：

```markdown
- **Phase 1B（控制面收口）在开发仓库中已部分完成**：
  ...
  - 以上均为开发仓库内的候选产物，**publish 脚本已增加 `--allow-live-target` flag 和交互确认机制，首次现网发布 operator runbook 已编写（`docs/runbook-first-live-publish.md`），只读 preflight 预检脚本已实现（`scripts/preflight-first-live-publish.sh`），但脚本化发布链尚未首次用于 live target**（workspace-main 本身已在 Phase 1A 手动部署，见上文）。
- 当前仍不是"Phase 1 完整态"：
  - **Phase 1B 的现网发布、校验闭环尚未执行**
```

### 改为：

```markdown
- **Phase 1B（控制面收口）已完成**：
  ...
  - 以上均为开发仓库内的候选产物，**脚本化发布链已于 YYYY-MM-DD 首次用于 live target 并校验通过**（workspace-main 本身最初在 Phase 1A 手动部署，本次通过 publish 脚本完成首次脚本化覆写发布）。
- 当前是 **Phase 1 完整态**（Phase 1A + 1B 均已完成）：
  - **Phase 1B 的现网发布、校验闭环已执行并通过**
  - **Phase 2（正式 broker / wrapper 写入链）尚未开始**
  - **Phase 1B 退出条件与 Phase 2 进入门槛见 `design-v3.md` §7**
```

---

## 3. host-sop.md §11.3 当前阶段标签：更新

### 将原文中的：

```markdown
- **Phase 1B / 控制面收口 — 开发仓候选产物已就绪（含 live publish 闸门、preflight 预检与 runbook），现网首次发布待执行**
```

### 改为：

```markdown
- **Phase 1B / 控制面收口 — 已完成（YYYY-MM-DD 首次现网脚本化发布通过）**
```

---

## 4. host-sop.md §11.3.1 Phase 1B 退出条件：更新

### 将原文中的：

```markdown
2. 首次通过脚本化发布链完成现网 workspace-main 发布（runbook 已就绪：...）；
3. 发布后通过 `check-workspace-main.sh` 校验通过。
```

### 改为：

```markdown
2. ~~首次通过脚本化发布链完成现网 workspace-main 发布~~ ✅ 已完成（YYYY-MM-DD）；
3. ~~发布后通过 `check-workspace-main.sh` 校验通过~~ ✅ 已完成（YYYY-MM-DD）。
```

---

## 5. host-sop.md §0.5 未决问题第 4 项：更新

### 将原文中的：

```markdown
4. **Phase 1B 发布 / 校验脚本已在开发仓就绪，但尚未在现网执行首次正式发布。**
   ...
   - 首次现网正式发布仍待安排。
```

### 改为：

```markdown
4. ~~Phase 1B 发布 / 校验脚本已在开发仓就绪，但尚未在现网执行首次正式发布。~~ ✅ 已完成（YYYY-MM-DD）。
```

---

## 6. design-v3.md §7 Phase 1B 交付物表：更新

### 将原文中的：

```markdown
| 首次现网脚本化发布 + 校验 | 现网操作 | ⬚ 待执行 |
```

### 改为：

```markdown
| 首次现网脚本化发布 + 校验 | 现网操作 | ✅ 已完成（YYYY-MM-DD） |
```

---

## 7. design-v3.md §7 Phase 1B 退出条件"尚未满足"项：更新

### 将原文中的：

```markdown
**尚未满足：**
6. ~~publish 脚本增加 `--allow-live-target` flag 或等效机制...~~ ✅ 已实现（2026-03-10）
7. 首次通过 `publish-workspace-main.sh --apply --allow-live-target` 将 workspace-main-template 发布到现网 live target；
8. 发布后通过 `check-workspace-main.sh` 校验发布产物结构完整性（published artifact 模式）。
```

### 改为：

```markdown
**已全部满足：**
6. ~~publish 脚本增加 `--allow-live-target` flag 或等效机制...~~ ✅ 已实现（2026-03-10）
7. ~~首次通过 `publish-workspace-main.sh --apply --allow-live-target` 将 workspace-main-template 发布到现网 live target~~ ✅ 已完成（YYYY-MM-DD）；
8. ~~发布后通过 `check-workspace-main.sh` 校验发布产物结构完整性（published artifact 模式）~~ ✅ 已完成（YYYY-MM-DD）。
```

---

## 8. design-v3.md §0 文档结论先行：追加或更新

在第 15 条之后追加：

```markdown
16. **Phase 1B 退出条件已于 YYYY-MM-DD 全部满足：首次现网脚本化发布已完成并校验通过。Phase 2 尚未开始。**
```

---

## 9. design-v3.md 文档头修订日期

### 将：

```markdown
> 本次修订日期：2026-03-10（Phase 1B live publish 闸门与 runbook 就绪）
```

### 改为：

```markdown
> 本次修订日期：YYYY-MM-DD（Phase 1B 退出条件全部满足）
```

---

## 回写纪律

- 所有 `YYYY-MM-DD` 和 `HHMM` 替换为实际操作日期和时间
- 不得将 Phase 2 写为"已开始"
- 不得将 broker / wrapper / task-runner / Docker 写为"已落地"
- 回写 commit message 应明确包含"Phase 1B exit criteria met"而不是"Phase 2 started"
- 回写后应在同一 commit 中更新 host-sop.md 和 design-v3.md，保持两份文档同步
