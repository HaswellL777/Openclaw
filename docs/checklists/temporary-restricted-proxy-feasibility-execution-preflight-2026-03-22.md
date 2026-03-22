# Temporary Restricted Proxy Feasibility Execution Preflight Checklist

> 日期：2026-03-22
> 文档类型：operator-facing preflight checklist draft
> 当前状态：**draft / 仅用于进入评审与执行前门禁，不构成已批准直接执行 runbook**
> 父切片：`docker-prerequisite-establishment-for-phase3`
> baseline：OpenClaw `2026.3.13`
> 直接前置证据：`docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md`；`docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md`；`docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md`
> 配套 operator runbook：`docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md`
> 文档性质：**这是 temporary restricted proxy feasibility execution 的执行前门禁清单，不是 execution record，不是 operator runbook，不是 Phase 3 implementation completion record**

---

## 使用说明

- 本清单只服务于下一次 `temporary restricted proxy feasibility execution` 的进入评审与 operator preflight。
- 本窗口只是 feasibility execution，不等于 `Phase 3 = GO`，不等于 implementation completion，也不等于 `phase3-docker-sandbox-foundation` 已放行。
- 本清单中的命令只能写成检查项或建议命令骨架，不能视为已批准的直接执行步骤。
- 进入任何 live-side readonly evidence / operator preflight 之前，必须先完成 current-run artifact pre-generation 与 alignment precheck；不得再把 previous-run baseline 当作 current-run 已就绪的替代物。
- `2026-03-22` 的 hard-stop lesson 已升级为硬门禁：只有 current-run artifact alignment PASS 后，才允许进入 live-side pre-snapshot。
- 如需一次性回收 execution 前 fresh evidence，配套只读取证包见：`docs/checklists/temporary-restricted-proxy-feasibility-execution-readonly-evidence-pack-2026-03-22.md`。
- 每一项都应由 operator 在执行前标记 `PASS / FAIL / N/A`，并补充证据位置或人工备注；任一硬门禁未满足时，不得进入 execution。
- 成功判据、失败分类、evidence points、stop conditions 必须在 execution 开始前写清楚；若仍存在模糊项，应停在 repo-side 审查层。

## 1. 文档基线确认

| 检查项 | 通过标准 | 建议命令骨架 / 核对方式 | 结论备注 |
|------|------|------|------|
| 当前 direct next window 已写为进入评审 | 文档一致写明当前 direct next 是返回 temporary restricted proxy feasibility execution 的进入评审 | `sed -n '<start>,<end>p' docs/current-boundary.md` |  |
| Phase 3 仍为 NO-GO | 边界与设计文档均未把当前状态写成 GO | `sed -n '<start>,<end>p' docs/current-boundary.md`；`sed -n '<start>,<end>p' docs/design-v3.md` |  |
| 本窗口性质无漂移 | 文档明确写成 feasibility execution，不是 implementation，不是 establishment completion | 人工核对本清单头部、planning 文档与 records 文档 |  |
| 权威事实源未被替换 | `/etc/openclaw/openclaw.json` 仍被表述为唯一 system gateway 生效配置源 | `sed -n '<start>,<end>p' docs/design-v3.md`；`sed -n '<start>,<end>p' docs/host-sop.md` |  |

## 2. 当前 blocker 解除确认

| 检查项 | 通过标准 | 建议命令骨架 / 核对方式 | 结论备注 |
|------|------|------|------|
| `2026-03-21` 唯一 hard-stop reason 已被准确识别 | 仍只接受 `hello-world image missing` 作为上次唯一 blocker | `sed -n '<start>,<end>p' docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md` |  |
| `hello-world` prerequisite 已补齐 | remediation record 明确写回 `hello-world image prerequisite established` | `sed -n '<start>,<end>p' docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md` |  |
| blocker 解除没有被误写成 execution 已开始 | remediation record 仍明确写回 `proxy 未启动`、`audit jsonl 未创建`、`proxy execution 未验证` | `sed -n '<start>,<end>p' docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md` |  |
| blocker 解除没有越界 | remediation record 仍明确写回未修改 `/etc/openclaw/openclaw.json`、未修改 `openclaw.live.json`、未变更 `openclaw` 用户组归属 | `sed -n '<start>,<end>p' docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md` |  |

## 3. git / repo 基线确认

| 检查项 | 通过标准 | 建议命令骨架 / 核对方式 | 结论备注 |
|------|------|------|------|
| 当前分支正确 | 分支仍为 `feat/phase1b-workspace-foundation` | `git rev-parse --abbrev-ref HEAD` |  |
| 最近已推送基线未漂移 | 最近提交链顶部仍包含 `a58567c` 作为已知基线 | `git log --oneline -n 5` |  |
| 本轮 repo-side 补文可审计 | 本清单已纳入 git 跟踪，且除允许范围外无额外改动 | `git status --short` |  |
| 本轮未把 local draft 纳入执行包 | 那两个未跟踪 local draft 仍保持未跟踪，且不纳入本窗口事实源 | `git status --short` |  |

## 4. current-run artifact preparation gate

| 检查项 | 通过标准 | 建议命令骨架 / 核对方式 | 结论备注 |
|------|------|------|------|
| `2026-03-22` 新 hard-stop 已被准确识别 | 仍只接受 `current-run artifact alignment not established` 作为本次 repair 的直接根因 | `sed -n '<start>,<end>p' docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md` |  |
| current-run freeze card 已生成 | current-run `run_id`、endpoint、candidate path、evidence sink 已冻结落盘 | `scripts/prepare-temporary-restricted-proxy-feasibility-artifacts.sh --run-id <run-id> --rc-base <rc-base>`；`sed -n '1,160p' <rc-base>/freeze-card.env` |  |
| current-run helper 已生成 | `docker_restricted_proxy.py` 已存在于 current-run `rc_base` | `ls -l <rc-base>/docker_restricted_proxy.py` |  |
| current-run validate-only candidate 已生成 | current-run validate-only candidate 已存在于 current-run `rc_base` | `ls -l <rc-base>/openclaw.docker-access-feasibility.<run-id>.validate-only.json` |  |
| expected layout 已形成 | current-run `rc_base` 下不再只有 `freeze-card.env`、`evidence/`、`runtime/` 空壳 | `sed -n '1,120p' <rc-base>/expected-artifact-layout.txt`；`find <rc-base> -maxdepth 1 -mindepth 1 | sort` |  |
| alignment precheck 已 PASS | 只读 precheck 明确返回 `current-run artifact alignment established` | `scripts/precheck-temporary-restricted-proxy-artifact-alignment.sh --rc-base <rc-base>` |  |
| previous-run baseline 未被误写成 current-run ready | 文档与预检结果都明确区分 historical baseline 与 current-run prepared artifacts | 人工核对 precheck 输出与 hard-stop record |  |
| live-side pre-snapshot 仍被锁住直到 alignment PASS | 在 current-run artifact alignment PASS 前，不得开始任何 live-side pre-snapshot | 人工核对 precheck 输出；对照 `2026-03-22` hard-stop record |  |

## 5. 快照 / Vault / 回滚前提

| 检查项 | 通过标准 | 建议命令骨架 / 核对方式 | 结论备注 |
|------|------|------|------|
| operator 已接受 host-affecting change 纪律 | 执行前明确采用 `pre snapshot -> Vault sync -> change -> health validation -> post snapshot -> Vault sync` | 人工逐条宣读并记录 |  |
| pre-snapshot gate 顺序正确 | 只有在 current-run alignment PASS 且 readonly evidence green 后，才允许进入 live-side pre-snapshot | 对照配套 runbook 与 readonly evidence pack 逐条核对 |  |
| 快照边界被正确理解 | 明确 root snapshot 不覆盖 `/var/lib/openclaw` 运行态子卷 | `sed -n '<start>,<end>p' docs/design-v3.md`；`sed -n '<start>,<end>p' docs/host-sop.md` |  |
| 回滚边界先于 execution 写清 | 若 execution 失败，回滚对象只限实验临时对象，不扩展为 Phase 3 rollback | `sed -n '<start>,<end>p' docs/planning/docker-access-model-feasibility-experiment-for-openclaw-2026.3.13-2026-03-21.md` |  |
| 未形成保护包不得开窗 | 若快照、Vault、健康校验路径未先确认，则本窗口不得开始 | 人工门禁判断 |  |

## 6. 当前运行态确认

| 检查项 | 通过标准 | 建议命令骨架 / 核对方式 | 结论备注 |
|------|------|------|------|
| `docker.service` 状态可复核 | execution 开始前可再次确认 `active` | `systemctl status docker.service --no-pager` |  |
| `docker.socket` 状态可复核 | execution 开始前可再次确认 `active` | `systemctl status docker.socket --no-pager` |  |
| gateway 状态可复核 | execution 开始前 gateway 保持健康 | `systemctl status openclaw-gateway.service --no-pager` |  |
| broker 状态可复核 | execution 开始前 broker 保持健康 | `systemctl status openclaw-broker.service --no-pager` |  |
| `hello-world` image 直接存在证据可复核 | execution 开始前仍可证明 `hello-world` 已存在 | `sudo docker image inspect hello-world`；`sudo docker image ls hello-world` |  |
| 当前权限边界未漂移 | `openclaw` 仍不在 `docker` 组，且不是通过长期放权直接访问 Docker daemon | `id openclaw`；`getent group docker`；只读核对既有 evidence |  |

## 7. candidate execution path 确认

| 检查项 | 通过标准 | 建议命令骨架 / 核对方式 | 结论备注 |
|------|------|------|------|
| candidate 仍是唯一存活候选 | 当前仅讨论“受限 proxy + 显式 endpoint”，不引入新候选混跑 | `sed -n '<start>,<end>p' docs/planning/docker-access-model-feasibility-experiment-for-openclaw-2026.3.13-2026-03-21.md` |  |
| validate-only candidate 已形成 current-run 准备物 | current-run candidate 已生成并通过 alignment precheck，不再只停留在上次 bundle 的 historical baseline | 只读核对 current-run freeze card / manifest / precheck 输出 |  |
| helper payload 已形成 current-run 准备物 | current-run helper 已生成并通过 alignment precheck，不再只停留在上次 bundle 的 historical baseline | 只读核对 current-run freeze card / manifest / precheck 输出 |  |
| success criteria 已写清 | 最低通过标准必须是 OpenClaw 发起并完成最小 sandbox lifecycle 闭环 | 只读核对 feasibility definition；人工签字确认 |  |
| evidence points 已写清 | preflight、proxy start、audit jsonl、backend connect、create/start、task end、cleanup、post-check 均有证据位 | 人工逐条确认并登记预期证据路径 |  |
| stop conditions 已写清 | 出现权限漂移、配置越界、运行态异常、闭环失败即停 | 人工逐条确认并登记 |  |

## 8. 本窗口允许事项

- 只验证 OpenClaw `2026.3.13` 在“受限 proxy + 显式 endpoint”下，能否完成最小 sandbox lifecycle 闭环。
- 允许先做 repo-side current-run helper / candidate 预生成与 alignment precheck，并把其结果作为 execution 前硬门禁。
- 只收集与 feasibility execution 直接相关的最小 evidence。
- 只允许围绕以下节点做验证与收口：
  - preflight baseline
  - proxy / endpoint 可达性
  - OpenClaw 对 candidate `sandbox.docker` 配置的接受情况
  - lifecycle 的 `create / start / run / cleanup` 最小闭环
  - post-check 与结果归类
- 允许把结果收口为通过或失败分类，但即使通过，也只能写成“当前候选模型具备进入后续 establishment 细化的证据基础”，不能写成 `Phase 3 = GO`。

## 9. 本窗口禁止事项

- 不触碰 `/etc/openclaw/openclaw.json`。
- 不触碰 `openclaw.live.json`。
- 不变更 `openclaw` 用户组归属。
- 不把 `openclaw` 加入 `docker` 组。
- 不引入 rootless Docker。
- 不修改 systemd 单元终态设计。
- 不把 task-runner / image / network / workspace 的正式实施混入本窗口。
- 不把 feasibility execution 写成 implementation completion。
- 不把 proxy + endpoint 写成冻结终态。
- 不在证据不足时把结果写成“基本可行”或“等同放行”。
- 不把 previous-run helper / candidate baseline 误写成 current-run artifact already prepared。

## 10. 必须回收的最小 evidence

### 10.1 execution 前最小基线 evidence

| evidence 点 | 最低要求 | 建议命令骨架 / 核对方式 | 备注 |
|------|------|------|------|
| 工作树与提交基线 | 本轮文档变更可审计；未混入无关文件 | `git status --short`；`git log --oneline -n 5` |  |
| current-run artifact pack | current-run freeze card、helper、validate-only candidate、manifest、expected layout 已落盘 | `scripts/prepare-temporary-restricted-proxy-feasibility-artifacts.sh --run-id <run-id> --rc-base <rc-base>`；`sed -n '1,220p' <rc-base>/current-run-artifact-manifest.json` |  |
| current-run alignment precheck | precheck 明确返回 `PREFLIGHT PASSED`，并作为进入 live-side pre-snapshot 的锁释放条件 | `scripts/precheck-temporary-restricted-proxy-artifact-alignment.sh --rc-base <rc-base>` |  |
| 服务健康 | `docker.service`、`docker.socket`、gateway、broker 的 pre-check | `systemctl status <unit> --no-pager` |  |
| `hello-world` prerequisite | 直接存在证据可复核 | `sudo docker image inspect hello-world`；`sudo docker image ls hello-world` |  |
| 权限边界 | `openclaw` 不在 `docker` 组，未改长期权限模型 | `id openclaw`；`getent group docker` |  |

### 10.2 execution 中最小 evidence

> **Blocked-State Note（2026-03-22）**
>
> 当前 `temporary restricted proxy feasibility execution` 仍停在：
>
> - `BLOCKED_BEFORE_HOST_SIDE_CHANGE`
> - `GATE0_3=GREEN`
> - `PREPARED_STATE_PASS=YES`
> - `READONLY_EVIDENCE_GREEN=YES`
> - `APPROVED_PROXY_EXEC_CMD=NO`
>
> 因此，`10.2 execution 中最小 evidence` 当前只定义 **必须回收的证据类型**，**不构成 operator 可直接执行的命令块**。
>
> 在单独的 `Approved Direct Proxy Execution Block` 被写入并批准前：
>
> - 不得现场拼接 proxy start / lifecycle / cleanup 命令；
> - 不得把 `<proxy-unit>`、`<audit-jsonl-path>` 或“保留相关输出”类占位语句，当作已批准的执行步骤；
> - 不得把 `candidate config accepted`、`proxy actually started`、`backend reachable via explicit endpoint`、`lifecycle create / start / run / cleanup` 填写为已可执行；
> - 只允许写回：当前 execution 仍 blocked by missing approved operator block。

### 10.2 execution 中最小 evidence（blocked-state 补充）

在 `Approved Direct Proxy Execution Block` 缺失的情况下，下表各项只保留为 **目标 evidence points**，不得被解释为已存在 operator 命令。

| evidence 点 | 当前可写结论 | 当前仍缺的批准项 |
|------|------|------|
| candidate config accepted | 尚无已批准 operator 路径 | candidate acceptance operator 路径 |
| proxy actually started | 尚无已批准 start anchor | proxy 启动锚点；proxy unit / process identity |
| audit jsonl actually created | audit 路径已冻结，但创建动作未获准执行 | approved start block；evidence-command binding |
| backend reachable via explicit endpoint | explicit endpoint 已冻结在 freeze card / helper / candidate 中，但运行态接入路径未获准执行 | candidate acceptance path；lifecycle trigger |
| lifecycle create / start / run / cleanup | 只定义了目标闭环，未定义已批准 trigger / teardown | lifecycle trigger；teardown；evidence-command binding |

在上述批准项补齐前，本节出口只能写成：

- `blocked by missing approved operator block`

| evidence 点 | 最低要求 | 建议命令骨架 / 核对方式 | 备注 |
|------|------|------|------|
| candidate config accepted | OpenClaw 接受相关 `sandbox.docker` 配置，而非 schema/config 级拒绝 | 保留 validate / load / start 相关输出 |  |
| proxy actually started | 有 socket、unit/进程、journal 等直接证据 | `systemctl status <proxy-unit> --no-pager`；`journalctl -u <proxy-unit> --no-pager`；相关文件存在性检查 |  |
| audit jsonl actually created | audit jsonl 存在且非空 | `test -s <audit-jsonl-path>`；只读查看头尾 |  |
| backend reachable via explicit endpoint | 证据能表明 OpenClaw 走的是显式 endpoint，而非默认本地 socket 假设 | 保留配置快照与运行输出 |  |
| lifecycle create / start / run / cleanup | 至少一次最小任务执行到可判定结束，并完成清理 | 保留 gateway / backend / proxy 相关日志与结果摘要 |  |

### 10.3 execution 后最小收口 evidence

| evidence 点 | 最低要求 | 建议命令骨架 / 核对方式 | 备注 |
|------|------|------|------|
| post-check 服务健康 | `docker.service`、`docker.socket`、gateway、broker 仍健康 | `systemctl status <unit> --no-pager` |  |
| 结果归类 | 结果必须明确落入 success 或 failure class | 人工写回结果摘要 |  |
| 边界说明 | 明确写回本窗口只是 feasibility execution，不等于 Phase 3 GO，不等于 implementation completion | 人工写回结果摘要 |  |

### 10.4 本窗口最低成功判据

- current-run helper 与 validate-only candidate 已先在 repo-side 形成准备物，并通过 alignment precheck。
- OpenClaw `2026.3.13` 接受 candidate `sandbox.docker` 配置。
- OpenClaw 通过受限 proxy + 显式 endpoint 发起最小 sandbox lifecycle。
- 至少一次最小任务完成 `create / start / run / cleanup` 闭环。
- execution 前后关键服务保持健康。
- 结果能够以直接证据支撑，而不是仅凭 `docker version`、`docker info`、proxy 健康检查或单独 endpoint 连通性。

## 11. 失败分类

| 分类 | 含义 | 收口要求 |
|------|------|------|
| `config rejected` | OpenClaw 不接受 candidate `sandbox.docker` 配置，或在校验阶段即被拒绝 | 保留配置与校验输出，不得写成 backend 问题 |
| `backend unreachable` | 配置被接受，但显式 endpoint 无法触达受限 proxy | 保留 endpoint、proxy、连通性证据 |
| `lifecycle operation unsupported` | backend 可达，但 `create / start / run / wait` 中关键步骤无法完成 | 保留生命周期关键日志与失败点 |
| `cleanup/teardown unsupported` | 前置步骤成功，但 cleanup / teardown 无法稳定完成 | 保留残留资源与清理失败证据 |
| `current-run artifact alignment failed` | current-run helper / validate-only candidate 缺失或 drift，execution 尚未开始 | 保留 freeze card、manifest、precheck 输出，不得误写成 runtime failure |

## 12. HARD_STOP 条件

- current-run helper / validate-only candidate 尚未先完成 repo-side 预生成。
- current-run alignment precheck 未通过。
- 进入窗口前仍无法再次形成 `hello-world` image 直接存在证据。
- 需要触碰 `/etc/openclaw/openclaw.json` 或 `openclaw.live.json`。
- 需要变更 `openclaw` 用户组归属，或把 `openclaw` 加入 `docker` 组。
- 需要引入 rootless Docker。
- 操作开始滑向 task-runner / image / network / workspace 的正式实施。
- 操作开始滑向 systemd 单元终态设计、secrets handling 或其他未审查系统变更。
- 成功判据、失败分类、evidence points、stop conditions 仍未在 execution 前写清。
- gateway、broker、`docker.service` 或 `docker.socket` 出现非预期健康退化。
- execution 只能证明“配置可读”或“endpoint 可连”，却不能推进最小 lifecycle 闭环。
- 任何结果需要靠解释性推断而非直接证据才能维持“可继续”结论。

---

本清单的出口语义只能是二选一：

- **允许 operator 进入 temporary restricted proxy feasibility execution preflight**
- **维持 `Phase 3 = NO-GO` 并返回 repo-side 收口**
