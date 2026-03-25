# 综合变更：vLLM 关停 + Hook 清理 + 长期任务 + GPU 支持

> 日期：2026-03-25
> 候选文件：`candidates/openclaw.longtask-gpu-cleanup.candidate.json5`
> 前置：vLLM 必须先停掉才能启用 GPU 透传

---

## 1. 变更摘要

| 变更项 | 旧值 | 新值 | 原因 |
|--------|------|------|------|
| `plugins.allow` | `["feishu", "tool-audit-plugin"]` | `["feishu"]` | 测试残留清理 |
| `hooks` 块 | tool-audit-probe enabled | **删除整个 hooks 块** | 注释写了"验证后删除" |
| `subagents.runTimeoutSeconds` | 3600 (1h) | 14400 (4h) | 支持多步研究循环 |
| `subagents.archiveAfterMinutes` | 120 (2h) | 1440 (24h) | 步骤间保持上下文 |
| `sandbox.prune.idleHours` | 4 | 24 | shared 容器步骤间可能空闲 |
| `sandbox.prune.maxAgeDays` | 3 | 7 | 支持周级研究周期 |
| task-runner `scope` | `"session"` | `"shared"` | 文件跨 session 持久 |
| task-runner `docker.gpus` | 无 | `"all"` | GPU 透传到容器 |

## 2. vLLM 关停步骤

```bash
# 2.1 检查 vLLM 运行状态
ps aux | grep vllm
# 或
systemctl status vllm 2>/dev/null || echo "not a systemd service"

# 2.2 如果是 systemd 服务
sudo systemctl stop vllm
sudo systemctl disable vllm

# 2.3 如果是手动进程
# 找到 PID
pgrep -f vllm
# kill
sudo kill <PID>

# 2.4 验证 GPU 已释放
nvidia-smi
# 期望：Processes 列表中无 vllm，GPU Memory Used 接近 0
```

## 3. Hook 清理说明

**当前状态（来自 live config snapshot）：**
```json5
// ---- 测试用 hooks（验证后删除） ----
hooks: {
    internal: {
        enabled: true,
        entries: {
            "tool-audit-probe": { enabled: true }
        }
    }
}
```

**操作：** 从 openclaw.json 中删除整个 `hooks` 块。同时从 `plugins.allow` 移除 `"tool-audit-plugin"`。

**影响：** 无。这些是 Phase 2 验证阶段的测试探针，已完成使命。移除后不影响任何生产功能。

## 4. 部署步骤

```bash
# 4.1 Pre-snapshot
sudo btrfs subvolume snapshot -r / /.snapshots/root-pre-longtask-gpu-cleanup-20260325-HHMM

# 4.2 停掉 vLLM（见上方 §2）

# 4.3 验证 GPU 释放
nvidia-smi  # 确认无 vllm 进程

# 4.4 编辑 openclaw.json
# 应用 candidate delta（手动合并或通过 broker validate+deploy）
# 关键变更：
#   - 删除 hooks 块
#   - 从 plugins.allow 移除 tool-audit-plugin
#   - 修改 subagents timeout/archive
#   - 修改 prune limits
#   - 修改 task-runner scope → shared
#   - 添加 docker.gpus: "all"

# 4.5 重启 gateway
sudo systemctl restart openclaw-gateway
sudo systemctl status openclaw-gateway

# 4.6 健康检查
# 通过飞书发送 "系统健康检查" 给 main agent
# 或 broker: gateway_health

# 4.7 Post-snapshot
sudo btrfs subvolume snapshot -r / /.snapshots/root-post-longtask-gpu-cleanup-20260325-HHMM

# 4.8 Vault sync
```

## 5. 验证清单

- [ ] vLLM 已停止，`nvidia-smi` 显示 GPU 空闲
- [ ] gateway 正常启动，无 hook/plugin 错误
- [ ] 飞书对话正常
- [ ] `sessions_spawn("task-runner")` 正常
- [ ] 容器内 `nvidia-smi` 可见 GPU（验证 gpus 透传）
- [ ] shared scope：第一次 spawn 创建容器，第二次 spawn 复用同一容器
- [ ] shared scope：第一次写入的文件在第二次 spawn 中可见

## 6. 风险评估

| 风险 | 严重度 | 缓解 |
|------|--------|------|
| `docker.gpus` 字段可能不被 OpenClaw sandbox 支持 | 中 | 如不支持，改用 docker run 参数或 docker compose |
| shared scope 下多任务文件冲突 | 低 | 当前只有 main agent 发起任务，并发低 |
| 长 timeout 导致僵尸任务 | 低 | prune maxAgeDays=7 兜底清理 |
| vLLM 停掉后无法恢复 | 无 | systemctl start vllm 即可恢复 |

## 7. 回滚

```bash
# 快速回滚：恢复旧配置 + 重启 vLLM
sudo systemctl start vllm
sudo systemctl enable vllm
# 手动恢复 openclaw.json 中的 hooks、plugins.allow、scope、timeout

# 完整回滚：snapshot restore
```
