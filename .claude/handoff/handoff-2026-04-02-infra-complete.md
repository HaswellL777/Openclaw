# OpenClaw 对话交接提示词

> 生成日期：2026-04-02
> 上一轮：Phase 4/6 close — 全基础设施完成，文档树重构为使用者导向
> 模型：Claude Opus 4.6 (1M context)

---

## 第零部分：必读文档（开始工作前必须读完）

**按此顺序读取，不可跳过**：
1. `CLAUDE.md` — 安全边界、escalation 规则、anti-stall 规则
2. `docs/current-boundary.md` — 唯一实时状态文件
3. `docs/guide/README.md` — 系统能力概览（面向使用者）
4. `docs/guide/agents.md` — Agent 编排指南
5. `.claude/handoff/handoff-2026-04-02-infra-complete.md` — 本文件

---

## 第一部分：基础设施状态（已完成，不需要继续开发）

截至 2026-04-02，OpenClaw 基础设施全部就绪：

| 组件 | 状态 | 说明 |
|------|------|------|
| Gateway | ✅ 运行中 | systemd 服务，OpenClaw 2026.3.23-2 |
| Broker | ✅ 运行中 | 8 个 host-ops action，root wrapper 链 |
| Docker sandbox | ✅ 运行中 | scope=shared, GPU(CUDA 12.8), ReadonlyRootfs |
| GUI | ✅ 运行中 | 16 页面，token auth，端口 3000 |
| 多 Agent 编排 | ✅ 运行中 | main(GPT-5.4), task-runner(deepseek), RC(opus-4-6), auditor(opus-4-6) |
| ACP Claude Code | ✅ 可用 | acpx + DuckCoding proxy |
| 备份/恢复 | ✅ 脚本就绪 | backup + restore + validate，已完成演练 |
| 权限持久化 | ✅ 已部署 | tmpfiles.d + systemd ExecStartPost |
| Hotfixes (3个) | ✅ 生效中 | streamTo noop, chmod 0640, cleanup keep |

**不需要再做基础设施开发。** 后续会话聚焦于使用系统构建业务能力。

---

## 第二部分：验证路线图 — 三阶段投资系统

### 阶段 1: Paper Money 模拟投资系统

**目标**：验证 OpenClaw 的端到端 harness 循环能力。与投资领域专家合作。

**合作模式**：
- **投资专家负责**：投资逻辑设计、策略定义、信息源选择、决策框架、agent 编排思路
- **OpenClaw 系统负责**：执行实现、数据获取、计算分析、报告生成、自动化编排

**需要共同定义的**：
1. 投资策略框架（价值 / 动量 / 量化 / 因子模型等）
2. 信息源（财务数据 API、新闻、社交媒体、基本面数据）
3. 决策流程（信号生成 → 风险评估 → 持仓管理 → 执行）
4. 所需 Skill（行情获取、财务分析、回测、报告等）
5. 所需 Tool（数据 API、计算引擎、可视化）
6. Agent 编排方案（哪些 agent 负责哪些环节）
7. 评价指标（收益率、夏普比率、最大回撤等）

**技术准备清单**：
- [ ] 定义投资分析 skill 集合
- [ ] 接入市场数据 API（tushare / akshare / yfinance 等）
- [ ] 构建回测框架
- [ ] 构建 paper trading 模拟引擎
- [ ] 定义 portfolio 状态存储格式
- [ ] 定义 agent 协作流程（research → analysis → decision → execution → report）
- [ ] 构建评价和报告 skill

### 阶段 2: Steam 余额市场浅层真实实验

**目标**：在变量少但波动大的真实市场中验证系统。

**特点**：
- 市场规模小，参与者有限
- 价格波动大，适合验证策略逻辑
- 交易成本低，试错代价小
- 真实资金但风险可控

**需要额外构建的**：
- Steam 市场数据采集（API / 爬虫）
- 交易执行接口
- 实时监控和风控 skill
- 异常检测和止损机制

### 阶段 3: 真实投资

**目标**：将验证过的能力应用到真实金融市场。

（在阶段 1-2 完成后再详细规划）

---

## 第三部分：系统能力快速参考

### 可用 Agent

| Agent | 模型 | 能力 | 适合任务 |
|-------|------|------|---------|
| main | GPT-5.4 | 编排、审批、对话 | 任务分配、结果审查、用户交互 |
| task-runner | deepseek-chat | 工程执行 | 编码、数据处理、API 调用、分析 |
| research-coordinator | opus-4-6 | 研究编排 | 多步骤研究、文献综述、实验设计 |
| auditor | opus-4-6 | 质量审计 | 代码审查、报告质量检查 |
| ACP claude | claude | Claude Code | 深度代码分析、复杂重构 |

### 创建新 Skill

在 `workspace-task-runner-template/skills/<skill-name>/SKILL.md` 创建：

```yaml
---
name: skill-name
description: |
  一句话描述 skill 做什么以及何时激活。
---
```

发布：`sudo bash scripts/publish-workspace-all.sh --apply --allow-live-target all`

### 多阶段任务编排

main agent 的 `task-delegation` skill 支持：
- 单步任务：spawn → wait → report
- 多步任务：spawn step 1 → wait → spawn step 2 → ... → synthesize → report
- 步间状态传递：通过 `/workspace/outputs/<task-id>/task-state.json`
- 模型选择：按步骤需求选择不同模型

### 数据和输出

- 容器工作目录：`/workspace/`
- 任务输出：`/workspace/outputs/<task-id>/`
- Knowledge（只读）：`/workspace/knowledge/`
- Schema：`/workspace/schemas/`
- 项目模板：`/workspace/project-template/`

---

## 第四部分：下一步行动

1. **与投资专家对齐**：确定阶段 1 的具体投资策略和信息源需求
2. **定义 Skill 集合**：基于投资需求设计 task-runner skill
3. **接入数据源**：选择并接入市场数据 API
4. **构建回测框架**：在 Docker sandbox 中搭建回测引擎
5. **定义 Agent 协作流程**：main 编排、task-runner 执行、auditor 审计

---

## 第五部分：技术参考（开发向）

如需修改基础设施，参考：
- `docs/internal/design-v3.md` — 架构设计规格
- `docs/internal/host-sop.md` — 宿主机操作 SOP
- `docs/internal/specs/` — 冻结协议规格
- `scripts/` — 部署和运维脚本
