
# OpenClaw 多 Agent + Claude Code 协作体系设计稿 v3

> 编写日期：2026-03-07  
> 适用宿主机：当前单机 Ubuntu 24.04 LTS / Btrfs / systemd / OpenClaw 2026.3.2 基线  
> 上游输入：`openclaw-host-sop-2026-03-06.md`、`1.md`、`openclaw-design-v2-2026-03-07.md`  
> 文档定位：**可实施规格稿**，用于后续直接开发、验证、回滚与审计

---

## 0. 文档结论先行

本 v3 方案保留 v2 的大方向，但做出以下关键修正：

1. **主控制面仍在宿主机，不容器化。**
2. **真正执行代码与构建测试的任务域进入 OpenClaw Docker sandbox。**
3. **Claude Code CLI 被正式纳入体系**：既作为 `nick` 用户的开发工具，也作为任务容器内的工程执行器。
4. **Claude Code 的硬门控必须落在 `PreToolUse` hook + 本地 gate shim 上**，不能把“HTTP 直连 vLLM 且超时自动阻断”当成既成事实。
5. **task-runner 不再对整个 agent workspace 拥有宽泛 `rw`**，而是只写“每任务 repo/outputs”。
6. **任何宿主机副作用都不能由容器内 Claude Code 直接执行**，只能走 host-ops broker → 白名单 wrapper → 快照/健康检查/入 Vault 的批准链。
7. **OpenClaw 子 agent 深度只到任务域为止**；任务域内部的细分协作，优先使用 Claude Code 的 project subagents，而不是让 OpenClaw 树无限扩张。
8. **涉及 OpenClaw 与 Docker 的具体接入方式，设计上只依赖官方 sandbox 配置能力，不把未验证的 `DOCKER_HOST=tcp://127.0.0.1:2375` 写成规范前提。**

---

## 1. 设计目标与非目标

### 1.1 设计目标

本体系的目标不是“让 OpenClaw 在宿主机上拥有更大权限”，而是：

- 让 **main agent** 成为宿主机控制面与人机交互入口；
- 让 **task-runner** 成为受限、可丢弃、按任务实例化的执行面；
- 让 **Claude Code CLI** 成为：
  - `nick` 用户的主要开发辅助工具；
  - 任务容器内的代码编辑/测试/重构执行器；
- 让 **宿主机变更链** 保持：
  - 可审计；
  - 可快照；
  - 可回滚；
  - 可最小授权；
- 让 **SOP** 成为 OpenClaw 与 Claude Code 的共同事实源；
- 让整套方案支持后续逐步扩展，而不是一开始把全部高风险能力一次性打开。

### 1.2 非目标

本设计**不追求**：

- 让主 agent 直接拥有宿主机 `exec + elevated`;
- 让 Docker 容器内 Claude Code 直接操作 `/etc/openclaw`、`/opt/openclaw`、systemd、Vault；
- 让 OpenClaw 在当前阶段直接依赖 ACP Claude Code runtime 解决容器内工程执行；
- 让 OpenClaw 子 agent 网络状 peer-to-peer 协作成为核心路径；
- 让容器内持有长期宿主机密钥或长期 root 权限。

---

## 2. 不可突破的宿主机基线（来自现有 SOP）

以下约束不是建议，而是 **v3 的硬约束**：

### 2.1 路径边界

- `/opt/openclaw`：程序代码，仅 root 可写；
- `/etc/openclaw/openclaw.json`：唯一权威配置源；
- `/etc/openclaw/openclaw.env`：长期敏感凭证；
- `/var/lib/openclaw`：OpenClaw 运行态数据，独立 Btrfs 子卷；
- `/var/log/openclaw`：日志目录。

### 2.2 运行身份

- `openclaw`：system user，`nologin`，仅用于后台 gateway；
- `nick`：管理员与图形远程桌面/SSH 的操作用户。

### 2.3 当前 systemd 安全边界

现有 `openclaw-gateway.service` 已经启用了只读系统保护、禁止新增特权、限制可写目录等约束；本设计不得通过“为了方便开发”去破坏这些约束。

### 2.4 变更纪律

所有宿主机状态变更必须遵循：

1. 变更前只读快照  
2. 变更  
3. 健康检查  
4. 变更后只读快照  
5. Vault 入库

### 2.5 已验证事实

- OpenClaw `before_tool_call` 在当前版本上已验证可触发，但在本机现状中仍应被视为**软门控/审计入口**，而不是唯一硬阻断点；
- 宿主机已部署 vLLM 审计服务，监听 `127.0.0.1:8000`；
- `nick` 账号历史上误运行 user-level gateway 曾造成双 gateway 事故，因此 **Claude Code CLI 的开发工作只能帮助构建 OpenClaw，不得替代 system-level gateway 运行模型**。

---

## 3. v3 的外部事实边界（基于官方文档）

以下是 v3 采用的、已核实的外部事实：

### 3.1 OpenClaw agent workspace

- workspace 是 agent 的 home，也是文件工具与 workspace 上下文的默认目录；
- workspace **不是硬沙箱**；
- 绝对路径若未开启 sandbox，仍可触达宿主机其他位置；
- 当启用 sandbox 且 `workspaceAccess != "rw"` 时，工具实际工作于 sandbox workspace，而非宿主机原始 workspace。

### 3.2 OpenClaw sandbox 关键语义

- `workspaceAccess` 有 `none | ro | rw`;
- `scope` 有 `session | agent | shared`;
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
- 子 agent 的 auth 以目标 agent 的 auth 为主，但 **主 agent auth 会作为 fallback 合并**；真正完全隔离的每-agent 凭证域当前并不支持。

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
  - rootless Docker 更适合交互用户域，而不适合你当前 `openclaw` 的 `nologin` system-user 设计。

---

## 4. v3 最终架构

---

### 4.1 控制面与执行面分离

#### A. 宿主机控制面（持久）

运行位置：宿主机  
主要组件：

1. `openclaw-gateway.service`
2. `main` agent
3. `host-ops broker`
4. `vLLM audit service`
5. `LLM gateway / upstream proxy`
6. `SOP authority repo + publish scripts`
7. Btrfs snapshot / Vault backup 链

职责：

- 接收人与渠道消息；
- 维护长期上下文与宿主机认知；
- 根据任务类型路由到 task-runner；
- 收集 task-runner 输出；
- 审批宿主机变更请求；
- 驱动快照/健康检查/回滚链；
- 维护 SOP 与审计记录。

#### B. 任务执行面（可丢弃）

运行位置：OpenClaw Docker sandbox  
主要组件：

1. `task-runner` agent
2. 每任务工作目录 `tasks/<task-id>/`
3. 容器内 `claude` / `claude code` CLI
4. 项目级 `.claude/`
5. `gate-check` hook shim
6. 必要的编译/测试工具链

职责：

- 代码修改；
- patch 生成；
- 构建与测试；
- 文档整理；
- 结构化输出；
- 必要时生成 `host-change-request.json`；
- **不直接修改宿主机关键路径**。

---

### 4.2 统一事件流

#### 4.2.1 普通只读/轻任务

用户 → main agent →（若无需执行面）直接回答

#### 4.2.2 工程任务

用户 → main agent  
→ 生成任务描述 / 选择 runner  
→ `sessions_spawn(agentId="task-runner")`  
→ OpenClaw 为该任务启动 sandbox session  
→ runner 进入 `tasks/<task-id>/repo`  
→ 容器内 Claude Code CLI 执行工程任务  
→ 输出写入 `outputs/`  
→ runner 完成并 announce 给 main  
→ main 汇总并回用户

#### 4.2.3 涉及宿主机状态变更的任务

用户 → main  
→ task-runner 在容器内完成分析 / patch / 验证方案  
→ 产出 `host-change-request.json`  
→ main 读取请求并判定是否进入批准链  
→ 调用 host-ops broker  
→ broker 调 wrapper  
→ 变更前快照 → 变更 → 健康检查 → 变更后快照 → Vault 入库  
→ main 汇总结果并回复

---

## 5. 组件详细规格

---

## 5.1 main agent（宿主机主控制代理）

### 5.1.1 角色定位

`main` 是长期存在的宿主机控制代理，不做重执行，不直接做高风险宿主机写操作。它负责：

- 读取 SOP；
- 与人对话；
- 路由任务；
- 管理 approvals；
- 收集 task-runner 结果；
- 调用 host-ops broker 的少量白名单动作；
- 维护宿主机运行知识。

### 5.1.2 工具权限策略

建议：

- allow：
  - `read`
  - `write`（仅 workspace 内部）
  - `edit`（仅 workspace 内部）
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
  - 其他不必要工具按最小化原则收紧

**设计原则：**

- main 可以更新自己的控制面文档与审批状态；
- main 不能直接在宿主机 shell 里跑命令；
- main 若要触发宿主机副作用，只能经由 broker。

### 5.1.3 subagent 策略

建议：

- `subagents.allowAgents = ["task-runner"]`
- 默认不对 main 开放大量跨 agent target
- `maxSpawnDepth = 2`

解释：

- main 只允许把任务交给已知 `task-runner`；
- 不允许 main 随意把任务投递到未来未经审计的新 agent；
- OpenClaw 侧深度只保留为：
  - depth 0：main
  - depth 1：task-runner
- 任务内更细分的“coder / tester / reviewer / doc”角色，由 **Claude Code project subagents** 负责，而不是再扩 OpenClaw 深度。

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

### 5.1.5 main 的规则文件写法要求

- **强约束写进 `AGENTS.md`**：
  - 目标优先级；
  - 不得直接修改宿主机；
  - 必须引用 SOP；
  - 什么时候 spawn `task-runner`；
  - 什么时候走 broker；
- **工具约定写进 `TOOLS.md`**：
  - 何时读 `control/`;
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
- task-runner 需要的不是“长期 workspace 可写”，而是“当前任务 repo/outputs 可写”。

因此 v3 的策略是：

- OpenClaw sandbox 对 agent workspace 采用 `none`;
- 所有任务所需文件，显式落入 per-task 目录；
- 宿主机向 sandbox 提供的内容，只通过任务目录、只通过发布脚本、只通过 bind/mount 进入。

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

v3 把 Claude Code CLI 分成两个明确角色。

### 5.3.1 角色 A：`nick` 用户的开发工具

用途：

- 帮你开发 broker、plugin、publish scripts、OpenClaw 配置与 workspace 文件；
- 帮你审查设计、生成测试脚本、编写部署脚本；
- 在 `~/projects/openclaw-dev/` 中进行版本化开发。

规则：

- 安装与登录只在 `nick` 用户域完成；
- **绝不**以 `openclaw` 用户登录 Claude Code；
- **绝不**用 Claude Code 替代 system-level gateway 运行；
- `~/projects/openclaw-dev/` 是开发仓库，不是运行目录。

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
│   └── acceptance-tests.md
├── broker/
├── plugins/
├── scripts/
├── examples/
└── tests/
```

### 5.3.2 角色 B：任务容器内的工程执行器

用途：

- 在 sandbox 容器内处理 repo 级工程任务；
- 通过项目级 `.claude/` 读取任务规则；
- 通过 `PreToolUse` hooks 执行本地 gate；
- 通过 project subagents 细分 coder/tester/reviewer 等角色。

规则：

- Claude Code 在容器内只针对 `tasks/<task-id>/repo/` 这个项目根运行；
- 它不是宿主机的控制面；
- 它不能直达宿主机 secrets；
- 它不能直接重启服务或修改 `/etc/openclaw`。

### 5.3.3 为什么需要双角色

因为这两个场景的风险模型不同：

- `nick` 开发仓库：是**人主导**、可交互、可手动审阅的开发环境；
- 任务容器：是 **OpenClaw 代理驱动**、可丢弃、需要强审计与最小权限的自动执行环境。

把二者混为一谈，会导致：

- 要么开发效率太低；
- 要么自动执行环境获得了不必要的人类级长期权限。

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
- 测试/构建命令；
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
- 必要的 permissions allow/deny;
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

---

### 5.5.1 v3 的核心修正

v2 最大的问题之一，是把“Claude Code HTTP hook 直连 vLLM，然后超时即 fail-closed”写成了设计前提。

这在官方语义上并不成立，因为：

- HTTP hook 的非 2xx、连接失败、超时，都是**非阻断错误**；
- 真正的阻断必须依赖：
  - command hook 的 `exit 2`；
  - 或 HTTP hook 返回 2xx + 合法阻断 JSON。

因此 v3 的硬门控改为：

```text
Claude Code PreToolUse (command hook)
  -> gate-check.sh
    -> 本地 gate shim
      -> vLLM /v1/chat/completions
      -> 解析决策
    -> 若 deny/解析失败/超时
         exit 2
       否则 exit 0
```

### 5.5.2 组件分工

#### A. `gate-check.sh`

职责：

- 从 Claude Code hook stdin 读取 `tool_name`, `tool_input`, `cwd`, task metadata；
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
  - 直接 `sudo`;
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
- 你的任务容器执行路径未来很可能会进入半自动/自动模式；
- 所以真正的强门控必须落在 `PreToolUse`。

### 5.5.6 OpenClaw plugin 审计仍然保留

v3 不是放弃 OpenClaw `before_tool_call`，而是重新定位：

- OpenClaw `before_tool_call`：**外层审计 + 记录 + 额外风控**
- Claude Code `PreToolUse`：**容器内真实执行命令的硬门控**

原因：

OpenClaw 外层工具调用看不到 Claude Code 内部所有真实待执行 payload；Claude Code hook 才能拿到内部真实 Bash/Edit/Write 事件。

---

## 5.6 host-ops broker（宿主机副作用代理）

---

### 5.6.1 角色定位

broker 是 v3 的唯一宿主机副作用执行面。它不是通用 shell，不接受自然语言，也不允许任意命令拼接。

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

- main 不直接拥有 `exec`；
- main 调用 `host_ops(...)` 插件工具；
- 插件工具只把结构化请求交给 broker；
- broker 再走 wrapper。

这样主控制面拥有“调用受限操作”的能力，但并不拥有“任意命令执行”的能力。

---

## 5.7 SOP 权威源与发布机制

---

### 5.7.1 只保留一个权威源

权威源建议：

```text
/srv/openclaw-control/docs/host-sop.md
```

或你确定的单一控制仓库路径。

### 5.7.2 双层发布而非 symlink

原因：

OpenClaw 官方明确说明，sandbox seed copy 只接受常规 in-workspace 文件；解析到 workspace 外部的 symlink/hardlink 会被忽略。

因此 v3 采用：

- 权威源：单一仓库中的 SOP
- 发布副本：
  - `workspace-main/control/SOP.md`
  - `tasks/<task-id>/repo/docs/host-sop.md`
  - 开发仓库 `docs/host-sop.md`

### 5.7.3 发布脚本职责

`publish-sop.sh` 至少做：

1. 从权威源复制到目标
2. 写入 SHA256
3. 写入版本号/时间戳
4. 若 hash 未变可跳过
5. 记录发布日志

### 5.7.4 为什么开发仓库也要有副本

因为：

- `nick` 的 Claude Code 开发仓库需要看 SOP；
- 开发仓库不在 OpenClaw workspace 内；
- 它与运行时副本的同步，也必须通过发布脚本，而不是手工复制。

---

## 5.8 LLM gateway / 上游模型代理

---

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

在未完成兼容性验证前，v3 只把该网关定义为：

- **必须存在的组件**
- **需要 Phase 4 专项验收**
- **不把当前 MotChat / Nginx 改写路径直接视为已验证完成**

### 5.8.4 凭证策略

任务容器内不存长期主密钥，而是：

- 由宿主机 gateway/proxy 维护长期上游凭证；
- 每任务注入短期 task token；
- token 只允许该任务访问必要模型与额度；
- 容器销毁即失效。

---

## 5.9 Docker 方案

---

### 5.9.1 规范级要求

v3 规范层只要求：

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

但并没有足够证据证明“你当前这版 OpenClaw + 受限 socket proxy + `DOCKER_HOST`”已经被完整验证能承载其所有 sandbox 生命周期操作。

因此 v3 不写死实现路径，只写：

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
- Python / Node 等你任务需要的最小工具链
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

---

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

---

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

## 6. 配置建议（规范草案）

---

## 6.1 OpenClaw agent 规划

建议最终只保留两个正式 agent：

1. `main`
2. `task-runner`

未来可增加的 agent，只有在完成专门安全审查后才能进入 allowlist。

---

## 6.2 `main` agent 配置草案

```json5
{
  agents: {
    defaults: {
      skipBootstrap: true,
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
            "session_status",
            "host_ops"
          ],
          deny: [
            "exec",
            "process",
            "apply_patch",
            "elevated"
          ],
          elevated: { enabled: false }
        }
      }
    ]
  }
}
```

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

> 注：Docker 接入的底层连通实现必须在 Phase 2 通过 capability probe 验证，不在 v3 规格中假定为某个固定 `DOCKER_HOST` 方案。

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

> 注：实际允许列表需要按任务镜像的工具链再微调；这里只给出 v3 的安全方向。

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
- 它的职责是**生成与审查**，最终落地走你的人类批准或后续 broker 执行链。

---

## 7. 分阶段实施路径

---

## Phase 0：开发工具链与控制仓库（前置阶段）

### 目标
把 Claude Code CLI 正式纳入开发流程，但不碰生产执行面。

### 工作内容

1. 以 `nick` 用户安装 Claude Code CLI
2. 创建开发仓库 `~/projects/openclaw-dev/`
3. 建立：
   - `docs/host-sop.md`
   - `docs/design-v3.md`
   - `.claude/settings.json`
   - `.claude/agents/*`
   - `CLAUDE.md`
4. 创建权威控制仓库，例如 `/srv/openclaw-control/`
5. 建立 SOP 发布脚本
6. 起草：
   - main workspace 文件
   - task-runner workspace 文件
   - broker 代码框架
   - plugin 框架
   - gate shim 框架

### 验收标准

- Claude Code 仅在 `nick` 环境正常工作；
- 不产生任何第二个 gateway；
- 开发仓库可生成规范文件与测试脚本；
- SOP 可从权威源发布到目标副本。

---

## Phase 1：main agent 上线

### 目标
让 main 成为稳定的宿主机控制代理，但仍不接入 Docker task execution。

### 工作内容

1. 创建 `workspace-main`
2. 写入 bootstrap/control 文件
3. 更新 `openclaw.json`，加入 `main`
4. 配置 `subagents.allowAgents = ["task-runner"]`
5. 配置 main 的工具 deny/allow
6. 部署 `host_ops` 插件壳，但先只暴露只读动作：
   - `gateway_health`
   - `list_snapshots`
   - `show_last_backup`

### 验收标准

- main 能对话；
- main 能读 SOP；
- main 不能执行宿主机 shell；
- main 能调用只读 host_ops；
- systemd 与快照链不被破坏。

---

## Phase 2：host-ops broker 正式落地

### 目标
建立唯一宿主机副作用入口。

### 工作内容

1. 实现 broker
2. 实现 root-owned wrappers
3. 部署 Unix socket / 权限组
4. 扩展 `host_ops` plugin
5. 新增结构化动作：
   - `validate_openclaw_json_candidate`
   - `deploy_openclaw_json_candidate`
   - `gateway_restart`
   - `snapshot_pre`
   - `snapshot_post`
   - `vault_sync`

### 验收标准

- main 仍无宿主机任意 exec；
- broker 能按 schema 拒绝非法输入；
- wrapper 不接受自由路径/自由命令；
- 配置变更可完成完整快照 → 变更 → 验证 → 入库链路。

---

## Phase 3：Docker sandbox capability probe 与 task-runner 上线

### 目标
验证 OpenClaw 对 Docker sandbox 的真实接入能力，并上线 task-runner。

### 工作内容

1. 安装/整理 Docker Engine
2. 构建 `openclaw-task-claude:2026-03-v3`
3. 创建 `workspace-task-runner`
4. 配置 `task-runner` agent
5. 做 capability probe：
   - 容器创建
   - 容器销毁
   - `scope=session`
   - `workspaceAccess=none`
   - 自定义 bridge 网络
   - 只读根
   - tmpfs
   - bind 任务目录
6. 若受限 Docker 接入方案可行，则固化；
7. 若不可行，记录为实现阻塞项，不将未验证方案推进生产。

### 验收标准

- task-runner 可成功 spawn；
- 每任务单独容器；
- 容器结束可清理；
- 不能逃逸到宿主机；
- 任务目录与 outputs 正常读写。

---

## Phase 4：Claude Code 容器内执行链与硬门控

### 目标
让 task-runner 在容器内实际使用 Claude Code 完成工程任务，并由 gate shim 强门控。

### 工作内容

1. 在镜像中安装固定版本 Claude Code CLI
2. 建立 task project 模板
3. 配置 `.claude/settings.json`
4. 实现 `gate-check.sh`
5. 实现 gate shim
6. 对接宿主机 vLLM
7. 实现 task outputs 契约
8. 引入 project subagents：
   - coder
   - tester
   - reviewer
   - doc-writer

### 验收标准

- Claude Code 可在容器内针对 task repo 正常运行；
- `PreToolUse` hook 可拿到真实 Bash/Edit/Write 事件；
- deny/timeout/解析失败能 fail-closed；
- gate 事件被完整记录；
- 容器内无法直接操作宿主机关键路径。

---

## Phase 5：LLM gateway / 短期 token / 上游兼容性

### 目标
把 Claude Code 上游模型访问纳入可控代理层。

### 工作内容

1. 部署兼容 Claude Code 的 LLM gateway
2. 验证 Anthropic Messages API 兼容性
3. 实现 task token 机制
4. 验证模型名、headers、流式输出、计费与错误处理
5. 将长期上游密钥完全收回宿主机 proxy

### 验收标准

- Claude Code 通过网关正常调用上游；
- 容器内不持有长期 key；
- task token 可过期；
- 失败模式可审计。

---

## Phase 6：宿主机变更任务闭环

### 目标
完成“容器内生成候选 → main 审批 → broker 落地 → 快照入库”的完整闭环。

### 工作内容

1. 定义 `host-change-request.json` schema
2. task-runner 生成结构化请求
3. main 自动审查请求
4. broker 执行批准链
5. 写回变更结果与回滚索引
6. 主 agent 形成用户可读报告

### 验收标准

- 从 task 容器到宿主机变更的链路完整跑通；
- 每一步都有审计与 request-id；
- 失败时可安全回退；
- 用户能清楚看到“提议、批准、执行、验证、入库”的全过程。

---

## 8. 完整 TODO 清单

---

## 8.1 Phase 0 TODO

- [ ] 以 `nick` 用户安装 Claude Code CLI
- [ ] 确认不会生成 `~/.openclaw/` gateway 运行态
- [ ] 创建 `~/projects/openclaw-dev/`
- [ ] `git init`
- [ ] 写 `docs/host-sop.md`
- [ ] 写 `docs/design-v3.md`
- [ ] 写 `CLAUDE.md`
- [ ] 写 `.claude/settings.json`
- [ ] 写 `.claude/agents/config-auditor.md`
- [ ] 写 `.claude/agents/plugin-dev.md`
- [ ] 写 `.claude/agents/broker-dev.md`
- [ ] 写 `.claude/agents/test-runner.md`
- [ ] 创建 `/srv/openclaw-control/`
- [ ] 初始化控制仓库 git
- [ ] 确认权威 SOP 路径
- [ ] 编写 `scripts/publish-sop.sh`
- [ ] 编写 `scripts/check-no-user-gateway.sh`
- [ ] 编写 `tests/test_sop_publish.sh`

---

## 8.2 Phase 1 TODO

- [ ] 创建 `workspace-main/`
- [ ] 写 `AGENTS.md`
- [ ] 写 `SOUL.md`
- [ ] 写 `TOOLS.md`
- [ ] 写 `IDENTITY.md`
- [ ] 写 `USER.md`
- [ ] 写 `HEARTBEAT.md`
- [ ] 写 `MEMORY.md`（若启用）
- [ ] 写 `skills/host-sop/SKILL.md`
- [ ] 写 `skills/routing/SKILL.md`
- [ ] 写 `skills/approvals/SKILL.md`
- [ ] 写 `control/routing-policy.md`
- [ ] 写 `control/approval-policy.md`
- [ ] 写 `control/allowed-workers.md`
- [ ] 发布 SOP 到 `control/SOP.md`
- [ ] 更新 `openclaw.json` 加入 `main`
- [ ] 变更前快照
- [ ] 重启 gateway
- [ ] 验证 main 可读 SOP
- [ ] 验证 main 无 exec/elevated
- [ ] 变更后快照
- [ ] Vault 入库

---

## 8.3 Phase 2 TODO

- [ ] 创建 `broker/`
- [ ] 实现 broker 主程序
- [ ] 实现 Unix socket 权限
- [ ] 实现 `ocw-gateway-health`
- [ ] 实现 `ocw-list-snapshots`
- [ ] 实现 `ocw-validate-openclaw-json`
- [ ] 实现 `ocw-deploy-openclaw-json`
- [ ] 实现 `ocw-gateway-restart`
- [ ] 实现 `ocw-snapshot-pre`
- [ ] 实现 `ocw-snapshot-post`
- [ ] 实现 `ocw-vault-sync`
- [ ] 创建 `plugins/host-ops-tool/`
- [ ] 写 `openclaw.plugin.json`
- [ ] 写 `package.json`
- [ ] 写 `index.js`
- [ ] 写部署脚本
- [ ] 注册 plugin
- [ ] 变更前快照
- [ ] 重启 gateway
- [ ] 验证只读 host_ops
- [ ] 验证写操作 schema 拒绝
- [ ] 变更后快照
- [ ] Vault 入库

---

## 8.4 Phase 3 TODO

- [ ] 安装/整理 Docker Engine
- [ ] 设计 `openclaw-task-net`
- [ ] 编写 Docker capability probe 脚本
- [ ] 构建 `openclaw-task-claude:2026-03-v3`
- [ ] 验证非 root 运行用户
- [ ] 验证只读 rootfs
- [ ] 验证 tmpfs
- [ ] 验证自定义网络
- [ ] 验证 bind task repo/outputs
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
- [ ] wrapper 执行配置部署
- [ ] 执行健康检查
- [ ] 记录 pre/post snapshot
- [ ] Vault 入库
- [ ] 生成回滚索引
- [ ] main 输出用户报告
- [ ] 端到端演练一次完整配置变更

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
- 只写本任务 repo/outputs；
- 不触达宿主机关键路径。

### 9.4 关于宿主机变更

- 容器内只生成候选与请求；
- 真正变更只走 broker；
- 所有变更必须快照、验证、入库。

---

## 10. 关键风险与对应策略

| 风险 | 说明 | v3 对策 |
|------|------|---------|
| HTTP hook 被误认为硬阻断 | 超时/连接失败其实会继续执行 | 改为 command hook + gate shim + exit 2 |
| runner 污染长期 workspace | `workspaceAccess=rw` 面太大 | 改为只写 per-task repo/outputs |
| Docker 接入方式不明 | 未证实某个 `DOCKER_HOST` 方案可完整支撑 OpenClaw sandbox | 在 Phase 3 做 capability probe，不把未验证方案写死 |
| 容器持有长期凭证 | 一旦泄漏影响宿主机长期安全 | 使用上游 proxy + task token |
| OpenClaw 子 agent 继承过多上下文/凭证 | 官方只有 `AGENTS.md + TOOLS.md` 稳定注入，且 auth 会 fallback 合并 | 关键规则写进 `AGENTS.md/TOOLS.md`，凭证靠 proxy/task token 隔离 |
| 把 OpenClaw 深度做得过深 | 编排复杂、排障困难、成本高 | OpenClaw 只到 task-runner；容器内细分交给 Claude Code subagents |
| main 变成“半 root” | 宿主机控制面失去边界 | main 无 exec/elevated，只能调用 broker |
| SOP 漂移 | 多副本不一致 | 单一权威源 + 发布脚本 + hash/version |

---

## 11. 迁移与回滚策略

### 11.1 总体策略

每个 phase 都必须满足：

- 能单独验收；
- 能独立回滚；
- 不依赖后续 phase 才能保持安全。

### 11.2 回滚边界

- Phase 0 失败：删除开发仓库与 Claude Code 设置，不影响生产运行；
- Phase 1 失败：回滚 `openclaw.json` 中 main agent 变更，恢复快照；
- Phase 2 失败：下线 broker/plugin，恢复前快照；
- Phase 3 失败：不启用 task-runner，对生产主控制面无影响；
- Phase 4 失败：task container 内 Claude Code 停用，runner 仍可存在；
- Phase 5 失败：回到直接受控上游模式，不发 task token；
- Phase 6 失败：宿主机仍保留 broker 保护链，不允许半完成写入停留。

---

## 12. v3 的最终推荐拓扑

```text
Human (nick)
  │
  ├─ Claude Code CLI (dev repo, human-driven)
  │     └─ 产出：broker/plugin/scripts/config/tests/docs
  │
  └─ OpenClaw Gateway (systemd, User=openclaw)
        │
        ├─ main agent (host control plane)
        │    ├─ 读取：workspace-main/control/SOP.md
        │    ├─ 调度：task-runner
        │    └─ 调用：host-ops broker
        │
        ├─ task-runner agent (Docker sandbox, scope=session)
        │    └─ 每任务：
        │         tasks/<task-id>/repo
        │         tasks/<task-id>/outputs
        │         └─ Claude Code CLI
        │              ├─ CLAUDE.md
        │              ├─ .claude/settings.json
        │              ├─ .claude/agents/*
        │              └─ PreToolUse -> gate-check.sh -> gate shim -> vLLM
        │
        ├─ host-ops broker
        │    └─ root-owned wrappers
        │         └─ snapshot -> change -> health -> snapshot -> vault
        │
        ├─ vLLM audit service
        └─ LLM gateway / upstream proxy
```

---

## 13. 最终设计决策摘要（供快速复用）

### 必须坚持
- 主控制面在宿主机
- task execution 在 Docker sandbox
- Claude Code CLI 正式纳入体系
- 强门控在 Claude `PreToolUse` command hook
- 宿主机副作用必须走 broker
- SOP 单一权威源 + 双层发布
- OpenClaw 深度控制在 2，容器内细分交给 Claude Code subagents

### 明确禁止
- main 直接拿 `exec + elevated`
- runner 拿全局 workspace `rw`
- 容器内直接操作 `/etc/openclaw`、`/opt/openclaw`、systemd
- 把未验证的 Docker 接入方案写成既定事实
- 把 `PermissionRequest` 当自动化主门控
- 让 task 容器持有长期上游密钥

---

## 14. 下一步最优执行顺序

如果按“最小风险、最大收益”的顺序推进，建议：

1. **先做 Phase 0**：把 Claude Code 开发仓库与 SOP 发布体系建起来  
2. **再做 Phase 1**：main agent 上线，但不给执行权  
3. **再做 Phase 2**：broker 与只读 host_ops 先跑通  
4. **之后做 Phase 3**：Docker capability probe，确认 sandbox 能否安全落地  
5. **再做 Phase 4**：把 Claude Code 放进 task container  
6. **最后做 Phase 5-6**：上游代理与宿主机变更闭环

这是最稳的次序。先把“控制面正确”建立起来，再把“自动执行面”接入。

---

## 15. 文档状态

- 本文档是 **v3 实施规格稿**
- 可直接作为后续开发仓库中的 `docs/design-v3.md`
- 后续只允许在以下条件下进入 v4：
  1. Docker capability probe 有实测结论；
  2. Claude Code 容器内 hook 链完成验收；
  3. broker 首批 wrapper 已真实跑通。
