# 容器隔离方案设计

> 日期：2026-03-27
> close-by：2026-04-01（设计文档，依赖阶段 B/C 部署后的运行验证）
> 状态：**设计完成，repo-side only，不部署**

---

## 1. Operator 需求

1. 不同大任务用独立容器，同一任务下的 agent 共享容器
2. 三档生命周期：一次性（单次任务）、中期（数天研究项目）、固化（大型项目，销毁需批准）
3. Per-task 目录：`/workspace/outputs/<task-id>/` 替代扁平的 `/workspace/outputs/`

## 2. OpenClaw sandbox.scope 源码事实

**文件**：`docker-Bhjg8g2t.js:337-340`（resolveSandboxScope）

| scope 值 | 行为 | 容器名 |
|----------|------|--------|
| `"shared"` | 所有 session 共享 1 个容器 | `openclaw-sbx-shared` |
| `"session"` | 每个 session 独立容器 | `openclaw-sbx-{session-slug}-{hash}` |
| `"agent"` | 每个 agent ID 一个容器（默认值） | `openclaw-sbx-agent-{agentid}-{hash}` |

**关键限制**（`docker-Bhjg8g2t.js:343`）：
- `scope === "shared"` 时，per-agent docker 配置（image/network/tmpfs）被忽略
- 没有 `"per-task"` scope
- 没有动态 label/tag 机制来关联容器与任务

**Prune 配置**（`docker-Bhjg8g2t.js:404-410`）：
- `sandbox.prune.idleHours`：空闲多久后自动清理（默认 24h）
- `sandbox.prune.maxAgeDays`：最大存活天数（默认 7d）
- 当 `scope === "shared"` 时，agent-level prune 配置被忽略

**容器命名**（`docker-Bhjg8g2t.js:1189-1191`）：
```
${containerPrefix}${slug}
containerPrefix = "openclaw-sbx-" (default)
slug = "shared" | slugifySessionKey(scopeKey) | "agent:{agentId}"
```

## 3. 方案对比

### 方案 A：保持 shared scope + 软目录隔离（推荐）

**改动范围**：仅 workspace skill/policy，不改 OpenClaw config

**原理**：
- 保持当前 `scope: "shared"` 不变
- 在容器内通过目录规范实现 per-task 隔离
- task-runner 和 research-coordinator 在 skill 中强制使用 task 目录

**目录结构**：
```
/workspace/
├── outputs/
│   ├── <task-id>/           # 每个任务独立目录
│   │   ├── README.md        # 任务描述 + 状态
│   │   ├── data/            # 数据文件
│   │   ├── results/         # 结果文件
│   │   └── logs/            # 执行日志
│   └── _shared/             # 跨任务共享资源
├── knowledge/               # ro bind mount（不变）
├── skills/                  # skill 定义（不变）
└── control/                 # 控制文件（不变）
```

**task-id 命名规范**：`YYYYMMDD-<短描述>`（例：`20260327-protein-folding-survey`）

**优势**：
- 零 config 变更，无 gateway restart
- 兼容当前 shared container，所有 agent 都能看到所有 task 输出
- 通过 skill 约束而非基础设施约束实现隔离

**劣势**：
- 隔离是"软"的——agent 可以访问其他 task 的目录
- 无法做到真正的资源隔离（CPU/内存限制 per task）

**三档生命周期映射**：
| 档位 | OpenClaw 机制 | 清理 |
|------|---------------|------|
| 一次性 | task 完成后 agent 通过 skill 标记 `status: completed` | 手动或 cron 清理 |
| 中期 | 同上，但 `status: active` 持续数天 | `prune.maxAgeDays` 不适用（目录级） |
| 固化 | `status: protected` 标记 + `README.md` 注明 | 需 operator 批准才能删除 |

### 方案 B：切换到 agent scope

**改动范围**：openclaw.json config 变更

**原理**：
- 每个 agent ID 一个独立容器
- task-runner 和 research-coordinator 各有自己的容器

**问题**：
- **与需求不符**：operator 要的是"同一任务下的 agent 共享容器"，agent scope 是 per-agent 隔离，恰好相反
- **文件不共享**：task-runner 的输出 research-coordinator 看不到（除非挂载 volume）
- **且 scope 是全局设置**：不能给不同 agent 不同 scope（shared 时 per-agent config 被忽略）

**不推荐**。

### 方案 C：混合 scope（需要多个 agent 定义）

**改动范围**：较大 config 变更 + 可能需要新的 agent 条目

**原理**：
- 为不同任务类型创建不同的 agent 实例（如 `task-runner-research`、`task-runner-dev`）
- 每个实例设 `scope: "agent"`，自然获得独立容器
- 同一任务的不同 agent 实例通过共享 volume 交换数据

**问题**：
- 管理复杂度高——每个新"大任务"需要新的 agent 配置
- OpenClaw 不支持动态创建 agent（agents.list 是静态配置）
- Volume 共享需要 Docker compose 或手动配置，OpenClaw config 不原生支持

**复杂度过高，不推荐**。

## 4. 推荐方案：A（shared + 软目录隔离）

### 实施步骤

1. **制定目录规范** — 写入 workspace-task-runner-template 的 skill 或 AGENTS.md
2. **创建 task-init skill** — task-runner 每个新任务调用此 skill 创建目录结构
3. **修改 workspace template** — 在 `/workspace/outputs/` 下预置 `.gitkeep` 和 README

### task-init skill 设计

```
# /workspace/skills/task-init.md

当收到一个新任务时，执行以下步骤：
1. 生成 task-id: YYYYMMDD-<slug>（从任务描述提取 2-4 个关键词）
2. 创建目录: /workspace/outputs/<task-id>/{data,results,logs}
3. 写入 README.md: 任务描述、创建时间、状态(active)、预期产出
4. 所有后续输出写入此 task 目录
5. 任务完成时更新 README.md 状态为 completed
```

### 清理策略

| 状态 | 保留时间 | 清理方式 |
|------|----------|----------|
| `completed` | 7 天 | 自动（cron 或 operator 定期清理） |
| `active` | 无限 | 手动（operator 决定） |
| `protected` | 无限 | 需 operator 批准 |

这些可以通过宿主机的 cron job 或 broker action 实现，不需要 OpenClaw 原生支持。

## 5. 未来增强（不在本轮实施）

- 当 OpenClaw 支持 per-task scope 或 dynamic agent 时，迁移到硬隔离
- 实现 broker `task-cleanup` action，自动清理已完成任务的目录
- Volume mount 方案：为固化项目创建独立 Docker volume，挂载到 shared container
