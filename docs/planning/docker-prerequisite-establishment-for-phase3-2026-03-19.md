# Docker Prerequisite Establishment For Phase 3

> 日期：2026-03-19
> 文档类型：planning / active parent slice design
> 当前状态：**active / parent slice**
> 当前 direct-next closure：`docs/planning/approved-direct-proxy-execution-block-source-closure-2026-03-22.md`
> 前置事实：`2026-03-19` post-upgrade capability probe 已在 OpenClaw 2026.3.13 baseline 上执行，并在 `P5 Docker / task-runner prerequisites` hard gate FAIL；`2026-03-21` temporary restricted proxy feasibility window 已在 proxy start 前 `HARD_STOP`；`2026-03-22` 曾因 `current-run artifact alignment not established` 停在 `before_proxy_start`，随后 repo-side prepared state 与 readonly evidence 已补齐，但当前仍 `BLOCKED_BEFORE_HOST_SIDE_CHANGE`
> 相关执行记录：`docs/records/post-upgrade-capability-probe-execution-2026-03-19.md`；`docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md`；`docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md`

---

## 1. 背景

OpenClaw 已完成 `2026.3.13` 升级，focused regression 与 Phase 2 host_ops 回归均已通过。  
升级后 capability probe 也已实际执行，并在 `P5 Docker / task-runner prerequisites` 处 hard gate FAIL。

`2026-03-21` 的 temporary restricted proxy feasibility window execution evidence、`2026-03-22` 的 prerequisite-only remediation record 与同日新的 hard-stop record 共同把 Docker prerequisite establishment 的当前边界收口为：

- Docker 已安装；
- `docker.service` / `docker.socket` 已为 `active`；
- `/var/run/docker.sock` 为 `root:docker`；
- `openclaw` 不在 `docker` 组；
- previous-run validate-only candidate 曾通过 config validate；
- previous-run temporary restricted proxy helper payload 曾生成并编译；
- `hello-world` prerequisite 已补齐；
- current-run helper / current-run validate-only candidate 已可由 repo-side prepare / precheck 形成，且 prepared state 已通过；
- readonly evidence green 已形成；
- 但 `Approved Direct Proxy Execution Block` 仍未形成批准版本，当前 authoritative 状态仍是 `BLOCKED_BEFORE_HOST_SIDE_CHANGE`，因此 execution 尚未启动，且仍不得进入 live-side pre-snapshot。

这意味着：

- Phase 3 当前仍 **不得开始**；
- temporary restricted proxy execution 仍 **尚未启动**；
- `docker-prerequisite-establishment-for-phase3` 继续作为 **active parent slice** 存在；
- 当前 direct next child slice 已从 `hello-world-image-prerequisite-window-2026-03-21` 与 repo-side artifact repair 收口，进一步收敛为 repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐；在该批准块形成前，不得进入 live-side pre-snapshot。

因此，本文件的定位不是实施记录，而是 **repo-side planning 文档**，用于定义当前 active parent slice 及其子窗口边界。

## 2. 为什么它是当前 active parent slice

依据 `docs/records/post-upgrade-capability-probe-execution-2026-03-19.md` 与 `docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md`：

- `2026-03-19` 的 probe 已把 `P5` 明确打成 `FAIL`，因此 Phase 3 仍是 `NO-GO`；
- `2026-03-21` 的 feasibility window 证明当前 immediate blocker 已收敛到 `hello-world image missing`；
- `2026-03-22` 的新 hard-stop 进一步证明 previous-run helper / candidate baseline 不能直接当作 current-run prepared state；
- proxy/helper/candidate 仍只是 prerequisite / feasibility 语境中的候选与准备物，不能写成长期终态；
- 当前缺的不是“直接开始 Phase 3 implementation”，而是继续完成 prerequisite establishment 的剩余子窗口。

因此当前应按两层理解：

- active parent slice = `docker-prerequisite-establishment-for-phase3`
- current direct next child slice = repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐
- current repo-side repair slice = `Approved Direct Proxy Execution Block` 的命令-证据绑定与批准路径收口

在该 parent slice 完成前：

- 不继续 capability probe 主流程；
- 不把 hello-world prerequisite-only window 与 temporary restricted proxy execution 合并；
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

本 parent slice 的目标仅限于为 Phase 3 建立最小 Docker prerequisite，具体包括：

1. 固化当前已知 prerequisite baseline：Docker 已安装，`docker.service` / `docker.socket` active，`/var/run/docker.sock = root:docker`，`openclaw` 不在 `docker` 组；
2. 明确当前 direct next child slice 已收敛为 repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐，而不是 live-side pre-snapshot；
3. 建立 current-run helper / validate-only candidate 的 repo-side 预生成能力，不再依赖 previous-run baseline 假定可复用；
4. 建立 current-run artifact alignment precheck，把 `MISSING / DRIFT / PASS` 在 live-side 之前先打出来，并把通过结果沉淀为 blocked-state 的前置条件；
5. 补齐 `Approved Direct Proxy Execution Block` 的来源条件、命令-证据绑定与批准路径；
6. 明确 validate-only candidate、helper payload、temporary restricted proxy 候选都只是准备物或候选，不写成长期终态；
7. 明确 capability probe 后续重试 `P5 / P4 / P3` 所需的剩余最小前置条件；
8. 形成可审计、可回滚、可验证的 repo-side 文档与实施准备包。

## 5. 非目标

本 slice 不做以下事项：

- 不进入 `phase3-docker-sandbox-foundation`
- 不构建 task-runner 镜像
- 不接入容器内 Claude Code
- 不调整 broker、plugin、host_ops 实现
- 不做 live-side Docker 安装或修机
- 不把本 planning 写成执行证据

## 6. 前置条件

开始该 parent slice 的当前子窗口前，以下事实必须保持成立：

1. live baseline 仍为 OpenClaw `2026.3.13`
2. post-upgrade capability probe 执行记录已存在，且结论明确为 `P5 FAIL / Phase 3 = NO-GO`
3. `2026-03-21` temporary restricted proxy feasibility window execution evidence 已存在，且结论明确为 `HARD_STOP before proxy start`
4. `docs/current-boundary.md`、`docs/design-v3.md`、`docs/map.md` 与 `docs/planning/README.md` 已同步到当前边界
5. `2026-03-22` current-run artifact alignment hard-stop record 已存在，且结论明确为 `before_proxy_start`
6. authoritative blocked-state 已固定为：`RESULT=BLOCKED_BEFORE_HOST_SIDE_CHANGE`、`GATE0_3=GREEN`、`PREPARED_STATE_PASS=YES`、`READONLY_EVIDENCE_GREEN=YES`、`APPROVED_PROXY_EXEC_CMD=NO`
7. 本 slice 仅在 repo-side 文档与计划层推进，不夹带 live-side 实施

## 7. 实施顺序

建议顺序如下：

1. 固化当前边界
2. `hello-world-image-prerequisite-window-2026-03-21` 已完成并作为 prerequisite-only 窗口收口
3. current-run helper / validate-only candidate 的 repo-side 预生成
4. current-run artifact alignment precheck
5. readonly evidence green
6. repo-side 补齐 `Approved Direct Proxy Execution Block` 的来源条件、命令-证据绑定与批准路径
7. 仅在该批准块形成并单独批准后，才允许进入 live-side pre-snapshot
8. 继续明确 `openclaw` 用户访问 Docker 的安全方案候选与剩余风险项
9. 定义实施后必须满足的验证标准
10. 在 prerequisite establishment 完成后，再决定是否重启 capability probe 的 `P5 / P4 / P3`

其中 parent slice 收口时至少应回答：

- hello-world image prerequisite 是否已形成直接证据
- current-run helper / validate-only candidate 是否已形成准备物并完成对齐预检
- 是否已形成可审阅的 `Approved Direct Proxy Execution Block`
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
   - active parent slice = `docker-prerequisite-establishment-for-phase3`
   - current direct next child slice = repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐
   - current-run artifact pre-generation + alignment precheck 与 readonly evidence green 已形成，但在 `APPROVED_PROXY_EXEC_CMD=NO` 时仍不得进入 live-side pre-snapshot
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

它的作用，是把当前 `P5 FAIL / Phase 3 = NO-GO` 之后的 Docker prerequisite establishment 明确定义为：

- active parent slice：`docker-prerequisite-establishment-for-phase3`
- current direct next child slice：repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐
