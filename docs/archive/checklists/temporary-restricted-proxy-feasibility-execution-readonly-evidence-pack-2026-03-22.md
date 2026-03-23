# Temporary Restricted Proxy Feasibility Execution Readonly Evidence Pack

> 日期：2026-03-22
> 文档类型：operator-facing readonly evidence pack
> 适用范围：`temporary restricted proxy feasibility execution` 开始前的最后一轮只读取证
> baseline：OpenClaw `2026.3.13`
> 配套 operator runbook：`docs/runbook-temporary-restricted-proxy-feasibility-execution-next-window-2026-03-22.md`
> 当前 direct-next closure：`docs/planning/approved-direct-proxy-execution-block-source-closure-2026-03-22.md`
> 文档性质：**本文件只定义 execution 前必须回收的 fresh readonly evidence，不是 execution runbook，不是 implementation completion record**

---

## 使用说明

- 本包只用于 operator 在正式 feasibility execution 之前，一次性回收 fresh evidence。
- 本包内命令必须保持只读；不得启动 proxy，不得创建 audit jsonl，不得修改配置，不得改变用户组归属，不得写系统状态。
- 本包开始前，repo-side 必须已经完成 current-run artifact pre-generation 且 alignment precheck 已 PASS；本包不负责补生成 helper / validate-only candidate，只负责只读复核。
- 本包允许 operator 仅为回收 `hello-world` fresh existence evidence 使用 `sudo docker image inspect/ls`；该 `sudo` 只服务于只读取证，不等于放开长期 direct Docker access，也不改变 `openclaw` 仍不在 `docker` 组这一权限边界。
- 本包回收完成后，repo-side 可直接依据输出做二分判断：
  - 是否继续维持 `BLOCKED_BEFORE_HOST_SIDE_CHANGE`
  - 或返回 repo-side 补齐 `Approved Direct Proxy Execution Block`
- 若任一命令输出显示权限边界漂移、服务健康退化、`hello-world` 不存在、或需要借助解释性推断才能维持结论，则不得释放 blocked-state，更不得进入 pre-snapshot 或 execution。

## 1. repo-side 基线证据

### 1.1 工作树与分支

```bash
git status --short
```

目的：
- 证明本轮 repo-side 收口可审计
- 再次确认那两个 local draft 仍为未跟踪，且未被纳入执行事实源

fresh 要求：
- 必须 fresh 回收

### 1.2 current-run artifact pack

```bash
scripts/precheck-temporary-restricted-proxy-artifact-alignment.sh \
  --rc-base /tmp/openclaw-docker-access-feasibility/<run-id>
```

目的：
- 在进入 live-side readonly evidence 之前，先只读确认 current-run helper / validate-only candidate / manifest 已经对齐
- 避免再把 previous-run baseline 错认成 current-run prepared state

fresh 要求：
- 必须 fresh 回收

判读：
- 若返回 `RESULT: PREFLIGHT PASSED`，说明 current-run artifact alignment 已建立
- 若返回 `RESULT: PREFLIGHT FAILED`，则当前应直接维持 `HARD_STOP`，不得继续 live-side evidence 回收，更不得进入 pre-snapshot

```bash
sed -n '1,220p' /tmp/openclaw-docker-access-feasibility/<run-id>/freeze-card.env
sed -n '1,220p' /tmp/openclaw-docker-access-feasibility/<run-id>/current-run-artifact-manifest.json
```

目的：
- 只读核对 current-run `run_id`、endpoint、candidate path、evidence sink 与 helper / candidate 实物路径

fresh 要求：
- 本轮 repo-side 收口后回收一次即可

```bash
git rev-parse --abbrev-ref HEAD
```

目的：
- 确认当前分支仍为 `feat/phase1b-workspace-foundation`

fresh 要求：
- 必须 fresh 回收

```bash
git log --oneline -n 8
```

目的：
- 只核对本地最近关键提交链仍包含 `0b409d4`、`1b73805`、`f60e992`
- 不据此推断 remote push 状态

fresh 要求：
- 必须 fresh 回收

## 2. 文档门禁证据

```bash
sed -n '53,112p' docs/current-boundary.md
```

目的：
- 确认当前 direct next 已写成 repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐
- 确认 Phase 3 仍为 `NO-GO`

fresh 要求：
- 本轮 repo-side 收口后回收一次即可

```bash
sed -n '8,29p' docs/design-v3.md
```

目的：
- 确认 authority 设计文档已与当前 direct next 对齐
- 确认 temporary restricted proxy execution 仍未启动

fresh 要求：
- 本轮 repo-side 收口后回收一次即可

```bash
sed -n '1,18p' docs/host-sop.md
```

目的：
- 确认 SOP 主叙述层已与当前 direct next 对齐

fresh 要求：
- 本轮 repo-side 收口后回收一次即可

## 3. 只读运行态 pre-check

```bash
systemctl status docker.service --no-pager
```

目的：
- execution 前 fresh 确认 `docker.service` 仍为健康状态

fresh 要求：
- 必须 fresh 回收

```bash
systemctl status docker.socket --no-pager
```

目的：
- execution 前 fresh 确认 `docker.socket` 仍为健康状态

fresh 要求：
- 必须 fresh 回收

```bash
systemctl status openclaw-gateway.service --no-pager
```

目的：
- execution 前 fresh 确认 gateway 仍健康

fresh 要求：
- 必须 fresh 回收

```bash
systemctl status openclaw-broker.service --no-pager
```

目的：
- execution 前 fresh 确认 broker 仍健康

fresh 要求：
- 必须 fresh 回收

## 4. prerequisite 与权限边界证据

```bash
sudo docker image inspect hello-world
```

目的：
- 以 operator 的只读 `sudo` 路径回收 `hello-world` 直接存在证据
- 该命令只用于 execution 前 existence evidence，不等于放开长期 direct Docker access

fresh 要求：
- 必须 fresh 回收

判读：
- 若返回完整镜像元数据，可作为直接存在证据
- 若返回 `No such image` 或空数组，则应判定当前 prerequisite direct evidence 未成立
- 若出现与 `sudo` 本身相关的异常，则本轮只读取证未完成，不得进入 execution

```bash
sudo docker image ls hello-world
```

目的：
- 以更易读形式补充 `hello-world` 存在性证据
- 与上一条共同构成 operator 的只读 Docker existence evidence

fresh 要求：
- 必须 fresh 回收

判读：
- 若显示 `hello-world` 条目，可作为直接存在证据
- 若只有表头或明确无 `hello-world` 条目，则应判定当前 prerequisite direct evidence 未成立
- 不再使用“非 sudo docker permission denied”作为 blocker 逻辑，因为本包不再依赖该错误路径

```bash
id openclaw
```

目的：
- fresh 确认 `openclaw` 用户仍存在，供权限边界核对

fresh 要求：
- 必须 fresh 回收

```bash
getent group docker
```

目的：
- fresh 确认 `docker` 组存在及其成员列表
- 用于判断 `openclaw` 是否仍未被加入 `docker` 组

fresh 要求：
- 必须 fresh 回收

## 5. 既有 execution 基线核对

```bash
sed -n '65,132p' docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md
```

目的：
- 回看上次 `HARD_STOP` 的唯一原因
- 回看 validate-only candidate、helper payload、pre-proxy 观测已存在的 dated baseline

fresh 要求：
- 本轮 repo-side 收口后回收一次即可

```bash
sed -n '44,124p' docs/records/hello-world-image-prerequisite-remediation-micro-window-2026-03-22.md
```

目的：
- 回看 `hello-world prerequisite established`
- 回看 remediation 后 `proxy not started`、`audit jsonl not created`、未改配置、未改组归属

fresh 要求：
- 本轮 repo-side 收口后回收一次即可

```bash
sed -n '55,170p' docs/records/temporary-restricted-proxy-feasibility-execution-hard-stop-exp-docker-access-feasibility-20260322-111033.md
```

目的：
- 回看本次新的 hard-stop 根因确实是 `current-run artifact alignment not established`
- 回看 `current-run helper missing` 与 `current-run validate-only candidate missing` 不能再在下一轮重演

fresh 要求：
- 本轮 repo-side 收口后回收一次即可

## 6. preflight 出口判读

- 允许继续维持 Gate 0-3 green 的最小条件：
  - `git` 基线无额外漂移，且两个 local draft 仍保持未跟踪
  - current-run artifact precheck 已返回 `PREFLIGHT PASSED`
  - 四个关键服务 fresh 状态未出现退化
  - `hello-world` fresh 直接存在证据可由当前 operator 通过只读 `sudo docker image inspect/ls` 回收
  - `openclaw` 仍不在 `docker` 组
  - 未出现需要触碰 `/etc/openclaw/openclaw.json`、`openclaw.live.json`、systemd 终态设计或长期权限模型的迹象

本包的出口语义只允许写成：

- **维持 `BLOCKED_BEFORE_HOST_SIDE_CHANGE`，并返回 repo-side 补齐 `Approved Direct Proxy Execution Block`**
- **维持 `HARD_STOP` 并返回 repo-side 收口**

- 继续 `HARD_STOP` 的任一条件：
  - current-run artifact precheck 未通过，或 helper / validate-only candidate 仍缺失
  - 任一关键服务 fresh 状态不是健康可继续状态
  - `hello-world` 无法形成 fresh 直接存在证据
  - fresh 输出显示 `openclaw` 已进入 `docker` 组，或权限边界发生未审查漂移
  - 需要使用写操作、高权限变更或临时解释才能维持“可继续保持 green”结论

- 本包回收的输出足够支持 repo-side 做下一步二分判断；即使 Gate 0-3 继续为绿，也仍不得进入 live-side pre-snapshot 或 execution。当前 direct next work 仍只能是 repo-side `Approved Direct Proxy Execution Block` 来源条件 / 批准路径补齐。
