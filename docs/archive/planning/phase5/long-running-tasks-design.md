# 长期任务支持方案设计

> 日期：2026-03-25
> Close-by：2026-04-01（选择方案并实施，或归档）
> 状态：draft

---

## 1. 需求

Operator 希望运行持续数十小时的自动化研究循环：

```
获取数据 → 分析 → 写代码 → 实验 → 改进 → 测试 → 生成报告
```

### 当前限制

| 项目 | 当前值 | 问题 |
|------|--------|------|
| sandbox.scope | `"session"` | 容器随 session 结束销毁，不持久 |
| subagents.runTimeoutSeconds | 3600 (1h) | 单次执行不能超过 1 小时 |
| subagents.archiveAfterMinutes | 120 (2h) | 子 agent 归档后上下文丢失 |
| prune.idleHours | 4 | 空闲 4 小时后容器被清理 |
| prune.maxAgeDays | 3 | 容器最长存活 3 天 |
| GPU | vLLM 占用 ~14.2GB/16.3GB | 几乎无剩余给容器 GPU 任务 |

---

## 2. 三个方案

### Option A：调整现有参数（最小变更）

**做什么**：
1. 将 `scope` 从 `"session"` 改为 `"shared"` — 所有 task-runner session 共享一个容器
2. 调大 `runTimeoutSeconds` 到 14400 (4h) 或 43200 (12h)
3. 调大 `archiveAfterMinutes` 到 720 (12h) 或 1440 (24h)
4. 调大 `prune.idleHours` 到 24
5. 任务编排由 main agent 通过多次 `sessions_spawn` 实现

**优点**：
- 零新组件，仅改配置
- shared scope 意味着容器内的文件跨 session 保留
- 主 agent 可以分步发起 session，每步继承前一步的文件

**缺点**：
- 没有真正的任务编排层（main agent 必须在线才能驱动循环）
- 如果 main agent session 中断，循环中断
- shared scope 意味着多任务可能互相干扰（文件冲突）
- 不支持"无人值守"运行

**配置 candidate（delta）**：
```json5
{
  agents: {
    defaults: {
      subagents: {
        runTimeoutSeconds: 14400,     // 4 hours
        archiveAfterMinutes: 1440,    // 24 hours
      },
      sandbox: {
        prune: {
          idleHours: 24,
          maxAgeDays: 7,
        },
      },
    },
    list: [
      {
        id: "task-runner",
        sandbox: {
          scope: "shared",     // was: "session"
        },
      },
    ],
  },
}
```

### Option B：Task Orchestration Skill（main agent 驱动循环）

**做什么**：
1. Option A 的配置变更作为基础
2. 创建 `autoresearch` skill（main agent 侧），定义循环步骤
3. 每个步骤通过 `sessions_spawn` 委托给 task-runner
4. 步骤之间的状态通过 shared workspace 中的文件传递
5. Main agent 读取上一步输出，决定下一步

**架构**：
```
main agent (循环驱动)
  ├── step 1: sessions_spawn(task-runner) → 获取数据 → /workspace/outputs/step1.json
  ├── step 2: sessions_spawn(task-runner) → 分析数据 → /workspace/outputs/step2.json
  ├── step 3: sessions_spawn(task-runner) → 写代码 → /workspace/repo/
  ├── step 4: sessions_spawn(task-runner) → 实验 → /workspace/outputs/step4.json
  ├── step 5: sessions_spawn(task-runner) → 改进 → /workspace/repo/
  └── step 6: sessions_spawn(task-runner) → 报告 → /workspace/outputs/report.md
```

**优点**：
- 利用现有基础设施
- 每步有明确的输入/输出契约
- main agent 可以在步骤间做智能决策（是否继续、调整方向）
- 失败可以重试单个步骤

**缺点**：
- main agent 必须保持在线驱动循环
- 飞书 session 可能超时
- 步骤间延迟（每次 spawn 有开销）
- 需要 ACP（Phase 4）才能让 claude-engineer 驱动更复杂的循环

### Option C：Dedicated Long-running Agent（独立长期 agent）

**做什么**：
1. 定义新 agent `long-runner`，scope=shared，超长 TTL
2. `long-runner` 有自己的 workspace，包含循环编排逻辑
3. 循环驱动逻辑写在 workspace 的 CLAUDE.md / skills 中
4. main agent 只负责启动和监控
5. 需要 ACP Claude Code 或类似持久进程在容器/宿主机运行

**架构**：
```
main agent
  └── sessions_spawn(long-runner, runtime: "acp")
        └── Claude Code ACP session (persistent)
              ├── step 1: 获取数据
              ├── step 2: 分析
              ├── ... (自主循环)
              └── report back to main
```

**优点**：
- 真正的"无人值守"运行
- 循环逻辑完全自包含
- main agent 不需要一直在线
- 利用 ACP session 的 persistent mode

**缺点**：
- 需要 Phase 4 ACP 先完成
- ACP session TTL 限制（当前设计 60 min，需大幅调大）
- Claude Code context window 限制（单 session 不能无限运行）
- 需要设计 checkpoint/resume 机制
- 安全风险：长时间无人监控的 approve-all session

---

## 3. 推荐

**推荐 Option B（Task Orchestration Skill），分两阶段实施。**

### Phase 1（现在可做）：
- 将 task-runner scope 改为 shared
- 调大 timeout/archive/prune 参数
- 创建 autoresearch skill 模板（main agent 侧）
- main agent 手动驱动循环（通过飞书对话）

### Phase 2（Phase 4 ACP 完成后）：
- 用 ACP Claude Code session 驱动循环（Option C 的简化版）
- ACP session 做"思考"和编排，task-runner 做"执行"
- 设计 checkpoint/resume 机制处理 session 中断

### 为什么不推荐 Option A：
- 纯参数调整没有编排层，无法实现真正的自动循环
- 只适合单步长任务，不适合多步骤研究循环

### 为什么不推荐 Option C（现在）：
- 依赖 Phase 4 ACP，当前不可用
- 但 Phase 2 实施时应瞄准此方向

---

## 4. GPU 方案

### 当前状态

- RTX 5060 Ti 16GB, CUDA 13.1, Driver 590.48.01
- vLLM 占用 ~14.2GB / 16.3GB VRAM
- 容器 GPU 透传技术上可行（`docker run --gpus all`）
- 但实际上没有剩余 VRAM

### 选项

| 选项 | VRAM 释放 | 影响 |
|------|-----------|------|
| A. 停掉 vLLM | ~14.2GB | 失去本地 LLM 审计能力（已决定不需要，§5.5 ABANDONED） |
| B. vLLM + 容器共存 | 0 | 容器 GPU 任务 OOM |
| C. 按需切换（停 vLLM → 跑 GPU 任务 → 重启 vLLM） | 按需 ~14.2GB | 复杂，需编排 |

### 推荐

**Option A：停掉 vLLM，释放全部显存给容器 GPU 任务。**

理由：
1. §5.5 gate shim + vLLM audit 已 ABANDONED，vLLM 审计功能不再需要
2. 当前模型路由全走 MotChat 代理（deepseek/Claude/GPT），本地 vLLM 无生产用途
3. 释放 14.2GB VRAM 可以支持容器内运行中小规模 ML 任务
4. 如果未来需要本地 LLM，可以重新启动 vLLM

**Operator 命令**：
```bash
# 检查 vLLM 进程
ps aux | grep vllm

# 如果是 systemd 管理：
sudo systemctl stop vllm
sudo systemctl disable vllm

# 如果是手动运行：
# 找到 PID 并 kill

# 验证 GPU 释放
nvidia-smi
```

**Docker GPU 透传配置**（停掉 vLLM 后）：

在 openclaw.json 的 task-runner sandbox.docker 中添加：
```json5
{
  docker: {
    // ... existing config ...
    gpus: "all",    // 或 "device=0" 指定 GPU
  }
}
```

注意：OpenClaw sandbox.docker 是否支持 `gpus` 字段需要查阅文档确认。如果不支持，
可能需要在 Dockerfile 或 docker run 命令中另行处理。

---

## 5. 实施步骤（Phase 1）

1. 生成 openclaw.json candidate（scope: shared + timeout 调整）
2. 创建 autoresearch skill 模板（workspace-main-template/skills/autoresearch/SKILL.md）
3. Operator deploy config candidate
4. Operator 停掉 vLLM（如果决定释放 GPU）
5. 测试：从飞书发送多步骤研究任务，验证 shared scope 下文件持久性
