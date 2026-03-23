# Approved Direct Proxy Execution Block Source Closure

> 日期：2026-03-22
> 文档类型：planning / closure / current direct-next slice
> 当前状态：**active / authoritative repo-side closure doc**
> 父切片：`docker-prerequisite-establishment-for-phase3`
> baseline：OpenClaw `2026.3.13`
> 文档性质：**本文件只收口 `Approved Direct Proxy Execution Block` 的来源条件、批准路径与缺口类型；不是 operator exact command block，不是 live-side runbook，不是 execution record**

---

## 1. 当前 authoritative 状态

当前 blocked-state 必须继续固定为：

- `RESULT=BLOCKED_BEFORE_HOST_SIDE_CHANGE`
- `GATE0_3=GREEN`
- `PREPARED_STATE_PASS=YES`
- `READONLY_EVIDENCE_GREEN=YES`
- `APPROVED_PROXY_EXEC_CMD=NO`

这意味着：

- temporary restricted proxy feasibility execution 仍未进入 host-side change；
- Gate 0-3 green 只证明 repo-side prepare / precheck 与 readonly evidence 已经收口；
- 当前 direct next work 不是 execution，也不是 implementation；
- 当前 direct next work 只剩 repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐；
- 在单独批准的 exact operator block 形成前，仍不得进入 live-side pre-snapshot。

## 2. 目的与非目标

本文件只回答三个问题：

1. future `Approved Direct Proxy Execution Block` 现在分别依赖哪些已有来源文档；
2. 这些来源是否已经足以支撑 future operator approval；
3. 若不足，还缺什么类型的 repo-side 收口，而不是去现场发明命令。

本文件不做以下事项：

- 不生成 proxy start / lifecycle / teardown exact operator command block；
- 不修改 `/etc/openclaw/openclaw.json`；
- 不修改 `openclaw.live.json`；
- 不修改 `openclaw` 用户组归属；
- 不启动第二个 gateway；
- 不把 feasibility 写成 implementation；
- 不替代 future operator approval。

## 3. 来源层级

future `Approved Direct Proxy Execution Block` 的 repo-side 来源只能来自以下四层的组合，不允许单独抽取某一条命令骨架就视为已批准来源：

### 3.1 authority 层

- `docs/current-boundary.md`
- `docs/host-sop.md`
- `docs/design-v3.md`

作用：

- 固定 blocked-state；
- 固定宿主机硬边界；
- 固定 `/etc/openclaw/openclaw.json` 是唯一 system gateway 生效配置源；
- 固定 snapshot / Vault discipline；
- 固定不得引入第二个 gateway、不得长期放大 Docker 权限边界。

### 3.2 planning / closure 层

- `docs/planning/docker-prerequisite-establishment-for-phase3-2026-03-19.md`
- `docs/planning/docker-access-model-feasibility-experiment-for-openclaw-2026.3.13-2026-03-21.md`
- `docs/planning/approved-direct-proxy-execution-block-source-closure-2026-03-22.md`

作用：

- 固定 parent slice 与 current direct-next slice；
- 固定 feasibility 问题定义；
- 固定 future approval 需要的 closure structure。

### 3.3 repo-side preparation / operator-facing draft 层

- `docs/execution-pack-temporary-restricted-proxy-feasibility-artifact-preparation-2026-03-22.md`
- `docs/checklists/temporary-restricted-proxy-feasibility-execution-preflight-2026-03-22.md`
- `docs/checklists/temporary-restricted-proxy-feasibility-execution-readonly-evidence-pack-2026-03-22.md`
- `docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md`

作用：

- 固定 Gate 0-3 的 prepare / precheck / readonly evidence 语义；
- 保留 future execution 的阶段顺序、evidence points 与 hard-stop matrix；
- 明确这些文档目前都还不是 approved operator block。

### 3.4 evidence 层

- `docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md`
- `docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md`
- `docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md`

作用：

- 固定已发生事实；
- 固定 hello-world blocker 已补齐；
- 固定 proxy 未启动、audit jsonl 未创建；
- 固定 `current-run artifact alignment not established` 的 hard-stop 教训。

## 4. Closure Structure

future operator approval 至少要覆盖以下 8 类。每一类都必须先回答“来源是什么、是否足够、缺口类型是什么”，才能进入 exact block 审阅。

| 类别 | 当前来源文档 | 当前来源是否存在 | 是否足以直接支撑 future operator approval | 当前仍缺的 repo-side 收口类型 |
|------|------|------|------|------|
| 1. proxy 启动锚点 | `docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md`；`docs/execution-pack-temporary-restricted-proxy-feasibility-artifact-preparation-2026-03-22.md`；`docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md` | 有，占位顺序与未启动证据都已存在 | 否 | 需要一个 reviewable 的 start-anchor closure：只定义 anchor 类型、前置 gate、冻结路径与停止点，不生成 exact command text |
| 2. proxy unit / process identity | `docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md` | 有，但仍是 `<proxy-unit>` / process 占位语义 | 否 | 需要一个 identity closure：明确 future approval 将绑定 unit 还是临时 process、其证据锚点是什么、为什么不会落成长期 systemd 终态改造 |
| 3. candidate acceptance operator 路径 | `docs/planning/docker-access-model-feasibility-experiment-for-openclaw-2026.3.13-2026-03-21.md`；`docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md` | 有，已知目标是“accepted / rejected”而非 implementation | 否 | 需要一个 acceptance-path closure：只定义 acceptance 结果应由哪类 operator path 触发与回收，不发明命令 |
| 4. 在不改 `/etc/openclaw/openclaw.json`、不改 `openclaw.live.json`、不改组归属、不开第二 gateway 前提下，让 OpenClaw 实际使用 current-run validate-only candidate 的 operator 路径 | `docs/current-boundary.md`；`docs/host-sop.md`；`docs/design-v3.md`；`docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md` | 有，约束边界很清楚 | 否 | 需要一个 candidate-usage-path closure：明确 future approval 要依赖的 route 类型、触发点、回收证据点与禁止越界项 |
| 5. lifecycle trigger | `docs/planning/docker-access-model-feasibility-experiment-for-openclaw-2026.3.13-2026-03-21.md`；`docs/checklists/temporary-restricted-proxy-feasibility-execution-preflight-2026-03-22.md`；`docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md` | 有，目标闭环与 failure classes 已存在 | 否 | 需要一个 lifecycle-trigger closure：把 create / start / run / cleanup 目标 evidence points 与 future trigger family 对齐 |
| 6. teardown | `docs/planning/docker-access-model-feasibility-experiment-for-openclaw-2026.3.13-2026-03-21.md`；`docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md` | 有，cleanup / teardown unsupported 已被定义为 failure class | 否 | 需要一个 teardown closure：明确 future approval 必须自带 cleanup / post-check / failure-stop binding |
| 7. command-evidence binding | `docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md`；`docs/checklists/temporary-restricted-proxy-feasibility-execution-preflight-2026-03-22.md`；`docs/checklists/temporary-restricted-proxy-feasibility-execution-readonly-evidence-pack-2026-03-22.md` | 有，evidence points 很多，但还是散的 | 否 | 需要一个 command-to-evidence matrix closure：把 future approved block 的每一步绑定到直接 evidence，而不是解释性推断 |
| 8. hard boundary / forbidden actions | `docs/current-boundary.md`；`docs/host-sop.md`；`docs/design-v3.md`；`docs/checklists/temporary-restricted-proxy-feasibility-execution-preflight-2026-03-22.md` | 有，且 authority 已经很强 | 部分足够 | 不需要发明新限制；只需要把现有禁止项原样 carry forward 到 future approved block，并明确任何偏离都应回到 repo-side 审阅 |

## 5. Eight Categories In Detail

### 5.1 proxy 启动锚点

当前已有来源：

- runbook 已定义 change phase 会出现 `start temporary restricted proxy`；
- `2026-03-21` 与 `2026-03-22` records 都明确了 proxy 未启动时的直接证据；
- repo-side artifact pack 已冻结 helper、endpoint、candidate 与 audit path。

当前不足：

- 还没有一个被审阅的“start anchor 类型”收口；
- 还没有一个可供批准的“从 Gate 0-3 进入 start anchor 前还要再检查什么”单点落点；
- 还没有把 start anchor 与 stop-before-start 条件做成同一闭环。

缺的不是命令文本，而是：

- start-anchor source note；
- start 前置 gate summary；
- start anchor 对应的 evidence expectation。

### 5.2 proxy unit / process identity

当前已有来源：

- runbook 要求 future evidence 包含 socket / unit / journal；
- records 已证明过去窗口里 unit inactive、journal empty 可以支撑 `proxy not started`。

当前不足：

- 还没有明确 future approved block 到底绑定哪一种 identity 语义；
- 还没有明确该 identity 为什么不会被误写成长期 systemd 终态改造；
- 还没有一个专门说明 identity 与 evidence 之间一一对应关系的 closure。

缺的不是 unit 名称本身，而是：

- identity class closure；
- identity-to-evidence note；
- identity 不越界声明。

### 5.3 candidate acceptance operator 路径

当前已有来源：

- feasibility definition 明确 success/failure 判据里必须包含 candidate config accepted / rejected；
- runbook 已把它列为 execution evidence；
- preflight checklist 已把它列为 future target evidence point。

当前不足：

- 还没有一个可批准的 acceptance-path source；
- 还没有说明 acceptance 结果应该由什么类型的 operator path 回收；
- 还没有将 acceptance 结果与其他 runtime evidence 绑定。

缺的不是“现场试一条命令”，而是：

- acceptance-path source closure；
- acceptance result capture note；
- acceptance 与 failure class 的绑定说明。

### 5.4 current-run validate-only candidate 的实际使用路径

当前已有来源：

- authority 层已把所有硬边界写得足够清楚：
  - 不改 `/etc/openclaw/openclaw.json`
  - 不改 `openclaw.live.json`
  - 不改组归属
  - 不开第二 gateway
- runbook 已把这条路径列为当前仍未批准项。

当前不足：

- 还没有一个 repo-side 文档把“在这些硬边界内，future approval 需要审什么 route 类型”收口成单独说明；
- 还没有把 candidate usage route 与 acceptance、endpoint、lifecycle 串成一条 approval path。

缺的不是 candidate 文件本身，而是：

- candidate-usage route closure；
- route constraints note；
- route-to-evidence expectations。

### 5.5 lifecycle trigger

当前已有来源：

- feasibility definition 已把最低通过证据与 failure classes 写清；
- runbook 已写出 `create / start / run / cleanup` 最小闭环目标；
- preflight checklist 已把 lifecycle evidence points 列出来。

当前不足：

- 还没有 future approved block 可引用的 trigger family；
- 还没有把 lifecycle 的每一段与 start / acceptance / teardown 串成闭环；
- 还没有 future approval 级别的 stop conditions carry-forward matrix。

缺的不是更多试验描述，而是：

- lifecycle-trigger source closure；
- lifecycle stage matrix；
- lifecycle stop-binding note。

### 5.6 teardown

当前已有来源：

- feasibility definition 把 `cleanup/teardown unsupported` 固定为 failure class；
- runbook 已要求 hard stop 后做最小必要 cleanup / teardown、post-check 与 syncback。

当前不足：

- 还没有专门的 teardown source closure；
- 还没有把 failure stop、cleanup completion、post-check 四项服务健康写成一个 approval bundle；
- 还没有明确 teardown 的 evidence capture family。

缺的不是 cleanup 命令，而是：

- teardown closure note；
- failure-stop to cleanup binding；
- teardown post-check matrix。

### 5.7 command-evidence binding

当前已有来源：

- runbook、preflight、readonly evidence pack 已经定义了很多 evidence points；
- hard-stop records 也证明了直接证据比解释性推断更重要。

当前不足：

- 这些 evidence points 仍分散在多个文档里；
- 还没有 future approved block 的一对一绑定矩阵；
- 还没有明确哪些 evidence 必须由 direct artifact 支撑，哪些只能是辅助说明。

缺的不是更多 evidence points，而是：

- step-to-evidence matrix；
- direct evidence priority rule；
- failure evidence fallback rule。

### 5.8 hard boundary / forbidden actions

当前已有来源：

- authority 层已经非常清楚：
  - 不改 `/etc/openclaw/openclaw.json`
  - 不改 `openclaw.live.json`
  - 不改组归属
  - 不开第二 gateway
  - 不把 feasibility 写成 implementation
  - 不现场拼接 proxy start / lifecycle / teardown exact block
- preflight checklist 也已保留大量禁止项。

当前不足：

- 这些禁止项还没有被明确定义为 future approved block 的强制前置页；
- operator-facing draft 之间对 direct-next slice 的口径此前有漂移；
- 还需要一个统一的“任何越界都回 repo-side 审阅”的 carry-forward 说明。

因此本类当前缺的不是新规则，而是：

- forbidden-actions carry-forward page；
- approval-block front matter 约束；
- drift-back-to-repo rule。

## 6. 当前已足够与仍不足够的结论

### 6.1 已足够的部分

以下内容已经足够作为 future approval 的 authority basis，不需要再发明新事实：

- blocked-state 五元组；
- hello-world blocker 已补齐；
- Gate 0-3 已绿但不释放 pre-snapshot；
- proxy 未启动、audit jsonl 未创建；
- current-run artifact alignment hard-stop lesson；
- `/etc/openclaw/openclaw.json`、`openclaw.live.json`、组归属、第二 gateway 等硬边界。

### 6.2 仍不足够的部分

以下内容仍不足以直接支撑 future operator approval：

- 从 Gate 0-3 进入 proxy start 的 start-anchor source；
- proxy identity 的收口；
- candidate acceptance 与 actual candidate usage 的 route 收口；
- lifecycle trigger 与 teardown 的 source closure；
- exact step 与 direct evidence 的一对一绑定矩阵。

## 7. Approval Path

future approval 只能按以下 repo-side 路径形成，不得现场拼接：

1. 以本文件作为 source-closure 总表，确认 8 类来源与缺口类型；
2. 在 repo-side 继续补齐缺的 closure artifacts，但这些 artifacts 仍只应描述 source / route / evidence binding / forbidden actions，不生成 operator exact command block；
3. 仅当 8 类都具备 reviewable source closure 后，才允许生成单独审阅的 `Approved Direct Proxy Execution Block` 草案；
4. 该草案必须由 operator / reviewer 单独批准，不能从 runbook、checklist 或现场 shell 拼接自动推导；
5. 只有批准结果被明确写回 active docs 后，future blocked-state 才可能从 `APPROVED_PROXY_EXEC_CMD=NO` 变成 `YES`。

## 8. Approval Result Landing Points

future 如果真的完成批准，repo-side 落点至少要同步到：

- `docs/current-boundary.md`
- `docs/map.md`
- `docs/planning/README.md`
- `docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md`
- `docs/checklists/temporary-restricted-proxy-feasibility-execution-preflight-2026-03-22.md`
- `docs/checklists/temporary-restricted-proxy-feasibility-execution-readonly-evidence-pack-2026-03-22.md`

在批准真正发生前，上述文档都必须继续写为：

- current direct next = repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐；
- current state = `BLOCKED_BEFORE_HOST_SIDE_CHANGE`；
- current direct next 不是 execution；
- operator 不能现场生成 exact block。

## 9. 当前结论

截至 `2026-03-22`，本 repo-side closure 的结论只能是：

- authority / planning / map 层已经足以证明 blocked-state 与 hard boundary；
- Gate 0-3 green 已经足以证明 repo-side prepared state 与 readonly evidence green；
- 但 future `Approved Direct Proxy Execution Block` 的 8 类来源还没有被收口为可批准的 source bundle；
- 因此当前仍然是 `BLOCKED_BEFORE_HOST_SIDE_CHANGE`；
- 当前 direct next work 仍然只是 repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐；
- 任何 live-side execution、pre-snapshot、proxy start、candidate usage、lifecycle trigger、teardown exact block 仍只能留给 future operator approval，而不能由本轮 repo-side executor 生成。
