# Skill 开发指南

## 什么是 Skill

Skill 是 OpenClaw agent 的可激活能力模块。每个 skill 是一个 `SKILL.md` 文件，描述 skill 的触发条件、执行步骤和输出规范。Agent 在收到匹配任务时自动激活对应 skill。

## 创建 Skill

### 1. 创建目录

在对应 workspace 模板下创建 skill 目录：
```bash
mkdir -p workspace-task-runner-template/skills/<skill-name>/
```

### 2. 编写 SKILL.md

**必须包含 YAML frontmatter**（没有 frontmatter 的 skill 会被 gateway 静默丢弃）：

```markdown
---
name: skill-name
description: |
  一句话描述 skill 做什么以及何时激活。
---

# Skill 标题

**Trigger**: 描述何时使用此 skill

## Steps

### 1. 第一步
...

### 2. 第二步
...

## Output
描述 skill 的输出格式和位置。
```

### 3. 验证

```bash
bash scripts/check-workspace-skills.sh workspace-task-runner-template
```

### 4. 发布

```bash
sudo bash scripts/publish-workspace-all.sh --apply --allow-live-target all
```

## Frontmatter 规则

| 字段 | 必须 | 说明 |
|------|------|------|
| `name` | ✅ | 必须与父目录名一致 |
| `description` | ✅ | 一句话描述，用于 agent 判断是否激活 |

⚠ **常见错误**：
- 缺少 `description` → skill 被静默丢弃
- CRLF 换行符 → 检查脚本误报 frontmatter 缺失
- `name` 与目录名不匹配 → 加载失败

## 现有 Skill 参考

### main agent (6 skills)
| Skill | 用途 |
|-------|------|
| host-sop | 宿主机 SOP 查询 |
| routing | 消息路由策略 |
| approvals | 审批流程 |
| broker | host-ops broker 交互 |
| task-delegation | 任务分配和多步编排 |
| host-change-review | host-change-request 审批 |

### task-runner (12 skills)
| Skill | 用途 |
|-------|------|
| task-init | 任务初始化（创建目录 + 复制模板） |
| task-state | 步间状态管理 |
| coding | 编码任务 |
| testing | 测试执行 |
| research | 通用研究 |
| literature-search | 文献检索 |
| data-analysis | 数据分析 |
| hypothesis-generation | 假设生成 |
| experiment-loop | 实验循环 |
| autoresearch | 自动化研究 |
| report | 报告生成 |
| scrapling | Web scraping |

## 设计新 Skill 的建议

1. **单一职责**：每个 skill 做一件事
2. **明确触发条件**：description 要准确描述何时激活
3. **定义输入输出**：说明 skill 需要什么、产出什么
4. **引用 schema**：如果有结构化输出，引用对应的 JSON schema
5. **示例驱动**：在 skill 中给出具体的命令和输出示例
