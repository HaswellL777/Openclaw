# Agent 编排指南

## 可用 Agent

| Agent | 模型 | Workspace | 适合任务 |
|-------|------|-----------|---------|
| **main** | GPT-5.4 | workspace-main | 对话、任务分配、审批、编排 |
| **task-runner** | deepseek-chat | workspace-task-runner | 编码、数据处理、分析、爬虫 |
| **research-coordinator** | opus-4-6 | workspace-research-coordinator | 多步骤研究编排 |
| **auditor** | opus-4-6 | workspace-auditor | 质量审计、代码审查 |
| **ACP claude** | claude | （容器内项目模板） | 深度代码分析、复杂重构 |

## Agent 协作模式

### 单步任务
```
用户 → main → sessions_spawn(task-runner) → 结果 → main → 用户
```

### 多步骤任务
```
用户 → main → spawn step 1 → wait → spawn step 2 → ... → synthesize → 用户
```

步间状态通过 `/workspace/outputs/<task-id>/task-state.json` 传递。

### 研究编排
```
用户 → main → spawn(research-coordinator) → RC spawn(task-runner) × N → RC 汇总 → main → 用户
```

### 质量审计
```
任务完成后 → main → spawn(auditor, "审计 <task-id>") → 审计报告 → main → 用户
```

## 模型选择

`sessions_spawn` 支持 `model` 参数覆盖默认模型：

```
sessions_spawn(agentId: "task-runner", model: "duckcoding-claude/claude-opus-4-6", task: "...")
```

- **简单编码/脚本** → 默认模型
- **复杂算法/推理** → claude-opus-4-6 或 gpt-5.4
- **数据采集/爬虫** → 默认模型

## 添加新 Agent

1. 在 `/etc/openclaw/openclaw.json` 的 `agents` 部分添加配置
2. 创建 `workspace-<agent>-template/` 目录
3. 编写 AGENTS.md 和 TOOLS.md
4. 创建 skill 集合
5. 发布 workspace

> ⚠ 修改 openclaw.json 需要走 escalation 流程（pre-snapshot → 变更 → 验证 → post-snapshot）
