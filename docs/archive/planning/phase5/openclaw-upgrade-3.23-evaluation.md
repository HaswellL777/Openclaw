# OpenClaw v2026.3.22+ 升级评估

> 日期：2026-03-25
> 当前 live 版本：2026.3.13
> 目标版本：2026.3.23-2（当前最新稳定）
> Close-by：2026-03-30（决策升级与否）
> 状态：draft

---

## 1. 版本概览

v2026.3.13 到最新之间只有两个稳定版本（中间版本为 dev/beta）：

| 版本 | 日期 | 性质 |
|------|------|------|
| 2026.3.13 | Mar 14 | 当前 live |
| 2026.3.22 | Mar 23 | **重大版本**，12 个 breaking changes |
| 2026.3.23 | Mar 25 | 2026.3.22 回归修复 |
| 2026.3.23-2 | Mar 25 | 热修复（当前最新稳定） |

## 2. 升级动机

### 必须升级的理由

| 理由 | 严重度 |
|------|--------|
| v2026.3.13 `doctor` 命令 OOM (#47650) | 高 |
| v2026.3.13 `sessions.json` 膨胀（66MB 报告） | 高 |
| ACP 已移入 core（2026.3.22+），acpx plugin 路径废弃 | 高——直接影响 Phase 4 |
| 默认 agent timeout 从 10min 提升到 48h | 中——直接支持长期任务 |
| Gateway 冷启动优化（懒加载、预编译） | 中 |
| `memory_search` / `memory_get` 独立注册 | 中——改善记忆系统 |
| 30+ 安全修复 | 中 |
| `openclaw skills search/install/update` via ClawHub | 低——支持 LabClaw 接入 |

### 可以不升级的理由

| 理由 | 权重 |
|------|------|
| 2026.3.22 有 12 个 breaking changes | 高——升级成本 |
| acpx plugin 在 2026.3.22+ 有回归 (#52831, #52910) | 中——但 2026.3.23 修复了部分 |
| 当前 live 稳定运行 | 低——但有 OOM 隐患 |

### 结论：**推荐升级到 2026.3.23-2**

ACP 移入 core 是决定性因素——如果不升级，Phase 4 ACP spike 需要走 plugin 路径（已废弃），升级后走 core 路径（官方推荐）。同时解决 OOM 问题和记忆系统改善。

## 3. Breaking Changes 影响分析

### 3.1 必须处理的 breaking changes

| Breaking Change | 影响评估 | 操作 |
|-----------------|----------|------|
| `CLAWDBOT_*` / `MOLTBOT_*` 环境变量移除 | **无影响**——当前配置未使用这些 env var | 无需操作 |
| `.moltbot` 状态目录废弃 | **无影响**——当前使用 `~/.openclaw/` | 无需操作 |
| Chrome extension relay 移除 | **无影响**——未使用浏览器扩展 | 无需操作 |
| Plugin SDK 重构：`openclaw/extension-api` 移除 | **需检查**——host-ops-tool plugin 是否用了旧 SDK | 检查 plugin 导入路径 |
| ClawHub 替代 npm 为默认 plugin 源 | **需注意**——feishu plugin 安装路径可能变 | 升级后 `openclaw doctor --fix` |
| ACP 移入 core，acpx 扩展路径废弃 | **关键变更**——ACP spike candidate 需要重写 | 见 §4 |

### 3.2 受益的变更

| 变更 | 受益 |
|------|------|
| 默认 agent timeout 48h | 直接支持长期任务，不需要手动调 runTimeoutSeconds |
| ACP in core | ACP 配置更简单，不再需要 plugin |
| `openclaw skills search/install/update` | 直接从 ClawHub 安装 LabClaw skills |
| Pluggable sandbox backends (OpenShell) | 未来可选，当前不需要 |
| Gateway 懒加载 | 减少内存压力 |

### 3.3 已知回归（2026.3.22 → 2026.3.23-2 修复状态）

| 回归 | 版本 | 修复状态 |
|------|------|----------|
| acpx plugin 升级后静默损坏 (#52831) | 2026.3.22 | ✅ 2026.3.23 修复（ACP 在 core，不需要 plugin） |
| WhatsApp 等 plugin 从 npm tarball 丢失 (#52838) | 2026.3.22 | ✅ 2026.3.23-2 修复 |
| `acp.enabled` 自动注入 stale acpx plugin (#52910) | 2026.3.22 | ⚠️ 需手动清理 config |
| `openclaw plugins install acpx` 解析到 ClawHub skill (#53241) | 2026.3.22 | ⚠️ 可能仍存在，但不需要安装 acpx（已在 core） |

## 4. ACP Spike Candidate 更新

### 2026.3.13（旧方案——不再推荐）

```json5
// 需要 acpx plugin
plugins: { allow: [..., "acpx"], entries: { acpx: { ... } } }
acp: { backend: "acpx", ... }
```

### 2026.3.23-2（新方案——升级后使用）

```json5
// ACP 在 core，不需要 plugin
// 不要添加 plugins.entries.acpx（会触发 #52910 警告）
acp: {
  enabled: true,
  // backend 字段不再需要（core 内置）
  dispatch: { enabled: true },
  defaultAgent: "claude",
  allowedAgents: ["claude"],
  maxConcurrentSessions: 2,
  stream: { coalesceIdleMs: 300, maxChunkChars: 1200 },
  runtime: { ttlMinutes: 60 },
}
```

**变更影响**：
- `candidates/openclaw.acp-spike.candidate.json5` 中的 `plugins.entries.acpx` 块需要移除
- `acp.backend` 字段需要移除
- 其余 ACP 配置（agent、环境变量、workspace）不变

## 5. Node.js 要求

| 版本 | 要求 |
|------|------|
| 2026.3.13 | Node.js 22+ |
| 2026.3.22+ | **Node.js 22.16+ 最低，24 推荐** |

当前容器 Node.js：v22.22.1 ✅（满足要求）
宿主机 Node.js：需检查 `node --version`

## 6. 升级步骤

### 6.1 Pre-upgrade

```bash
# 1. Pre-snapshot
sudo btrfs subvolume snapshot -r / /.snapshots/root-pre-upgrade-3.23-20260325-HHMM

# 2. 检查 Node.js 版本
node --version
# 需要 >= 22.16.0；如果低于，先升级 Node.js

# 3. 清理 sessions.json（如果膨胀）
ls -lh /var/lib/openclaw/.openclaw/sessions.json
# 如果 > 10MB，考虑备份后清理

# 4. Vault sync
```

### 6.2 Upgrade

```bash
# 5. 升级 OpenClaw
sudo npm i -g openclaw@2026.3.23-2

# 6. 只读诊断（不要加 --fix 或 --repair！）
# CLAUDE.md 安全边界禁止 auto-repair flows
sudo -u openclaw openclaw doctor 2>&1 | tee /tmp/doctor-output.txt
# 查看输出，逐项手动处理问题
cat /tmp/doctor-output.txt

# 7. 清理 stale acpx plugin 条目（如果 config 中存在）
# 手动编辑 /etc/openclaw/openclaw.json：
#   - 确保不存在 plugins.entries.acpx
#   - 确保不存在 plugins.allow 中的 "acpx"

# 8. 重启 gateway
sudo systemctl restart openclaw-gateway

# 9. 健康检查
sudo systemctl status openclaw-gateway
# 通过飞书发送消息验证
```

### 6.3 Post-upgrade

```bash
# 10. 验证版本
sudo -u openclaw openclaw --version
# 期望：2026.3.23-2

# 11. 验证 ACP core
sudo -u openclaw openclaw doctor
# 检查 ACP 相关输出

# 12. 验证记忆系统
# 飞书发消息，观察 memory_search / memory_get 工具是否可用

# 13. Post-snapshot
sudo btrfs subvolume snapshot -r / /.snapshots/root-post-upgrade-3.23-20260325-HHMM

# 14. Vault sync
```

## 7. 回滚方案

```bash
# 快速回滚
sudo npm i -g openclaw@2026.3.13
sudo systemctl restart openclaw-gateway

# 完整回滚
# 恢复到 pre-upgrade snapshot
```

## 8. 与其他变更的编排建议

**推荐顺序**（单次维护窗口）：

1. Pre-snapshot
2. 停掉 vLLM（释放 GPU）
3. 升级 OpenClaw 到 2026.3.23-2
4. 清理 hooks + tool-audit-plugin
5. 应用长期任务配置（scope:shared, timeout 调大）
6. 应用 ACP 配置（新版，无 acpx plugin）
7. 设置 ANTHROPIC 环境变量
8. 重建 Docker image（full + gpu）
9. 重启 gateway
10. 健康检查 + 功能验证
11. Post-snapshot + Vault sync

这样一次维护窗口完成所有变更，减少重启次数和中断时间。

## 9. host-ops-tool plugin 兼容性

**需在升级前检查**：host-ops-tool plugin 是否使用了 `openclaw/extension-api`（旧 SDK）。

```bash
# 检查 plugin 导入
grep -r "extension-api\|require.*openclaw" /var/lib/openclaw/.openclaw/extensions/
```

如果使用了旧 SDK，需要迁移到 `openclaw/plugin-sdk/*`。如果 plugin 只使用 `api.registerTool()`，大概率兼容。

## 10. feishu plugin 兼容性

当前 feishu plugin 版本：2026.3.2（通过 npm 安装）。

2026.3.22+ 将 ClawHub 作为默认 plugin 源。升级后：
- 如果 feishu plugin 在 ClawHub 上有对应版本，可能自动迁移
- 如果没有，npm fallback 应该仍然工作
- `openclaw doctor --fix` 应该处理此问题

建议升级后验证飞书连接是否正常。
