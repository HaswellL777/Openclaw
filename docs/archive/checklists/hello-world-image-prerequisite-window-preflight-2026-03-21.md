# Hello-World Image Prerequisite Window Preflight Checklist

> 日期：2026-03-21
> 文档类型：checklist / prerequisite-only live-side window 执行前门禁清单
> 当前状态：**draft / repo-side 起草，供 operator 在下次 live-side window 前人工核对**
> 适用窗口：`hello-world-image-prerequisite-window-2026-03-21`
> 父切片：`docker-prerequisite-establishment-for-phase3`
> 文档性质：**这是执行前门禁清单，不是执行记录，不是已批准 runbook，不是 temporary restricted proxy execution 包**

---

## 使用说明

- 本清单只服务于下一次 `hello-world prerequisite-only live-side window` 的进入判断。
- 本清单中的命令只允许写成“执行前检查项 / 建议命令骨架”，不构成自动批准执行。
- 标注为“`operator`”的检查项，表示必须由 live-side 操作者在窗口开始前或窗口过程中人工完成并留痕。
- 本清单不会把 proxy start、proxy audit、proxy execution validation 写成当前窗口内动作。
- 任一 `HARD_STOP` 条件命中时，本窗口不得继续推进，必须回到 repo-side 收口。

## 1. 文档基线确认

| 检查项 | 由谁完成 | 目标状态 | 建议命令骨架（执行前检查项） | 需留存 evidence |
|---|---|---|---|---|
| 当前边界冻结文档已对齐 | operator / repo-side reviewer | `docs/current-boundary.md` 明确写明：`Phase 3 = NO-GO`、active parent slice = `docker-prerequisite-establishment-for-phase3`、current direct next window = `hello-world-image-prerequisite-window-2026-03-21` | `sed -n '1,220p' docs/current-boundary.md` | 文档截屏或摘录 |
| planning 关系已对齐 | operator / repo-side reviewer | `docs/planning/README.md`、父切片 planning、当前 child window planning 三者一致 | `sed -n '1,220p' docs/planning/README.md`；`sed -n '1,220p' docs/planning/docker-prerequisite-establishment-for-phase3-2026-03-19.md`；`sed -n '1,220p' docs/planning/hello-world-image-prerequisite-window-2026-03-21.md` | 文档截屏或摘录 |
| 既有 execution evidence 已被引用 | operator / repo-side reviewer | `2026-03-19` probe record 与 `2026-03-21` hard-stop record 已作为本窗口前置事实 | `sed -n '1,220p' docs/records/post-upgrade-capability-probe-execution-2026-03-19.md`；`sed -n '1,220p' docs/records/temporary-restricted-proxy-feasibility-window-execution-2026-03-21.md` | 前置证据引用清单 |
| 本包边界未漂移 | operator / repo-side reviewer | 明确写出：本窗口只处理 `hello-world` image prerequisite；不启动 temporary restricted proxy；不创建 audit jsonl；不验证 proxy execution | 人工逐条核对本清单与 execution pack draft | 核对备注 |

## 2. git 基线确认

| 检查项 | 由谁完成 | 目标状态 | 建议命令骨架（执行前检查项） | 需留存 evidence |
|---|---|---|---|---|
| 冻结提交一致 | operator | HEAD 应仍可追溯到冻结提交 `fa3e32b`，或有明确 review 说明为什么偏离 | `git log --oneline -n 3`；`git rev-parse --short HEAD` | git 输出截屏 |
| 工作树状态可解释 | operator | 工作树应为 clean，或所有未提交变更都被明确解释为本窗口所需 repo-side 草稿变更 | `git status --short` | git 输出截屏 |
| 本次 live-side window 不夹带无关 repo 变更 | operator / repo-side reviewer | 只携带本窗口需要的文档 / 候选 / evidence 组织项 | `git diff --stat` | diff 摘要 |

## 3. 快照 / 回滚前提

| 检查项 | 由谁完成 | 目标状态 | 建议命令骨架（执行前检查项） | 需留存 evidence |
|---|---|---|---|---|
| host-affecting change 纪律已确认 | `operator` | 若窗口内会发生 host-side write，则必须遵守 `pre-change snapshot -> change -> health validation -> post-change snapshot -> Vault sync`，且不得把 Vault sync 插在 pre snapshot 与 change 之间 | 参考骨架：`sudo btrfs subvolume snapshot -r / "/.snapshots/root-pre-<label>-$(date +%F-%H%M)"`；`sudo btrfs subvolume snapshot -r / "/.snapshots/root-post-<label>-$(date +%F-%H%M)"`；`sudo /usr/local/sbin/vault-backup-root-btrfs` | 计划中的 snapshot label、窗口步骤顺序与回滚说明 |
| 回滚说明未越界 | `operator` | 回滚说明必须明确：根快照不恢复 `/var/lib/openclaw`；不得把根系统回滚写成恢复全部 OpenClaw 运行态 | 人工核对 rollback note | rollback note |
| post-change 锚点已预留 | `operator` | 若窗口进入 live-side write，post snapshot、post-window Vault sync 的命名与回收责任已预先写明 | 参考骨架：`sudo btrfs subvolume snapshot -r / "/.snapshots/root-post-<label>-$(date +%F-%H%M)"`；`sudo /usr/local/sbin/vault-backup-root-btrfs` | 计划中的 post-change label 与 post-window Vault sync 说明 |
| 未把 Vault 当作常规工作区 | `operator` | Vault 只作为既有同步纪律的一部分，不在 repo-side 流程中被当成常规可写目录 | 人工核对窗口说明 | 核对备注 |

## 4. 当前运行态确认

| 检查项 | 由谁完成 | 目标状态 | 建议命令骨架（执行前检查项） | 需留存 evidence |
|---|---|---|---|---|
| live baseline 未变 | `operator` | 仍为 OpenClaw `2026.3.13` | `openclaw --version` 或等价版本确认骨架 | 版本输出 |
| gateway 当前健康 | `operator` | `openclaw-gateway.service` 为 `active`，且未见本窗口前异常 | `systemctl is-active openclaw-gateway.service`；必要时按 SOP 健康检查骨架复核 | 状态输出 |
| broker 当前健康 | `operator` | `openclaw-broker.service` 为 `active` | `systemctl is-active openclaw-broker.service` | 状态输出 |
| Phase 3 结论未漂移 | operator / repo-side reviewer | 仍明确为 `NO-GO` | 人工核对当前边界文档与窗口说明 | 核对备注 |
| `2026-03-21` hard-stop 事实未被改写 | operator / repo-side reviewer | 仍明确承认：`proxy not started`、`audit jsonl not created`、gateway / broker remained active | 人工核对前置 record 与本窗口 draft | 核对备注 |

## 5. Docker 相关现状确认

| 检查项 | 由谁完成 | 目标状态 | 建议命令骨架（执行前检查项） | 需留存 evidence |
|---|---|---|---|---|
| Docker 服务状态已重新核对 | `operator` | `docker.service` / `docker.socket` 的窗口前状态被重新记录 | `systemctl is-active docker.service`；`systemctl is-active docker.socket` | 状态输出 |
| Docker socket 权限现状已重新核对 | `operator` | `/var/run/docker.sock` 的拥有者 / 组 / mode 被记录 | `ls -l /var/run/docker.sock` | 状态输出 |
| `docker` 组现状已记录 | `operator` | 只记录现状，不把组归属变更写入本窗口 | `getent group docker`；`id openclaw` | 状态输出 |
| `openclaw` 直接访问现状已重新确认 | `operator` | 若仍为 `permission denied`，应被记录为现状，而不是在本窗口内扩展成长期开权动作 | `sudo -u openclaw docker info` 或等价只读骨架 | 只读输出 |
| `hello-world` image 缺失基线已在窗口前复核 | `operator` | 进入窗口前重新确认“当前是否仍缺失”，为后续 prerequisite establishment 提供对照 | `docker image inspect hello-world`；`docker image ls hello-world` | pre-change 对照输出 |

## 6. 本窗口允许事项

| 允许事项 | 由谁完成 | 说明 |
|---|---|---|
| 只处理 `hello-world` image prerequisite | `operator` | 本窗口的唯一目标是补齐 `hello-world` image prerequisite，并形成可审计证据 |
| 只做与 image prerequisite 直接相关的最小 live-side 动作 | `operator` | 允许范围仅限建立 image prerequisite 所必需的最小动作；不得顺带扩展到 proxy execution |
| 记录 pre / post 对照 evidence | `operator` | 至少记录 image 状态、Docker 服务状态、gateway / broker 状态，以及“未启动 proxy / 未创建 audit jsonl”的窗口结论 |
| 明确写回“未验证 proxy execution” | `operator` | 本窗口结束时必须显式写回：未启动 temporary restricted proxy，未创建 proxy audit jsonl，未验证 proxy execution |
| 在必要时按既有纪律做 snapshot / Vault sync | `operator` | 仅当窗口包含 host-side write 时适用，且必须遵守既有 SOP 纪律 |

## 7. 本窗口禁止事项

| 禁止事项 | 说明 |
|---|---|
| 启动 temporary restricted proxy | 本窗口不是 proxy execution window |
| 创建 proxy audit jsonl | 本窗口不验证 proxy execution，因此不得创建该类审计产物 |
| 修改 `/etc/openclaw/openclaw.json` 或 `openclaw.live.json` | 本窗口不处理 OpenClaw config 变更 |
| 变更 `openclaw` 用户组归属 | 不把 `openclaw` 加入 `docker` 组，不冻结长期 Docker 权限模型 |
| 推进 Phase 3 implementation | 不进入 `phase3-docker-sandbox-foundation`，不把 prerequisite establishment 写成 implementation completion |
| 将 helper / proxy / endpoint 写成长期终态 | 它们在本上下文中仍只能是候选或后续 feasibility execution 输入 |
| 把 prerequisite-only window 与 temporary restricted proxy execution 合并 | 两个窗口必须继续分离 |
| 建议或执行 doctor / repair | 本窗口不允许此类路径 |

## 8. 执行后必须回收的 evidence

| evidence 项 | 由谁完成 | 最低要求 |
|---|---|---|
| `hello-world` image 的 pre / post 对照 | `operator` | 窗口前后的 `inspect` / `image ls` 或等价直接证据，能够证明“从缺失到存在”或记录未达成 |
| Docker 服务 / socket pre / post 状态 | `operator` | `docker.service`、`docker.socket`、`/var/run/docker.sock` 权限现状的前后对照 |
| gateway / broker post-check | `operator` | 窗口结束时两者仍保持健康的直接证据 |
| “未启动 proxy”证据 | `operator` | 至少有一条可核对说明：本窗口未启动 temporary restricted proxy |
| “未创建 audit jsonl”证据 | `operator` | 至少有一条可核对说明：本窗口未创建 proxy audit jsonl |
| “未验证 proxy execution”说明 | `operator` | 至少有一条可核对说明：本窗口没有验证 proxy execution，只为后续 feasibility execution 保留进入条件 |
| 未触碰 OpenClaw config / 用户组归属的说明 | `operator` | 明确写回：未修改 `/etc/openclaw/openclaw.json`、未修改 `openclaw.live.json`、未变更 `openclaw` 用户组归属 |
| snapshot / Vault evidence（如适用） | `operator` | 若窗口包含 host-side write，则必须补齐 pre / post snapshot 与 Vault sync evidence |

## 9. HARD_STOP 条件

| 条件 | 说明 |
|---|---|
| 文档边界不一致 | 任一文档把本窗口写成 proxy execution、Phase 3 implementation 或 establishment completion |
| git 基线不可解释 | 无法说明为何偏离冻结提交 `fa3e32b`，或工作树混入无关变更 |
| snapshot / rollback 前提不清 | 若需要 host-side write，但 pre / post snapshot、Vault sync、rollback note 未事先写清 |
| 当前运行态异常 | gateway 或 broker 在窗口开始前已不健康 |
| live baseline 不再是 `2026.3.13` | 该窗口只基于当前已冻结 baseline 起草 |
| Docker 现状无法形成前后对照 | 无法在窗口开始前明确记录 `hello-world` image 与 Docker 服务现状 |
| 推进过程要求修改 OpenClaw config 或 `openclaw` 用户组归属 | 这超出本窗口边界 |
| 推进过程滑向 temporary restricted proxy execution | 一旦开始触碰 proxy start、proxy journal、audit jsonl，即应立即停下 |
| 推进过程滑向 Phase 3 implementation | 一旦开始讨论 task-runner image / network / workspace 正式实施，即应立即停下 |
