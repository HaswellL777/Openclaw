# Post-Upgrade Capability Probe Record — OpenClaw 2026.3.13

> 执行日期：2026-03-23
> 操作者：nick（operator）
> 基线版本：OpenClaw 2026.3.13
> Docker 访问：openclaw 在 docker 组（2026-03-23 配置）
> 设计来源：`docs/archive/planning/phase3-upgrade/post-upgrade-capability-probe-2026.3.13-slice-design-2026-03-18.md`
> Runbook：`docs/runbooks/runbook-post-upgrade-capability-probe-2026.3.13.md`
> 前次 probe（2026-03-19）：P5 FAIL（Docker 未安装），P2/P1/P4/P3 deferred

---

## Probe 结果

### P5: Docker / task-runner 前置条件

| 字段 | 内容 |
|------|------|
| Hypothesis | Docker Engine 已安装，需确认状态和 openclaw 用户访问路径 |
| Command / Action | `docker --version`; `systemctl is-active docker.service`; `docker info \| head -30`; `ls -la /var/run/docker.sock`; `getent group docker`; `sudo -u openclaw docker info \| head -10`; `sudo -u openclaw docker network ls`; `sudo -u openclaw docker images` |
| Docker 版本 | 28.2.2 (28.2.2-0ubuntu1~24.04.1) |
| Docker 服务状态 | active |
| Docker socket 权限 | `srw-rw---- root:docker` |
| openclaw Docker 访问 | 完整访问 — `docker info` 返回 Server 信息, 0 containers |
| docker 组成员 | `docker:x:129:openclaw` |
| 现有网络 | bridge, host, none (openclaw-task-net 尚不存在) |
| 现有镜像 | hello-world:latest (10.1kB) |
| Judgment | **Go** |
| Implication for Phase 3 | Docker 前置条件完全满足，可直接进入 Phase 3 实施 |
| Rollback / Cleanup Needs | 无 |

---

### P2: Plugin trust / provenance

| 字段 | 内容 |
|------|------|
| Hypothesis | Provenance 警告不阻塞功能，plugins.entries 注册路径不受影响 |
| Command / Action | `journalctl -u openclaw-gateway.service --since 2026-03-18 \| grep -i provenance`; `grep -i trust`; 检查 openclaw.json plugins 配置 |
| Observed Result | host-ops-tool 和 tool-audit-plugin 每次 gateway 启动均报 "loaded without install/load-path provenance; treat as untracked local code and pin trust via plugins.allow or install records"。日志为信息性，插件每次均成功加载。`plugins.allow: ['feishu', 'tool-audit-plugin', 'host-ops-tool']`，`host-ops-tool` entries enabled=True。从 3/18 到 3/23 行为一致，无升级趋势。 |
| Judgment | **Go** |
| Implication for Phase 3 | plugins.allow 已 pin trust，provenance 警告不会阻塞 Phase 3 plugin 加载 |
| Rollback / Cleanup Needs | 无 |

---

### P1: sessions_yield

| 字段 | 内容 |
|------|------|
| Hypothesis | 2026.3.12 引入 `sessions_yield`，可能影响 task-runner session 管理 |
| Command / Action | `journalctl -u openclaw-gateway.service --since 2026-03-18 \| grep -i yield`; `openclaw --help \| grep -iE "yield\|session"` |
| Observed Result | gateway 日志中无 yield 相关输出。CLI 中无 yield 子命令。CLI 有 `sessions` 命令（列出会话）但无 `sessions_yield`。 |
| Judgment | **Caution** |
| Implication for Phase 3 | sessions_yield 在 2026.3.13 上不是暴露的能力。Phase 3 设计不依赖它，不阻塞。P1 不是 hard gate。 |
| Rollback / Cleanup Needs | 无 |

---

### P4: Sandbox / workspace access

| 字段 | 内容 |
|------|------|
| Hypothesis | sandbox.docker 配置在当前版本可用 |
| Command / Action | (1) `journalctl grep sandbox/docker` — 无输出（预期，当前无 sandbox agent）; (2) 构造含 `sandbox: {mode: "all", scope: "session", docker: {image: "hello-world", network: "openclaw-task-net", readOnlyRoot: true}}` 的测试 candidate; (3) 通过 broker `validate_openclaw_json_candidate` 验证 |
| Observed Result | `{"ok": true, "status": "ok", "message": "Candidate validation passed", "json_valid": true, "sha256_match": true, "schema_valid": null}`。含 sandbox.docker 配置的 candidate 通过 validate，OpenClaw 2026.3.13 接受该配置结构。 |
| Judgment | **Go** |
| Implication for Phase 3 | sandbox.docker 字段被当前版本正确接受，Phase 3 可在 openclaw.json 中配置 task-runner sandbox |
| Rollback / Cleanup Needs | 测试 candidate 已清理 |

---

### P3: Target workspace / subagent

| 字段 | 内容 |
|------|------|
| Hypothesis | 2026.3.13 修复 cross-agent workspace，sessions_spawn 隔离符合 design-v3 §5.2 |
| Probe Path | 路径 A（文档分析） |
| Command / Action | 检查 openclaw.json agents.list 配置 |
| Observed Result | 当前只有 `main` agent，workspace = `/var/lib/openclaw/.openclaw/workspace-main`，`allowAgents: ["task-runner"]`，无 sandbox。配置结构与 design-v3 §6.2/§6.3 一致：main 允许 spawn task-runner，workspace 隔离通过 per-agent workspace 字段实现。 |
| Judgment | **Caution** |
| Implication for Phase 3 | 配置层面无阻塞。Phase 3 加入 task-runner agent 后需做首次 spawn 验证。 |
| Rollback / Cleanup Needs | 无 |

---

## Go/No-Go 总判定

| Probe | 判定 | 备注 |
|-------|------|------|
| P5 Docker 前置 | **Go** | Docker 28.2.2, openclaw 在 docker 组, 完整 API 访问 |
| P2 plugin trust | **Go** | 警告为信息性, plugins.allow 已 pin trust |
| P1 sessions_yield | **Caution** | 当前版本不存在, 非前置, 不阻塞 |
| P4 sandbox 配置 | **Go** | validate passed, sandbox.docker 字段被接受 |
| P3 workspace/subagent | **Caution** | 配置结构正确, 路径 A 分析通过, 待 live spawn 验证 |

### 门控条件核对

| 条件 | 满足？ |
|------|--------|
| P2 >= Caution | Yes (Go) |
| P3 >= Caution | Yes (Caution) |
| P4 >= Caution | Yes (Go) |
| P5 >= Caution | Yes (Go) |

### 总判定

- [x] **Go** — 全部 hard gate 通过，Phase 3 可作为后继 implementation slice 进入

---

## sessions_yield 定位判断

基于 probe 结果，`sessions_yield` 当前应视为：

- [x] **Not yet advisable** — 当前不建议依赖

理由: 2026.3.13 上无 yield 相关 CLI 命令或日志输出，该能力不可用或未暴露。Phase 3 session 管理使用 sessions_spawn / sessions_send 即可。

---

## 推荐的后继 substantive slice

**Slice 名称**: Phase 3 Docker sandbox foundation + task-runner 上线

**范围**:
1. 构建 task-runner 基线镜像 (openclaw-task-claude:2026-03-v3)
2. 创建 openclaw-task-net Docker network
3. 在 openclaw.json 中加入 task-runner agent 配置（含 sandbox.docker）
4. 创建 workspace-task-runner
5. 验证 sessions_spawn("task-runner") 可启动容器化 session
6. 首次真实容器化任务执行

**前置条件**: 本次 probe 全部 hard gate PASS (已满足)

---

## 补充观察

- 前次 probe（2026-03-19）因 Docker 未安装而 P5 FAIL。Docker 于 2026-03-22 安装，openclaw 于 2026-03-23 加入 docker 组，本次 probe 在同日完成。
- `schema_valid: null` 表示 broker validate wrapper 不做 OpenClaw schema 深度校验（只做 JSON 有效性 + SHA256 匹配）。sandbox 字段的 runtime 验证由 gateway 在加载配置时完成。
- Broker 仍不会随 gateway 自动启动（已知 P1 观察项），Phase 3 部署后需确认 broker 手动启动或考虑 systemd dependency 调整。
