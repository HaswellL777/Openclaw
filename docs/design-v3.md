# OpenClaw 多 Agent + Claude Code 协作体系设计稿 v3.1

> 初版编写日期：2026-03-07
> 本次修订日期：2026-03-11（Phase 1B 退出条件全部满足）
> 适用宿主机：当前单机 Ubuntu 24.04 LTS / Btrfs / systemd / OpenClaw 2026.3.2 基线
> 上游输入：`openclaw-host-sop-2026-03-06.md`、`1.md`、`openclaw-design-v2-2026-03-07.md`、本轮 Phase 1A 实际落地结果、Phase 1B 开发仓候选产物
> 文档定位：**可实施规格稿 + 落地状态稿**，用于后续继续开发、验证、回滚、审计与发布

---

## 0. 文档结论先行

截至 2026-03-11，本设计稿 v3.1 的状态应表述为：

1. **当前真实落地阶段是 Phase 1（Phase 1A + Phase 1B 均已完成），Phase 2 尚未开始。**
2. **主控制面仍在宿主机，不容器化。**
3. **`main` agent 已在现网落地（落地起点属于 Phase 1A：main bootstrap only；当前宿主机整体阶段已到 Phase 1 完成）。**
4. **`workspace-main` 已实际发布到 `/var/lib/openclaw/.openclaw/workspace-main/`，并已成为 `main` 的 runtime workspace。**
5. **`main` 当前已经具备 `read / write / edit / sessions_*` 基础控制面工具，但仍无 `exec`、无 `elevated`、无 direct host mutation。**
6. **`main` 的 per-agent allowlist 与全局 `tools.profile` 不可并存；当使用 per-agent allow/deny 时，不再保留全局 `tools.profile`。**
7. **Claude Code CLI 已正式纳入体系，但当前只完成了角色 A：`nick` 用户开发工具这一侧的实际可用落地。**
8. **task-runner / Docker sandbox / host-ops broker 仍是后续阶段目标，尚未进入生产执行链。**
9. **任何宿主机副作用仍必须坚持“快照 → 变更 → 健康检查 → post 快照 → Vault 入库”的纪律。**
10. **`/var/lib/openclaw` 已是独立 Btrfs 子卷，因此不在 root snapshot 保护范围内；`workspace-main` 必须被视为可重复发布产物，而不是依赖 root snapshot 恢复的长期真相源。**
11. **本轮实际落地过程中，曾出现 `main` 工具集被顶层 `tools.profile = messaging` 覆盖的问题；该问题已通过移除顶层 `tools.profile` 修复。**
12. **默认主模型已从 `motchat-claude-4-6/claude-opus-4-6` 切换到 `motchat-gpt-max/gpt-5.4`；当前把 g54 视为更稳妥的主控制面默认值，但不把“Claude 4.6 一定是卡顿根因”写成已证事实。**
13. **Claude Code 容器内执行链、只读 `host_ops`、正式 broker 与 wrapper 仍属于后续阶段目标；除非特别注明”已验证”，否则不得写成当前事实。**
14. **Phase 1B 控制面收口已完成（2026-03-11）：`workspace-main-template/` 已建立并提交；`scripts/publish-workspace-main.sh`、`scripts/publish-sop.sh`、`scripts/check-workspace-main.sh` 已实现；`docs/runtime-allowlist-backup-draft.md` 已升级为设计定稿候选（design candidate）；脚本化发布链已于 2026-03-11 首次用于 live target 并校验通过。**
15. **Phase 1B 退出条件与 Phase 2 进入门槛已正式定义（2026-03-10，见 §7）；控制面备份脚本实现从 Phase 1B 重新归入 Phase 6。**
16. **Phase 1B 退出条件已于 2026-03-11 全部满足：首次现网脚本化发布已完成并校验通过。Phase 2 尚未开始。**

---

## 1. 设计目标与非目标

### 1.1 设计目标

本体系的目标不是“让 OpenClaw 在宿主机上拥有更大权限”，而是：

- 让 **main agent** 成为宿主机控制面与人机交互入口；
- 让 **task-runner** 成为受限、可丢弃、按任务实例化的执行面；
- 让 **Claude Code CLI** 成为：
  - `nick` 用户的主要开发辅助工具；
  - 任务容器内的代码编辑、测试、重构执行器；
- 让 **宿主机变更链** 保持：
  - 可审计；
  - 可快照；
  - 可回滚；
  - 可最小授权；
- 让 **SOP** 成为 OpenClaw 与 Claude Code 的共同事实源；
- 让整套方案支持逐步扩展，而不是一开始把全部高风险能力一次性打开。

### 1.2 非目标

本设计**不追求**：

- 让主 agent 直接拥有宿主机 `exec + elevated`；
- 让 Docker 容器内 Claude Code 直接操作 `/etc/openclaw`、`/opt/openclaw`、systemd、Vault；
- 让 OpenClaw 在当前阶段直接依赖 ACP Claude Code runtime 解决容器内工程执行；
- 让 OpenClaw 子 agent 网络状 peer-to-peer 协作成为核心路径；
- 让容器内持有长期宿主机密钥或长期 root 权限。

---

## 2. 不可突破的宿主机基线（来自现有 SOP）

以下约束不是建议，而是 **v3.1 的硬约束**。

### 2.1 路径边界

- `/opt/openclaw`：程序代码，仅 root 可写；
- `/etc/openclaw/openclaw.json`：当前 system gateway 的唯一生效配置源；
- `/etc/openclaw/openclaw.env`：长期敏感凭证，不给 `nick` 直接读；
- `/var/lib/openclaw`：OpenClaw 运行态数据，**独立 Btrfs 子卷**；
- `/var/log/openclaw`：日志目录；
- `/srv/openclaw-control/`：原设计建议的权威控制仓库根（当前尚未独立运作，权威文档实际编辑入口在开发仓）；
- `~/projects/openclaw-dev/`：开发仓库；
- `/var/lib/openclaw/.openclaw/workspace-main/`：`main` agent 的 runtime published workspace。

特别说明：

- `/var/lib/openclaw` 因为是独立子卷，**不会被根 `/` 的只读快照递归覆盖**；
- 因此 `workspace-main`、extensions、部分 runtime state 不在 root snapshot 恢复范围内；
- `workspace-main` 必须被视为 **publish output / reproducible artifact**，而不是根快照可恢复的长期真相源。

### 2.2 运行身份

- `openclaw`：system user，`nologin`，仅用于后台 gateway；
- `nick`：管理员与图形远程桌面 / SSH 的操作用户。

### 2.3 当前 systemd 安全边界

现有 `openclaw-gateway.service` 已启用只读系统保护、禁止新增特权、限制可写目录等约束；本设计不得通过“为了方便开发”破坏这些约束。

### 2.4 变更纪律

所有宿主机状态变更必须遵循：

1. 变更前只读快照  
2. 变更  
3. 健康检查  
4. 变更后只读快照  
5. Vault 入库

### 2.4.1 快照边界补充

任何首次创建或修改 `/var/lib/openclaw/.openclaw/workspace-main` 的动作，都属于 host-side write。

因此：

1. pre-change snapshot 必须发生在第一次 host-side write 之前；
2. root snapshot 保护的是根系统变更；
3. `workspace-main` 的恢复主要依赖重新发布，而不是依赖 root snapshot 回滚。

### 2.5 已验证事实

- OpenClaw `before_tool_call` 在当前版本上已验证可触发，但在本机现状中仍应被视为**软门控 / 审计入口**，而不是唯一硬阻断点；
- 宿主机已部署 vLLM 审计服务，监听 `127.0.0.1:8000`；
- `nick` 账号历史上误运行 user-level gateway 曾造成双 gateway 事故，因此 **Claude Code CLI 的开发工作只能帮助构建 OpenClaw，不得替代 system-level gateway 运行模型**。

---

## 3. 外部事实边界（基于已核实文档）

以下是 v3.1 采用的外部事实边界。

### 3.1 OpenClaw agent workspace

- workspace 是 agent 的 home，也是文件工具与 workspace 上下文的默认目录；
- workspace **不是硬沙箱**；
- 绝对路径若未开启 sandbox，仍可触达宿主机其他位置；
- 当启用 sandbox 且 `workspaceAccess != "rw"` 时，工具实际工作于 sandbox workspace，而非宿主机原始 workspace。

### 3.2 OpenClaw sandbox 关键语义

- `workspaceAccess` 有 `none | ro | rw`；
- `scope` 有 `session | agent | shared`；
- Docker 默认 `network: "none"`；
- 若任务需要网络，必须显式切换到桥接网络或自定义桥接网络；
- `host` 网络被阻止；
- 额外宿主机目录挂载通过 `docker.binds` 完成。

### 3.3 OpenClaw subagents

- 默认不允许子 agent 再生子 agent（`maxSpawnDepth: 1`）；
- 开启 `maxSpawnDepth: 2` 后，允许 main → orchestrator → worker 这一级模式；
- 最大支持到 5，但官方明确说 **depth 2 对绝大多数场景最合适**；
- 子 agent 默认不带 session tools；
- depth 1 orchestrator 在 `maxSpawnDepth >= 2` 时才会拿到 `sessions_spawn` 等少量编排工具；
- 子 agent 注入上下文默认只有 `AGENTS.md + TOOLS.md`，**不会自动注入** `SOUL.md / IDENTITY.md / USER.md / HEARTBEAT.md / BOOTSTRAP.md`；
- 子 agent 的 auth 以目标 agent 的 auth 为主，但 **主 agent auth 会作为 fallback 合并**；真正完全隔离的 per-agent 凭证域当前并不支持。

### 3.4 OpenClaw ACP 限制

- 若 requester session 本身是 sandboxed，则 `runtime: "acp"` 的 spawn 会被阻止；
- `runtime: "acp"` 当前运行在 host runtime，不在 OpenClaw sandbox 内；
- 因此本设计不采用“从 sandbox 里再拉 ACP Claude Code”作为主路径。

### 3.5 Claude Code hooks

- hooks 支持 command、HTTP、prompt 等形式；
- `PreToolUse` 可以决定 allow / deny / ask，并可改写输入；
- **command hook** 通过退出码控制：
  - `exit 0`：放行；
  - `exit 2`：阻断；
  - 其他退出码：视为非阻断错误，执行继续；
- **HTTP hook** 的错误处理不同：
  - 非 2xx、连接失败、超时，都是**非阻断错误**，执行继续；
  - 若要阻断，必须返回 **2xx + 合法决策 JSON**；
- `PermissionRequest` hook 在 **非交互模式 `-p` 下不会触发**；
- 所以自动化审批必须基于 `PreToolUse`，不能依赖 `PermissionRequest`。

### 3.6 Claude Code 配置与项目根

- `CLAUDE.md` 用于项目级指令；
- `.claude/settings.json` 用于项目共享设置；
- `.claude/settings.local.json` 用于本地非共享设置；
- `.claude/agents/` 是项目 subagents 的官方位置；
- project subagents 适合代码库内的专职 worker；
- Claude Code 支持接入 LLM gateway，但网关必须至少兼容 Anthropic Messages API 等官方规定格式。

### 3.7 Docker 安全边界

- `docker` 组等价于 root 级权限；
- rootless Docker 是用户级 daemon 形态；
- 这意味着：
  - 不应把 `openclaw` 直接加入 `docker` 组当作“普通低权限用户”理解；
  - rootless Docker 更适合交互用户域，而不适合当前 `openclaw` 的 `nologin` system-user 设计。

---

## 4. v3.1 最终架构

### 4.1 控制面与执行面分离

v3.1 继续坚持“控制面 / 执行面分离”，但必须明确区分 **当前已落地状态** 与 **最终目标态**。

#### A. 当前已落地的宿主机控制面（2026-03-07）

运行位置：宿主机

当前已实际落地组件：

1. `openclaw-gateway.service`
2. `main` agent
3. `workspace-main`
4. Btrfs root snapshot / Vault backup 链
5. 现有 LLM provider / upstream proxy 配置
6. vLLM audit service（已存在，但未与最终 Claude Code gate flow 完整闭环）
7. 开发仓库 `~/projects/openclaw-dev/` 与候选配置生成流程

当前实际职责：

- 接收飞书消息；
- 维护长期控制面上下文；
- 读取 SOP / routing / approval 等控制文件；
- 更新 workspace 内控制状态；
- 以最小工具集执行对话与控制面编排；
- 在未来 task-runner 上线前，先承担单代理控制入口角色。

#### B. 当前尚未落地、但仍保留的宿主机控制面目标组件

以下仍属于后续阶段目标，而不是现网已完成能力：

1. `host-ops broker`
2. root-owned wrapper 链
3. 正式 `host_ops` plugin
4. task token / gateway token 下发链
5. `/var/lib/openclaw` 独立 allowlist 备份链（开发仓设计定稿候选 `docs/runtime-allowlist-backup-draft.md` 已结构化，尚未转化为可执行脚本）

#### C. 目标中的任务执行面（尚未落地）

运行位置：OpenClaw Docker sandbox

规划组件：

1. `task-runner` agent
2. 每任务工作目录 `tasks/<task-id>/`
3. 容器内 `claude` / `claude code` CLI
4. 项目级 `.claude/`
5. `gate-check` hook shim
6. 必要的构建 / 测试工具链

说明：

- 执行面仍是 v3.1 的主方向；
- 但截至本次修订，task-runner 尚未上线；
- 因此本设计稿必须把“已落地控制面”和“待落地执行面”写清楚，避免把未来组件误写成当前事实。

### 4.2 统一事件流

#### 4.2.1 当前实际事件流（Phase 1A）

用户  
→ 飞书  
→ `openclaw-gateway.service`  
→ `main` agent  
→ `main` 在 `workspace-main` 内读取 / 写入控制文件  
→ 直接回答用户

当前阶段说明：

- `main` 已能处理控制面问答；
- 已能拒绝直接宿主机 shell；
- 已能列出自己的当前工具集；
- 但还不能把任务正式派发到已上线的 `task-runner`，因为 task-runner 尚未进入生产。

#### 4.2.2 Phase 1A 之后的工程任务目标流

用户  
→ `main`  
→ 生成任务描述 / 选择 runner  
→ `sessions_spawn(agentId="task-runner")`  
→ OpenClaw 启动 sandbox session  
→ runner 进入 `tasks/<task-id>/repo`  
→ 容器内 Claude Code CLI 执行工程任务  
→ 输出写入 `outputs/`  
→ runner 完成并 announce 给 `main`  
→ `main` 汇总并回复用户

#### 4.2.3 涉及宿主机状态变更的最终目标流

用户  
→ `main`  
→ task-runner 在容器内完成分析 / patch / 验证方案  
→ 产出 `host-change-request.json`  
→ `main` 读取请求并判定是否进入批准链  
→ 调用 `host-ops broker`  
→ broker 调 wrapper  
→ pre snapshot → 变更 → 健康检查 → post snapshot → Vault 入库  
→ `main` 汇总结果并回复

#### 4.2.4 当前限制说明

截至本次修订：

- 4.2.2 / 4.2.3 仍是目标路径；
- 当前现网只真正落到了 4.2.1；
- 因此任何文中出现的 `task-runner`、`host-ops broker`、`wrapper`、容器内 Claude Code 执行流，除非特别注明“已验证”，都应视为后续阶段目标。

---

## 5. 组件详细规格

## 5.1 main agent（宿主机主控制代理）

### 5.1.1 角色定位

`main` 是长期存在的宿主机主控制代理。  
截至 2026-03-07，它已经实际落地，但当前仍处于 **Phase 1A / main bootstrap only** 状态。

当前职责：

- 读取 `workspace-main/control/` 下的控制文件；
- 与人通过飞书对话；
- 回答控制面相关问题；
- 维护审批状态、健康状态、任务索引等控制面文件；
- 明确拒绝直接宿主机 shell / elevated / 任意 patch；
- 为后续 `task-runner` / broker 接入提供稳定入口。

当前不做的事：

- 不直接执行宿主机 shell；
- 不直接修改 `/etc/openclaw`；
- 不直接调用未来的 host-ops 写操作链；
- 不把自己当成工程任务执行器。

### 5.1.2 工具权限策略

当前现网实装结果：

- allow：
  - `read`
  - `write`
  - `edit`
  - `sessions_list`
  - `sessions_history`
  - `sessions_send`
  - `sessions_spawn`
  - `session_status`

- deny：
  - `exec`
  - `process`
  - `apply_patch`
  - `elevated`

补充说明：

- 初次落地后，曾因顶层 `tools.profile = "messaging"` 存在，导致 `main` 实际只拿到 session 类工具；
- 该问题已通过移除顶层 `tools.profile` 修复；
- 因此 v3.1 后续规范中，应明确禁止再保留会覆盖 per-agent `tools.allow` 的全局 profile 配置，除非其优先级与行为已被重新验证。

### 5.1.3 subagent 策略

建议：

- `subagents.allowAgents = ["task-runner"]`
- 默认不对 `main` 开放大量跨 agent target
- `maxSpawnDepth = 2`

解释：

- `main` 只允许把任务交给已知 `task-runner`；
- 不允许 `main` 随意把任务投递到未来未经审计的新 agent；
- OpenClaw 侧深度只保留为：
  - depth 0：`main`
  - depth 1：`task-runner`
- 任务内更细分的 `coder / tester / reviewer / doc-writer` 角色，由 **Claude Code project subagents** 负责，而不是再扩 OpenClaw 深度。

### 5.1.4 workspace 结构

建议目录：

```text
/var/lib/openclaw/.openclaw/workspace-main/
├── AGENTS.md
├── SOUL.md
├── TOOLS.md
├── IDENTITY.md
├── USER.md
├── HEARTBEAT.md
├── BOOT.md                  # 可选，若后续启用内部 boot 流
├── MEMORY.md                # 可选，仅主私有会话长期记忆
├── memory/
│   └── YYYY-MM-DD.md
├── skills/
│   ├── host-sop/
│   │   └── SKILL.md
│   ├── routing/
│   │   └── SKILL.md
│   ├── approvals/
│   │   └── SKILL.md
│   └── broker/
│       └── SKILL.md
└── control/
    ├── SOP.md
    ├── routing-policy.md
    ├── approval-policy.md
    ├── allowed-workers.md
    ├── host-ops-api.md
    ├── state/
    │   ├── pending-approvals.json
    │   ├── last-health.md
    │   ├── last-sop-hash.txt
    │   └── last-task-index.json
    └── runbooks/
        ├── openclaw-config-change.md
        ├── gateway-restart.md
        └── rollback.md
```

补充约束：

- `workspace-main` 当前已实际发布到 `/var/lib/openclaw/.openclaw/workspace-main/`；
- 它是 runtime published artifact；
- 它不应被当作长期权威文档源；
- 其内容应来自权威控制仓库和 / 或开发仓库的 publish 流；
- root snapshot 不负责恢复它；
- 开发仓中已建立 `workspace-main-template/` 目录作为发布源模板（2026-03-09）。

### 5.1.5 main 的规则文件写法要求

- **强约束写进 `AGENTS.md`**：
  - 目标优先级；
  - 不得直接修改宿主机；
  - 必须引用 SOP；
  - 什么时候 spawn `task-runner`；
  - 什么时候走 broker；
- **工具约定写进 `TOOLS.md`**：
  - 何时读 `control/`；
  - 何时查 pending approvals；
  - 何时调用 `host_ops`；
- `SOUL.md` / `IDENTITY.md` 只负责风格与身份，不承载关键安全逻辑。

---

## 5.2 task-runner（OpenClaw sandbox 内任务代理）

### 5.2.1 角色定位

`task-runner` 是**一次任务一容器**的执行代理。它的唯一目的，是在受限环境中完成工程工作并提交结构化结果。

### 5.2.2 OpenClaw 侧安全策略

建议：

```json5
{
  "tools": {
    "allow": ["read", "write", "edit", "apply_patch", "exec", "process"],
    "deny": ["sessions_spawn", "elevated"],
    "elevated": { "enabled": false }
  },
  "sandbox": {
    "mode": "all",
    "scope": "session",
    "workspaceAccess": "none",
    "docker": {
      "image": "openclaw-task-claude:2026-03-v3",
      "network": "openclaw-task-net"
    }
  }
}
```

### 5.2.3 为什么从 `workspaceAccess: "rw"` 改为 `none`

原因：

- OpenClaw 官方明确指出 workspace 是默认 cwd，不是硬沙箱；
- runner 若对整块 workspace 拥有 `rw`，会污染长期状态与 agent 记忆；
- task-runner 需要的不是“长期 workspace 可写”，而是“当前任务 repo / outputs 可写”。

因此 v3.1 的策略是：

- OpenClaw sandbox 对 agent workspace 采用 `none`；
- 所有任务所需文件，显式落入 per-task 目录；
- 宿主机向 sandbox 提供的内容，只通过任务目录、只通过发布脚本、只通过 bind / mount 进入。

### 5.2.4 task-runner workspace 与任务目录

建议：

```text
/var/lib/openclaw/.openclaw/workspace-task-runner/
├── AGENTS.md
├── TOOLS.md
├── control/
│   ├── runner-policy.md
│   └── artifact-contract.md
└── tasks/
    └── <task-id>/
        ├── repo/
        │   ├── .claude/
        │   │   ├── settings.json
        │   │   ├── settings.local.json   # 可选，运行时生成，不入库
        │   │   ├── agents/
        │   │   │   ├── coder.md
        │   │   │   ├── tester.md
        │   │   │   ├── reviewer.md
        │   │   │   └── doc-writer.md
        │   │   └── hooks/
        │   │       └── gate-check.sh
        │   ├── CLAUDE.md
        │   ├── docs/
        │   │   └── host-sop.md
        │   ├── src/
        │   ├── tests/
        │   └── ...
        └── outputs/
            ├── plan.md
            ├── summary.md
            ├── diff.patch
            ├── changed-files.json
            ├── test.log
            ├── lint.log
            ├── gate-events.jsonl
            ├── claude-transcript.md
            ├── summary.json
            └── host-change-request.json
```

### 5.2.5 runner 的上下文设计

关键点：

- OpenClaw 子 agent 稳定注入的只有 `AGENTS.md + TOOLS.md`；
- 因此 runner 最关键的执行规则必须放在这两个文件；
- 不要把安全假设写在 `SOUL.md` / `USER.md` 里；
- `repo/CLAUDE.md` 和 `.claude/agents/` 则供容器内 Claude Code 使用。

### 5.2.6 runner 的网络需求

runner 只应访问：

- 宿主机上暴露给任务容器的 **LLM gateway**；
- 宿主机上暴露给任务容器的 **gate shim / HTTP endpoint**（仅在未来必要时）；
- 必要的软件镜像源 / 依赖源（若该任务镜像未预装完全部依赖）；
- 其他出站默认拒绝。

建议使用自定义 bridge 网络 `openclaw-task-net`，配合白名单出站规则，而不是 `host` 网络。

---

## 5.3 Claude Code CLI：双角色纳入体系

v3.1 继续把 Claude Code CLI 分成两个角色，但必须明确写出：**当前只完成了角色 A 的实际落地**。

### 5.3.1 角色 A：`nick` 用户的开发工具（已落地）

用途：

- 开发 broker、plugin、publish scripts、OpenClaw 配置与 workspace 文件；
- 审查设计、生成测试脚本、编写部署脚本；
- 在 `~/projects/openclaw-dev/` 中进行版本化开发。

当前实际状态：

- Claude Code CLI 已安装于 `nick` 用户域；
- 路径：`~/.local/bin/claude`
- 已安装版本：`2.1.58`
- 本机安装过程中，直接使用 `socks5h://127.0.0.1:7890` 作为 `ALL_PROXY / HTTP_PROXY / HTTPS_PROXY` 会导致 bootstrap 失败；
- 实际可用方案是：
  - `HTTP_PROXY=http://127.0.0.1:7890`
  - `HTTPS_PROXY=http://127.0.0.1:7890`
  - 不使用 `ALL_PROXY=socks5h://...`

当前接入方式：

- 通过 MotChat 中转站接入，而非官方账号直连；
- 实际使用环境变量包括：
  - `ANTHROPIC_BASE_URL=https://new.motchat.com`
  - `ANTHROPIC_AUTH_TOKEN=<token>`
  - `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`
- 这些仅用于 `nick` 开发侧工作流，不进入 system gateway runtime。

规则：

- 安装与认证只在 `nick` 用户域完成；
- 绝不以 `openclaw` 用户登录 Claude Code；
- 绝不让 Claude Code 替代 system-level gateway 常驻运行；
- `~/projects/openclaw-dev/` 是开发仓，不是 system runtime。

建议开发仓库结构：

```text
~/projects/openclaw-dev/
├── CLAUDE.md
├── .claude/
│   ├── settings.json
│   ├── agents/
│   │   ├── config-auditor.md
│   │   ├── plugin-dev.md
│   │   ├── broker-dev.md
│   │   └── test-runner.md
│   └── commands/              # 可选
├── docs/
│   ├── host-sop.md
│   ├── design-v3.md
│   ├── runtime-allowlist-backup-draft.md   # Phase 1B 设计定稿候选
│   └── acceptance-tests.md
├── workspace-main-template/   # Phase 1B：workspace-main 发布源模板
│   ├── AGENTS.md
│   ├── SOUL.md / IDENTITY.md / USER.md / TOOLS.md / HEARTBEAT.md / README.md
│   ├── control/
│   │   ├── SOP.md (placeholder, 由 publish-sop.sh 替换)
│   │   ├── routing-policy.md / approval-policy.md / allowed-workers.md / host-ops-api.md
│   │   ├── state/ (pending-approvals.json, last-health.md, last-sop-hash.txt, last-task-index.json)
│   │   └── runbooks/ (openclaw-config-change.md, gateway-restart.md, rollback.md)
│   ├── skills/ (host-sop, routing, approvals, broker 各含 SKILL.md)
│   └── memory/
├── broker/
├── plugins/
├── scripts/
│   ├── publish-workspace-main.sh   # Phase 1B：workspace 发布脚本
│   ├── publish-sop.sh              # Phase 1B：SOP 发布脚本
│   ├── check-workspace-main.sh     # Phase 1B：结构校验脚本
│   └── preflight-first-live-publish.sh  # Phase 1B：首次 live publish 只读预检
├── examples/
└── tests/
```

### 5.3.2 角色 B：任务容器内的工程执行器（尚未落地）

用途：

- 在 sandbox 容器内处理 repo 级工程任务；
- 通过项目级 `.claude/` 读取任务规则；
- 通过 `PreToolUse` hooks 执行本地 gate；
- 通过 project subagents 细分 coder / tester / reviewer / doc-writer 等角色。

当前状态：

- 该角色仍属于后续 Phase 3+ / 4+；
- 当前尚未进入生产可用状态；
- 不应在文档中写成“已上线”。

### 5.3.3 双角色存在的必要性

因为两个场景风险模型不同：

- `nick` 开发仓：人主导、可交互、可手审；
- 任务容器：代理驱动、可丢弃、需强审计、最小权限。

所以：

- 开发仓里的 Claude Code 解决“构建体系”问题；
- 未来任务容器里的 Claude Code 解决“执行任务”问题；
- 二者不得混成同一个权限域。

---

## 5.4 Claude Code 项目规范（容器内）

### 5.4.1 项目根

Claude Code 必须从：

```text
tasks/<task-id>/repo/
```

启动。

不要默认从：

- `/opt/openclaw`
- `/var/lib/openclaw/.openclaw/workspace-task-runner`
- 其他运行态 workspace 根

直接启动 Claude Code。

### 5.4.2 `CLAUDE.md` 的职责

建议只写：

- 当前任务目标；
- 项目约束；
- 测试 / 构建命令；
- 文件输出契约；
- 何时调用 project subagents；
- 何时生成 `host-change-request.json`；
- 不允许直接修改宿主机。

不要在 `CLAUDE.md` 中嵌入大量长期宿主机事实。长期宿主机事实放 `docs/host-sop.md`，按需由 Claude Code 读取。

### 5.4.3 `.claude/settings.json`

项目共享设置建议至少包含：

- 允许的 hooks；
- 必要环境变量白名单；
- 输出风格与行为约束；
- 必要的 permissions allow / deny；
- project subagents 启用。

### 5.4.4 `.claude/settings.local.json`

仅容器运行时生成，内容包括：

- 临时 token / base URL；
- 本任务的本地参数；
- 不进入版本控制；
- 任务结束后容器销毁。

### 5.4.5 `.claude/agents/`

建议内置：

- `coder.md`
- `tester.md`
- `reviewer.md`
- `doc-writer.md`

原则：

- 单一职责；
- 明确 description；
- 最小工具授权；
- 只服务当前 repo 任务。

---

## 5.5 硬门控：gate shim + vLLM audit

### 5.5.1 v3.1 的核心修正

v2 的核心问题之一，是把“Claude Code HTTP hook 直连 vLLM，然后超时即 fail-closed”写成设计前提。

这在官方语义上并不成立，因为：

- HTTP hook 的非 2xx、连接失败、超时，都是**非阻断错误**；
- 真正的阻断必须依赖：
  - command hook 的 `exit 2`；
  - 或 HTTP hook 返回 2xx + 合法阻断 JSON。

因此 v3.1 的硬门控改为：

```text
Claude Code PreToolUse (command hook)
  -> gate-check.sh
    -> 本地 gate shim
      -> vLLM /v1/chat/completions
      -> 解析决策
    -> 若 deny / 解析失败 / 超时
         exit 2
       否则 exit 0
```

### 5.5.2 组件分工

#### A. `gate-check.sh`

职责：

- 从 Claude Code hook stdin 读取 `tool_name`、`tool_input`、`cwd`、task metadata；
- 标准化为 gate 请求；
- 调用本地 gate shim；
- 根据返回值决定：
  - 放行；
  - 阻断；
  - 改写输入；
- 将事件写入 `outputs/gate-events.jsonl`。

#### B. gate shim（本地小服务或本地命令）

职责：

- 不暴露复杂控制面；
- 只实现：
  - 请求校验；
  - 超时控制；
  - 调用 vLLM；
  - 结构化解析；
  - 输出统一决策格式；
- 若发生内部异常，返回明确 deny，让 `gate-check.sh` 以 `exit 2` fail-closed。

#### C. vLLM 审计模型

职责：

- 仅做审计判断与建议；
- 输出结构化审计意见；
- 不直接控制最终执行；
- deterministic final gate 由 shim 落地。

### 5.5.3 决策格式

建议 gate shim 返回：

```json
{
  "decision": "allow|deny|rewrite",
  "reason": "string",
  "updated_input": {},
  "risk_level": "low|medium|high|critical",
  "policy_hits": ["..."]
}
```

### 5.5.4 审计规则分层

- **L0 deterministic deny**：
  - 访问宿主机关键路径；
  - 直接 `sudo`；
  - 网络访问非白名单；
  - 读取 secrets 文件；
  - 删除大范围目录；
- **L1 deterministic rewrite**：
  - 把危险 Bash 改写成 safer variant；
  - 强制加 `--dry-run`；
- **L2 model advisory**：
  - 分析命令意图；
  - 判断是否偏离任务；
  - 解释风险。

最终放行原则：

- 先 deterministic policy；
- 后 model advisory；
- 解析失败或超时默认 deny。

### 5.5.5 为什么不用 `PermissionRequest` 作为主门控

因为官方明确：

- `PermissionRequest` 在非交互模式 `-p` 下不触发；
- 任务容器执行路径未来很可能会进入半自动 / 自动模式；
- 所以真正的强门控必须落在 `PreToolUse`。

### 5.5.6 OpenClaw plugin 审计仍然保留

v3.1 不是放弃 OpenClaw `before_tool_call`，而是重新定位：

- OpenClaw `before_tool_call`：**外层审计 + 记录 + 额外风控**
- Claude Code `PreToolUse`：**容器内真实执行命令的硬门控**

原因：

OpenClaw 外层工具调用看不到 Claude Code 内部所有真实待执行 payload；Claude Code hook 才能拿到内部真实 Bash / Edit / Write 事件。

---

## 5.6 host-ops broker（宿主机副作用代理）

### 5.6.1 角色定位

broker 是 v3.1 的唯一宿主机副作用执行面。它不是通用 shell，不接受自然语言，也不允许任意命令拼接。

它只接受结构化请求，例如：

- `gateway_health`
- `gateway_restart`
- `validate_openclaw_json_candidate`
- `deploy_openclaw_json_candidate`
- `snapshot_pre`
- `snapshot_post`
- `vault_sync`
- `rollback_prepare`

### 5.6.2 broker 输入契约

建议统一 JSON：

```json
{
  "action": "deploy_openclaw_json_candidate",
  "request_id": "uuid",
  "task_id": "task-...",
  "requested_by": "agent:main",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/openclaw.json",
    "expected_sha256": "..."
  }
}
```

### 5.6.3 broker 安全要求

- Unix socket 或 root-owned local IPC；
- 严格 schema 校验；
- 参数白名单；
- 路径白名单；
- 只调用 root-owned wrapper；
- wrapper 绝不执行自由 shell 拼接；
- 完整日志；
- 失败默认拒绝；
- 支持 request-id 追踪。

### 5.6.4 wrapper 设计原则

每个 wrapper 只做一件事。例如：

- `ocw-validate-openclaw-json`
- `ocw-deploy-openclaw-json`
- `ocw-gateway-restart`
- `ocw-snapshot-pre`
- `ocw-snapshot-post`
- `ocw-vault-sync`

每个 wrapper 内部：

1. 验证输入
2. 验证候选文件 hash
3. 执行操作
4. 返回结构化结果 JSON

### 5.6.5 broker 与 main 的关系

- `main` 不直接拥有 `exec`；
- `main` 调用 `host_ops(...)` 插件工具；
- 插件工具只把结构化请求交给 broker；
- broker 再走 wrapper。

这样主控制面拥有“调用受限操作”的能力，但并不拥有“任意命令执行”的能力。

---

## 5.7 SOP 权威源与发布机制

### 5.7.1 只保留一个权威源

当前权威源：

```text
~/projects/openclaw-dev/docs/host-sop.md
```

未来若 `/srv/openclaw-control/` 独立运作，权威源迁移到该仓库。在此之前，开发仓即为权威编辑入口。

### 5.7.2 双层发布而非 symlink

原因：

OpenClaw 官方说明，sandbox seed copy 只接受常规 in-workspace 文件；解析到 workspace 外部的 symlink / hardlink 会被忽略。

因此 v3.1 采用：

- 权威源：单一仓库中的 SOP
- 发布副本：
  - `workspace-main/control/SOP.md`
  - `tasks/<task-id>/repo/docs/host-sop.md`
  - 开发仓库 `docs/host-sop.md`

### 5.7.3 发布脚本职责

`publish-sop.sh` 至少做：

1. 从权威源复制到目标
2. 写入 SHA256
3. 写入版本号 / 时间戳
4. 若 hash 未变可跳过
5. 记录发布日志

> **2026-03-09 状态**：`scripts/publish-sop.sh` 已在开发仓实现并提交。实际行为符合上述 5 条要求：从 `docs/host-sop.md` 复制到 `TARGET_DIR/control/SOP.md`，附加 SHA256 + 时间戳头，写入 `control/state/last-sop-hash.txt`，hash 相同时跳过。默认 dry-run，拒绝写入生产路径。

### 5.7.4 为什么开发仓库也要有副本

因为：

- `nick` 的 Claude Code 开发仓库需要看 SOP；
- 开发仓库不在 OpenClaw workspace 内；
- 它与运行时副本的同步，也必须通过发布脚本，而不是手工复制。

---

## 5.8 LLM gateway / 上游模型代理

### 5.8.1 角色定位

它是任务容器内 Claude Code 的上游模型出口，用于：

- 藏住长期上游凭证；
- 做统一计量与审计；
- 必要时做路由或限速；
- 为任务容器发放短期 token。

### 5.8.2 设计要求

必须满足 Claude Code 官方对 LLM gateway 的要求：

- 至少兼容 Anthropic Messages API 或其他官方支持格式；
- 正确透传必要 headers；
- 正确处理模型名映射。

### 5.8.3 当前保守策略

在未完成兼容性验证前，v3.1 只把该网关定义为：

- **必须存在的组件**；
- **需要 Phase 4 专项验收**；
- **不把当前 MotChat / Nginx 改写路径直接视为已验证完成**。

### 5.8.4 凭证策略

任务容器内不存长期主密钥，而是：

- 由宿主机 gateway / proxy 维护长期上游凭证；
- 每任务注入短期 task token；
- token 只允许该任务访问必要模型与额度；
- 容器销毁即失效。

---

## 5.9 Docker 方案

### 5.9.1 规范级要求

v3.1 规范层只要求：

- OpenClaw task-runner 使用官方 `sandbox.docker` 配置；
- 任务容器镜像固定、可复现、可审计；
- 网络显式限制；
- 额外挂载最小化；
- root filesystem 默认只读；
- task repo / outputs 明确可写；
- 容器逃逸面最小化。

### 5.9.2 为什么不把 `DOCKER_HOST=tcp://127.0.0.1:2375` 写成规范前提

因为目前已核实的是：

- OpenClaw 官方支持 `sandbox.docker` 配置；
- Docker 默认通过 root-owned Unix socket 暴露；
- `docker` 组是 root 级权限；

但并没有足够证据证明“当前这版 OpenClaw + 受限 socket proxy + `DOCKER_HOST`”已经被完整验证能承载其所有 sandbox 生命周期操作。

因此 v3.1 不写死实现路径，只写：

- **优先目标**：通过受限且可审计的 Docker 接入方式满足 OpenClaw sandbox；
- **必须通过专门 capability probe 后才能落地**。

### 5.9.3 任务网络

建议网络名：

```text
openclaw-task-net
```

出站白名单：

- 宿主机 LLM gateway 端口
- 宿主机 gate shim 端口（如启用 HTTP 备用模式）
- 必要依赖源（可选）
- 其他全部拒绝

### 5.9.4 基线镜像

镜像名建议：

```text
openclaw-task-claude:2026-03-v3
```

镜像内容：

- Claude Code CLI（固定版本）
- git
- bash
- jq
- ripgrep
- Python / Node 等任务需要的最小工具链
- 测试工具
- 非 root 运行用户
- 固定工作目录
- 固定 entrypoint

### 5.9.5 容器写入面

只允许：

- `/workspace/repo`
- `/workspace/outputs`
- 临时目录 `/tmp`

其他根文件系统保持只读。

---

## 5.10 认证与 secrets

### 5.10.1 长期 secrets 的原则

长期 secrets 只应位于宿主机受控路径：

- `/etc/openclaw/openclaw.env`
- 受控 proxy / gateway 本地配置

不得：

- 写入 OpenClaw workspace
- 写入开发仓库
- 写入任务 repo
- bake 进 Docker image

### 5.10.2 task token

每任务容器使用：

- 短期 token
- 最小模型权限
- 最小额度
- 任务结束即失效

### 5.10.3 为什么不指望 OpenClaw 每 agent 完全隔离 auth

因为官方当前明确说明：

- 子 agent auth 以目标 agent 为主；
- main agent auth 仍会作为 fallback 合并；
- fully isolated auth per agent 目前不支持。

所以真正的隔离策略必须依赖：

- task token
- 上游 proxy
- 容器不接触长期 key

---

## 5.11 审计、日志与可回滚性

### 5.11.1 统一 request-id / task-id

整个链路都必须带：

- `task_id`
- `request_id`
- `parent_session_key`
- `agent_id`

### 5.11.2 日志分层

#### OpenClaw 层

- `before_tool_call`
- `after_tool_call`
- spawn / announce / timeout / failure

#### Claude Code 层

- hook 决策日志
- transcript 摘要
- project subagents 结果

#### broker 层

- action 请求
- wrapper 调用结果
- 快照名
- Vault 入库状态

### 5.11.3 回滚要求

凡是修改宿主机配置的动作，必须输出：

- pre snapshot 名称
- post snapshot 名称
- 健康检查结果
- Vault send 结果
- rollback 建议路径

---

## 6. 配置建议（规范草案 + 当前现网状态）

## 6.1 OpenClaw agent 规划

建议最终只保留两个正式 agent：

1. `main`
2. `task-runner`

未来可增加的 agent，只有在完成专门安全审查后才能进入 allowlist。

---

## 6.2 `main` agent 配置草案

### 6.2.1 当前生效版（Phase 1A）

```json5
{
  agents: {
    defaults: {
      model: {
        primary: "motchat-gpt-max/gpt-5.4"
      },
      subagents: {
        maxSpawnDepth: 2,
        maxChildrenPerAgent: 3,
        maxConcurrent: 4,
        runTimeoutSeconds: 3600,
        archiveAfterMinutes: 120
      }
    },
    list: [
      {
        id: "main",
        default: true,
        workspace: "/var/lib/openclaw/.openclaw/workspace-main",
        subagents: { allowAgents: ["task-runner"] },
        tools: {
          allow: [
            "read",
            "write",
            "edit",
            "sessions_list",
            "sessions_history",
            "sessions_send",
            "sessions_spawn",
            "session_status"
          ],
          deny: ["exec", "process", "apply_patch", "elevated"],
          elevated: { enabled: false }
        }
      }
    ]
  }
}
```

并明确：

> 顶层不得再保留 `tools: { profile: "messaging" }`；否则会压制上述 per-agent allowlist。

### 6.2.2 未来扩展版（Phase 1B / 2 以后）

只有在 `host_ops` 插件 / 工具真正部署并通过审计后，才考虑把 `host_ops` 加回 allowlist。

---

## 6.3 `task-runner` agent 配置草案

```json5
{
  agents: {
    list: [
      {
        id: "task-runner",
        workspace: "/var/lib/openclaw/.openclaw/workspace-task-runner",
        tools: {
          allow: ["read", "write", "edit", "apply_patch", "exec", "process"],
          deny: ["sessions_spawn", "elevated"],
          elevated: { enabled: false }
        },
        sandbox: {
          mode: "all",
          scope: "session",
          workspaceAccess: "none",
          docker: {
            image: "openclaw-task-claude:2026-03-v3",
            network: "openclaw-task-net",
            readOnlyRoot: true,
            tmpfs: ["/tmp", "/var/tmp", "/run"]
          }
        }
      }
    ]
  }
}
```

> 注：Docker 接入的底层连通实现必须在 Phase 3 通过 capability probe 验证，不在 v3.1 规格中假定为某个固定 `DOCKER_HOST` 方案。

---

## 6.4 `tools.subagents` 建议

不建议对全局 subagent 开太宽：

```json5
{
  tools: {
    subagents: {
      tools: {
        deny: ["gateway", "cron", "browser", "canvas"]
      }
    }
  }
}
```

---

## 6.5 Claude Code 项目 `.claude/settings.json` 草案

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(python -m pytest *)",
      "Bash(pytest *)",
      "Bash(npm test *)",
      "Bash(npm run lint *)",
      "Read(./**)",
      "Edit(./**)",
      "Write(./outputs/**)"
    ],
    "deny": [
      "Bash(sudo *)",
      "Bash(docker *)",
      "Bash(systemctl *)",
      "Bash(mount *)",
      "Bash(umount *)",
      "Read(/etc/openclaw/**)",
      "Read(/opt/openclaw/**)",
      "Read(/etc/**)",
      "Read(/root/**)",
      "Write(/etc/**)",
      "Write(/opt/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/gate-check.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

> 注：实际允许列表需要按任务镜像的工具链再微调；这里只给出 v3.1 的安全方向。

---

## 6.6 Claude Code 项目 `CLAUDE.md` 骨架

```markdown
# Task Project Rules

## Goal
- 完成当前 task 的代码与文档工作
- 只在本项目根内操作
- 输出必须写入 `outputs/`

## Hard Constraints
- 不得直接操作宿主机
- 不得尝试 sudo/systemctl/docker/mount
- 需要宿主机变更时，生成 `outputs/host-change-request.json`
- 关键宿主机事实以 `docs/host-sop.md` 为准

## Required Outputs
- outputs/plan.md
- outputs/summary.md
- outputs/diff.patch
- outputs/summary.json
- 如涉及宿主机：outputs/host-change-request.json

## Build/Test
- 先读取项目构建与测试命令
- 先小范围验证，再全量验证
- 失败要把日志写入 outputs/
```

---

## 6.7 `nick` 开发仓库的 Claude Code 规则

建议 `~/projects/openclaw-dev/CLAUDE.md` 明确写：

- 你正在开发的是 OpenClaw 宿主机控制链；
- 所有最终落地到 `/etc/openclaw`、`/opt/openclaw`、systemd 的内容都必须产出：
  - 候选文件
  - 部署脚本
  - 回滚脚本
  - 验证步骤
- 不要让 Claude Code 在 `nick` 用户环境里直接“代执行”会改变生产宿主机状态的高风险命令；
- 它的职责是**生成与审查**，最终落地走人的批准或后续 broker 执行链。

---

## 6.8 当前现网状态快照（2026-03-07）

### 6.8.1 已生效配置结论

- `main` 已存在并为默认主 agent；
- `main.workspace = /var/lib/openclaw/.openclaw/workspace-main`；
- `main.tools.allow` 已生效：
  - `read`
  - `write`
  - `edit`
  - `sessions_list`
  - `sessions_history`
  - `sessions_send`
  - `session_status`
  - `sessions_spawn`
- `main.tools.deny` 已生效：
  - `exec`
  - `process`
  - `apply_patch`
  - `elevated`
- 默认主模型当前为 `motchat-gpt-max/gpt-5.4`。

### 6.8.2 已完成快照里程碑

- `root-pre-main-agent-2026-03-07-1804`
- `root-pre-toolfix-2026-03-07-1830`
- `root-post-phase1a-2026-03-07-1911`

### 6.8.3 当前仍未上线的能力

- 正式 `host-ops broker`
- 正式 `host_ops` plugin
- `task-runner`
- Docker sandbox 任务执行面
- 容器内 Claude Code 执行链
- `/var/lib/openclaw` 独立 allowlist 备份链

### 6.8.4 当前经验性运行建议

- 主控制面默认使用 `g54`；
- Claude 4.6 保留作显式切换测试，不恢复为默认；
- 若飞书长时间不回复，优先检查 gateway 日志中的 embedded run timeout / dispatch 状态。

---

## 6.9 运行态备份分层设计

1. **Root system snapshots（继续保留）**
   - `/etc/openclaw`
   - `/opt/openclaw`
   - systemd
   - snapshot / Vault scripts
2. **Control-plane runtime backup（新增设计目标）**
   - `workspace-main/control/state/`
   - `.openclaw/extensions/`
   - `.openclaw/cron/`
   - `/var/lib/openclaw/backup/`
3. **Ephemeral runtime noise（默认不强恢复）**
   - memory
   - canvas
   - 中间产物
   - 高频调试日志

并明确：

> 未来的“运行态备份增强”不等于把 `/var/lib/openclaw` 整体重新塞回 root snapshot，而是建立独立、选择性的控制面备份机制。

---

## 6.10 已观测但未定案的问题

1. Claude 4.6 默认路径在飞书会话中观测到长时间无回复；
2. 日志可见 `embedded run timeout ... timeoutMs=600000`；
3. 切换到 g54 后现象明显缓解；
4. `session-memory` 路径日志显示为 `~/.openclaw/...`，需核实真实落点；
5. 这些问题都应进入独立 follow-up，而不应被误写成“Phase 1A 已全部解决”。

---

## 7. 分阶段实施路径

## Phase 0：开发工具链与控制仓库（已完成）

### 目标

把 Claude Code CLI 正式纳入开发流程，但不碰生产执行面。

### 已完成内容

1. `nick` 用户侧 Claude Code CLI 已安装并可用
2. 开发仓库 `~/projects/openclaw-dev/` 已建立
3. 已建立：
   - `CLAUDE.md`
   - `.claude/settings.json`
   - `.claude/agents/*`
   - `docs/*`
   - `broker/` skeleton
   - `plugins/` skeleton
   - `tests/` / `scripts/`
4. 权威控制源与发布思路已建立
5. repo-local 测试链已存在
6. 未引入第二个 user-level gateway

### 阶段结论

Phase 0 结束后，开发体系已能安全地产生候选配置、脚本和文档，但尚未触碰现网执行面。

---

## Phase 1A：main bootstrap only（已完成）

### 目标

让 `main` 成为稳定的宿主机控制代理，但不接入正式 broker，不接入 Docker task execution。

### 已完成内容

1. 创建并发布 `workspace-main`
2. 更新 `openclaw.json`，加入 `main`
3. 配置：
   - `subagents.allowAgents = ["task-runner"]`
   - `maxSpawnDepth = 2`
   - `maxChildrenPerAgent = 3`
   - `runTimeoutSeconds = 3600`
   - `archiveAfterMinutes = 120`
4. 让 `main` 拥有：
   - `read / write / edit / sessions_*`
5. 保持 deny：
   - `exec`
   - `process`
   - `apply_patch`
   - `elevated`
6. 修复了顶层 `tools.profile = messaging` 对 `main.tools.allow` 的覆盖问题
7. 默认主模型切换到 `motchat-gpt-max/gpt-5.4`
8. 已完成 pre / post 快照与 Vault 入库

### 当前验收结果

- `main` 能对话；
- `main` 能列出当前工具；
- `main` 能拒绝宿主机 shell；
- `main` 的 runtime workspace 已生效；
- 但 `host_ops` 正式链与 task-runner 尚未上线。

---

## Phase 1B：控制面收口与文档 / 发布模型固化（已完成）

### 目标

把 Phase 1A 的实操经验固化成正式控制规范，消除”计划态文档”和”现网事实”之间的漂移。

### 工作内容

1. 更新 SOP
2. 更新 design-v3.1
3. 明确：
   - 权威控制仓库
   - 开发仓
   - runtime published workspace
   - 任务级 repo
4. 固化 publish 流与 candidate config 流
5. 补齐 `workspace-main` 发布 / 校验脚本
6. 决定 `/var/lib/openclaw` 哪些内容纳入独立备份 allowlist

### 当前状态（2026-03-09）

**已完成（开发仓内）：**
- `workspace-main-template/` 目录已建立并提交（25 个文件）
- `scripts/publish-workspace-main.sh` 已实现（默认 dry-run，保留 `control/state/`，自动调用 `publish-sop.sh`）
- `scripts/publish-sop.sh` 已实现（SHA256 + 时间戳头，hash 相同则跳过）
- `scripts/check-workspace-main.sh` 已实现（模板模式 vs 发布产物模式校验）
- `docs/runtime-allowlist-backup-draft.md` 已升级为设计定稿候选（三类分类 + 恢复语义 + 恢复优先级 + 实施约束）
- SOP 与 design-v3 回写 Phase 1B 状态（本次修订）
- `scripts/preflight-first-live-publish.sh` 已实现（只读预检，含 Go/No-Go 判定）
- `docs/runbook-first-live-publish.md` 已增强（Go/No-Go checklist、证据采集要求、preflight 集成）

**尚未完成（Phase 1B 退出所需）：**
- ~~在现网执行首次 `publish-workspace-main.sh --apply --allow-live-target` 正式发布~~ ✅ 已完成（2026-03-11）
- ~~移除 publish 脚本的生产路径 safety guard（需要 `--allow-live-target` flag）~~ ✅ 已实现（2026-03-10，`--allow-live-target` flag + 交互确认 + TTY 检查）

**已重新归入后续阶段：**
- 控制面备份脚本（将 backup draft 转化为可执行脚本）→ Phase 6
- `last-sop-hash.txt` 运行态自动更新集成（cron 触发）→ 后续阶段

### 退出条件（Exit Criteria）

Phase 1B 完成收口需要同时满足以下全部条件：

**已满足：**
1. 文档能完整反映现网 Phase 1A 结果（SOP §0.2、§15 已回写）；
2. 权威源 / 开发仓 / runtime 副本边界不再混淆（四层模型已在 SOP §13.8.3 固化）；
3. `workspace-main-template/` 已建立，publish / check 脚本已实现并通过 dry-run 验证；
4. `/var/lib/openclaw` 备份策略已完成设计定稿候选（`runtime-allowlist-backup-draft.md`）；
5. 文档间无未修复的事实冲突。

**已全部满足：**
6. ~~publish 脚本增加 `--allow-live-target` flag 或等效机制，使其可用于生产路径；~~ ✅ 已实现（2026-03-10）
7. ~~首次通过 `publish-workspace-main.sh --apply --allow-live-target` 将 workspace-main-template 发布到现网 live target~~ ✅ 已完成（2026-03-11）；
8. ~~发布后通过 `check-workspace-main.sh` 校验发布产物结构完整性（published artifact 模式）~~ ✅ 已完成（2026-03-11）。

**明确不作为本阶段退出条件的事项：**
- 控制面备份脚本的编写与部署（设计已完成，实现归 Phase 6）
- `host_ops` broker / wrapper 的部署（归 Phase 2）
- task-runner / Docker sandbox 的任何部署（归 Phase 3+）
- `last-sop-hash.txt` 运行态自动更新集成（publish 脚本已支持手动触发，cron 触发归后续阶段）

### 阶段交付物

| 交付物 | 类型 | 状态 |
|--------|------|------|
| `workspace-main-template/`（25 文件） | 开发仓模板 | ✅ 已提交 |
| `scripts/publish-workspace-main.sh` | 发布脚本 | ✅ 已实现（含 `--allow-live-target`） |
| `scripts/publish-sop.sh` | SOP 发布脚本 | ✅ 已实现（无条件拒绝 live path；live 场景由父脚本 inline 处理） |
| `scripts/check-workspace-main.sh` | 结构校验脚本 | ✅ 已实现（含 SOP hash 交叉校验） |
| `docs/runtime-allowlist-backup-draft.md` | 备份设计稿 | ✅ 设计定稿候选 |
| SOP + design-v3 Phase 1B 状态回写 | 文档同步 | ✅ 已完成 |
| Phase 1B 退出条件 + Phase 2 进入门槛定义 | 阶段边界 | ✅ 已定义 |
| `docs/runbook-first-live-publish.md` | 首次现网发布 Operator Runbook | ✅ 已编写（含 Go/No-Go checklist 与证据采集要求，首轮已执行 2026-03-11） |
| `scripts/preflight-first-live-publish.sh` | 首次 live publish 只读预检脚本 | ✅ 已实现 |
| `docs/execution-pack-first-live-publish.md` | 首次现网发布执行包（分步命令 + 确认点 + 回退速查卡） | ✅ 已编写（执行前准备材料；首轮已执行完成，见 records） |
| `docs/templates/first-live-publish-record-template.md` | 现场记录模板 | ✅ 已编写 |
| `docs/templates/phase1b-live-publish-syncback-template.md` | 发布后文档回写模板 | ✅ 已编写 |
| 首次现网脚本化发布 + 校验 | 现网操作 | ✅ 已完成（2026-03-11） |

---

## Phase 2：host-ops broker 正式落地

### 当前状态（2026-03-11）

**Phase 2 尚未正式启动。** 以下开发仓内准备工作已完成：

- broker 请求/结果 JSON Schema（`broker/schemas/`）
- 8 个 per-action 输入 schema（`broker/schemas/actions/`）
- 8 个 wrapper stub（`broker/wrappers/ocw-*.sh`，仅验证 + echo，不执行 live 操作）
- wrapper 共享验证库（`broker/wrappers/lib/common.sh`，消除 8 个 wrapper 间代码重复）
- 8 对 request/result 测试 fixture + 1 negative test（`examples/broker/`）
- schema / wrapper / fixture 交叉验证脚本（`scripts/validate-broker-schemas.sh`，192 checks pass）
- wrapper stub 运行时测试脚本（`tests/test_broker_schemas.sh`，62 checks pass）
- host-ops broker 协议规格文档（`docs/specs/host-ops-broker-protocol-v1.md`）
- plugin skeleton 已升级为 phase2-prep：request builder、request validator、result validator（`plugins/host-ops-tool/`）
- 聚合验证脚本（`scripts/validate-phase2-prep.sh`）与集成测试（`tests/test_phase2_integration.sh`）
- `workspace-main-template/control/host-ops-api.md` 已对齐 §5.6.2 请求契约
- `workspace-main-template/skills/broker/SKILL.md` 已对齐当前协议契约（消除 operation/parameters/approval_id 漂移）
- 错误分类规格文档（`docs/specs/error-taxonomy-v1.md`，定义 E_*/D_* 错误码与 error/denied 语义）
- 22 组负面测试 fixture + 1 missing-file result + 1 ok-status-mismatch result（`examples/broker/negative/`，覆盖所有 §4 error/denied 类别）
- 协议契约冻结测试（`tests/test_contract_freeze.sh`，冻结 action enum / required fields / property types / ok-status invariant / 跨层一致性）
- `host-ops-api.md` SHA256 示例修正（消除 abc123 占位符，添加 error/denied 区分文档）
- 跨层契约矩阵（`docs/specs/contract-matrix-v1.md`，字段映射 / 镜像关系 / deprecated 名称索引）
- result schema 强化（`additionalProperties: false`、`minLength`、`if/then/else` ok/status 不变量、reserved `error_code` 字段）
- `SKILL.md` SHA256 占位符修正（`abc123...` → proper 64-char hex）
- **Phase 2 部署设计包已完成（2026-03-11）**：
  - 部署布局规格文档（`docs/specs/phase2-broker-deployment-layout.md`，定义目标文件系统布局、权限、systemd unit）
  - 部署 runbook（`docs/runbook-phase2-broker-deployment.md`，含 10 项进入条件、7 项禁止条件、10 阶段部署序列、回滚规程）
  - 执行包（`docs/execution-pack-phase2-broker-deployment.md`，含 15 步分步命令块、人工确认点）
  - 现场记录模板（`docs/templates/phase2-broker-deployment-record-template.md`）
  - 文档回写模板（`docs/templates/phase2-broker-deployment-syncback-template.md`）
  - 只读预检脚本（`scripts/preflight-phase2-broker-deployment.sh`）

现网部署需要 Phase 2 正式启动后按进入门槛逐项执行。部署设计包已就绪供操作员审阅与执行。

### 进入门槛（Entry Gates）

开始 Phase 2 前必须满足以下全部前置条件：

1. **Phase 1B 退出条件全部满足**（见上文 Phase 1B 退出条件 §1–§8）；
2. `main` agent 在现网稳定运行（飞书可达、health check 通过）；
3. `workspace-main` 已至少通过脚本化发布链（`publish-workspace-main.sh --apply`）完成一次端到端发布并校验通过；
4. Phase 1B 收口操作（含首次现网发布）已按 §11.1 通用操作纪律完成 post snapshot 与 Vault 入库；
5. design-v3 Phase 2 工作内容已审阅，broker / wrapper 设计方案已明确。

### 目标

建立唯一宿主机副作用入口。

### 工作内容

1. 实现 broker
2. 实现 root-owned wrappers
3. 部署 Unix socket / 权限边界
4. 部署正式 `host_ops` plugin
5. 新增结构化动作：
   - `validate_openclaw_json_candidate`
   - `deploy_openclaw_json_candidate`
   - `gateway_restart`
   - `snapshot_pre`
   - `snapshot_post`
   - `vault_sync`

### 验收标准

- `main` 仍无宿主机任意 exec；
- broker 能按 schema 拒绝非法输入；
- wrapper 不接受自由路径 / 自由命令；
- 配置变更可完成完整快照链。

---

## Phase 3：Docker sandbox capability probe 与 task-runner 上线

### 目标

把工程执行面从主控制面中剥离出来，正式引入 task-runner。

### 工作内容

1. 整理 Docker Engine
2. capability probe
3. 构建任务镜像
4. 创建 `workspace-task-runner`
5. 更新 `openclaw.json` 加入 `task-runner`
6. 验证 `sessions_spawn("task-runner")`
7. 验证任务目录 bind / 清理

### 验收标准

- `main` 只做控制，不做重执行；
- `task-runner` 在受限容器内完成工程任务；
- 容器退出后状态可清理；
- 不破坏宿主机控制面。

---

## Phase 4：容器内 Claude Code 执行链

### 目标

把 Claude Code 作为任务容器内工程执行器正式接入。

### 工作内容

1. 固定版本安装 Claude Code CLI
2. 任务 project 模板
3. `.claude/agents/*`
4. `gate-check.sh`
5. `host-change-request.json` / `summary.json` 等输出契约
6. `PreToolUse` allow / deny / fail-closed 验证

### 验收标准

- Claude Code 仅在任务 repo 内运行；
- hook / gate 行为可审计；
- 宿主机变更仍需通过 broker。

---

## Phase 5：LLM gateway / token / secret 最小化

### 目标

让任务容器不持有长期密钥，仅持短期受限凭据。

### 工作内容

1. 选定 gateway
2. 模型映射
3. task token 发放与过期
4. 审计日志
5. 验证容器内不持长期 key

### 验收标准

- 任务容器的密钥暴露面最小化；
- 可审计；
- 可吊销。

---

## Phase 6：备份扩展与长期运行收口

### 目标

补齐 `/var/lib/openclaw` 独立备份策略与长期运行收口。

### 工作内容

1. 为 `/var/lib/openclaw` 设计独立备份链
2. 对 `workspace-main`、正式 extensions、cron state 等做 allowlist
3. 排除高 churn 临时任务垃圾
4. 收口长期恢复流程

### 验收标准

- 根系统恢复与运行态恢复职责边界清晰；
- 高价值运行态可恢复；
- 容量与审计复杂度可控。

---

## 8. 完整 TODO 清单

## 8.1 Phase 0 已完成项

- [x] 以 `nick` 用户安装 Claude Code CLI
- [x] 确认不会生成 `~/.openclaw/` gateway 运行态
- [x] 创建 `~/projects/openclaw-dev/`
- [x] `git init`
- [x] 写 `docs/host-sop.md`
- [x] 写 `docs/design-v3.1.md`
- [x] 写 `CLAUDE.md`
- [x] 写 `.claude/settings.json`
- [x] 写 `.claude/agents/config-auditor.md`
- [x] 写 `.claude/agents/plugin-dev.md`
- [x] 写 `.claude/agents/broker-dev.md`
- [x] 写 `.claude/agents/test-runner.md`
- [x] 创建 `/srv/openclaw-control/`
- [x] 初始化控制仓库 git
- [x] 确认权威 SOP 路径
- [x] 编写 `scripts/publish-sop.sh`
- [x] 编写 `scripts/check-no-user-gateway.sh`
- [x] 编写 `tests/test_sop_publish.sh`

---

## 8.2 Phase 1B TODO

- [x] 更新 `docs/host-sop.md`
- [x] 更新 `docs/design-v3.md`（原 `design-v3.1.md`）
- [x] 在文档中明确 Phase 1A 已落地事实
- [x] 明确 `/var/lib/openclaw` 为独立 Btrfs 子卷且不在 root snapshot 内
- [x] 明确 `workspace-main` 是 published artifact
- [x] 明确权威控制仓库 / 开发仓 / runtime workspace / task repo 四层模型
- [x] 固化 `candidate -> deploy -> health -> snapshot -> vault -> capture-current` 流程
- [x] 补齐 `workspace-main` 的 publish / check 脚本
- [x] 记录 Phase 1A 快照名与 Vault 入库结果
- [x] 记录 `tools.profile` 覆盖问题与 fix-forward 结果
- [x] 记录默认主模型切换到 `g54`
- [x] 设计 `/var/lib/openclaw` 独立备份 allowlist 并升级为设计定稿候选
- [x] 在现网执行首次 `publish-workspace-main.sh --apply --allow-live-target` 正式发布
- [x] 移除 publish 脚本生产路径 safety guard 或增加 `--allow-live-target` flag
- [x] 实现首次 live publish 只读 preflight 脚本（`scripts/preflight-first-live-publish.sh`）
- [x] 增强 runbook（Go/No-Go checklist、证据采集要求、preflight 集成、check 命令 sudo 修正）
- [x] 修正 `publish-sop.sh` 描述（无条件拒绝 live path，非"含 --allow-live-target"）
- [x] 发布后通过 `check-workspace-main.sh` 校验发布产物结构完整性

> 注：控制面备份脚本的实现（将 `runtime-allowlist-backup-draft.md` 转化为可执行脚本）已从 Phase 1B 重新归入 Phase 6（§8.7），Phase 1B 的交付物为设计定稿候选文档。

---

## 8.3 Phase 2 TODO

### 开发仓内准备工作（Phase 2 prep，仓库内落地，不涉及现网部署）

- [x] 创建 `broker/`（目录结构、README）
- [x] 创建 `broker/schemas/host-ops-request.schema.json`（请求 JSON Schema，8 个 action enum）
- [x] 创建 `broker/schemas/host-ops-result.schema.json`（结果 JSON Schema，ok/error/denied）
- [x] 创建 `broker/schemas/actions/*.schema.json`（8 个 per-action 输入 schema）
- [x] 创建 `broker/wrappers/ocw-*.sh`（8 个 wrapper stub，仅验证 + echo，不执行）
- [x] 创建 `examples/broker/`（8 对 request/result fixture + 1 negative test pair）
- [x] 创建 `scripts/validate-broker-schemas.sh`（schema / wrapper / fixture 交叉验证，192 checks）
- [x] 创建 `tests/test_broker_schemas.sh`（wrapper stub 运行时测试 + negative cases，62 checks）
- [x] 创建 `plugins/host-ops-tool/`（skeleton index.js、package.json，phase2-prep 标记）
- [x] 对齐 `workspace-main-template/control/host-ops-api.md` 与 `design-v3.md` §5.6.2 请求契约（消除 operation/parameters/approval_id 与 action/inputs/requested_by 漂移）
- [x] 修正全仓 "Phase 1B+" / "Phase 0" 残留引用为准确阶段标号（routing-policy、approval-policy、broker SKILL、broker README、wrappers README）
- [x] 创建 `broker/wrappers/lib/common.sh`（共享验证库，消除 8 个 wrapper stub 间代码重复）
- [x] 重构 8 个 wrapper stub 使用 `common.sh`（validate_request_file、parse_common、validate_action、emit_result）
- [x] 创建 `docs/specs/host-ops-broker-protocol-v1.md`（协议规格文档：传输、信封、字段语义、fail-closed 规则、per-action 输入规格）
- [x] 创建 `plugins/host-ops-tool/lib/build-request.sh`（shell-based request fixture generator）
- [x] 创建 `plugins/host-ops-tool/lib/validate-request.sh`（shell-based request validator，与 common.sh 和 index.js 验证逻辑镜像）
- [x] 增强 `plugins/host-ops-tool/index.js`（buildRequest、validateRequest、validateResult 函数）
- [x] 创建 `scripts/validate-phase2-prep.sh`（聚合验证：schema + wrapper + plugin + fixture + protocol spec + cross-layer contract）
- [x] 创建 `tests/test_phase2_integration.sh`（集成测试：plugin→wrapper pipeline、negative tests、contract drift detection）
- [x] 修正 `workspace-main-template/skills/broker/SKILL.md` 契约漂移（operation/parameters/approval_id → action/inputs/requested_by）
- [x] 创建 `docs/specs/error-taxonomy-v1.md`（错误分类、错误码、denied/error 语义区分、negative fixture 索引）
- [x] 创建 `tests/test_contract_freeze.sh`（协议冻结测试：action enum、envelope fields、status enum、per-action schema、ok/status invariant、deprecated fields、cross-layer consistency、negative fixture coverage）
- [x] 扩充 negative fixture 覆盖至 17 场景（empty-reason、empty-label、empty-sha256、missing-snapshot-name、missing-target-snapshot、missing-label、type-error-reason、empty-action）
- [x] 在 `common.sh`、`index.js`、`validate-request.sh` 三层同步 `maxLength` 校验（label/snapshot_name/target_snapshot ≤ 128 chars）
- [x] 扩展 builder→wrapper pipeline 集成测试覆盖全部 8 个 action
- [x] 增强 `validate-phase2-prep.sh`：扩展 builder 测试 action 覆盖、负面 fixture 验证器拒绝测试、schema maxLength 一致性校验
- [x] 修正 protocol spec 描述漂移：snapshot_name / target_snapshot / label 字段描述由 "alphanumeric" 精确化为 "alphanumeric, dots, hyphens, underscores; max 128 chars"
- [x] 冻结 per-action schema property types 与 maxLength=128 约束
- [x] 冻结 wrapper stub 存在性（8 个 ocw-*.sh）
- [x] 冻结 fixture 中无 deprecated field names
- [x] 更新 error taxonomy negative fixture index 至完整 19 条
- [x] 强化 result schema：`additionalProperties: false`、required string 字段 `minLength: 1`、`if/then/else` ok/status 不变量、reserved `error_code` 字段
- [x] 创建 `docs/specs/contract-matrix-v1.md`（跨层契约矩阵：字段映射、镜像关系、deprecated 名称、共享校验规则）
- [x] 扩充 negative fixture 至 22 组 + 2 特殊场景（extra-fields、null-action、null-inputs、array-inputs、numeric-action、ok-status-mismatch）
- [x] 冻结 result envelope property types 与 minLength/invariant schema 约束
- [x] 修正 `SKILL.md` SHA256 占位符（`abc123...` → proper 64-char hex）
- [x] 更新 error taxonomy negative fixture index 至完整 25 条
- [x] 创建 `broker/schemas/action-inventory.json`（单一来源 action inventory，frozen=true，映射 schema/wrapper/fixture/required_inputs）
- [x] 创建 `examples/broker/fixture-registry.json`（fixture registry：happy-path、negative、expected results、error types）
- [x] 在 `host-ops-api.md` 补充 `error_code` 可选字段文档（reserved，指向 error-taxonomy-v1.md）
- [x] 在 `contract-matrix-v1.md` §7 添加验证脚本实现状态标记与单一来源引用
- [x] 创建 `docs/specs/phase2-repo-prep-gate.md`（prep 退出标准、明确 deferred 事项、残留低优先级项）
- [x] 增强 `test_contract_freeze.sh`：action inventory 冻结验证、fixture registry 一致性验证
- [x] 增强 `validate-phase2-prep.sh`：action inventory、fixture registry、prep gate、validator parity freeze 校验
- [x] 创建 `docs/specs/phase2-broker-deployment-layout.md`（部署目标文件系统布局规格：daemon、socket、wrappers、logs、state、systemd unit、权限模型）
- [x] 创建 `docs/runbook-phase2-broker-deployment.md`（部署 runbook：进入条件、禁止条件、10 阶段部署序列、验证序列、回滚规程、快照纪律）
- [x] 创建 `docs/execution-pack-phase2-broker-deployment.md`（分步执行包：15 步命令块 + 人工确认点 + 回退规程）
- [x] 创建 `docs/templates/phase2-broker-deployment-record-template.md`（部署现场记录模板）
- [x] 创建 `docs/templates/phase2-broker-deployment-syncback-template.md`（部署后文档回写模板）
- [x] 创建 `scripts/preflight-phase2-broker-deployment.sh`（只读预检脚本：10 段验证，不访问 live path）

### 现网部署（需 Phase 2 正式启动后执行）

- [ ] 实现 broker 主程序（Unix socket daemon / CLI）
- [ ] 实现 Unix socket 权限边界
- [ ] 将 wrapper stub 升级为 root-owned 生产版本
- [ ] 实现 `ocw-gateway-health`（live execution）
- [ ] 实现 `ocw-validate-openclaw-json`（live execution）
- [ ] 实现 `ocw-deploy-openclaw-json`（live execution）
- [ ] 实现 `ocw-gateway-restart`（live execution）
- [ ] 实现 `ocw-snapshot-pre`（live execution）
- [ ] 实现 `ocw-snapshot-post`（live execution）
- [ ] 实现 `ocw-vault-sync`（live execution）
- [ ] 实现 `ocw-rollback-prepare`（live execution）
- [ ] 写 `openclaw.plugin.json`（正式 manifest）
- [ ] 写部署脚本
- [ ] 注册 plugin 到 `openclaw.json`
- [ ] 变更前快照
- [ ] 重启 gateway
- [ ] 验证只读 host_ops（gateway_health）
- [ ] 验证写操作 schema 拒绝（invalid action / bad path）
- [ ] 变更后快照
- [ ] Vault 入库

---

## 8.4 Phase 3 TODO

- [ ] 安装 / 整理 Docker Engine
- [ ] 设计 `openclaw-task-net`
- [ ] 编写 Docker capability probe 脚本
- [ ] 构建 `openclaw-task-claude:2026-03-v3`
- [ ] 验证非 root 运行用户
- [ ] 验证只读 rootfs
- [ ] 验证 tmpfs
- [ ] 验证自定义网络
- [ ] 验证 bind task repo / outputs
- [ ] 创建 `workspace-task-runner/`
- [ ] 写 runner `AGENTS.md`
- [ ] 写 runner `TOOLS.md`
- [ ] 写 `control/runner-policy.md`
- [ ] 写 `control/artifact-contract.md`
- [ ] 更新 `openclaw.json` 加入 `task-runner`
- [ ] 验证 `sessions_spawn("task-runner")`
- [ ] 验证 `scope=session`
- [ ] 验证容器清理
- [ ] 变更前快照
- [ ] 变更后快照
- [ ] Vault 入库

---

## 8.5 Phase 4 TODO

- [ ] 在镜像中安装固定版本 Claude Code CLI
- [ ] 创建 task project 模板
- [ ] 写 `repo/CLAUDE.md`
- [ ] 写 `.claude/settings.json`
- [ ] 写 `.claude/agents/coder.md`
- [ ] 写 `.claude/agents/tester.md`
- [ ] 写 `.claude/agents/reviewer.md`
- [ ] 写 `.claude/agents/doc-writer.md`
- [ ] 写 `.claude/hooks/gate-check.sh`
- [ ] 实现 gate shim
- [ ] 对接 vLLM `/v1/chat/completions`
- [ ] 定义 gate response schema
- [ ] 定义 deterministic deny policy
- [ ] 定义 rewrite policy
- [ ] 写 `outputs/summary.json` schema
- [ ] 写 `outputs/host-change-request.json` schema
- [ ] 验证 `PreToolUse` allow
- [ ] 验证 `PreToolUse` deny
- [ ] 验证超时 fail-closed
- [ ] 验证解析失败 fail-closed
- [ ] 验证 gate 事件日志

---

## 8.6 Phase 5 TODO

- [ ] 选定 LLM gateway 实现
- [ ] 验证 Anthropic Messages API 兼容
- [ ] 验证 headers 透传
- [ ] 验证流式响应
- [ ] 验证模型映射
- [ ] 实现 task token 发放
- [ ] 实现 token 过期
- [ ] 实现网关审计日志
- [ ] 验证容器内不持长期 key

---

## 8.7 Phase 6 TODO

- [ ] 定义 `host-change-request.json` 完整 schema
- [ ] task-runner 生成该请求
- [ ] main 审批逻辑落地
- [ ] broker 接收审批请求
- [ ] broker 写回执行结果
- [ ] 将 `runtime-allowlist-backup-draft.md`（Phase 1B 设计定稿候选）转化为可执行备份脚本
- [ ] 明确恢复顺序与恢复脚本（基于 `runtime-allowlist-backup-draft.md` §4 恢复优先级）
- [ ] 验证失败时可安全回退

---

## 9. 实施中的硬性规则

### 9.1 关于 Claude Code CLI

- 只能在 `nick` 用户域做人类开发辅助；
- 只能在 task container 内做受限工程执行；
- 不允许在 `openclaw` 用户域交互登录；
- 不允许替代 OpenClaw gateway 运行模型；
- 不允许长期凭证直灌入任务镜像。

### 9.2 关于 OpenClaw main

- 不给 `exec`；
- 不给 `elevated`；
- 允许 workspace 内最小写入；
- 只允许已审计的 `task-runner`。

### 9.3 关于 task-runner

- 每任务一容器；
- 不给 `elevated`；
- 不给 OpenClaw 深层继续 spawn；
- 只写本任务 repo / outputs；
- 不触达宿主机关键路径。

### 9.4 关于宿主机变更

- 容器内只生成候选与请求；
- 真正变更只走 broker；
- 所有变更必须快照、验证、入库。

---

## 10. 关键风险与对应策略

| 风险 | 说明 | v3.1 对策 |
|------|------|-----------|
| HTTP hook 被误认为硬阻断 | 超时 / 连接失败其实会继续执行 | 改为 command hook + gate shim + exit 2 |
| runner 污染长期 workspace | `workspaceAccess=rw` 面太大 | 改为只写 per-task repo / outputs |
| Docker 接入方式不明 | 未证实某个 `DOCKER_HOST` 方案可完整支撑 OpenClaw sandbox | 在 Phase 3 做 capability probe，不把未验证方案写死 |
| 容器持有长期凭证 | 一旦泄漏影响宿主机长期安全 | 使用上游 proxy + task token |
| OpenClaw 子 agent 继承过多上下文 / 凭证 | 官方只有 `AGENTS.md + TOOLS.md` 稳定注入，且 auth 会 fallback 合并 | 关键规则写进 `AGENTS.md/TOOLS.md`，凭证靠 proxy / task token 隔离 |
| 把 OpenClaw 深度做得过深 | 编排复杂、排障困难、成本高 | OpenClaw 只到 task-runner；容器内细分交给 Claude Code subagents |
| main 变成“半 root” | 宿主机控制面失去边界 | main 无 exec / elevated，只能调用 broker |
| SOP 漂移 | 多副本不一致 | 单一权威源 + 发布脚本 + hash / version |
| 全局 `tools.profile` 压制 per-agent allowlist | `main` 可能只有 session 工具，无法读写 workspace | 部署 `main` 时移除全局 `tools.profile` |
| 默认 Claude 4.6 路径在飞书场景下可能卡住 | 现场出现 `embedded run timeout` 与长时间不回复 | 当前默认改为 `g54`，并把 Claude 4.6 稳定性排查列为独立 follow-up |
| `workspace-main` 被误当作长期权威源 | root snapshot 无法覆盖该子卷，恢复语义被误判 | 明确将其定义为 published artifact，恢复依赖重发布 |
| `session-memory` 路径展示混淆 | 日志出现 `~/.openclaw/...`，可能导致误判真实写入路径 | 单独核实日志展示与真实落点，不把 `nick` 用户路径重新引入运行态 |

---

## 11. 迁移与回滚策略

### 11.1 总体策略

每个 phase 都必须满足：

1. 变更前先做只读快照；
2. 先在最小范围内引入新能力；
3. 新能力通过健康检查后，才能成为下一阶段依赖；
4. 未经验证的组件，不得反向写入“当前已完成能力”；
5. 若阶段验收失败，优先回滚到最近一个已知健康快照；
6. 回滚后必须重新做健康检查并记录结论。

### 11.2 Phase 1A 的回滚原则

若 Phase 1A 需要回滚，优先路径为：

1. 回退 `openclaw.json` 到上一已知可用版本；
2. 重启 `openclaw-gateway.service`；
3. 验证飞书 / gateway 基本健康；
4. 必要时恢复到 `root-pre-main-agent-*` 或 `root-pre-toolfix-*` 快照；
5. `workspace-main` 若被判定为损坏，优先使用 publish 流重发，而不是寄希望于 root snapshot 自动恢复。

### 11.3 Phase 2 以后的回滚原则

一旦引入 broker / wrapper / host-write chain，所有写操作回滚都必须输出：

- pre snapshot 名称；
- post snapshot 名称；
- 变更对象；
- 健康检查结果；
- rollback 建议路径。

任何没有这些元数据的宿主机写操作，都不应视为合格实施。

### 11.4 长期恢复原则

长期恢复分为两类：

- **根系统恢复**：依赖 root snapshot + Vault；
- **运行态控制面恢复**：依赖 published artifact 重发 + 运行态 allowlist 备份。

不得再把两者混写成“恢复整个系统等于恢复所有运行态目录”。

