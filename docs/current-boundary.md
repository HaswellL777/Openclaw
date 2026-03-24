# OpenClaw 当前真实边界

> 更新日期：2026-03-24
> 基线版本：OpenClaw 2026.3.13（2026-03-18 从 2026.3.2 升级完成）
> 阶段：**Phase 3 operational**（task-runner deployed, Docker sandbox verified, 端到端任务执行已验证）

---

## 已完成

| 阶段 | 状态 | 完成日期 |
|------|------|----------|
| Phase 0 (dev skeleton) | 完成 | 2026-03-07 |
| Phase 1A (main bootstrap) | 完成 | 2026-03-07 |
| Phase 1B (控制面收口 + 首次 live publish) | 完成 | 2026-03-11 |
| Phase 2 broker deployment | 完成 | 2026-03-14 |
| Phase 2 plugin activation | 完成 | 2026-03-15 |
| Phase 2 agent-facing host_ops **8/8** | 完成 | 2026-03-17 |
| OpenClaw 版本升级 (2026.3.2 → 2026.3.13) | 完成 | 2026-03-18 |
| Docker prerequisite establishment | 完成 | 2026-03-23 |
| Capability probe rerun (P5/P2/P1/P4/P3) | 完成 — **全部 PASS** | 2026-03-23 |
| Phase 3 基础部署 (task-runner + Docker sandbox) | 完成 | 2026-03-23 |
| Phase 3 端到端验证 (sessions_spawn → 容器内 git clone → 结果回传) | 完成 | 2026-03-24 |
| Phase 3+ artifacts (Dockerfile.full, network check, per-task isolation, prune candidate) | 完成 (repo-side) | 2026-03-24 |
| workspace-main skills 更新至 Phase 3 operational | 完成 | 2026-03-24 |

### 已验证的 8 个 host_ops action

| Action | 验证日期 | 类型 |
|--------|----------|------|
| `gateway_health` | 2026-03-15 | 只读 |
| `validate_openclaw_json_candidate` | 2026-03-15 | 只读 |
| `deploy_openclaw_json_candidate` | 2026-03-15 | 写（Route C） |
| `snapshot_pre` | 2026-03-16 | 写 |
| `snapshot_post` | 2026-03-16 | 写 |
| `rollback_prepare` | 2026-03-16 | 只读（prepare-only） |
| `gateway_restart` | 2026-03-16 | 写（两段式） |
| `vault_sync` | 2026-03-17 | 写（incremental send） |

全部 8 action 证据见 `docs/records/`。

### 2026.3.13 升级窗口事实

- Pre snapshot：`root-pre-upgrade-2026.3.13-20260318-1530`
- Post snapshot：`root-post-upgrade-2026.3.13-20260318-1615`
- Pre / post vault_sync：均已完成
- Plugin 文件级备份：`/var/lib/openclaw/host-ops-tool-backups/host-ops-tool-pre-upgrade-20260318-1530.tar.gz`
- P0 focused regression：19/19 PASS
- Phase 2 host_ops 升级后回归：8/8 PASS
- Rollback：未触发
- 升级记录：`docs/records/openclaw-2026.3.13-upgrade-activation-2026-03-18.md`

### Docker prerequisite establishment 事实（2026-03-23）

- 方案选型：docker group（`sudo usermod -aG docker openclaw`）
- 选型理由：OpenClaw `sandbox.docker` 设计假定运行用户有权访问 Docker；openclaw 是 nologin 系统用户，攻击面增量有限；支持完整 Docker API（镜像模板库、multi-agent 并发所需）
- Pre snapshot：`root-pre-docker-group-20260323-1456`
- Post snapshot：`root-post-docker-group-20260323-1457`
- Vault sync：已完成
- daemon-reload：已执行
- 验证结果：
  - `sudo -u openclaw docker version`：client + server 正常
  - `sudo -u openclaw docker run --rm hello-world`：Hello from Docker!
  - `openclaw-gateway.service`：active
  - `openclaw-broker.service`：active
  - `id openclaw`：groups 包含 docker
- P5 原始 blocker（Docker 未安装 + openclaw 无 Docker 访问权）：**已全部解决**

## 当前真实边界

| 事项 | 状态 |
|------|------|
| Docker Engine | **已安装并运行** — Docker 28.2.2, `docker.service` active, `docker.socket` active |
| `openclaw` Docker 访问 | **已建立** — `openclaw` 在 `docker` 组，`docker version` / `docker run hello-world` 均已验证通过 |
| 升级后 capability probe P5 | **PASS** — Docker 28.2.2 active, openclaw 在 docker 组, 完整 API 访问 |
| Capability probe P2 | **Go** — provenance 警告为信息性, plugins.allow 已 pin trust |
| Capability probe P1 | **Caution** — sessions_yield 不存在于当前版本, 非前置, 不阻塞 |
| Capability probe P4 | **Go** — 含 sandbox.docker 的 candidate validate passed |
| Capability probe P3 | **Caution** — 配置结构正确, 待 live spawn 验证 |
| Phase 3 (Docker sandbox / task-runner) | **operational** — 端到端验证通过：sessions_spawn → 容器内 git clone + 文件生成 → 结果回传飞书 |
| Phase 3+ (full image / per-task isolation / prune) | **repo-side artifacts ready** — Dockerfile.full 已构建，网络检查 4/4 PASS，待 Dockerfile UID 修复后重建镜像 |
| Phase 4 (ACP Claude Code 执行链) | **方案已修正** — 容器是工具沙箱，不运行 LLM 进程；Claude Code 通过 ACP 在宿主机运行。下一步：验证 ACP session spawn + sandbox routing probe |
| Phase 5 (LLM gateway / token 最小化) | 未开始 |
| Phase 6 (备份扩展 / 长期收口) | 未开始 |
| Scrapling 接入 | 未开始 |

## 当前下一步

**Phase 3 基础部署已完成（2026-03-23）。** 全部验证通过：

- task-runner 基线镜像：`openclaw-task-claude:2026-03-v3` (构建完成)
- Docker network：`openclaw-task-net` (创建完成)
- openclaw.json：task-runner agent 配置已部署（sandbox.docker, workspaceAccess=rw）
- 默认模型：已切换为 `custom-api-deepseek-com/deepseek-chat`
- workspace-task-runner：已创建
- workspace-main 控制文件：已更新为 Phase 3 operational 状态并发布
- sessions_spawn("task-runner")：验证通过
- 容器内 exec/写入：验证通过（/workspace/repo 可写）
- 首次真实任务执行：通过（系统信息收集 + 文件创建）
- Post snapshot：`root-post-phase3-complete-20260323-1847`
- Vault sync：已完成

当前可进入 Phase 3 日常使用阶段。后续方向：
1. 通过飞书给 main agent 发送工程任务，自动路由到 task-runner
2. 按需构建更多镜像模板（Codex 镜像、带 Node.js 的镜像等）
3. Phase 4：ACP Claude Code session（宿主机进程 + sandbox routing probe）

Probe 记录：`docs/records/post-upgrade-capability-probe-rerun-2026-03-23.md`

## 当前执行器状态

- **Claude Code (claude-opus-4-6)** 是当前主执行者，用于 repo-side 和 live-side 工作。
- **Codex** 暂不用于 live-side 操作，保留 repo-side 文档/脚本辅助能力。详见 `.codex/config.toml` 注释。
- `CLAUDE.md` 是 repo 级协作规则入口。

## 已知非阻塞观察项

- 权威脚本 `vault-backup-root-btrfs` 检查的是 `openclaw.service`，而历史文档中曾写 `openclaw-gateway.service`。属于脚本/文档命名漂移，不影响 vault_sync 已收口的结论。
- Broker 不会随 gateway 自动启动，需 operator 手动 `systemctl start openclaw-broker.service`（2026-03-18 升级窗口发现）。
- Plugin provenance 警告出现但不阻塞功能（P1）。
- OpenClaw log file size cap reached（P1）。

## 已发现并修复的 recurring issues

### publish-workspace-main.sh 权限问题（多次发生）
- **现象**：publish 后 gateway 报 EACCES: permission denied, mkdir `.openclaw`
- **原因**：publish 脚本以 root/nick 运行，生成文件属 root:root 或 nick:nick，gateway 以 openclaw 运行
- **修复**：publish 脚本已添加 auto-chown（`chown -R openclaw:openclaw`）
- **验证**：publish 后检查 `ls -la /var/lib/openclaw/.openclaw/workspace-main/`

### 容器 UID 不匹配（"I have no name!"）
- **现象**：`docker exec -it` 进容器后显示 "I have no name!"，/home/runner permission denied
- **原因**：Dockerfile 的 runner 用户 UID 与 openclaw 用户 UID (997) 不匹配
- **修复**：Dockerfile 改为 `useradd --uid 997 --gid 984`，需重建镜像
- **验证**：`docker exec -it <container> id` 应显示 `uid=997(runner) gid=984(runner)`

## 历史记录

Mar 19-22 期间曾探索 "temporary restricted proxy" 路线作为 Docker 访问模型，
两次 feasibility execution 均在 proxy start 前 hard-stop（hello-world image missing / artifact alignment）。
经评估后改用 docker group 方案，于 2026-03-23 完成。
相关历史文档已归档至 `docs/archive/planning/phase3-stall/` 和 `docs/archive/records/phase3-stall/`。

## 关键参考

- 权威 SOP：`docs/host-sop.md`
- 架构设计：`docs/design-v3.md`
- 文档地图：`docs/map.md`
- 证据索引：`docs/records/README.md`
- Runbooks：`docs/runbooks/`
- Execution packs：`docs/execution-packs/`
