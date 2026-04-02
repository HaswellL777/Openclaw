# OpenClaw 系统概览

> 更新日期：2026-04-02

## 什么是 OpenClaw

OpenClaw 是一个多 Agent 编排系统，运行在宿主机上，通过 LLM 驱动的 Agent 协作完成复杂任务。

## 系统能力

### Agent 编排
- **main** (GPT-5.4) — 任务分配、结果审查、用户对话
- **task-runner** (deepseek-chat) — 工程执行、数据处理、编码分析（Docker sandbox 内）
- **research-coordinator** (opus-4-6) — 多步骤研究编排
- **auditor** (opus-4-6) — 质量审计
- **ACP claude** — Claude Code 深度代码分析

### 执行环境
- Docker 沙箱（GPU 支持，CUDA 12.8 + PyTorch）
- 只读根文件系统，隔离安全
- 共享容器模式，按需启动
- 网络隔离（openclaw-task-net）

### 管理界面
- GUI 管理前端（16 页面，端口 3000）
- 实时 Chat + Streaming
- Session 管理 + Task Flow 可视化
- Docker 容器 + Cron + 日志 + 配置查看

### 宿主机操作
- Broker daemon + 8 个 host-ops action
- 审批链：task-runner → main 审批 → broker 执行
- 快照/恢复链完整

## 快速开始

1. 阅读 [Agent 编排指南](agents.md)
2. 阅读 [Skill 开发指南](skills.md)
3. 阅读 [任务编排指南](task-delegation.md)

## 目录结构

```
workspace-main-template/        # main agent workspace 模板
workspace-task-runner-template/  # task-runner workspace 模板（含 skill、schema、project-template）
workspace-*-template/            # 其他 agent workspace 模板
gui/                             # GUI 管理前端源码
plugins/                         # OpenClaw 插件
scripts/                         # 部署和运维脚本
docs/guide/                      # 使用者指南（本目录）
docs/internal/                   # 基础设施参考文档
docs/current-boundary.md         # 当前系统状态
```

## 当前状态

详见 [current-boundary.md](../current-boundary.md)
