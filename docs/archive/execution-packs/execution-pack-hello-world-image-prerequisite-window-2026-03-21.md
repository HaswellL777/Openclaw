# Hello-World Image Prerequisite Window Execution Pack Draft

> 日期：2026-03-21
> 文档类型：execution pack / operator-facing draft
> 当前状态：**draft / 仅供下次 prerequisite-only live-side window 审阅，不构成无审查执行 runbook**
> 适用窗口：`hello-world-image-prerequisite-window-2026-03-21`
> 父切片：`docker-prerequisite-establishment-for-phase3`
> 直接前置事实：`2026-03-19` capability probe 在 `P5` FAIL；`2026-03-21` temporary restricted proxy feasibility window 在 proxy start 前 `HARD_STOP`
> 文档性质：**本包只处理 hello-world image prerequisite，不启动 temporary restricted proxy，不创建 proxy audit jsonl，不把 prerequisite establishment 写成 implementation completion**

---

## 1. 目标

本 draft 的唯一目标是为下一次 operator-led live-side window 提供一个可审阅的执行前资料包，用于：

- 只处理 `hello-world` image prerequisite；
- 为后续是否允许重新进入 temporary restricted proxy feasibility execution 提供前置条件；
- 在窗口结束后继续保持 `Phase 3 = NO-GO`，直到后续 execution evidence 另行给出通过结论。

本包不回答以下问题：

- temporary restricted proxy execution 是否已经开始；
- proxy + endpoint 是否已经冻结为长期终态；
- Phase 3 implementation 是否已经放行。

## 2. 范围内事项

- 重新确认 `2026-03-21` hard-stop 的唯一原因仍是 `hello-world image missing`。
- 在 live-side window 内，仅执行与 `hello-world` image prerequisite 直接相关的最小动作。
- 记录 `hello-world` image 从“缺失”到“存在”或“仍缺失”的直接 evidence。
- 记录 Docker 服务状态、gateway / broker 状态，以及“未启动 proxy / 未创建 audit jsonl”的窗口边界 evidence。
- 如窗口内确有 host-side write，则按既有 SOP 纪律准备 `pre-change snapshot -> change -> health validation -> post-change snapshot -> Vault sync` 的保护说明，且不得把 Vault sync 插在 pre snapshot 与 change 之间。

## 3. 范围外事项

- 不启动 temporary restricted proxy。
- 不创建 proxy audit jsonl。
- 不验证 proxy execution。
- 不修改 `/etc/openclaw/openclaw.json`。
- 不修改 `openclaw.live.json`。
- 不变更 `openclaw` 用户组归属。
- 不把 `docker-prerequisite establishment` 写成 `Phase 3 implementation completion`。
- 不进入 `phase3-docker-sandbox-foundation`。
- 不冻结 helper / proxy / endpoint 的长期终态。
- 不建议或执行 doctor / repair。

## 4. 进入窗口前的冻结条件

进入本窗口前，应再次确认以下冻结条件全部保持成立：

| 条件 | 目标状态 | 说明 |
|---|---|---|
| git 基线 | 最新冻结提交仍可追溯到 `fa3e32b` | 若偏离，必须先说明原因并完成 repo-side review |
| 文档边界 | `docs/current-boundary.md`、相关 planning、相关 records 与本包表述一致 | 不允许把 prerequisite-only window 与 proxy execution 混写 |
| live baseline | OpenClaw 仍为 `2026.3.13` | 本包基于当前冻结 baseline 起草 |
| 阶段结论 | `Phase 3 = NO-GO` 仍保持不变 | 本窗口成功也不改变该结论 |
| 前置事实 | `2026-03-21` hard-stop 仍承认：`proxy not started`、`audit jsonl not created` | 不允许重写既有 execution evidence |
| 服务健康 | gateway / broker 在入窗前为健康状态 | 若不健康，应先 stop 本窗口并回到 repo-side 收口 |
| rollback 前提 | 若预计会有 host-side write，则 `pre-change snapshot -> change -> health validation -> post-change snapshot -> Vault sync` 的顺序与 rollback note 已预先写明 | 不允许先执行、后补说明，也不允许把 Vault sync 插在 pre snapshot 与 change 之间 |

## 5. 步骤顺序（高层级）

以下步骤只描述 operator-facing 的高层顺序，不提供可直接无审查执行的逐条 runbook 命令。

### Step 0. 入窗前边界复核

目的：
- 再次确认本窗口仍是 `hello-world prerequisite-only window`。
- 再次确认不启动 temporary restricted proxy，不创建 proxy audit jsonl，不推进 Phase 3 implementation。

建议检查骨架：
- 文档核对：`current-boundary`、父切片 planning、child window planning、两份前置 execution record。
- git 核对：`git status --short`、`git log --oneline -n 3`。

本步需要收集的 evidence：
- 文档边界核对截图或摘录。
- git 基线输出。

### Step 1. 窗口前现状取证

目的：
- 在 live-side 动作前，重新记录当前运行态与 Docker 相关现状。
- 形成与 `2026-03-21` hard-stop record 可对照的 pre-change baseline。

建议检查骨架：
- gateway / broker 状态确认。
- `docker.service` / `docker.socket` 状态确认。
- `/var/run/docker.sock` 权限现状确认。
- `hello-world` image 当前是否缺失的直接检查。

本步需要收集的 evidence：
- OpenClaw 版本输出。
- gateway / broker active 证据。
- Docker 服务 / socket 状态输出。
- `hello-world` image pre-check 输出。

### Step 2. 进入变更前保护条件

目的：
- 如果本窗口将发生 host-side write，先完成保护条件确认，再进入 image prerequisite establishment。

建议检查骨架：
- 预定 pre snapshot label。
- 预定 post snapshot label。
- 预定 post-window Vault sync 对应说明。
- 回滚说明中明确“根快照不恢复 `/var/lib/openclaw`”。
- 明确窗口步骤顺序中不存在“pre snapshot 之后立即 Vault sync 再变更”的写法。

本步需要收集的 evidence：
- snapshot / Vault sync 计划说明。
- rollback note。

### Step 3. 仅执行 hello-world image prerequisite establishment

目的：
- 只完成 `hello-world` image prerequisite 本身。

边界要求：
- 该步只允许处理与 image prerequisite 直接相关的最小动作。
- 该步不得扩展到 temporary restricted proxy start、proxy journal 检查、proxy audit jsonl 生成。
- 该步不得改写 OpenClaw config、不得变更 `openclaw` 用户组归属、不得宣称 prerequisite establishment 已完成 Phase 3 implementation。

本步需要收集的 evidence：
- 能直接证明 `hello-world` image 已存在或仍未存在的输出。
- 如有 host-side write，对应的 change note。

### Step 4. 窗口后健康与边界复核

目的：
- 在 image prerequisite establishment 之后，确认系统健康未受影响，且窗口边界未被突破。
- 明确本窗口仍未启动 proxy，仍未创建 audit jsonl，仍未验证 proxy execution。

建议检查骨架：
- gateway / broker post-check。
- `docker.service` / `docker.socket` post-check。
- `hello-world` image post-check。
- 核对未产生 proxy socket / proxy journal / proxy audit jsonl。

本步需要收集的 evidence：
- gateway / broker post-check 输出。
- Docker 服务 / socket post-check 输出。
- `hello-world` image post-check 输出。
- “proxy not started / audit jsonl not created / proxy execution not validated” 的窗口内确认说明。

### Step 5. 窗口关闭与 syncback 准备

目的：
- 以 prerequisite-only 语义收口本窗口，为后续是否重新进入 temporary restricted proxy feasibility execution 提供输入。

本步需要收集的 evidence：
- 本窗口结果判定：成功、未完成或 `HARD_STOP`。
- 如果成功，明确写成“`hello-world` image prerequisite 已补齐”，而不是“Phase 3 已完成”。
- 如果未成功，明确写出失败点，并保持 `Phase 3 = NO-GO`。

## 6. 每一步需要收集什么 evidence

| 步骤 | 最低 evidence |
|---|---|
| Step 0 | 文档边界核对说明、git 基线输出 |
| Step 1 | OpenClaw 版本、gateway / broker 状态、Docker 服务 / socket 状态、`hello-world` image pre-check |
| Step 2 | pre / post snapshot 计划、Vault sync 计划、rollback note |
| Step 3 | `hello-world` image prerequisite establishment 的直接证据或失败证据 |
| Step 4 | gateway / broker post-check、Docker post-check、`hello-world` image post-check、未启动 proxy / 未创建 audit jsonl / 未验证 proxy execution 的说明 |
| Step 5 | 窗口结果摘要、syncback 草稿、下一步建议入口 |

## 7. 成功判据

本窗口只在以下条件同时满足时，才可判定为“按 prerequisite-only 边界成功收口”：

1. 已形成 `hello-world` image 存在的直接 evidence。
2. 该 evidence 能与 `2026-03-21` 的 `hello-world image missing` hard-stop 形成前后闭环。
3. 窗口结束时 gateway / broker 仍保持健康。
4. 窗口结束时 `docker.service` / `docker.socket` 状态可被重新举证。
5. 本窗口未启动 temporary restricted proxy。
6. 本窗口未创建 proxy audit jsonl。
7. 本窗口未验证 proxy execution。
8. 本窗口未修改 OpenClaw config。
9. 本窗口未变更 `openclaw` 用户组归属。
10. 窗口结论没有把 prerequisite establishment 写成 implementation completion。

## 8. HARD_STOP / ROLLBACK 触发点

### HARD_STOP 触发点

- 入窗前文档边界不一致。
- git 基线不可解释。
- live baseline 不再是 `2026.3.13`。
- gateway 或 broker 在入窗前已不健康。
- 需要修改 `/etc/openclaw/openclaw.json` 或 `openclaw.live.json` 才能继续。
- 需要变更 `openclaw` 用户组归属才可继续。
- 操作开始滑向 temporary restricted proxy execution。
- 操作开始滑向 proxy execution validation。
- 操作开始滑向 Phase 3 implementation。
- 不能形成 `hello-world` image 的直接前后对照 evidence。

### ROLLBACK 触发点

- 若窗口内存在 host-side write，且该动作导致 gateway / broker 健康异常。
- 若窗口内存在 host-side write，且变更后状态无法回到窗口前已记录的可接受健康基线。
- 若 operator 无法清楚说明回滚只覆盖本窗口内的最小变更对象。

说明：
- rollback 只应覆盖本窗口引入的最小变更对象。
- rollback 说明不得扩展成 proxy execution rollback，也不得写成 Phase 3 rollback。
- 若无 host-side write，本窗口更适合写成 `HARD_STOP / stop-and-syncback`，而不是强行进入 rollback 叙事。

## 9. 窗口后文档 syncback 要点

- 明确记录本窗口是否只处理了 `hello-world` image prerequisite。
- 明确记录本窗口是否仍然没有启动 temporary restricted proxy。
- 明确记录本窗口是否仍然没有创建 proxy audit jsonl。
- 明确记录本窗口是否仍然没有验证 proxy execution。
- 明确记录 gateway / broker 在窗口结束时的状态。
- 明确记录是否发生 host-side write，以及若发生，对应的 snapshot / Vault sync evidence 是什么。
- 若成功，只能写成“`hello-world` image prerequisite 已补齐，可作为后续 temporary restricted proxy feasibility execution 的进入条件之一”。
- 若失败或 `HARD_STOP`，必须继续写成“Phase 3 仍为 NO-GO”，并指出下一次 repo-side 需要补哪一块资料或前置条件。

## 10. 语气约束

- 本文件始终保持 operator-facing draft 语气。
- 本文件不是可直接无审查执行的 runbook。
- 本文件不得把 candidate、helper、proxy、endpoint 写成长期终态。
- 本文件不得把 prerequisite establishment 与 Phase 3 implementation 混写。
