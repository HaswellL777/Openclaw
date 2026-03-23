# OpenClaw 升级就绪评估

> 评估日期：2026-03-18
> 当前基线：OpenClaw 2026.3.2 / commit 85377a2
> 目标候选：2026.3.13（当前上游最新稳定版）
> 状态：**升级准备文档，不是升级执行文档**

---

## 1. 为什么要升级

1. **版本落后 11 个稳定版本**（2026.3.2 → 2026.3.13），其中包含安全修复（2026.3.11）
2. **Phase 3 可能依赖上游新能力**：2026.3.12 带来 sessions_yield 和 workspace plugin trust 变更，且可能涉及进一步 sandbox 相关变化；具体范围待升级后验证
3. **plugin trust 模型变更**（2026.3.12）：implicit workspace plugin auto-load 被禁用，需验证 host-ops-tool 不受影响
4. **在旧版本上做 Phase 3 capability probe 没有意义**：结论可能在升级后失效

## 2. 为什么目标候选优先看 2026.3.13

- 2026.3.13 是截至 2026-03-18 的最新稳定版
- 包含 2026.3.13 的 cross-agent subagent target workspace 修复、`agents.list[].params` schema 修复、防止 gateway token 泄露到 Docker build context 修复——这些对未来 task-runner / Docker 执行面高度相关
- 2026.3.13-1 recovery tag 修复了 2026.3.13 的发布路径问题，npm 版本仍为 2026.3.13

## 3. 关键上游变更影响评估

### 2026.3.7

| 变更 | 影响 | 需验证 |
|------|------|--------|
| ContextEngine plugin slot（7 lifecycle hooks） | 未来 context 管理可用插件化策略 | 不影响现有 host-ops-tool（非 context-engine plugin） |
| config schema lookup 相关能力线索 | 可在升级后评估是否用于减少无效 validate 调用 | 本轮不视为已收口依赖 |
| Skills/workspace 边界强化 | skill root/SKILL.md realpath 检查 | 需验证现有 workspace-main skills 不受影响 |

### 2026.3.8

| 变更 | 影响 | 需验证 |
|------|------|--------|
| `openclaw backup create` / `openclaw backup verify` | 补充性 backup/verify 链 | **不替代**现有 Btrfs snapshot + Vault discipline + candidate workflow，但作为额外安全网有价值 |
| Docker image pruning | 更小的 runtime image | 低影响 |

### 2026.3.11

| 变更 | 影响 | 需验证 |
|------|------|--------|
| 安全修复 | 不能降级为普通 bugfix | 长期停留在 2026.3.2 不合理 |

### 2026.3.12

| 变更 | 影响 | 需验证 |
|------|------|--------|
| `sessions_yield` | 新的会话管理原语 | 评估对 task-runner 会话管理的影响 |
| Implicit workspace plugin auto-load 禁用 | 安全强化：cloned repos 不能自动执行 plugin 代码 | **必须验证** host-ops-tool 通过 `plugins.entries` 注册不受影响（预期不受影响，auto-load 针对 workspace plugins） |
| 其余 sandbox 相关能力变更 | 可能涉及 sandbox backend 扩展、session-tree 可见性等 | 本轮不将其写为已锁定结论，待升级后验证 |

### 2026.3.13

| 变更 | 影响 | 需验证 |
|------|------|--------|
| Cross-agent subagent target workspace 修复 | 对 future sessions_spawn("task-runner") 直接相关 | Phase 3 入口依赖 |
| `agents.list[].params` schema 修复 | agent 配置可能更严格 | 需验证现有 main agent 配置 |
| 防止 gateway token 泄露到 Docker build context | Phase 4 任务镜像构建安全前提 | Phase 4 入口依赖 |
| plugin-sdk bundling 修复 | plugin 内存使用改善 | 低风险 |

## 4. 升级前需要冻结什么

| 冻结项 | 方式 |
|--------|------|
| 当前 feature 分支代码状态 | 合并到 main 或 tag pre-upgrade baseline |
| host-ops-tool plugin 源码 hash | 记录 `plugins/host-ops-tool/index.js` SHA256 |
| live 部署的 plugin 版本 | operator 记录 `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js` SHA256 |
| live openclaw.json 配置 | operator 记录 `/etc/openclaw/openclaw.json` SHA256 |
| live OpenClaw 版本 | operator 记录 `openclaw --version` 输出 |
| live gateway + broker 服务状态 | operator 记录 `systemctl is-active` |

## 5. 升级后必须做的 focused regression

| 检查项 | 方法 | 优先级 |
|--------|------|--------|
| gateway 健康 | `systemctl is-active` + agent `gateway_health` | P0 |
| broker 健康 | `systemctl is-active openclaw-broker.service` | P0 |
| host-ops-tool plugin 无 registration error | gateway 日志检查 | P0 |
| 全部 8 个 host_ops action 回归 | 逐 action 正例测试 | P0 |
| workspace-main skills 可见性 | agent workspace 内 skill 检查 | P1 |
| openclaw.json 配置格式兼容 | gateway 启动无 schema error | P1 |

## 6. 为什么升级不能和 Phase 3 合并

1. 升级本身是一个独立的变更窗口，需要完整的 pre-snapshot → 升级 → health check → post-snapshot → Vault sync
2. 如果升级引入回归（plugin 不兼容、配置格式变化），必须有独立的 rollback 路径
3. Phase 3 的 Docker/sandbox 变更是另一个独立的变更窗口
4. 两个变更合并时，如果出问题无法区分是升级还是 Phase 3 引入的

## 7. 升级执行不在本文档范围

本文档是升级就绪评估。实际升级执行需要：
- 独立的 runbook（含 operator 手动步骤）
- pre-change snapshot
- 明确的升级命令路径（需 operator 确认）
- post-upgrade regression test plan
- rollback procedure

这些将在后续独立的升级执行 slice 中规划。
