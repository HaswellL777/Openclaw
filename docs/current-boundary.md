# OpenClaw 当前真实边界

> 更新日期：2026-03-25（维护窗口后全量更新）
> 基线版本：**OpenClaw 2026.3.23-2**（2026-03-25 从 2026.3.13 升级完成）
> 阶段：**Phase 3+ operational, Phase 4 配置已部署待验证**

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
| Phase 3 端到端验证 | 完成 | 2026-03-24 |
| Phase 3+ image upgrade (v3-full + Scrapling) | 完成 | 2026-03-25 |
| **OpenClaw 版本升级 (2026.3.13 → 2026.3.23-2)** | **完成** | **2026-03-25** |
| **vLLM 关停 + SecureBoot 修复** | **完成** | **2026-03-25** |
| **Hook 清理 (tool-audit-probe)** | **完成** | **2026-03-25** |
| **长期任务配置 (scope:shared + timeout)** | **已部署** | **2026-03-25** |
| **ACP 配置 (acp block + claude-engineer agent)** | **已部署，待验证** | **2026-03-25** |
| **Knowledge repos (LabClaw + autoresearch)** | **已 clone + mount 可见** | **2026-03-25** |
| **workspace-main publish (MEMORY.md + skills)** | **已发布** | **2026-03-25** |
| **design-v3 清理 (§5.5 ABANDONED + ACP 修正)** | **完成** | **2026-03-25** |
| **Skills 体系扩展 (6 task-runner + 1 main)** | **模板已发布** | **2026-03-25** |

### 2026-03-25 维护窗口事实

**Pre snapshot**: `root-pre-maintenance-20260325-HHMM`
**Post snapshot**: `root-post-maintenance-20260325-1558`

**升级路径**:
- 升级方式：`cd /opt/openclaw && sudo npm install --omit=dev openclaw@2026.3.23-2`（SOP §13.5.3）
- 注意：`sudo npm i -g` 是**错误方式**（装到了 `/usr/lib/node_modules/`，不影响 `/opt/openclaw/`）
- 已清理错误安装：`sudo npm uninstall -g openclaw`
- `/usr/local/bin/openclaw` 是 symlink → `/opt/openclaw/node_modules/.bin/openclaw`

**vLLM 关停**:
- 服务名：`vllm-audit.service`（不是 `vllm.service`）
- 根因：SecureBoot 启用 → 拒绝加载未签名 NVIDIA DKMS 模块 → vLLM 崩溃循环 278+ 次
- 修复：BIOS 关闭 SecureBoot → nvidia.ko 正常加载 → `nvidia-smi` 正常
- vllm-audit.service：stopped + disabled
- GPU：RTX 5060 Ti 16GB 完全释放（15MiB/16311MiB）

**飞书插件**:
- 尝试切换到飞书官方插件 `@larksuiteoapi/feishu-openclaw-plugin` → 失败（`Cannot find module 'openclaw/plugin-sdk'`，extensions 目录的模块解析无法找到 OpenClaw SDK）
- 回退到 bundled feishu 插件（从备份恢复）→ 成功
- 飞书 WebSocket 连接正常，消息收发正常
- 官方插件集成需要后续解决 SDK 解析问题（可能需要 symlink 或不同安装方式）

**配置变更（已部署到 /etc/openclaw/openclaw.json）**:
- 删除 `hooks` 块（tool-audit-probe 测试残留）
- `plugins.allow`: `["feishu", "host-ops-tool"]`（移除 tool-audit-plugin）
- 添加 `acp` 顶级块（enabled, maxConcurrentSessions=2, ttl=60min）
- `subagents`: runTimeoutSeconds=14400, archiveAfterMinutes=1440
- `agents.defaults.sandbox.docker`: image/network/readOnlyRoot/tmpfs（**必须在 defaults 级别设置**）
- `sandbox.prune`: idleHours=24, maxAgeDays=7
- task-runner `scope`: session → shared
- 添加 `claude-engineer` agent（ACP runtime）
- 注意：`acp.runtime.permissionMode` 和 `sandbox.docker.gpus` 被 config schema 拒绝，已移除
- **关键发现：scope=shared 时 per-agent docker 配置被忽略**（源码 `params.scope === "shared" ? void 0 : params.agentDocker`），必须在 `agents.defaults.sandbox.docker` 设置镜像

**环境变量（已追加到 /etc/openclaw/openclaw.env）**:
- `ANTHROPIC_BASE_URL=https://new.motchat.com`
- `ANTHROPIC_API_KEY=<motchat-key>`

**目录创建**:
- `/var/lib/openclaw/.openclaw/workspace-claude-engineer/`（openclaw:openclaw）
- `/var/lib/openclaw/task-workspaces/`（openclaw:openclaw）
- `/var/lib/openclaw/.claude/settings.json`（全权限 allow）

**Docker image 重建**:
- `openclaw-task-claude:2026-03-v3-full`：重建成功（含 Scrapling 0.4.2）
- UID 验证：uid=997(runner) gid=984(runner) ✅

## 当前真实边界

| 事项 | 状态 |
|------|------|
| OpenClaw 版本 | **2026.3.23-2** (7ffe7e4) — 升级自 2026.3.13 |
| Gateway | **active (running)** — ws://127.0.0.1:17777 |
| Broker | **active (running)** — Unix socket |
| 飞书 | **连接正常** — WebSocket, bundled feishu plugin |
| host-ops-tool | **已加载** — provenance 警告为信息性 |
| GPU | **可用** — RTX 5060 Ti 16GB, nvidia-smi 正常, vLLM 已停 |
| vLLM | **stopped + disabled** — vllm-audit.service |
| SecureBoot | **disabled** — NVIDIA DKMS 模块正常加载 |
| task-runner scope | **shared** — 容器跨 session 共享 |
| task-runner image | **v3-full** — 含 Scrapling 0.4.2 |
| ACP 配置 | **已部署，待验证** — acp.enabled=true, claude-engineer agent 已定义 |
| Knowledge repos | **LabClaw + autoresearch 已 clone** — `/workspace/knowledge/` 可见 |
| Memory | **MEMORY.md 已发布到 live workspace** |
| Skills | **7 个 skill 已发布** — task-delegation(main) + coding/testing/research/report/scrapling/autoresearch(task-runner 模板) |
| 长期任务 | **配置已部署** — runTimeout=4h, archive=24h, prune idle=24h/age=7d |

## 待验证项

1. ~~Shared scope~~: ✅ 通过（文件跨 session 可见）
2. ~~Broker~~: ✅ 通过（gateway_health action 成功）
3. ~~Knowledge~~: ✅ 通过（LabClaw + autoresearch 目录可见）
4. ~~Scrapling~~: ✅ 通过（v0.4.2）
5. ~~正确镜像~~: ✅ 通过（`openclaw-task-claude:2026-03-v3-full`）
6. Memory: ⚠️ agent 写入 health state 而非 MEMORY.md（需调查 memory-core 行为）
7. ACP claude-engineer: ❌ 未通过（"not allowed by ACP policy"——需进一步调试 ACP core 配置）

## 待解决

- **飞书官方插件**: `@larksuiteoapi/feishu-openclaw-plugin` 需要 `openclaw/plugin-sdk` 模块解析，从 extensions 目录加载失败。需要研究 symlink 方案或其他安装方式
- **GPU 透传**: `sandbox.docker.gpus` 不被 config schema 识别。需要通过 Docker daemon 默认 runtime 或其他方式实现
- **日志文件大小**: `log file size cap reached`，需要轮转 `/var/log/openclaw/openclaw.log`
- **Vault sync**: 维护窗口后的 vault sync 尚未执行

## 当前下一步

1. 执行上述 5 项验证
2. Vault sync
3. 飞书官方插件 SDK 解析问题研究
4. GPU 透传替代方案
5. 日志轮转

## 已知非阻塞观察项

- Plugin provenance 警告（host-ops-tool）：信息性，不影响功能
- doctor 报告 28 个 orphan transcript files：可清理，不紧急
- Memory search 无 embedding provider：语义搜索不可用，但文件级记忆正常
- doctor 报告 gateway.mode unset：doctor 读取的是 state 目录配置，不是 `/etc/openclaw/openclaw.json`

## 已发现并修复的 recurring issues

### publish-workspace-main.sh 权限问题（多次发生）
- **修复**：publish 脚本已添加 auto-chown

### 容器 UID 不匹配（"I have no name!"）
- **修复**：Dockerfile 改为 `useradd --uid 997 --gid 984`

### OpenClaw 升级路径错误（2026-03-25 发现）
- **现象**：`sudo npm i -g openclaw@2026.3.23-2` 后版本仍为 2026.3.13
- **原因**：全局 npm 装到 `/usr/lib/node_modules/`，但 production 在 `/opt/openclaw/`
- **正确做法**：`cd /opt/openclaw && sudo npm install --omit=dev openclaw@<version>`（SOP §13.5.3）
- **修复**：`sudo npm uninstall -g openclaw` 清理 + 正确路径安装

### vLLM 服务名混淆
- **实际名称**：`vllm-audit.service`（不是 `vllm.service`）
- **记忆已更新**

## 关键参考

- 权威 SOP：`docs/host-sop.md`
- 架构设计：`docs/design-v3.md`
- 文档地图：`docs/map.md`
- 证据索引：`docs/records/README.md`
- 维护窗口执行包：`docs/execution-packs/execution-pack-phase4-maintenance.md`
- 升级评估：`docs/planning/openclaw-upgrade-3.23-evaluation.md`
