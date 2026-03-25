# ADR: Scrapling 系统定位

> 决策日期：2026-03-18
> 状态：已决策
> 决策者：nick (operator) + Claude Code (旁路审计)

---

## 背景

Scrapling 是 Python 3.10+ 的自适应 Web 抓取框架（BSD-3-Clause），核心能力包括：
- HTTP 请求 + 自适应 HTML 解析（自动重定位元素）
- 浏览器自动化（Playwright Chromium / Camoufox 反检测浏览器）
- 内置 MCP server（供 AI agent 调用）
- Spider/Crawler 框架（并发爬取、代理轮换）

需要决定 Scrapling 在 OpenClaw 体系中的正确位置。

## 决策

**Scrapling 不进入控制面，不进入 host_ops。Scrapling 定位为 task-runner / Docker 执行面 capability。**

## 排除的方案

### 方案 A：控制面 plugin（排除）

排除原因：
- `main` agent 无 `exec` 能力，无法运行 Python 进程
- 控制面 plugin 运行在 gateway 进程中，引入 Python + 浏览器引擎依赖不合理
- Scrapling 需要外网访问目标站点，控制面不应有广泛出站网络

### 方案 B：host_ops broker action（排除）

排除原因：
- broker 是宿主机状态变更通道（snapshot / config deploy / restart），不是数据采集通道
- 抓取任务是工程执行面工作，不是宿主机控制面工作
- 在宿主机直接运行浏览器引擎违反最小权限原则

### 方案 C：main agent MCP 直连（排除）

排除原因：
- Scrapling MCP server 需要运行在有网络和浏览器的环境中
- main agent 运行环境没有 Python、没有浏览器、没有广泛出站网络
- 把 Scrapling MCP 暴露给主控制面会扩大控制面攻击面

## 选定方案：task-runner Docker 执行面 capability

### 实施路径（Phase 3+ 时期落地）

- Scrapling 作为任务镜像 `openclaw-task-claude` 的可选 layer 预装
- task-runner 容器通过 `openclaw-task-net` 提供受控网络出口
- 容器内 Claude Code 可通过 Scrapling MCP server 或 Python API 调用抓取能力
- 容器销毁时 Scrapling SQLite 缓存一并清理

### 为什么是这个位置

1. **网络隔离**：抓取需要外网，task-runner 容器通过自定义 bridge 网络提供白名单出站，符合 `design-v3.md` §5.2.6
2. **资源隔离**：浏览器引擎消耗大量 CPU/内存，容器内受 cgroups 限制，不污染控制面
3. **安全边界**：抓取涉及执行不可信 JavaScript（浏览器引擎），必须在 sandbox 内
4. **生命周期**：抓取是一次性任务，符合 task-runner "一次任务一容器" 模型
5. **MCP 兼容**：Scrapling 内置 MCP server，未来 Claude Code 在容器内可直接通过 MCP 调用

## 风险与边界

| 风险 | 缓解 |
|------|------|
| 浏览器引擎逃逸 | sandbox 容器只读 rootfs + 非 root 用户 + seccomp |
| 抓取合规性 | 容器内 CLAUDE.md 中明确 robots.txt / ToS 遵守规则 |
| 依赖膨胀 | 可选 layer：仅需 HTTP 抓取时只装 parser（无浏览器） |
| 宿主机 IP 暴露 | task 容器共享宿主机出口 IP；未来可通过 proxy 隔离 |

## 当前状态

**Scrapling 已加入 Dockerfile.full（2026-03-25）。**
- HTTP-only mode（pip install scrapling，无浏览器引擎）
- 浏览器自动化（Playwright Chromium）作为可选扩展，当前未安装
- Scrapling skill 模板已创建：`workspace-task-runner-template/skills/scrapling/SKILL.md`（待镜像重建后启用）
- 镜像重建命令见下方 operator 操作清单
