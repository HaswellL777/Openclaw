# Post-Upgrade Capability Probe Operator Runbook (2026.3.13)

> 文档类型：**live-side operator 执行步骤**
> 创建日期：2026-03-18
> 当前基线：OpenClaw 2026.3.13
> 设计来源：`docs/planning/post-upgrade-capability-probe-2026.3.13-slice-design-2026-03-18.md`
> Probe matrix：`docs/checklists/post-upgrade-capability-probe-matrix-2026.3.13.md`
> Result template：`docs/templates/post-upgrade-capability-probe-record-template.md`
> **执行状态：尚未执行**

---

## 重要声明

- 本 runbook 是给 operator 的 live probe 执行步骤
- 所有步骤按建议顺序编排，但 operator 可根据实际情况调整
- **本 probe 不做任何 live 变更**（除 P3 可选的临时 test agent 外）
- 如果 P3 选择 live spawn 测试路径，**必须先完成 pre-probe 保护动作**
- Probe 结果记录在 `docs/templates/post-upgrade-capability-probe-record-template.md` 的实例中

---

## R0. Pre-Probe 保护动作

> 仅在计划执行 P3 live spawn 测试（涉及临时修改 openclaw.json）时需要。
> 如果所有 probe 均为只读/日志分析，可跳过此节。

### R0.1 确认当前 baseline

```bash
# 确认版本
sudo -u openclaw /opt/openclaw/node_modules/.bin/openclaw --version 2>/dev/null \
  || (cd /opt/openclaw && sudo node -e "console.log(require('./node_modules/openclaw/package.json').version)")
# 预期: 2026.3.13

# 确认服务状态
systemctl is-active openclaw-gateway.service
systemctl is-active openclaw-broker.service
# 预期: 均 active
```

- [ ] 版本: 2026.3.13
- [ ] gateway: active
- [ ] broker: active

### R0.2 Pre-probe snapshot（仅 P3 live spawn 路径需要）

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
sudo btrfs subvolume snapshot -r / "/.snapshots/root-pre-capprobe-${TIMESTAMP}"
```

- [ ] Snapshot 创建成功
- [ ] Snapshot 名称: `root-pre-capprobe-____________________`

### R0.3 配置备份（仅 P3 live spawn 路径需要）

```bash
sudo cp /etc/openclaw/openclaw.json /etc/openclaw/openclaw.json.pre-capprobe
sudo sha256sum /etc/openclaw/openclaw.json
```

- [ ] 配置备份完成
- [ ] SHA256: ____________________

---

## R1. Probe P5 — Docker 前置条件（最低风险，先执行）

> 全部只读命令，零系统影响。

### R1.1 Docker Engine 状态

```bash
# Docker 版本
docker --version 2>&1

# Docker 服务状态
systemctl is-active docker.service 2>&1

# Docker 详细信息（如果 active）
docker info 2>&1 | head -30
```

- [ ] Docker 版本: ____________________
- [ ] Docker 服务: ________________（active / inactive / not-found）
- [ ] 如 not-found，记录: Docker 未安装

### R1.2 Docker socket 权限

```bash
ls -la /var/run/docker.sock 2>&1
```

- [ ] Socket 权限: ____________________
- [ ] Socket 属主: ____________________

### R1.3 Docker 组成员

```bash
getent group docker 2>&1
```

- [ ] docker 组成员: ____________________
- [ ] `openclaw` 是否在 docker 组: ____________________

### R1.4 openclaw 用户 Docker 访问测试

```bash
sudo -u openclaw docker info 2>&1 | head -5
```

- [ ] 结果: ____________________（成功 / permission denied / command not found）

### R1.5 现有网络和镜像

```bash
docker network ls 2>&1
docker images 2>&1
```

- [ ] 现有网络: ____________________
- [ ] `openclaw-task-net` 是否存在: ____________________
- [ ] 现有镜像: ____________________

### R1.6 P5 判定

- [ ] **Go** — Docker 安装且运行，openclaw 有访问路径
- [ ] **Caution** — Docker 安装但需权限/配置整理
- [ ] **No-Go** — Docker 未安装或不可用

备注: ____________________

---

## R2. Probe P2 — Plugin Trust / Provenance

> 日志分析和文档查阅，零系统影响。

### R2.1 Provenance 警告日志提取

```bash
# 提取 provenance 相关日志
sudo journalctl -u openclaw-gateway.service --since "2026-03-18" --no-pager | grep -i provenance

# 提取 trust 相关日志
sudo journalctl -u openclaw-gateway.service --since "2026-03-18" --no-pager | grep -i trust

# 提取 plugin 注册完整日志
sudo journalctl -u openclaw-gateway.service --since "2026-03-18" --no-pager | grep -i -E "plugin|register|host-ops"
```

- [ ] Provenance 日志已记录
- [ ] Trust 日志已记录
- [ ] Plugin 注册日志已记录

### R2.2 Plugin 配置检查

```bash
# 检查 plugins.entries 和 plugins.allow
sudo cat /etc/openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
print('plugins.allow:', cfg.get('plugins', {}).get('allow', 'NOT SET'))
entries = cfg.get('plugins', {}).get('entries', {})
for k, v in entries.items():
    print(f'  entry: {k} -> enabled={v.get(\"enabled\", \"NOT SET\")}')
" 2>&1
```

- [ ] plugins.allow 内容: ____________________
- [ ] host-ops-tool enabled: ____________________

### R2.3 上游文档查阅

operator 需要查阅：
- 2026.3.12 changelog 中 plugin trust / provenance 相关条目
- 2026.3.13 changelog 中 plugin-sdk 相关条目
- 上游文档中 `plugins.entries` vs workspace auto-load 的语义区别

- [ ] 上游文档已查阅
- [ ] provenance 警告的触发条件: ____________________
- [ ] 是否会升级为 hard block: ____________________

### R2.4 P2 判定

- [ ] **Go** — 警告为信息性，plugins.entries 路径不受影响
- [ ] **Caution** — 未来版本可能强制校验，需预防性调整
- [ ] **No-Go** — 当前版本已在某路径下 hard block

备注: ____________________

---

## R3. Probe P1 — sessions_yield

> 日志分析和可选 API 测试，低风险。

### R3.1 Gateway 日志中的 yield 能力声明

```bash
# 检查 gateway 启动日志中是否有 yield 相关能力声明
sudo journalctl -u openclaw-gateway.service --since "2026-03-18" --no-pager | grep -i yield

# 检查 sessions 相关能力
sudo journalctl -u openclaw-gateway.service --since "2026-03-18" --no-pager | grep -i "sessions"
```

- [ ] yield 相关日志: ____________________
- [ ] sessions 相关日志: ____________________

### R3.2 CLI 检查

```bash
# 检查 openclaw CLI 是否有 yield 子命令
sudo -u openclaw /opt/openclaw/node_modules/.bin/openclaw --help 2>&1 | grep -i yield

# 检查 sessions 子命令
sudo -u openclaw /opt/openclaw/node_modules/.bin/openclaw --help 2>&1 | grep -i session
```

- [ ] CLI 中 yield 命令: ____________________
- [ ] CLI 中 session 命令: ____________________

### R3.3 Agent session probe（可选）

如果 agent 当前可用，通过 agent session 尝试：

```
# 通过 agent 对话：
"请尝试调用 sessions_yield 工具，报告是否存在以及返回什么。"
```

- [ ] sessions_yield 是否存在: ____________________
- [ ] 调用结果: ____________________

### R3.4 上游文档查阅

operator 需要查阅：
- 2026.3.12 changelog 中 `sessions_yield` 的描述
- 上游 API 文档中 `sessions_yield` 的语义定义

- [ ] 上游文档已查阅
- [ ] sessions_yield 语义: ____________________
- [ ] 与 sessions_spawn 的关系: ____________________

### R3.5 P1 判定

- [ ] **Go** — 语义清晰，与 Phase 3 session 管理直接正相关
- [ ] **Caution** — 存在但语义不完全清晰，或非直接相关
- [ ] **No-Go** — 不存在、行为不确定、或有已知 issue

备注: ____________________

---

## R4. Probe P4 — Sandbox 配置行为

> 需构造测试 candidate，中低风险。不做 deploy。

### R4.1 上游 sandbox 文档查阅

operator 需要查阅：
- 2026.3.12/2026.3.13 中 sandbox 配置相关变更
- `sandbox.docker` 配置的官方文档

- [ ] 上游文档已查阅
- [ ] sandbox.docker 支持状态: ____________________

### R4.2 Gateway journal sandbox 日志

```bash
sudo journalctl -u openclaw-gateway.service --since "2026-03-18" --no-pager | grep -i sandbox
sudo journalctl -u openclaw-gateway.service --since "2026-03-18" --no-pager | grep -i docker
```

- [ ] Sandbox 日志: ____________________
- [ ] Docker 日志: ____________________

### R4.3 构造含 sandbox 配置的测试 candidate

> 此步骤仅做 validate，不做 deploy。

```bash
# 复制当前 config 作为测试基础
sudo cp /etc/openclaw/openclaw.json /tmp/capprobe-sandbox-test-candidate.json

# 在测试 candidate 中加入一个含 sandbox 配置的 test agent
# （operator 手动编辑 /tmp/capprobe-sandbox-test-candidate.json，
#   在 agents.list 中加入一个 test agent 配置，包含：
#   sandbox: { mode: "all", docker: { image: "hello-world" } }
# ）
```

然后通过 `validate_openclaw_json_candidate` 测试：

```bash
# 复制到候选目录
sudo cp /tmp/capprobe-sandbox-test-candidate.json \
  /var/lib/openclaw/approvals/candidates/capprobe-sandbox-test.json
sudo chown openclaw:openclaw /var/lib/openclaw/approvals/candidates/capprobe-sandbox-test.json

HASH=$(sha256sum /var/lib/openclaw/approvals/candidates/capprobe-sandbox-test.json | awk '{print $1}')
echo "Hash: $HASH"

# 通过 agent 或 broker socket 调用 validate
sudo socat - UNIX-CONNECT:/run/openclaw/broker.sock <<EOF
{"action":"validate_openclaw_json_candidate","request_id":"req-capprobe-sandbox-001","task_id":"task-capprobe","requested_by":"operator:nick","inputs":{"candidate_path":"/var/lib/openclaw/approvals/candidates/capprobe-sandbox-test.json","expected_sha256":"${HASH}"}}
EOF
```

- [ ] Validate 结果: ____________________
- [ ] sandbox 配置是否被接受: ____________________
- [ ] 如有 validation error，记录具体错误: ____________________

### R4.4 清理测试 candidate

```bash
sudo rm -f /var/lib/openclaw/approvals/candidates/capprobe-sandbox-test.json
sudo rm -f /tmp/capprobe-sandbox-test-candidate.json
```

- [ ] 测试 candidate 已清理

### R4.5 P4 判定

- [ ] **Go** — sandbox.docker 配置被正确解析
- [ ] **Caution** — 配置接受但 docker backend 未连接
- [ ] **No-Go** — 配置被拒绝

备注: ____________________

---

## R5. Probe P3 — Target Workspace / Subagent 行为（最高风险，最后执行）

> 有两条路径可选。Operator 选择一条。

### 路径 A：仅文档分析（零风险）

#### R5.A.1 上游文档查阅

operator 需要查阅：
- 2026.3.13 changelog 中 cross-agent subagent target workspace 修复的描述
- 上游文档中 `sessions_spawn` 的 workspace 隔离语义
- 修复前后的行为差异

- [ ] 上游文档已查阅
- [ ] cross-agent workspace 修复内容: ____________________
- [ ] sessions_spawn workspace 隔离语义: ____________________

#### R5.A.2 当前 agents.list 检查

```bash
sudo cat /etc/openclaw/openclaw.json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
agents = cfg.get('agents', {}).get('list', [])
for a in agents:
    print(f'  agent: {a.get(\"id\")} workspace: {a.get(\"workspace\", \"NOT SET\")}')
" 2>&1
```

- [ ] 当前 agents.list: ____________________

#### R5.A.3 P3 判定（路径 A）

- [ ] **Go** — 文档确认修复，语义符合 design-v3 假设
- [ ] **Caution** — 文档确认修复，但未 live 验证
- [ ] **No-Go** — 文档显示修复不完整或有已知限制

备注: ____________________

---

### 路径 B：Live spawn 测试（需 snapshot 保护）

> ⚠️ 此路径涉及临时修改 openclaw.json，**必须先完成 R0 Pre-Probe 保护动作**。
> 如果 R0 未完成，**立即停止，返回 R0**。

- [ ] R0 Pre-Probe 保护动作已完成

#### R5.B.1 创建临时 test agent 配置

```bash
# 在 openclaw.json 中加入临时 test agent
# operator 手动编辑：通过 candidate workflow
#   候选 config 中 agents.list 加入：
#   {
#     "id": "capprobe-test-agent",
#     "workspace": "/var/lib/openclaw/.openclaw/workspace-capprobe-test",
#     "tools": { "allow": ["read"], "deny": ["exec", "write", "edit", "elevated"] }
#   }

# 创建临时 workspace
sudo -u openclaw mkdir -p /var/lib/openclaw/.openclaw/workspace-capprobe-test
echo "# Capability Probe Test Agent" | sudo -u openclaw tee /var/lib/openclaw/.openclaw/workspace-capprobe-test/AGENTS.md
```

- [ ] 候选 config 已准备
- [ ] 临时 workspace 已创建

#### R5.B.2 Deploy 临时配置

```bash
# 通过标准 candidate workflow deploy
# validate → deploy → restart
```

- [ ] Validate PASS
- [ ] Deploy PASS
- [ ] Gateway restart PASS

#### R5.B.3 Spawn 测试

```bash
# 通过 main agent session：
# "请尝试 sessions_spawn(agentId='capprobe-test-agent')，
#  报告 spawn 出的 session 的 workspace 路径。"
```

- [ ] Spawn 结果: ____________________
- [ ] 子 session workspace: ____________________
- [ ] 是否指向 `workspace-capprobe-test`: ____________________

#### R5.B.4 恢复原配置

```bash
# 恢复 openclaw.json
sudo cp /etc/openclaw/openclaw.json.pre-capprobe /etc/openclaw/openclaw.json
sudo systemctl restart openclaw-gateway.service
# 等待 ~10s
systemctl is-active openclaw-gateway.service
systemctl is-active openclaw-broker.service

# 清理临时 workspace
sudo rm -rf /var/lib/openclaw/.openclaw/workspace-capprobe-test
```

- [ ] 配置已恢复
- [ ] Gateway active
- [ ] Broker active（如未自动启动：`sudo systemctl start openclaw-broker.service`）
- [ ] 临时 workspace 已删除

#### R5.B.5 P3 判定（路径 B）

- [ ] **Go** — workspace 隔离行为符合 design-v3 §5.2 假设
- [ ] **Caution** — spawn 成功但隔离行为有偏差
- [ ] **No-Go** — spawn 失败或隔离不成立

备注: ____________________

---

## R6. 汇总与 Go/No-Go 判定

### R6.1 汇总表

| # | Probe Item | 判定 | 备注 |
|---|-----------|------|------|
| P5 | Docker 前置条件 | | |
| P2 | Plugin trust / provenance | | |
| P1 | sessions_yield | | |
| P4 | Sandbox 配置行为 | | |
| P3 | Workspace / subagent | | |

### R6.2 Phase 3 Go/No-Go 判定

进入 Phase 3 的条件（全部满足）：

- [ ] P2 ≥ Caution
- [ ] P3 ≥ Caution
- [ ] P4 ≥ Caution
- [ ] P5 ≥ Caution

**总判定**：
- [ ] **Go** — 本 probe 执行完成；仅在 Go/No-Go hard gate 通过后，才可将 `phase3-docker-sandbox-foundation` 作为后继 implementation slice 评审入口
- [ ] **No-Go** — 记录原因，评估后续路径

### R6.3 Post-probe 记录

- [ ] 填写 `docs/templates/post-upgrade-capability-probe-record-template.md` 实例
- [ ] 保存为 `docs/records/post-upgrade-capability-probe-2026.3.13-activation-YYYY-MM-DD.md`

---

## 何时立即停止

以下情况应立即停止 probe：

1. **Gateway 在 probe 过程中停止响应**：停止所有 probe，先恢复服务
2. **P3 路径 B 的 deploy 导致 gateway 启动失败**：立即恢复 pre-capprobe 配置
3. **任何操作导致非预期的系统状态变化**：停止、评估、必要时使用 pre-capprobe snapshot 恢复
