# Phase 3 First Live Pilot Execution Seam Prep Pack

> 日期：2026-03-23
> 文档类型：planning / merged prep pack / direct-next closure
> 当前状态：**active / authoritative merged prep pack before the first live pilot**
> 父切片：`docker-prerequisite-establishment-for-phase3`
> baseline：OpenClaw `2026.3.13`
> 文档性质：**本文件一次性收住 operator-side / future execution seam 进入 first live pilot 前的最小准备项；不是 exact operator command block，不是 live-side runbook，不是 execution record**

---

## 1. 当前 phase 定位

截至 `2026-03-23`，当前状态应固定为：

- `first-live-pilot candidate pack` 已 ready；
- repo-side 控制面 dry-run、执行面 scaffold、reviewed-task handoff glue 已 assembled；
- remaining blocker 已收缩为 `future execution seam / operator input`；
- 当前 repo-side 工作应视为**已收口**；
- 下一阶段不是继续扩 repo-side 资产，而是处理 operator-side / future execution seam，直到 future first live pilot 的 exact input surface 被补齐。

这也意味着：

- 当前不应回到 proxy feasibility blocked line 继续做旧文档 source-closure 空转；
- 当前也不应把 Gate 0-3 green 写成已可进入 live-side pre-snapshot；
- 当前仍保持 `Phase 3 = NO-GO`，直到 future execution seam 的 operator-side exact input 被单独明确并审阅。
- repo-side 文档同步本身不需要 host-side 快照；只有未来 live-side 动作才进入 `快照 -> 变更 -> 健康检查 -> post 快照 -> Vault 入库`。

## 2. 唯一最小 First Live Pilot Case

本轮只选择一个最小 case：

- **`task-intake-host-affecting`**

其 repo-side anchor 固定为：

- `fixtures/control-plane-replay/valid-host-affecting/operator-review-bundle.json`
- `fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/handoff-manifest.json`
- `fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/exec-plan.json`
- `fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/workspace-layout.json`

它是唯一最小 case，原因只有四条：

1. 它是当前候选包里**最小且真实消耗 remaining blocker** 的路径。`readonly` 与 `broker-submission-candidate` 都还能停在 repo-side dry-run，不需要 operator-side exact input，因此不能证明 future execution seam 已补齐。
2. 它已经具备 reviewed bundle、handoff manifest、workspace layout、exec plan 四个锚点，不需要再扩任何新的 repo-side 资产。
3. 它把范围压到**单一 reviewed task / 单一 approval path / 单一 future execution seam**，不会把第一次 live pilot 扩成多任务或多路径联动。
4. 它仍然停留在 future execution seam 准备面，不要求本轮做 broker 调用、真实 Docker run、live publish 或 exact operator commands 发明。

因此，first live pilot 的最小定义不是“再找更小的 readonly case”，而是：

- 用现有 `task-intake-host-affecting` 这一条 reviewed host-affecting anchor，补齐 operator-side / future execution seam exact input；
- 在 exact input 之外，不新增 repo-side 资产。

## 3. Operator-Side 必须明确的 Exact Input 列表

下面只列真正必须项，不列优化项。

### 3.1 Pilot source anchor

operator 必须明确：

- 本次 first live pilot 只绑定哪一个 `candidate_id`
- 只绑定哪一个 `task_id`
- 只绑定哪一个 reviewed bundle
- 只绑定哪一个 handoff manifest

最小要求是把 pilot source 冻结到同一套 artifact anchor，而不是口头描述“走 host-affecting 那条路”。

### 3.2 Future execution seam identity

operator 必须明确：

- 本次 pilot 实际绑定的是哪一种 execution seam identity
- 该 identity 的 start / running / stop / cleanup 证据分别从哪里读取

这里必须明确的是 identity family 与 evidence anchor，不是 exact shell command text。

### 3.3 Candidate usage route under hard boundaries

operator 必须明确：

- 在**不修改** `/etc/openclaw/openclaw.json`
- **不修改** `openclaw.live.json`
- **不修改** `openclaw` 用户组归属
- **不开第二个 gateway**

的前提下，future first live pilot 将通过什么 route 让 OpenClaw 实际消费 current-run validate-only candidate。

这项如果不明确，future execution seam 就仍然只是 repo-side 设想。

### 3.4 Acceptance result capture

operator 必须明确：

- 什么信号算 `accepted`
- 什么信号算 `rejected`
- 这些结果分别从哪些 direct artifacts 读取

这里要冻结的是 acceptance result 的 direct evidence source，而不是在执行后再解释。

### 3.5 Post-change health check surface

operator 必须明确：

- change 之后要看哪一组健康检查
- 这些健康检查的 pass / fail 以哪些 direct artifacts 为准

没有这一项，就无法满足“变更后先健康检查，再决定 post snapshot / Vault”的纪律。

### 3.6 Snapshot / post-snapshot / Vault binding

operator 必须明确：

- 本次唯一 live pilot change window 的 pre-snapshot 标识
- post-snapshot 标识
- Vault 入库对象与完成判据

这三项不是优化项，而是 host-affecting pilot 的最小审计边界。

### 3.7 Cleanup / stop completion evidence

operator 必须明确：

- 本次 future execution seam 的 cleanup / stop 完成后，看哪些 direct artifacts 判定“确已收尾”

没有 cleanup completion evidence，first live pilot 就不是可审计的最小闭环。

### 3.8 Operator Exact-Input Ledger（待绑定，不得包装成 ready-to-run）

下列项当前只能写成“待 operator-side exact input 绑定”，不能包装成已就绪 live input：

| 类型 | 当前 repo-side 锚点 | 当前状态 |
|------|---------------------|----------|
| execution seam identity | 第 3.2 节；`task-intake-host-affecting` anchor | **未绑定 exact identity**；目前只有 case anchor，没有 live-side start / running / stop / cleanup evidence source |
| candidate usage route under hard boundaries | 第 3.3 节；`task-intake-host-affecting` anchor | **未绑定 exact route**；当前只冻结“不改 `/etc/openclaw/openclaw.json` / `openclaw.live.json` / `openclaw` 组归属 / 不开第二个 gateway”的硬边界 |
| candidate artifact exact binding | `fixtures/control-plane-replay/valid-host-affecting/operator-review-bundle.json` 中 `broker_requests[0].broker_request.inputs.candidate_path`、`broker_requests[0].broker_request.inputs.expected_sha256`、`broker_requests[2].broker_request.inputs.candidate_path`、`broker_requests[2].broker_request.inputs.expected_sha256` | **仍是 placeholder 性质绑定**；只能视为 future reviewed candidate 的逻辑占位，不得包装成 ready-to-run exact input |
| acceptance result capture | 第 3.4 节；现有 fixture 未冻结 acceptance artifact source | **未绑定 exact evidence source**；accepted / rejected 的 direct artifact 仍待 operator-side 明确 |
| post-change health check evidence | 第 3.5 节；现有 fixture 未冻结 health artifact source | **未绑定 exact evidence source**；health pass / fail 仍待 operator-side 明确 |
| pre / post snapshot binding | `fixtures/control-plane-replay/valid-host-affecting/operator-review-bundle.json` 中 `broker_requests[1].broker_request.inputs.label`、`broker_requests[4].broker_request.inputs.label` | **仅是逻辑标签，不是已批准的 live-side exact input**；实际 pre/post snapshot 标识仍待 operator-side 绑定 |
| Vault completion criteria | `fixtures/control-plane-replay/valid-host-affecting/operator-review-bundle.json` 中 `broker_requests[5].broker_request.inputs.snapshot_name` | **仅是逻辑占位，不是完成判据**；Vault 入库对象、完成信号与证据仍待 operator-side 绑定 |
| cleanup completion evidence | 第 3.7 节；现有 fixture 未冻结 cleanup artifact source | **未绑定 exact evidence source**；cleanup / stop 完成判据仍待 operator-side 明确 |

## 4. 进入第一次 Live Pilot 前的最小门禁顺序

first live pilot 前的最小门禁顺序应固定为：

1. **Gate 0：repo-side candidate pack green**
   当前候选包、控制面 replay、执行面 scaffold、handoff glue 均以 repo-side artifact 形式冻结。
2. **Gate 1：唯一最小 case frozen**
   只允许 `task-intake-host-affecting` 作为 first live pilot case。
3. **Gate 2：operator-side exact input complete**
   第 3 节列出的 exact input 必须全部明确。
4. **Gate 3：future execution seam reviewable**
   execution seam identity、candidate usage route、acceptance capture、cleanup evidence 均已可审阅，但仍未进入 live-side。
5. **Gate 4：单独决定是否进入 pre-snapshot**
   只有在 Gate 0-3 全部 green 且另行同意进入本次唯一 change window 后，才允许触发 live-side pre-snapshot。
6. **进入 live pilot 后的最小纪律固定为**
   `快照 -> 变更 -> 健康检查 -> post 快照 -> Vault 入库`

必须明确写清：

- **Gate 0-3 green 不等于可进入 pre-snapshot**
- Gate 0-3 只说明 repo-side pack 与 operator-side exact input surface 已收口
- 是否进入 pre-snapshot 仍是后续单独决定，不可被 repo-side green 结果自动释放

## 5. 将被直接带入该 Pilot 的 Repo-Side 资产

当前候选包中会被直接带入 first live pilot 的资产，只保留以下几组：

### 5.1 Candidate pack anchor

- `candidates/phase3/first-live-pilot-candidate/first-live-pilot-candidate-20260323-v1/candidate-summary.json`
- `candidates/phase3/first-live-pilot-candidate/first-live-pilot-candidate-20260323-v1/candidate-manifest.json`
- `candidates/phase3/first-live-pilot-candidate/first-live-pilot-candidate-20260323-v1/readiness-assertions.json`
- `candidates/phase3/first-live-pilot-candidate/first-live-pilot-candidate-20260323-v1/frozen-input-refs.json`

### 5.2 Control-plane host-affecting anchor

- `fixtures/control-plane-replay/valid-host-affecting/operator-review-bundle.json`
- `fixtures/control-plane-replay/valid-host-affecting/request.normalized.json`
- `fixtures/control-plane-replay/valid-host-affecting/intake-report.json`
- `fixtures/control-plane-replay/valid-host-affecting/routing-decision.json`
- `fixtures/control-plane-replay/valid-host-affecting/operator-approval-envelope.json`

### 5.3 Handoff anchor

- `fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/handoff-manifest.json`
- `fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/exec-plan.json`
- `fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/workspace-layout.json`
- `fixtures/task-runner-handoff-pack/valid-requires-approval/tasks/task-intake-host-affecting/inputs/control-plane/`

### 5.4 Execution-plane scaffold

- `workspace-task-runner-template/`
- `task-runner-container/`
- `schemas/task-runner-handoff-manifest.schema.json`
- `schemas/task-runner-exec-plan.schema.json`
- `schemas/task-runner-workspace-layout.schema.json`
- `schemas/task-runner-summary.schema.json`
- `schemas/host-change-request.schema.json`

### 5.5 Validation entrypoints

- `scripts/check-phase3-control-plane-dry-run.sh`
- `scripts/check-task-runner-container-spec.sh`
- `scripts/check-workspace-task-runner-template.sh`
- `scripts/check-task-runner-handoff-pack.sh`
- `scripts/check-first-live-pilot-candidate-pack.sh`

这些资产的作用是：

- 冻结 first live pilot 的 repo-side input surface；
- 给 operator-side / future execution seam 提供唯一最小审阅锚点；
- 避免再为了 first live pilot 继续扩 repo-side。

## 6. 当前仍然不能做什么

当前仍然不能做的事必须继续固定为：

- 不做 live-side publish
- 不做真实 Docker run（本轮）
- 不调用 broker（本轮）
- 不发明 operator exact command block
- 不修改 `/etc/openclaw/openclaw.json`
- 不修改 `openclaw.live.json`
- 不修改 `openclaw` 用户组归属
- 不把 Gate 0-3 green 写成可进入 pre-snapshot

## 7. 收口结论

本轮应明确收口为：

- 当前 repo-side 已收口；
- first-live-pilot candidate pack 已 ready；
- remaining blocker 已只剩 `future execution seam / operator input`；
- 下一阶段不是继续扩 repo-side，而是 operator-side / future execution seam 处理；
- 在下一次实质性修改前，不应再让 Codex 回到 repo-side 继续扩资产。

因此，本文件就是本轮唯一的合并式收口文档：

- 把“唯一最小 case”
- “operator-side 必须明确的 exact input”
- “进入 first live pilot 前的最小 gate 顺序”
- “直接带入 pilot 的 repo-side 资产”
- “当前仍不能做什么”

一次性收在同一刀里。
