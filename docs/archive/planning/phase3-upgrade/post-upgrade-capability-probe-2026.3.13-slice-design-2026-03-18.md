# Post-Upgrade Capability Probe Slice Design (2026.3.13)

> 设计日期：2026-03-18
> 当前基线：OpenClaw 2026.3.13（2026-03-18 升级完成，P0 19/19 PASS）
> 前置文档：`docs/records/openclaw-2026.3.13-upgrade-activation-2026-03-18.md`
> 状态：**active — 设计完成，probe 尚未执行**

---

## 1. 本 slice 的唯一目标

回答一个问题：

> 在当前 `2026.3.13` live baseline 上，哪些能力已经足以支持 Phase 3 第一刀，哪些仍不清楚，哪些明确不应现在依赖？

本 slice **是**：
- 一次结构化的 capability 探查
- Phase 3 Go/No-Go 的门控依据
- 对后续 substantive slice 的入口定义

本 slice **不是**：
- Phase 3 实现
- Docker sandbox 部署
- Scrapling 接入
- 任何 live 变更操作

---

## 2. 为什么不直接进入 Phase 3

1. **未验证能力不等于可用能力**。升级后 focused regression 验证的是 Phase 2 已有功能的向后兼容性（19/19 PASS），但 Phase 3 依赖的是升级引入的 **新** 能力（`sessions_yield`、cross-agent workspace 修复、sandbox backend 变更等），这些从未在 live 上执行过。
2. **Plugin provenance 警告需要定性**。升级后观察到 provenance 警告（P1），如果该行为在未来 task-runner 的 plugin 注册流中变成 hard block，Phase 3 设计假设就需要调整。
3. **Docker 接入路径未确认**。design-v3 §5.9.2 明确指出"不把 DOCKER_HOST 方案写死"，必须通过 capability probe 才能落地。当前完全没有 Docker 相关验证。
4. **`sessions_yield` 语义未知**。design-v3 §7.5 仅记录"需评估对 task-runner 会话管理的影响"，未做任何真实行为验证。

---

## 3. Probe 范围

### 3.1 纳入 probe 的 capability（5 项）

| # | Probe 领域 | 核心问题 | 对 Phase 3 的关系 |
|---|-----------|---------|------------------|
| P1 | `sessions_yield` | 这是什么语义？对 task-runner session 管理有什么影响？当前是否应视为依赖？ | Phase 3 session 管理设计基础 |
| P2 | Plugin trust / provenance | 升级后出现的 provenance 警告意味着什么？对 task-runner 容器内 plugin 有约束吗？ | Phase 3/4 plugin 注入方式 |
| P3 | Target workspace / subagent 行为 | 2026.3.13 cross-agent target workspace 修复是否真实可用？`sessions_spawn` 的 workspace 隔离语义是否符合设计预期？ | Phase 3 `sessions_spawn("task-runner")` 可行性 |
| P4 | Sandbox / workspace access 真实行为 | `sandbox.docker` 配置在当前版本上的真实行为？`workspaceAccess: "none"` 的实际效果？ | Phase 3 sandbox 策略设计 |
| P5 | Docker / task-runner 前置条件 | Docker Engine 当前状态？`openclaw` 用户的 Docker 访问路径？网络/镜像前置？ | Phase 3 第一步可行性 |

### 3.2 明确排除的 capability（不在本轮 probe）

| 排除项 | 排除原因 |
|--------|---------|
| Scrapling 接入 | ADR 已冻结定位（task-runner layer），当前不接入 |
| `openclaw backup create/verify` | 补充性工具，不是 Phase 3 前置（属 Phase 6 输入） |
| `gateway.auth.token` SecretRef | 与 Phase 5 相关，不是 Phase 3 前置 |
| Config schema lookup | 便利性优化，不影响 Phase 3 可行性 |
| LLM gateway / token 发放 | Phase 5 范围 |
| 容器内 Claude Code 集成 | Phase 4 范围 |

---

## 4. 逐项 probe 设计

### P1: `sessions_yield`

**假设**：`sessions_yield` 是 2026.3.12 引入的新会话管理原语，可能改变 agent session 的让出/恢复行为。

**probe 目标**：
1. 确认 `sessions_yield` 在当前 gateway 上是否可用（API 层面存在）
2. 确认其语义：是主动让出 CPU 调度、还是 session 持久化让出、还是 orchestration 级别的 yield
3. 评估与 `sessions_spawn("task-runner")` 的交互关系
4. 判定 Phase 3 是否应将其纳入设计假设

**repo-side 准备**：无代码变更。仅需 operator 在 live 上执行 probe。

**live-side operator 动作**：
1. 检查 gateway journal 是否有 `sessions_yield` 相关 capability 声明
2. 检查 `openclaw --help` 或 OpenClaw CLI 是否暴露 yield 相关子命令
3. 通过 agent session 尝试调用 `sessions_yield`（如果存在），观察行为
4. 查阅 2026.3.12 changelog 中 `sessions_yield` 的上游文档描述

**成功判据**：能明确回答"sessions_yield 的语义是什么"且能评估其对 task-runner 设计的影响。

**判定标准**：
- **可依赖（Go）**：语义清晰、行为可预测、与 Phase 3 session 管理直接正相关
- **可实验（Caution）**：存在但语义不完全清晰，或与 Phase 3 设计不直接相关
- **不建议依赖（No-Go）**：不存在、行为不确定、或有已知 issue

### P2: Plugin trust / provenance

**假设**：2026.3.12 禁用了 implicit workspace plugin auto-load，2026.3.13 升级后出现 provenance 警告。host-ops-tool 通过 `plugins.entries` config 注册，预期不受影响。

**probe 目标**：
1. 确认 provenance 警告的确切触发条件和日志内容
2. 判定警告是纯信息性、还是会在某些条件下升级为 hard block
3. 评估对 task-runner 容器内 plugin 注册方式的影响
4. 评估对未来 workspace plugin 自动加载路径的影响

**repo-side 准备**：无代码变更。

**live-side operator 动作**：
1. `sudo journalctl -u openclaw-gateway.service | grep -i provenance` — 提取完整日志
2. `sudo journalctl -u openclaw-gateway.service | grep -i trust` — 提取 trust 相关日志
3. 检查 `/etc/openclaw/openclaw.json` 中 `plugins.entries` 和 `plugins.allow` 配置
4. 检查上游 2026.3.12/2026.3.13 changelog 中 plugin trust 相关变更说明
5. 对比升级前后 gateway journal 中 plugin registration 日志差异

**成功判据**：能明确回答"provenance 警告是否会在 Phase 3 场景下升级为 hard block"。

**判定标准**：
- **无需调整（Go）**：警告是信息性的，`plugins.entries` 注册路径不受影响，task-runner 场景下也不会变成 hard block
- **需调整设计（Caution）**：警告暗示未来版本可能强制 provenance 校验，Phase 3 plugin 注入方式需要预防性调整
- **阻塞 Phase 3（No-Go）**：当前版本已在某些路径下将 provenance 作为 hard block

### P3: Target workspace / subagent 行为

**假设**：2026.3.13 修复了 cross-agent subagent target workspace 问题，`sessions_spawn("task-runner")` 的 workspace 隔离行为应更准确。

**probe 目标**：
1. 确认 `sessions_spawn` 在当前版本上的行为——spawn 出的子 session 的 workspace 是如何确定的？
2. 确认 subagent 的 workspace 是否正确指向其 agent config 中定义的 workspace 路径
3. 评估 workspace 隔离是否足够（子 agent 不能逃逸到父 agent 的 workspace）
4. 注意：此 probe 不创建 task-runner agent，仅验证 `sessions_spawn` 的基础语义

**repo-side 准备**：无代码变更。

**live-side operator 动作**：
1. 查阅 2026.3.13 changelog 中 cross-agent workspace 修复的具体描述
2. 检查当前 `openclaw.json` 中 `agents.list` 配置（目前只有 `main`）
3. 如安全可行：在 `openclaw.json` 中临时加入一个只读 test agent（不是 task-runner），验证 `sessions_spawn` 的 workspace 隔离行为
4. 或者：仅阅读上游文档/代码确认修复内容，不做 live spawn 测试

**成功判据**：能明确回答"sessions_spawn 的 workspace 隔离语义是否符合 design-v3 §5.2 假设"。

**判定标准**：
- **符合预期（Go）**：workspace 隔离行为与 design-v3 §5.2 一致，子 agent 使用自己的 workspace
- **需进一步验证（Caution）**：上游文档确认修复，但 live 行为未完整验证
- **不符合预期（No-Go）**：workspace 隔离不成立或有已知限制

### P4: Sandbox / workspace access 真实行为

**假设**：`sandbox.docker` 配置在当前版本上可用，`workspaceAccess: "none"` 会阻止 sandbox session 访问 agent workspace。

**probe 目标**：
1. 确认 `sandbox` 配置项在当前版本上是否被识别和执行
2. 确认 `sandbox.mode`、`sandbox.scope`、`sandbox.workspaceAccess` 的真实行为
3. 确认 `sandbox.docker` 子配置（image、network）的当前版本支持状态
4. 注意：此 probe 不执行 Docker sandbox，仅验证配置层面的接受度

**repo-side 准备**：无代码变更。

**live-side operator 动作**：
1. 查阅 2026.3.12/2026.3.13 上游文档中 sandbox 相关 API 和配置变更
2. 检查 `openclaw --help` 或 gateway API 是否有 sandbox 相关子命令/端点
3. 使用 `validate_openclaw_json_candidate` 测试一个包含 `sandbox` 配置的 candidate config（不 deploy，仅 validate），观察 schema validation 结果
4. 检查 gateway journal 是否有 sandbox backend 相关日志

**成功判据**：能明确回答"sandbox.docker 配置在当前版本上是否被正确解析和执行"。

**判定标准**：
- **配置可接受（Go）**：sandbox 配置被正确解析，docker backend 被识别
- **配置接受但 backend 未就绪（Caution）**：配置不报错但 docker backend 未连接/未实现
- **配置被拒绝（No-Go）**：当前版本不支持 sandbox.docker 配置

### P5: Docker / task-runner 前置条件

**假设**：Docker Engine 在宿主机上已安装但不确定是否配置就绪。`openclaw` system user 需要某种方式访问 Docker API。

**probe 目标**：
1. 确认 Docker Engine 是否安装、版本、运行状态
2. 确认 Docker socket 路径和权限
3. 确认 `openclaw` 用户是否有 Docker 访问权限（直接或通过 proxy）
4. 评估 Phase 3 Docker 整理的工作量
5. 注意：此 probe 不做 Docker 配置变更，仅收集当前状态

**repo-side 准备**：无代码变更。

**live-side operator 动作**：
1. `docker --version` — Docker Engine 版本
2. `systemctl is-active docker.service` — Docker 服务状态
3. `ls -la /var/run/docker.sock` — socket 权限
4. `getent group docker` — docker 组成员
5. `sudo -u openclaw docker info 2>&1 | head -20` — openclaw 用户 Docker 访问
6. `docker network ls` — 现有网络
7. `docker images` — 现有镜像

**成功判据**：能给出 Docker 前置条件的完整状态报告。

**判定标准**：
- **就绪（Go）**：Docker 安装且运行，openclaw 用户有某种访问路径
- **需要整理（Caution）**：Docker 已安装但需要权限/网络/镜像配置
- **需要从头安装（No-Go）**：Docker 未安装或不可用

---

## 5. Probe 结果对 Phase 3 的影响矩阵

| Probe | Go 结论 → Phase 3 影响 | Caution 结论 → Phase 3 影响 | No-Go 结论 → Phase 3 影响 |
|-------|----------------------|---------------------------|--------------------------|
| P1 sessions_yield | 纳入 Phase 3 session 设计 | 仅作参考，Phase 3 不依赖 | Phase 3 不依赖 |
| P2 plugin trust | 维持当前 plugin 注入方式 | 预防性调整 plugin 注入方式 | 重新设计 plugin 注入方式 |
| P3 workspace/subagent | 维持 design-v3 §5.2 假设 | 增加验证步骤 | 重新设计 workspace 策略 |
| P4 sandbox 配置 | 维持 design-v3 §5.9 假设 | 增加 sandbox 验证 slice | 重新评估 sandbox 路径 |
| P5 Docker 前置 | 直接进入 Phase 3 第一步 | Phase 3 第一步变为 Docker 整理 | Phase 3 前置增加 Docker 安装 |

---

## 6. Phase 3 Go/No-Go 门控条件

### 6.1 Go 条件（全部满足才放行 Phase 3）

1. **P2 plugin trust ≥ Caution**：provenance 警告已定性，非 hard block
2. **P4 sandbox 配置 ≥ Caution**：sandbox.docker 配置不被当前版本拒绝
3. **P5 Docker 前置 ≥ Caution**：Docker Engine 存在且有可行的访问路径
4. **P3 workspace/subagent ≥ Caution**：sessions_spawn workspace 隔离基本可行

### 6.2 P1 sessions_yield 不是 Go/No-Go 条件

`sessions_yield` 是新增能力，Phase 3 **第一刀** 不应将其作为前置依赖。如果 probe 结论为 Go，可在 Phase 3 后续 slice 中纳入；如果为 Caution 或 No-Go，Phase 3 按原有 `sessions_spawn` 路径设计即可。

### 6.3 No-Go 处置

如果 P2/P3/P4/P5 中有任一项为 No-Go：
- 不进入 Phase 3
- 记录 No-Go 原因
- 评估是否需要等待上游修复、或调整 design-v3 架构假设

---

## 7. Phase 3 第一刀的"最小可行入口"重定义

### 7.1 Phase 3 第一刀应该探什么

在 capability probe 全部 ≥ Caution 的前提下，Phase 3 第一刀应为：

**Docker sandbox 最小可达验证**

具体范围：
1. Docker Engine 配置就绪（包含 openclaw 用户的安全访问路径）
2. `openclaw-task-net` 自定义网络创建
3. 最小 test container 启动验证（不是完整 task-runner 镜像）
4. 从 openclaw gateway 侧验证 `sandbox.docker` 配置被正确识别

### 7.2 Phase 3 第一刀绝不该探什么

- 不构建完整 `openclaw-task-claude` 镜像
- 不创建 `workspace-task-runner`
- 不在 `openclaw.json` 中加入 `task-runner` agent
- 不接入 Scrapling
- 不部署容器内 Claude Code
- 不实现 `sessions_spawn("task-runner")` 完整流程

---

## 8. 直接下一刀与后继 implementation slice

> **直接下一刀：`execute-post-upgrade-capability-probe-on-2026.3.13`**

说明：
- 当前唯一推荐的下一刀是**执行**本 probe 设计包，而不是直接进入 Phase 3 implementation slice。
- `phase3-docker-sandbox-foundation` 不是当前直接下一刀。
- 只有在本 capability probe 全部完成、且 Go/No-Go hard gate 通过后，才推荐 `phase3-docker-sandbox-foundation` 作为**后继 implementation slice**。


范围：
1. Docker Engine 整理与 openclaw 用户安全接入
2. `openclaw-task-net` 自定义 bridge 网络
3. 最小 test image 构建与验证
4. `sandbox.docker` 配置集成验证
5. Pre/post snapshot + vault sync

不包含：
- task-runner agent 配置
- 完整任务镜像
- 容器内 Claude Code
- Scrapling

这个 slice 完成后，才进入"创建 task-runner agent + workspace + sessions_spawn 验证"。

---

## 9. Probe 执行包引用

- Probe matrix：`docs/checklists/post-upgrade-capability-probe-matrix-2026.3.13.md`
- Operator runbook：`docs/runbook-post-upgrade-capability-probe-2026.3.13.md`
- Result record template：`docs/templates/post-upgrade-capability-probe-record-template.md`
