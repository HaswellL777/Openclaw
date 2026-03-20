# Docker Prerequisite Establishment For Phase 3

> 日期：2026-03-19
> 文档类型：planning / next slice design
> 当前状态：**active**
> 前置事实：post-upgrade capability probe 已在 OpenClaw 2026.3.13 baseline 上执行，并在 `P5 Docker / task-runner prerequisites` hard gate FAIL
> 相关执行记录：`docs/records/post-upgrade-capability-probe-execution-2026-03-19.md`

---

## 1. 背景

OpenClaw 已完成 `2026.3.13` 升级，focused regression 与 Phase 2 host_ops 回归均已通过。  
升级后 capability probe 也已实际执行，但在 `P5 Docker / task-runner prerequisites` 处因 Docker prerequisite 缺失而 hard gate FAIL。

该 FAIL 的含义不是“Phase 3 实现失败”，而是：

- Phase 3 当前 **不得开始**；
- capability probe 主流程已按纪律提前中止；
- 当前需要先建立 Docker prerequisite，再决定是否重试后续 `P5 / P4 / P3` probe 项。

因此，本文件的定位不是实施记录，而是 **repo-side planning 文档**，用于定义当前唯一合理下一刀。

## 2. 为什么它是当前唯一下一刀

依据 `docs/records/post-upgrade-capability-probe-execution-2026-03-19.md`：

- `which docker` 无输出；
- `docker --version` 报“找不到命令”；
- `docker.service` 与 `docker.socket` 均 inactive；
- `getent group docker` 无输出；
- `sudo -u openclaw docker version` 报“docker：找不到命令”；
- operator 已确认主机未安装过 Docker。

因此当前缺的不是“更深入的 probe 设计”，也不是“直接开始 Phase 3 实装”，而是最基础的 prerequisite establishment。  
在该 prerequisite establishment 完成前：

- 不继续 capability probe 主流程；
- 不启动 `phase3-docker-sandbox-foundation`；
- 不把 Phase 3 写成可进入状态。

## 3. repo-side / live-side 边界

本 planning 只定义：

- repo-side 需要准备的文档、校验项、验证标准与实施顺序；
- live-side 后续实施时必须满足的前置条件与边界；
- 未来 operator / broker 执行时应遵守的风险控制点。

本 planning **不等于** 已实施记录，且本文件本身：

- 不安装 Docker；
- 不修改 systemd；
- 不变更 `openclaw` 用户权限；
- 不修改 `/etc/openclaw/openclaw.json`；
- 不触碰任何 live runtime 或宿主机配置。

## 4. 目标

本 slice 的目标仅限于为 Phase 3 建立最小 Docker prerequisite，具体包括：

1. 明确 Docker Engine 是否安装以及安装目标形态；
2. 明确 `docker.service` / `docker.socket` 的目标状态与启用方式；
3. 明确 `openclaw` 用户未来访问 Docker 的安全路径；
4. 明确 capability probe 后续重试 `P5 / P4 / P3` 所需的最小前置条件；
5. 形成可审计、可回滚、可验证的 repo-side 文档与实施准备包。

## 5. 非目标

本 slice 不做以下事项：

- 不进入 `phase3-docker-sandbox-foundation`
- 不构建 task-runner 镜像
- 不接入容器内 Claude Code
- 不调整 broker、plugin、host_ops 实现
- 不做 live-side Docker 安装或修机
- 不把本 planning 写成执行证据

## 6. 前置条件

开始该 slice 前，以下事实必须保持成立：

1. live baseline 仍为 OpenClaw `2026.3.13`
2. post-upgrade capability probe 执行记录已存在，且结论明确为 `P5 FAIL / Phase 3 = NO-GO`
3. `docs/current-boundary.md`、`docs/design-v3.md`、`docs/map.md` 与 `docs/planning/README.md` 已同步到当前边界
4. 本 slice 仅在 repo-side 文档与计划层推进，不夹带 live-side 实施

## 7. 实施顺序

建议顺序如下：

1. 固化当前边界
2. 明确 Docker prerequisite 的目标形态
3. 明确 `openclaw` 用户访问 Docker 的安全方案候选
4. 定义 live-side 实施前必须检查的风险项
5. 定义实施后必须满足的验证标准
6. 在 prerequisite establishment 完成后，再决定是否重启 capability probe 的 `P5 / P4 / P3`

其中“明确目标形态”至少应回答：

- 是否安装 Docker Engine
- 是否启用 `docker.service`
- 是否启用 `docker.socket`
- `openclaw` 用户是否需要通过某种受控路径访问 Docker
- 该访问路径是否会改变当前权限边界

## 8. 风险与回滚边界

本 slice 对应的未来 live-side 风险点包括：

- Docker 安装会引入新的宿主机执行面与 systemd 单元；
- `openclaw` 获得 Docker 访问路径可能改变现有权限边界；
- 若处理不当，可能把“Docker 可用”误写成“Phase 3 已开始”；
- 若缺少回滚边界，后续实施会违反当前仓库的快照 / Vault 纪律。

因此本 slice 必须坚持：

- 未形成 reviewable patch、风险表、回滚说明与验证清单前，不进入 live-side 实施；
- 不把 prerequisite establishment 与 `phase3-docker-sandbox-foundation` 合并；
- 不把 operator 用户级配置或运行态文件写回 repo 当作事实源。

回滚边界应至少明确：

- 若 live-side 后续实施开始，必须遵守“pre snapshot -> Vault sync -> change -> health validation -> post snapshot -> Vault sync”；
- 若 Docker prerequisite establishment 未完成或验证失败，应回到 `Phase 3 = NO-GO` 状态，不得越级推进后续 slice。

## 9. 验证标准

本 planning 完成时，repo-side 至少应满足：

1. 当前边界文档一致写明：
   - live baseline = `2026.3.13`
   - probe 已执行
   - `P5 FAIL`
   - `Phase 3 = NO-GO`
   - 当前唯一下一刀 = `docker-prerequisite-establishment-for-phase3`
2. planning 索引与文档地图已能正确指向本文件
3. 本文件清楚区分：
   - planning
   - execution record
   - implementation slice
4. 本文件未把任何 live-side 变更写成已完成事实

未来若进入 live-side 实施，还应另行定义并验证：

- Docker Engine 已安装且版本可确认
- `docker.service` / `docker.socket` 状态符合设计
- `openclaw` 的访问路径已通过安全审查
- capability probe 的 `P5` 可重新执行

## 10. 文档性质声明

本文件是 **planning 文档**，不是：

- 已实施记录
- operator runbook
- rollback 执行记录
- Phase 3 implementation record

它的唯一作用，是把当前 `P5 FAIL / Phase 3 = NO-GO` 之后的下一刀，明确定义为：

- `docker-prerequisite-establishment-for-phase3`
