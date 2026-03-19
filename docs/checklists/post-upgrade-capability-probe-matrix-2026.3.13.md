# Post-Upgrade Capability Probe Matrix (2026.3.13)

> 创建日期：2026-03-18
> 当前基线：OpenClaw 2026.3.13
> 依赖设计：`docs/planning/post-upgrade-capability-probe-2026.3.13-slice-design-2026-03-18.md`
> 状态：**probe 尚未执行**

---

## Probe Matrix

| # | Probe Item | 假设 | Repo-Side 准备 | Live-Side Operator 动作 | 成功判据 | 风险等级 | 对 Phase 3 的影响 |
|---|-----------|------|---------------|----------------------|---------|---------|-----------------|
| P1 | `sessions_yield` 语义与可用性 | 2026.3.12 引入了新会话管理原语 `sessions_yield`，可能影响 task-runner session 管理 | 无需代码变更 | (1) `sudo journalctl -u openclaw-gateway.service \| grep -i yield`；(2) 检查 CLI `openclaw --help` 是否有 yield 相关子命令；(3) 通过 agent session 尝试调用 `sessions_yield`（如存在）；(4) 查阅 2026.3.12 changelog | 能明确回答 sessions_yield 的语义是什么，以及它对 task-runner 设计的影响 | 低 — 仅探查，不改变系统状态 | Go：纳入 Phase 3 session 设计 / Caution：仅参考 / No-Go：不依赖 |
| P2 | Plugin trust / provenance 警告定性 | 升级后 provenance 警告出现但不阻塞功能；host-ops-tool 通过 `plugins.entries` config 注册 | 无需代码变更 | (1) `sudo journalctl -u openclaw-gateway.service \| grep -i provenance`；(2) `sudo journalctl -u openclaw-gateway.service \| grep -i trust`；(3) 检查 openclaw.json 中 plugins 配置；(4) 查阅上游 changelog 中 plugin trust 变更；(5) 对比升级前后 plugin registration 日志 | 能明确回答 provenance 警告是否会在 Phase 3 场景下升级为 hard block | 低 — 仅日志分析和文档查阅 | Go：维持当前方式 / Caution：预防性调整 / No-Go：重新设计 plugin 注入 |
| P3 | Target workspace / subagent 隔离行为 | 2026.3.13 修复了 cross-agent subagent target workspace 问题 | 无需代码变更 | (1) 查阅 2026.3.13 changelog 中 workspace 修复描述；(2) 检查 openclaw.json 中 agents.list 配置；(3) 可选：临时加入只读 test agent 验证 spawn workspace 隔离；(4) 或仅阅读上游文档确认修复 | 能明确回答 sessions_spawn 的 workspace 隔离是否符合 design-v3 §5.2 假设 | 中 — 如选择 live spawn 测试需临时变更 openclaw.json（需 snapshot 保护） | Go：维持设计假设 / Caution：增加验证步骤 / No-Go：重新设计 workspace 策略 |
| P4 | Sandbox / workspace access 配置行为 | `sandbox.docker` 配置在当前版本上可用 | 无需代码变更 | (1) 查阅上游文档中 sandbox API 变更；(2) 检查 CLI/API sandbox 相关命令；(3) 用 `validate_openclaw_json_candidate` 测试含 sandbox 配置的 candidate（仅 validate，不 deploy）；(4) 检查 gateway journal sandbox 相关日志 | 能明确回答 sandbox.docker 配置是否被当前版本正确解析 | 中 — validate candidate 是只读操作，但需构造测试 candidate | Go：维持 §5.9 假设 / Caution：增加验证 slice / No-Go：重新评估 sandbox 路径 |
| P5 | Docker / task-runner 前置条件 | Docker Engine 在宿主机已安装，需确认状态和访问路径 | 无需代码变更 | (1) `docker --version`；(2) `systemctl is-active docker.service`；(3) `ls -la /var/run/docker.sock`；(4) `getent group docker`；(5) `sudo -u openclaw docker info 2>&1 \| head -20`；(6) `docker network ls`；(7) `docker images` | 能给出 Docker 前置条件的完整状态报告 | 低 — 全部为只读命令 | Go：直接进入 Phase 3 / Caution：先整理 Docker / No-Go：需安装 Docker |

---

## Go/No-Go 门控规则

### 进入 Phase 3 的最低条件

| Probe | 最低要求 | 是否为 hard gate |
|-------|---------|-----------------|
| P1 sessions_yield | 无要求（新增能力，非前置） | 否 — 不阻塞 Phase 3 |
| P2 plugin trust | ≥ Caution | **是** — 如果 No-Go，阻塞 Phase 3 |
| P3 workspace/subagent | ≥ Caution | **是** — 如果 No-Go，阻塞 Phase 3 |
| P4 sandbox 配置 | ≥ Caution | **是** — 如果 No-Go，阻塞 Phase 3 |
| P5 Docker 前置 | ≥ Caution | **是** — 如果 No-Go，阻塞 Phase 3 |

### 判定标准定义

| 级别 | 含义 |
|------|------|
| **Go** | 能力已确认可用，Phase 3 可直接依赖 |
| **Caution** | 能力存在但有条件/限制，Phase 3 需加入额外验证或调整 |
| **No-Go** | 能力不可用或行为不符合预期，阻塞 Phase 3 或需重新设计 |

---

## Probe 执行顺序

建议按风险递增执行：

1. **P5 Docker 前置** — 全部只读命令，零风险，快速确认基础设施
2. **P2 Plugin trust** — 日志分析和文档查阅，零风险
3. **P1 sessions_yield** — 日志分析和可选 API 测试，低风险
4. **P4 Sandbox 配置** — 需构造测试 candidate，中低风险
5. **P3 Workspace/subagent** — 如做 live spawn 测试需 snapshot 保护，最高风险

---

## 汇总模板

| # | Probe Item | 判定 | 备注 |
|---|-----------|------|------|
| P1 | sessions_yield | _待填_ | |
| P2 | plugin trust / provenance | _待填_ | |
| P3 | target workspace / subagent | _待填_ | |
| P4 | sandbox / workspace access | _待填_ | |
| P5 | Docker 前置条件 | _待填_ | |
| **总判定** | Phase 3 Go/No-Go | _待填_ | |
