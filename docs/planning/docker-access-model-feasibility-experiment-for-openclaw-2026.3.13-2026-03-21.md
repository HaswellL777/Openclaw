# Docker Access Model Feasibility Experiment For OpenClaw 2026.3.13

> 日期：2026-03-21
> 文档类型：planning / feasibility experiment definition
> 当前状态：**retained as feasibility definition / not current direct next window**
> 父切片：`docker-prerequisite-establishment-for-phase3`
> baseline：OpenClaw `2026.3.13`
> 文档性质：**这是可行性实验定义，不是 establishment 记录，不是 Phase 3 实施记录**

---

## 1. 文档性质声明

本文件只定义一个 repo-side 可行性实验包，用于回答一个单点问题：

- OpenClaw `2026.3.13` 的 `sandbox.docker`，是否能通过“受限 proxy + 显式 endpoint”完成最小生命周期闭环。

本文件不是：

- live-side establishment 记录
- Docker prerequisite 已实施记录
- Phase 3 implementation record
- proxy + endpoint 终态冻结方案

因此，除非未来另有 live-side 执行证据，本文件内所有内容都只能理解为：

- 候选访问模型
- 待验证实验对象
- 进入或不进入后续 establishment 的判定输入

## 2. 背景

### 2.1 已知 blocker

`2026-03-19` 的 post-upgrade capability probe 已在 OpenClaw `2026.3.13` baseline 上执行，并在 `P5 Docker / task-runner prerequisites` 处 hard gate FAIL。

当前已知事实是：

- Docker prerequisite 缺失
- Phase 3 当前为 **NO-GO**
- `P2 / P1 / P4 / P3` 均为 `deferred / not executed`

### 2.2 当前唯一存活候选

在已收口的 repo-side 边界下，当前唯一存活候选是：

- `openclaw` 不进入 `docker` 组
- 不采用 rootless Docker
- 通过受限 proxy / 显式 endpoint 访问 Docker API

这里的“唯一存活候选”只表示：

- 目前没有其他更安全、边界更清晰的候选仍保持打开状态

它**不表示**：

- 该模型已经实施
- 该模型已经被 OpenClaw `2026.3.13` 验证可行
- 该模型已经被冻结为最终实施方案

### 2.3 为什么还不能直接进入 live-side establishment

当前还不能直接进入 live-side establishment，原因是：

1. 现有证据只证明了 `P5 blocker` 存在，并未证明 `sandbox.docker` 能在该访问模型下跑通最小生命周期。
2. `docs/design-v3.md` 已明确说明，不能把“受限 socket proxy + `DOCKER_HOST`”写成既定规范前提，因为缺少完整生命周期证据。
3. 若在证据不足时直接进入 establishment，会把“候选访问模型”误写成“已冻结实施路径”，违反当前边界纪律。
4. 本轮任务明确限定为 repo-side 文档定义，不允许 live-side establishment、系统配置变更或任何实际部署动作。

## 3. 实验唯一问题

本实验只回答一个问题：

- OpenClaw `2026.3.13` 的 `sandbox.docker`，是否能通过“受限 proxy + 显式 endpoint”完成最小生命周期闭环。

本实验**不**回答以下问题：

- Phase 3 是否已经放行
- proxy + endpoint 是否就是最终实施形态
- task-runner/image/network/workspace 是否已经可以进入正式实施
- Docker prerequisite establishment 是否已经开始

## 4. 实验范围

### 4.1 允许验证的内容

本实验未来如执行，只允许验证与“最小 sandbox lifecycle 闭环”直接相关的事项：

1. OpenClaw `2026.3.13` 是否接受指向该访问模型的 `sandbox.docker` 配置。
2. OpenClaw 是否能通过显式 endpoint 触达受限 proxy，而不是隐式依赖本地 root-owned Docker socket。
3. OpenClaw 发起的一次最小 sandbox 生命周期，是否至少能完成：
   - backend 连接
   - sandbox create / start
   - 一次最小任务执行到可判定结束
   - cleanup / teardown
4. 失败时是否能把失败点清楚归类到配置、连通性、生命周期能力或清理能力。

### 4.2 不允许扩展的内容

本实验不得扩展到以下事项：

- task-runner 正式实施
- baseline image 设计或冻结
- network 正式拓扑或出站策略实施
- workspace 正式挂载设计
- 长期 endpoint / proxy 服务部署
- Docker 权限体系终态冻结
- broker / plugin / host_ops 功能扩展
- 将实验写成 establishment 已开始或已完成

## 5. 最低通过证据

本实验的最低通过证据，不能只是：

- `docker version`
- `docker info`
- proxy 健康检查
- 单独的 endpoint 连通性

这些都只能算前置可读性证据，不构成通过。

真正的最低通过证据必须围绕 **OpenClaw 发起并完成最小 sandbox lifecycle 闭环**，至少包括：

1. OpenClaw `2026.3.13` 接受相关 `sandbox.docker` 配置，而不是 schema/config 级拒绝。
2. OpenClaw 通过受限 proxy + 显式 endpoint 发起 sandbox 生命周期，而不是回退到默认本地 socket 假设。
3. 一次最小 sandbox 任务被成功创建并启动。
4. 该任务完成到可判定结束状态，不要求扩展到正式 task-runner 工作负载。
5. OpenClaw 或其对应 backend 能完成关联容器/资源的 cleanup / teardown，不留下“只会创建不会收尾”的半闭环。

如果未来 live-side 执行时只能证明：

- 配置被接受
- backend 可连接
- 但无法完成 create/start/run/cleanup 的最小闭环

则本实验仍应判定为 **未通过**。

## 6. 失败分类

未来如执行本实验，失败结论只允许先收口到以下四类：

### 6.1 `config rejected`

含义：

- OpenClaw `2026.3.13` 不接受该 `sandbox.docker` 配置
- 或配置虽语法可读，但在校验阶段即被拒绝

代表问题在：

- 配置模型
- schema 支持度
- endpoint/proxy 指向方式与当前版本不兼容

### 6.2 `backend unreachable`

含义：

- 配置被接受
- 但 OpenClaw 无法通过显式 endpoint 触达受限 proxy

代表问题在：

- endpoint 可达性
- proxy 接入路径
- backend 连通性

### 6.3 `lifecycle operation unsupported`

含义：

- 配置被接受
- backend 可触达
- 但最小生命周期中的 create / start / run / wait 等关键操作无法完成

代表问题在：

- 当前 OpenClaw `sandbox.docker` 对该访问模型的行为不兼容
- 或 proxy 暴露的受限能力不足以支撑生命周期关键步骤

### 6.4 `cleanup/teardown unsupported`

含义：

- 前置步骤可以部分或大部分成功
- 但 cleanup / teardown 无法稳定完成

代表问题在：

- 生命周期闭环不完整
- 该候选模型即使可启动，也不足以作为 Phase 3 prerequisite establishment 的可进入对象

## 7. 执行前检查项

本节只定义实验执行前必须先明确的边界与保护条件，不包含 establishment 动作。

未来如进入执行窗口，开始前必须先明确：

1. 该窗口的性质是 feasibility experiment，而不是 Docker prerequisite establishment。
2. `Phase 3 = NO-GO` 仍保持不变；本实验只是为后续是否进入 establishment 提供判定输入。
3. proxy + endpoint 仍是“唯一存活候选”，不是已冻结终态。
4. 实验目标只限最小 lifecycle 闭环，不夹带 image / network / workspace 正式实施。
5. 所有 live-side 写操作都必须另行进入可审计执行窗口，并遵守 snapshot / Vault / validation 纪律。
6. 不触碰 `/etc/openclaw/openclaw.json`、`openclaw.live.json`、systemd 单元或 secrets handling，除非未来另有独立审查包放行。
7. 成功与失败判据、证据采集点、停止条件必须在执行前写清楚，避免把模糊结果误判为“基本可行”。

## 8. 实验后判定逻辑

### 8.1 通过意味着什么

如果未来执行结果满足“最低通过证据”，则只意味着：

- 当前唯一存活候选在 OpenClaw `2026.3.13` 上，**有证据表明**可以支撑 `sandbox.docker` 的最小生命周期闭环
- `docker-prerequisite-establishment-for-phase3` 可以基于该证据继续细化 live-side establishment 包

它**不意味着**：

- Phase 3 已经放行
- proxy + endpoint 已冻结为终态
- task-runner/image/network/workspace 已可直接进入正式实施

### 8.2 不通过意味着什么

如果未来执行结果落入四类失败之一，则意味着：

- 当前唯一存活候选尚不足以证明可支撑 `sandbox.docker` 最小生命周期闭环
- `docker-prerequisite-establishment-for-phase3` 不能直接以该候选进入 live-side establishment
- Phase 3 继续保持 **NO-GO**

### 8.3 为什么通过后仍不等于 `Phase 3 = GO`

即使本实验通过，Phase 3 仍不自动转为 GO，原因是：

1. 本实验只覆盖最小生命周期闭环，不覆盖正式 task-runner 实施范围。
2. 本实验不验证长期运维形态、权限边界终态、网络/镜像/workspace 正式设计。
3. Phase 3 仍需后续 establishment 包、风险评审、回滚说明与验证清单，才可能进入实现阶段。

## 9. 回滚边界

如果未来进入 live-side 实验执行，回滚边界必须先写清楚：

### 9.1 可回滚项

实验如需引入临时性对象，可回滚项只应限于：

- 为实验窗口准备的临时 candidate config
- 临时 proxy / endpoint 指向配置
- 实验产生的临时容器、临时网络或其他临时 Docker 资源
- 与实验直接相关、可审计且可删除的临时记录

### 9.2 仍不应触碰的项

即使未来执行本实验，下列项仍不应被该实验触碰：

- `/etc/openclaw/openclaw.json`
- `openclaw.live.json`
- systemd 单元终态设计
- `openclaw` 用户长期权限模型终态
- secrets handling 方案
- task-runner / image / network / workspace 正式实施

### 9.3 回滚边界的含义

回滚在这里的含义是：

- 只回收实验窗口引入的临时对象
- 不把实验窗口扩大为正式 establishment
- 不把一次可行性实验结果写成已落地运行态事实

## 10. 与父切片的关系

本文件是：

- `docker-prerequisite-establishment-for-phase3`
  的前置判定子包

父切片仍处于 active 状态；但当前直接下一刀已经切成 `hello-world-image-prerequisite-window-2026-03-21`。本文件只保留为 prerequisite establishment 内的 feasibility definition 子包：

- `docker access model feasibility experiment definition`

在该定义之外，不前推任何 live-side establishment 结论。
