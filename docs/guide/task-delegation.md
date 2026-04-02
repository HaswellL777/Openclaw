# 任务编排指南

## 任务生命周期

```
用户发起请求
  → main 分析任务类型和复杂度
  → main 选择 agent 和模型
  → sessions_spawn 创建子 agent session
  → task-runner 调用 task-init skill 初始化任务目录
  → task-runner 执行任务
  → 输出写入 /workspace/outputs/<task-id>/
  → completion event 通知 main
  → main 审查结果并回复用户
```

## 任务目录结构

每个任务在 `/workspace/outputs/<task-id>/` 下创建标准化目录：

```
/workspace/outputs/20260402-investment-backtest/
  CLAUDE.md           # ACP 项目规则（从 project-template 复制）
  .claude/            # ACP 配置和 agents（从 project-template 复制）
  README.md           # 任务元数据
  summary.json        # 机器可读结果（必须）
  summary.md          # 人类可读摘要（必须）
  plan.md             # 执行计划
  task-state.json     # 步间状态（多步任务）
  host-change-request.json  # 宿主机变更请求（如需要）
  data/               # 输入数据
  results/            # 处理结果
  logs/               # 执行日志
```

## 多步任务编排

### task-state.json 模式

每步完成时写入状态，下一步读取：

```json
{
  "taskId": "20260402-investment-backtest",
  "currentStep": 2,
  "totalSteps": 5,
  "steps": {
    "1": {
      "status": "completed",
      "description": "获取历史行情数据",
      "outputs": ["data/stock_prices.csv", "data/metadata.json"],
      "completedAt": "2026-04-02T10:30:00Z"
    }
  }
}
```

### main 编排模式

main 的 task-delegation skill 使用以下模式：

```
Step 1/N: spawn task-runner →
  "task-id: 20260402-xxx. Step 1/N: <具体任务描述>"
  ↓ (等待 completion event)

Step 2/N: spawn task-runner →
  "task-id: 20260402-xxx. Step 2/N: 读取 task-state.json。<具体任务描述>"
  ↓ (等待 completion event)

... 重复直到所有步骤完成 ...

FINAL: 读取最终输出，综合汇报给用户
```

## Schema 参考

- 任务摘要：`/workspace/schemas/task-runner-summary.schema.json`
- 宿主机变更请求：`/workspace/schemas/host-change-request.schema.json`
- 产出契约：`/workspace/control/artifact-contract.md`

## 宿主机变更流程

当任务需要修改宿主机配置时：

```
task-runner 产出 host-change-request.json
  → main 的 host-change-review skill 审批
  → 如果批准 → main 调用 broker skill
  → broker daemon 执行 wrapper（pre-snapshot → 变更 → 验证 → post-snapshot）
  → 结果回写
```
