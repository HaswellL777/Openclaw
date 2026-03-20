# Planning 目录索引

> `docs/planning/` 存放活跃的规划文档。
> 已完成的 Phase 2 slice 设计已归档至 `docs/archive/planning/phase2/`。

---

## 活跃规划

| 文件 | 日期 | 主题 | 状态 |
|------|------|------|------|
| `docker-prerequisite-establishment-for-phase3-2026-03-19.md` | 2026-03-19 | **Docker prerequisite establishment for Phase 3** | **active / current next slice** |
| `post-upgrade-capability-probe-2026.3.13-slice-design-2026-03-18.md` | 2026-03-18 | **升级后 capability probe 设计** | completed as design; execution ended with `P5 FAIL / Phase 3 = NO-GO` |
| `openclaw-upgrade-readiness-2026-03-18.md` | 2026-03-18 | OpenClaw 升级就绪评估 | completed |
| `openclaw-2026.3.13-upgrade-slice-design-2026-03-18.md` | 2026-03-18 | 2026.3.13 升级 slice 设计 | completed |
| `openclaw-2026.3.13-upgrade-rollback-design-2026-03-18.md` | 2026-03-18 | 2026.3.13 升级 rollback 设计 | completed |

当前 planning 层应按以下顺序理解：

1. 升级后 capability probe 设计已完成，且 probe 已执行。
2. probe 在 `P5 Docker / task-runner prerequisites` 因 Docker prerequisite 缺失而 hard gate FAIL。
3. 当前 Phase 3 结论为 **NO-GO**。
4. 当前唯一下一刀是 `docker-prerequisite-establishment-for-phase3`。

## 已归档

Phase 2 的 8 个 slice 设计文档已移至 `docs/archive/planning/phase2/`：

- `deploy-candidate-slice-design-2026-03-15.md`
- `snapshot-pre-slice-design-2026-03-15.md`
- `snapshot-post-slice-design-2026-03-16.md`
- `rollback-prepare-slice-design-2026-03-16.md`
- `gateway-restart-slice-design-2026-03-16.md`
- `gateway-restart-deferred-dispatch-design-2026-03-16.md`
- `gateway-restart-validation-hardening-2026-03-16.md`
- `vault-sync-slice-design-2026-03-17.md`
