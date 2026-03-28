# Skills 体系扩展设计

> 日期：2026-03-25
> Close-by：2026-04-01（实施或归档）
> 状态：draft

---

## 1. 当前 Skills 现状

### 已有 skills（workspace-main-template/skills/）

| Skill | 用途 | 类型 |
|-------|------|------|
| `approvals` | 审批策略查询 | 控制面 |
| `broker` | host-ops broker 接口 | 控制面 |
| `host-sop` | 宿主机 SOP 查询 | 控制面 |
| `routing` | 任务路由策略 | 控制面 |

### 现状问题

1. 只有控制面 skills，没有工程/研究类 skills
2. task-runner workspace 没有任何 skills
3. 没有 skill 发现机制（agent 只能看到 `skills/` 下的目录）
4. 没有 skill 模板标准（现有 SKILL.md 格式不一致）
5. agent 不能自主创建 skill

---

## 2. 设计目标

1. **控制面 vs 执行面 skill 分界清晰**：main agent 的 skill 不进入 task-runner，反之亦然
2. **标准化 SKILL.md 格式**：所有 skill 遵循统一模板
3. **支持 operator 添加外部 skill**（科研、autoresearch 等）
4. **为 agent 自主编写 skill 铺路**（Phase 4 ACP 后更自然）
5. **不过度工程**：当前只做目录结构和模板，不做运行时发现机制

---

## 3. Skill 目录结构设计

### 3.1 workspace-main（控制面 skills）

```
workspace-main-template/skills/
├── approvals/SKILL.md          # 既有
├── broker/SKILL.md             # 既有
├── host-sop/SKILL.md           # 既有
├── routing/SKILL.md            # 既有
├── task-delegation/SKILL.md    # 新增：委托任务给 task-runner
└── system-status/SKILL.md      # 新增：系统状态汇总
```

main agent 的 skill 关注：
- 宿主机管理（broker, snapshot, config deploy）
- 任务调度（routing, delegation）
- 状态查询（host-sop, system-status）
- 审批流程（approvals）

### 3.2 workspace-task-runner（执行面 skills）

```
workspace-task-runner-template/skills/
├── coding/SKILL.md             # 代码编写规范
├── testing/SKILL.md            # 测试编写与执行
├── research/SKILL.md           # 技术调研（搜索+总结）
├── autoresearch/SKILL.md       # 自动化研究循环
├── scrapling/SKILL.md          # Web 抓取（Scrapling，待 Dockerfile 接入后启用）
└── report/SKILL.md             # 报告生成
```

task-runner 的 skill 关注：
- 工程执行（coding, testing）
- 信息获取（research, autoresearch, scrapling）
- 产出（report）

### 3.3 Operator 自定义 skill 目录

```
workspace-*/skills/custom/      # operator 可直接在此目录添加自定义 skill
├── science-lit-review/SKILL.md
├── patent-search/SKILL.md
└── data-pipeline/SKILL.md
```

约定：`skills/custom/` 下的 skill 不在 repo 模板中管理，由 operator 直接在 live workspace 中创建。
publish 脚本不覆盖此目录（需修改 `publish-workspace-main.sh` 的 rsync 逻辑加 `--exclude skills/custom/`）。

---

## 4. SKILL.md 标准模板

```markdown
# <Skill Name>

## Skill identity
- **Name**: `<skill-id>` (lowercase, hyphen-separated)
- **Owner**: `<main|task-runner|claude-engineer>`
- **Purpose**: <one-line description>
- **Status**: <draft|operational|deprecated>

## Prerequisites
<!-- tools, packages, or config this skill depends on -->
- <prerequisite 1>
- <prerequisite 2>

## What this skill does
<2-3 paragraphs explaining the skill's capability>

## When to use this skill
<!-- trigger conditions: when should the agent activate this skill? -->
- <trigger condition 1>
- <trigger condition 2>

## Workflow
<!-- step-by-step procedure -->
1. <step 1>
2. <step 2>
3. <step 3>

## Input format
<!-- what the agent receives when this skill is invoked -->
```
<example input>
```

## Output format
<!-- what the agent should produce -->
```
<example output>
```

## Safety rules
<!-- constraints and guardrails -->
- <rule 1>
- <rule 2>

## Related skills
- `<related-skill>`: <how it relates>
```

---

## 5. Agent 自主编写 Skill 路径

### 5.1 当前限制

- main agent 对 workspace 有 `rw` 访问，理论上可以创建 `skills/` 下的文件
- 但没有 self-discovery 机制：新创建的 skill 不会自动被其他 session 看到（需 gateway restart 或 session 重建）
- task-runner 的 workspace 是 session-scoped，写入的 skill 在容器销毁后丢失

### 5.2 Phase 4 ACP 后的可行路径

1. **ACP Claude Code session 创建 skill**：
   - Claude Code 可在 task-workspaces 中创建 skill 文件
   - main agent 通过 workspace rw 将 skill 复制到 workspace-main 或 workspace-task-runner
   - publish 脚本将模板同步到 live

2. **反馈循环**：
   - Agent 执行任务 → 总结有效模式 → 生成 SKILL.md → 放入 `skills/custom/`
   - Operator 审阅 → 接受则保留，拒绝则删除
   - 被接受的 skill 可提升到模板 repo

3. **自动化程度递进**：
   - Level 0（当前）：operator 手写 skill，publish 到 live
   - Level 1（Phase 4 后）：agent 建议 skill，operator 审阅后 publish
   - Level 2（远期）：agent 创建 skill 到 `skills/custom/`，自动可用于后续 session

### 5.3 不做什么

- 不做 skill registry / discovery service
- 不做 skill versioning（Git 已足够）
- 不做 skill marketplace
- 不做运行时 skill loading（skill 就是 markdown 文件，agent 读取即可）

---

## 6. 需要的实施步骤

### 6.1 本轮可做（repo-side scaffolding）

1. 在 `workspace-task-runner-template/` 下创建 `skills/` 目录
2. 创建 `coding/SKILL.md`、`testing/SKILL.md`、`research/SKILL.md`、`report/SKILL.md`
3. 在 `workspace-main-template/` 下创建 `task-delegation/SKILL.md`
4. 修改 `publish-workspace-main.sh` 添加 `--exclude skills/custom/`

### 6.2 后续（需 operator 操作）

1. Publish 更新后的 workspace-main-template
2. 在 live workspace-task-runner 中创建 skills/
3. Operator 自定义 skill 直接写入 live workspace 的 `skills/custom/`

---

## 7. Operator 外部 Skill 示例

Operator 提到的外部 skill 类型：

| Skill | 适合的 owner | 备注 |
|-------|-------------|------|
| 科研文献综述 | task-runner | 需要网络、搜索、长文本处理 |
| autoresearch 循环 | task-runner | 需要长期任务支持（见 long-running-tasks-design） |
| 数据采集 (Scrapling) | task-runner | 需要 Scrapling 在镜像中（见任务 6） |
| 代码 review | task-runner / claude-engineer | ACP 后可用 claude-engineer |
| 专利搜索 | task-runner | 需要网络、结构化输出 |

这些 skill 的 SKILL.md 可以由 operator 编写放入 `skills/custom/`，也可以在 ACP 上线后由 agent 协助编写。
