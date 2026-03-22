# Temporary Restricted Proxy Feasibility Artifact Preparation Execution Pack Draft

> 日期：2026-03-22
> 文档类型：execution pack / repo-side preparation draft
> 当前状态：**draft / 仅用于 current-run artifact pre-generation + alignment precheck，不构成 live-side execution runbook**
> 适用窗口：`temporary restricted proxy feasibility execution` 进入评审之前的 repo-side repair slice
> 父切片：`docker-prerequisite-establishment-for-phase3`
> 直接前置事实：`2026-03-22` hard-stop record 明确写回唯一原因 = `current-run artifact alignment not established`
> 配套 operator runbook：`docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md`
> 文档性质：**本包只处理 current-run helper / validate-only candidate 的预生成与只读对齐预检；不启动 proxy，不创建 audit jsonl，不继续 deployment，不把 feasibility 写成 implementation**

---

## 1. 目标

本包的唯一目标是把下一次 `temporary restricted proxy feasibility execution` 所需的 current-run 准备物，在 repo-side 先收敛成可审阅、可重复、可二分的最小包：

- current-run `freeze-card.env`
- current-run `docker_restricted_proxy.py`
- current-run validate-only candidate
- current-run manifest / expected layout
- current-run alignment precheck 结果

本包不回答以下问题：

- temporary restricted proxy execution 是否已经开始；
- proxy + endpoint 是否已经冻结为长期终态；
- validate-only candidate 是否已经完成 live validate；
- Phase 3 implementation 是否已经放行。

## 2. 范围内事项

- 以 current-run `run_id` 驱动准备物重生成。
- 明确 current-run helper / candidate / endpoint / evidence sink 的冻结路径。
- 在进入任何 live-side readonly evidence、operator preflight 或 live-side pre-snapshot 前，先做只读 alignment precheck。
- 用 repo-side 产物说明 expected artifact layout，避免再次出现 `RC_BASE` 下只有 `freeze-card.env`、`evidence/`、`runtime/` 的空壳状态。

## 3. 范围外事项

- 不启动 temporary restricted proxy。
- 不创建 audit jsonl。
- 不修改 `/etc/openclaw/openclaw.json`。
- 不修改 `openclaw.live.json`。
- 不修改 `openclaw` 用户组归属。
- 不执行 validate/deploy broker action。
- 不把本包写成 Phase 3 implementation completion。

## 4. 准备入口

repo-side 准备入口固定为以下两个脚本：

```bash
scripts/prepare-temporary-restricted-proxy-feasibility-artifacts.sh
scripts/precheck-temporary-restricted-proxy-artifact-alignment.sh
```

第一步负责写 current-run 产物；第二步只负责读 current-run 产物并判断是否对齐。

## 5. 建议顺序

### Step 0. 定义 current-run 标识

最低要固定：

- `run_id`
- `rc_base`
- candidate promote path 的命名
- 对应 record path

建议骨架：

```bash
RUN_ID=exp-docker-access-feasibility-<YYYYMMDD-HHMMSS>
RC_BASE=/tmp/openclaw-docker-access-feasibility/${RUN_ID}
```

要求：

- 必须使用 fresh `run_id`。
- 不得复用 `exp-docker-access-feasibility-20260322-111033` 这次 hard-stop 的失败 run。

### Step 1. 生成 current-run artifact

建议骨架：

```bash
scripts/prepare-temporary-restricted-proxy-feasibility-artifacts.sh \
  --run-id "${RUN_ID}" \
  --rc-base "${RC_BASE}"
```

预期结果：

- `freeze-card.env` 已落盘
- helper 已落盘
- validate-only candidate 已落盘
- manifest 已落盘
- `evidence/` 与 `runtime/` 目录已建立

### Step 2. 复核 expected layout

建议骨架：

```bash
sed -n '1,120p' "${RC_BASE}/freeze-card.env"
sed -n '1,220p' "${RC_BASE}/current-run-artifact-manifest.json"
sed -n '1,80p' "${RC_BASE}/expected-artifact-layout.txt"
```

最低应看到的布局：

```text
<rc-base>/
|-- current-run-artifact-manifest.json
|-- docker_restricted_proxy.py
|-- expected-artifact-layout.txt
|-- freeze-card.env
|-- openclaw.docker-access-feasibility.<run-id>.validate-only.json
|-- evidence/
`-- runtime/
```

### Step 3. 执行只读 alignment precheck

建议骨架：

```bash
scripts/precheck-temporary-restricted-proxy-artifact-alignment.sh \
  --rc-base "${RC_BASE}"
```

通过标准：

- helper 存在且嵌入 current-run `run_id`
- validate-only candidate 存在且 endpoint / run_id 与 freeze card 对齐
- manifest 中的 sha256、路径与实物一致
- 不再出现 `current-run helper missing`
- 不再出现 `current-run validate-only candidate missing`

### Step 4. 只在 precheck PASS 后，才允许进入下一层

precheck PASS 的出口语义只能是：

- 允许进入 `temporary restricted proxy feasibility execution` 的 readonly evidence pack
- 允许进入后续 operator preflight 审阅
- 允许继续评估是否可进入 live-side pre-snapshot gate

它不等于：

- 允许立即开始 live execution
- 允许直接进入 live-side pre-snapshot
- 允许启动 proxy
- 允许创建 audit jsonl

## 6. HARD_STOP 条件

- `freeze-card.env` 未生成。
- current-run helper 未生成。
- current-run validate-only candidate 未生成。
- `run_id`、endpoint、candidate path、evidence sink 任一发生 drift。
- 仍需要 previous-run helper 才能补 current-run。
- 仍需要把 historical baseline 误写成 current-run prepared state。

## 7. 成功判据

本包只在以下条件同时满足时，才可判定为 repo-side repair 成功收口：

1. current-run helper 已生成。
2. current-run validate-only candidate 已生成。
3. current-run `freeze-card.env`、manifest 与 expected layout 已形成。
4. alignment precheck 返回 `PREFLIGHT PASSED`。
5. 结果仍保持 repo-side / preflight-only 边界，不写成 execution started。

## 8. 输出语义

本包成功后，下一步只能写成：

- `current-run artifact pre-generation + alignment precheck established`
- `temporary restricted proxy feasibility execution` 可回到 readonly evidence / operator preflight 层继续评审
- 只有在 readonly evidence 同样 fresh 通过后，才允许进入 live-side pre-snapshot

不能写成：

- temporary restricted proxy execution 已开始
- validate-only candidate 已完成 live validate
- Phase 3 = GO
- operator 在后续窗口中不得现场拼接 proxy start / lifecycle / teardown 命令，必须等待 runbook 中单独批准的 `Approved Direct Proxy Execution Block`。

## 9. 2026-03-22 Repo-Side Validation Reference

本轮 dev repo 收口已用 fresh `run_id` 完整跑通一遍：

- `RUN_ID=exp-docker-access-feasibility-20260322-123530`
- `RC_BASE=/tmp/openclaw-docker-access-feasibility/exp-docker-access-feasibility-20260322-123530`
- `scripts/prepare-temporary-restricted-proxy-feasibility-artifacts.sh` 已生成：
  - `freeze-card.env`
  - `docker_restricted_proxy.py`
  - `openclaw.docker-access-feasibility.exp-docker-access-feasibility-20260322-123530.validate-only.json`
  - `current-run-artifact-manifest.json`
  - `expected-artifact-layout.txt`
- `scripts/precheck-temporary-restricted-proxy-artifact-alignment.sh` 已返回：
  - `RESULT: PREFLIGHT PASSED — current-run artifact alignment established.`

这组 evidence 只证明 repo-side prep/precheck 机制已可用，不代表下一次 live-side window 可以复用同一个 `run_id` 直接开窗。下一次 operator window 仍应重新生成 fresh `run_id` 并重跑 prepare/precheck。
