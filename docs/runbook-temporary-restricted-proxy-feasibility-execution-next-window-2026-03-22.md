# Temporary Restricted Proxy Feasibility Execution Next-Window Runbook

> 日期：2026-03-22
> 文档类型：operator runbook / execution pack
> 当前状态：**draft / 仅用于下一次 live-side execution 开窗前的门禁与顺序收口，不构成已执行事实**
> 父切片：`docker-prerequisite-establishment-for-phase3`
> baseline：OpenClaw `2026.3.13`
> 当前 direct-next closure：`docs/planning/approved-direct-proxy-execution-block-source-closure-2026-03-22.md`
> 直接前置证据：`docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md`；`docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md`；`docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md`
> 文档性质：**这是下一次 live-side execution 的 operator runbook；不是 execution record，不是 deployment continuation，不是 Phase 3 GO 记录**

---

## 1. 目的与边界

本 runbook 只服务于下一次 `temporary restricted proxy feasibility execution` 开窗前的门禁、顺序和 operator pack 收口。

它只回答以下问题：

- repo-side prepare / precheck 先做什么
- 哪些条件满足后，才允许进入下一层 blocked-state 审阅，以及在何种前提下仍不得进入 live-side pre-snapshot
- snapshot / Vault / proxy start / evidence / hard stop / post-check / syncback 的顺序是什么
- `2026-03-22` hard-stop 教训如何转成下一次窗口的硬门禁

它不表示：

- feasibility execution 已开始
- proxy 可以提前启动
- audit jsonl 可以提前创建
- `Phase 3 = GO`
- `phase3-docker-sandbox-foundation` 已放行

## 2. Historical Lesson That Becomes a Gate

`2026-03-22` 的 hard-stop record 已经证明：

- previous-run helper / candidate baseline 不能当作 current-run prepared state
- `current-run artifact alignment not established` 必须被视为 `before_proxy_start` 的硬门禁
- 在 current-run helper、validate-only candidate、manifest、expected layout 和 alignment PASS 未形成前，不得进入任何 live-side pre-snapshot

因此，下一次窗口的第一条硬规则是：

- **只有 current-run artifact alignment PASS 后，才允许进入下一层 blocked-state 审阅；在 `Approved Direct Proxy Execution Block` 被单独批准前，仍不得进入 live-side pre-snapshot。**

## 3. Exact Gate Chain

### Gate 0. 文档与边界一致

必须先确认：

- `docs/current-boundary.md` 仍写明 `Phase 3 = NO-GO`
- 本窗口仍写成 feasibility execution，不是 implementation completion
- `/etc/openclaw/openclaw.json` 仍是唯一 system gateway 生效配置源

### Gate 1. Repo-Side Prepare With Fresh Run ID

必须先用 fresh `run_id` 生成 current-run prepared state：

```bash
RUN_ID=exp-docker-access-feasibility-<YYYYMMDD-HHMMSS>
RC_BASE=/tmp/openclaw-docker-access-feasibility/${RUN_ID}

scripts/prepare-temporary-restricted-proxy-feasibility-artifacts.sh \
  --run-id "${RUN_ID}" \
  --rc-base "${RC_BASE}"
```

必须形成：

- `${RC_BASE}/freeze-card.env`
- `${RC_BASE}/docker_restricted_proxy.py`
- `${RC_BASE}/openclaw.docker-access-feasibility.${RUN_ID}.validate-only.json`
- `${RC_BASE}/current-run-artifact-manifest.json`
- `${RC_BASE}/expected-artifact-layout.txt`

### Gate 2. Repo-Side Alignment Precheck PASS

```bash
scripts/precheck-temporary-restricted-proxy-artifact-alignment.sh \
  --rc-base "${RC_BASE}"
```

允许继续的唯一结果：

- `RESULT: PREFLIGHT PASSED — current-run artifact alignment established.`

若不是这个结果：

- `HARD_STOP`
- 阶段写回 `before_proxy_start`
- 不进入 readonly evidence
- 不进入 live-side pre-snapshot
- 不启动 proxy
- 不创建 audit jsonl

### Gate 3. Live-Side Readonly Evidence Pack Fresh Green

在 Gate 2 PASS 后，operator 才可执行只读证包：

- `docs/checklists/temporary-restricted-proxy-feasibility-execution-readonly-evidence-pack-2026-03-22.md`

必须 fresh 复核：

- current-run precheck 仍为 PASS
- `docker.service` / `docker.socket` / gateway / broker 保持健康
- `hello-world` image 可由 operator 的只读 `sudo docker image inspect/ls` 再次形成直接存在证据
- `openclaw` 仍不在 `docker` 组

若 Gate 3 不绿：

- `HARD_STOP`
- 不进入 live-side pre-snapshot

### Gate 4. Only Then May Operator Enter Live-Side Pre-Snapshot

只有 Gate 0 到 Gate 3 全部为绿，才允许开始 host-affecting sequence 的第一步：

- live-side pre-snapshot

## 4. Exact Execution Order

下一次窗口应严格按以下顺序执行：

1. repo-side 固定 fresh `run_id` 与 `RC_BASE`
2. repo-side 运行 `prepare` 生成 current-run helper / validate-only candidate / freeze-card / manifest / expected layout
3. repo-side 运行 `precheck`，必须得到 `PREFLIGHT PASSED`
4. operator 运行 readonly evidence pack，回收 fresh 服务健康、`hello-world` 存在性与权限边界证据
5. 只有在 steps 1-4 全部通过后，才表示 `GATE0_3=GREEN`、prepared state 与 readonly evidence 已形成；在 `APPROVED_PROXY_EXEC_CMD=NO` 时，仍不得进入 live-side pre-snapshot
6. live-side 执行 pre-change snapshot
7. live-side 执行 pre-change Vault sync
8. live-side 进入 change phase：
   - start temporary restricted proxy
   - 保留 proxy socket / unit / journal 直接证据
   - 不改 `/etc/openclaw/openclaw.json`
   - 不改 `openclaw.live.json` 的 deployed state
   - 不改 `openclaw` 组归属
9. live-side 回收 execution evidence：
   - candidate config accepted / rejected
   - proxy actually started
   - audit jsonl actually created
   - backend reachable via explicit endpoint
   - lifecycle `create / start / run / cleanup` 最小闭环
10. 任一执行中 hard stop 触发时：
   - 立即停止继续推进
   - 做最小必要 cleanup / teardown
   - 写回 failure class，不把 failure 解释成 `Phase 3 = GO`
11. live-side 做 post-check：
   - `docker.service`
   - `docker.socket`
   - `openclaw-gateway.service`
   - `openclaw-broker.service`
12. 只要本窗口发生过 host-side change，就继续完成：
   - post-change snapshot
   - post-change Vault sync
13. 将 evidence bundle、结果摘要与 gate 结论 sync back 到 repo-side，更新 record / checklist / pack，而不是继续 deployment continuation

### 4.1 Approved Direct Proxy Execution Block Status

截至 `2026-03-22` 的 blocked-check，当前窗口结论已固定为：

- `RESULT=BLOCKED_BEFORE_HOST_SIDE_CHANGE`
- `GATE0_3=GREEN`
- `PREPARED_STATE_PASS=YES`
- `READONLY_EVIDENCE_GREEN=YES`
- `APPROVED_PROXY_EXEC_CMD=NO`

这意味着：

- Gate 0-3 已绿，只代表 repo-side prepare/precheck 与 readonly evidence 已形成；
- 这 **不** 释放 live-side pre-snapshot gate；
- steps 8-10 目前仍只定义了顺序、目标和 evidence points，**尚未形成已批准的 direct operator command block**；
- steps 8-10 仍不得被解释为可执行 operator block，也不得在 live-side 现场拼接执行。

在本段被一个单独审阅并批准的 exact block 替换之前，operator 必须继续遵守以下限制：

- 不得现场拼接 proxy start / lifecycle / teardown 命令；
- 不得把 `docker_restricted_proxy.py` 的存在，误写成 proxy 已获准启动；
- 不得把 validate-only candidate 的存在，误写成 OpenClaw 已获准使用该 candidate；
- 不得进入 pre-snapshot；
- 不得开始 host-side change。

当前仍未批准的项至少包括以下八类：

1. proxy 启动锚点未批准
2. proxy unit / process identity 未批准
3. candidate acceptance operator 路径未批准
4. 在不修改 `/etc/openclaw/openclaw.json`、不修改 `openclaw.live.json`、不启动第二个 gateway 的前提下，如何让 OpenClaw 实际使用 current-run validate-only candidate，这条 operator 路径未批准
5. lifecycle trigger 未批准
6. teardown 未批准
7. 证据与命令未一一绑定
8. hard boundary / forbidden actions 仍未被整理成 future approved block 的前置页

因此，本 runbook 当前只能继续提供：

- Gate chain
- exact order 的阶段顺序
- hard-stop matrix
- evidence expectations

本 runbook 当前 **不能** 作为 operator 的 direct proxy start / lifecycle / cleanup 命令来源。

只有当上述八类被收敛为一个单独审阅、逐条可举证的 `Approved Direct Proxy Execution Block` 后，steps 8-10 才可从“占位执行顺序”升级为“可执行 operator block”。

## 5. Hard-Stop Matrix

### Before Pre-Snapshot

以下任一成立，直接停在 `before_proxy_start`：

- current-run helper 未生成
- current-run validate-only candidate 未生成
- manifest / expected layout 未形成
- alignment precheck 未 PASS
- readonly evidence pack 未 fresh 通过
- `hello-world` fresh 直接存在证据缺失
- `openclaw` 被发现加入 `docker` 组
- 需要触碰 `/etc/openclaw/openclaw.json`
- 需要触碰 `openclaw.live.json` 的 deployed state

### After Proxy Start

以下任一成立，立即 hard stop 并进入 cleanup / post-check / syncback：

- proxy 无法稳定启动
- audit jsonl 未创建或为空
- backend 不是走 frozen explicit endpoint
- lifecycle 无法形成最小闭环
- 关键服务健康退化
- 结果只能靠解释性推断而不是直接证据维持

## 6. Evidence Expectations

进入 execution 后至少要回收：

- pre-snapshot 名称与时间戳
- pre-change Vault sync 结果
- proxy socket / unit / journal 证据
- audit jsonl 存在性与非空证据
- candidate config accepted / rejected 输出
- lifecycle 关键阶段输出
- post-check 四项服务状态
- post-snapshot 名称与时间戳
- post-change Vault sync 结果

若最终失败，也必须写清：

- failure class
- 停止阶段
- cleanup 是否完成
- 为什么这仍只是 feasibility result，而不是 implementation conclusion

## 7. Minimal GPT-5.4 Handoff Bundle

下一次开一个新的 GPT-5.4 对话窗口时，最小 bundle 应包含：

### 文档

- `docs/current-boundary.md`
- `docs/host-sop.md`
- `docs/design-v3.md`
- `docs/planning/docker-prerequisite-establishment-for-phase3-2026-03-19.md`
- `docs/checklists/temporary-restricted-proxy-feasibility-execution-preflight-2026-03-22.md`
- `docs/checklists/temporary-restricted-proxy-feasibility-execution-readonly-evidence-pack-2026-03-22.md`
- `docs/execution-pack-temporary-restricted-proxy-feasibility-artifact-preparation-2026-03-22.md`
- `docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md`

### 脚本

- `scripts/prepare-temporary-restricted-proxy-feasibility-artifacts.sh`
- `scripts/precheck-temporary-restricted-proxy-artifact-alignment.sh`

### prepared-state evidence

- `<rc-base>/freeze-card.env`
- `<rc-base>/docker_restricted_proxy.py`
- `<rc-base>/openclaw.docker-access-feasibility.<run-id>.validate-only.json`
- `<rc-base>/current-run-artifact-manifest.json`
- `<rc-base>/expected-artifact-layout.txt`
- fresh `prepare` stdout 摘要
- fresh `precheck` stdout 摘要

### hard-stop / historical lessons

- `docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md`
- `docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md`
- `docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md`

不应纳入 bundle：

- `/etc/openclaw/openclaw.json`
- live deployed `openclaw.live.json`
- secrets、tokens、API keys
- 未跟踪 local draft

## 8. Suggested Packaging Commands

以下命令只作为远端打包建议，不在本轮执行：

```bash
RUN_ID=exp-docker-access-feasibility-<YYYYMMDD-HHMMSS>
RC_BASE=/tmp/openclaw-docker-access-feasibility/${RUN_ID}
STAMP=$(date +%Y%m%d-%H%M%S)
BUNDLE_DIR=/tmp/temporary-restricted-proxy-next-window-bundle-${STAMP}

mkdir -p "${BUNDLE_DIR}/docs" "${BUNDLE_DIR}/scripts" "${BUNDLE_DIR}/prepared-state"

cp docs/current-boundary.md "${BUNDLE_DIR}/docs/"
cp docs/host-sop.md "${BUNDLE_DIR}/docs/"
cp docs/design-v3.md "${BUNDLE_DIR}/docs/"
cp docs/planning/docker-prerequisite-establishment-for-phase3-2026-03-19.md "${BUNDLE_DIR}/docs/"
cp docs/checklists/temporary-restricted-proxy-feasibility-execution-preflight-2026-03-22.md "${BUNDLE_DIR}/docs/"
cp docs/checklists/temporary-restricted-proxy-feasibility-execution-readonly-evidence-pack-2026-03-22.md "${BUNDLE_DIR}/docs/"
cp docs/execution-pack-temporary-restricted-proxy-feasibility-artifact-preparation-2026-03-22.md "${BUNDLE_DIR}/docs/"
cp docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md "${BUNDLE_DIR}/docs/"
cp docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md "${BUNDLE_DIR}/docs/"
cp docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md "${BUNDLE_DIR}/docs/"
cp docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md "${BUNDLE_DIR}/docs/"
cp scripts/prepare-temporary-restricted-proxy-feasibility-artifacts.sh "${BUNDLE_DIR}/scripts/"
cp scripts/precheck-temporary-restricted-proxy-artifact-alignment.sh "${BUNDLE_DIR}/scripts/"
cp "${RC_BASE}/freeze-card.env" "${BUNDLE_DIR}/prepared-state/"
cp "${RC_BASE}/docker_restricted_proxy.py" "${BUNDLE_DIR}/prepared-state/"
cp "${RC_BASE}/openclaw.docker-access-feasibility.${RUN_ID}.validate-only.json" "${BUNDLE_DIR}/prepared-state/"
cp "${RC_BASE}/current-run-artifact-manifest.json" "${BUNDLE_DIR}/prepared-state/"
cp "${RC_BASE}/expected-artifact-layout.txt" "${BUNDLE_DIR}/prepared-state/"

tar -C /tmp -czf "${BUNDLE_DIR}.tar.gz" "$(basename "${BUNDLE_DIR}")"
```

这组命令只用于 handoff bundle，不用于 deployment，不用于 live-side execution continuation。
