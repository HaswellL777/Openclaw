# Hello-World Image Prerequisite Window

> 日期：2026-03-21
> 文档类型：planning / prerequisite-only window
> 当前状态：**active / current direct next window**
> 父切片：`docker-prerequisite-establishment-for-phase3`
> 前置执行证据：`docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md`
> 文档性质：**这是 prerequisite-only window，不是 temporary restricted proxy execution，不是 Phase 3 implementation，不是 docker-prerequisite establishment completion**

---

## 1. 文档性质声明

本窗口只定义一件事：

- 补齐 `hello-world` image prerequisite

本窗口**不**做以下事项：

- 不启动 temporary restricted proxy
- 不进入 temporary restricted proxy execution window
- 不进入 Phase 3 implementation 面
- 不把 `docker-prerequisite-establishment-for-phase3` 写成已完成

`2026-03-21` 的 execution evidence 已经收口为 `HARD_STOP`，且唯一 hard-stop reason 是 `hello-world image missing`。因此当前直接下一刀必须先切成单独的 prerequisite-only window，而不是继续推进 proxy execution。

## 2. 唯一目标

本窗口的唯一目标是：

- 为后续 feasibility execution 建立可直接举证的 `hello-world` image prerequisite

本窗口的成功**不等于**：

- temporary restricted proxy execution 已开始
- OpenClaw `sandbox.docker` 最小 lifecycle 已验证
- Phase 3 已放行

## 3. 明确禁止项

本窗口内明确禁止：

- `docker group`
- rootless Docker
- `/etc/openclaw/openclaw.json`
- `openclaw.live.json`
- Phase 3 implementation 面
- temporary restricted proxy execution 面

为避免边界漂移，本窗口也不应夹带：

- 长期 proxy/helper/systemd 终态设计
- task-runner image / network / workspace 正式实施
- `openclaw` 用户长期 Docker 权限模型冻结

## 4. Pre-Change Protection

任何 future live-side prerequisite establishment 如果要实际触碰宿主机，开始前必须先完成：

1. 明确该窗口仍是 `prerequisite-only window`，不是 proxy execution window。
2. 明确 `Phase 3 = NO-GO` 继续保持不变。
3. 记录当前 baseline 证据，至少覆盖：
   - `docker.service`
   - `docker.socket`
   - 当前 `hello-world` image 缺失状态
   - gateway / broker 当前状态
4. 遵守既有 host-affecting change 纪律：
   - pre-change snapshot
   - Vault sync
   - change
   - health validation
   - post-change snapshot
   - Vault sync
5. 不以本窗口为名义触碰 `/etc/openclaw/openclaw.json` 或 `openclaw.live.json`。

如果以上保护条件不能先写清并执行，则本窗口应停止，不得越级进入变更。

## 5. Evidence Requirements

本窗口 future execution 完成时，至少必须留下以下直接证据：

1. `hello-world` image 已存在的直接证据。
2. 该证据与窗口开始前的“image missing”状态形成可审计对照。
3. `docker.service` / `docker.socket` post-check 结果。
4. gateway / broker post-check 结果。
5. 未触碰 `/etc/openclaw/openclaw.json`、`openclaw.live.json` 的审计说明。
6. 未进入 temporary restricted proxy execution 的证据说明。

仅有以下内容时，证据仍然不足：

- 只有 Docker service/socket active
- 只有 Docker 版本输出
- 只有 helper/proxy 候选文件存在

这些都不能替代 `hello-world` image prerequisite 已补齐的直接证据。

## 6. Success Definition

本窗口只在以下条件同时满足时才算成功：

1. 可以直接证明 `hello-world` image 已经存在。
2. 该成功结论与 `2026-03-21` 的 `hello-world image missing` hard stop 形成闭环。
3. gateway / broker 在窗口结束后仍保持健康。
4. 没有把窗口扩展成 temporary restricted proxy execution。
5. 没有触碰：
   - `docker group`
   - rootless Docker
   - `/etc/openclaw/openclaw.json`
   - `openclaw.live.json`

即使成功，本窗口也只意味着：

- `hello-world` image prerequisite 已补齐

它**不意味着**：

- temporary restricted proxy feasibility 已通过
- Phase 3 已进入 GO

## 7. Hard Stop Rules

本窗口 future execution 中，出现以下任一情况应立即 `HARD_STOP`：

1. 无法形成 `hello-world` image 已存在的直接证据。
2. 需要通过 `docker group` 或 rootless Docker 才能推进。
3. 需要修改 `/etc/openclaw/openclaw.json` 或 `openclaw.live.json`。
4. 操作意图开始滑向 temporary restricted proxy execution。
5. 操作意图开始滑向 task-runner / network / workspace / Phase 3 implementation 面。
6. gateway 或 broker 健康状态出现非预期变化。

`HARD_STOP` 后应回到 repo-side 收口，不得在同一窗口内自动转入别的 live-side 方案。

## 8. Rollback / Cleanup

如果 future execution 失败、取消或触发 hard stop，本窗口的 rollback / cleanup 只允许覆盖与 image prerequisite 直接相关的临时对象，例如：

- 临时 staging 文件
- 临时下载缓存
- 临时验证输出

本窗口的 rollback / cleanup **不**应扩大为：

- proxy execution cleanup
- OpenClaw config rollback
- Phase 3 implementation rollback

窗口结束时应确保：

- 不留下被误认为 proxy execution 已开始的临时对象
- 不留下新的长期权限边界漂移

## 9. Post-Checks

本窗口 future execution 结束后，至少应执行以下 post-checks：

1. 再次确认 `hello-world` image 状态。
2. 再次确认 `docker.service` / `docker.socket` 状态。
3. 再次确认 gateway 状态。
4. 再次确认 broker 状态。
5. 再次确认没有产出 temporary restricted proxy socket / journal / audit jsonl。
6. 明确写回：本窗口结束后，下一步才可能回到 temporary restricted proxy feasibility execution 的进入评审。

## 10. 与现有切片的关系

本文件与现有 planning 的关系应理解为：

- `docker-prerequisite-establishment-for-phase3`
  仍是父切片
- `docker-access-model-feasibility-experiment-for-openclaw-2026.3.13-2026-03-21.md`
  仍是 feasibility definition
- `temporary-restricted-proxy-feasibility-window` 的 `2026-03-21` execution 已 `HARD_STOP`
- 当前新的直接下一刀是：
  - `hello-world-image-prerequisite-window-2026-03-21`

在该 prerequisite-only window 完成前，不得把 temporary restricted proxy execution 与本窗口重新合并。
