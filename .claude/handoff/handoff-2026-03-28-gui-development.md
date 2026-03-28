# OpenClaw 对话交接提示词

> 生成日期：2026-03-28
> 上一轮：Phase 5 完成 + GUI 前端开发 + DuckCoding API 迁移 + 全量文档更新
> 模型：Claude Opus 4.6 (1M context)

---

## 第零部分：必读文档（开始工作前必须读完）

**按此顺序读取，不可跳过**：
1. `CLAUDE.md` — 安全边界、escalation 规则、anti-stall 规则
2. `docs/current-boundary.md` — 唯一实时状态文件（刚更新到 2026-03-28）
3. `docs/map.md` — 文档总地图（刚更新到 2026-03-28）
4. `docs/design-v3.md` §0/§5.3.2/§8.5 — 架构设计核心章节
5. `docs/planning/frontend-gui-design.md` — GUI 需求规格 v2（含 MCP、会话增强需求）
6. `.claude/handoff/handoff-2026-03-28-gui-development.md` — 本文件

**然后自行探索**：
- `docs/planning/` 目录下的活跃规划文档
- `gui/src/` 前端源码（特别是 `api/rpc-client.ts` 理解 Gateway 协议）
- `workspace-*-template/` agent workspace 模板
- `docs/host-sop.md` 宿主机运行态事实
- OpenClaw 源码 `/opt/openclaw/node_modules/openclaw/dist/` — 不确定的行为从这里找证据

---

## 第一部分：工作纪律（长期规则，每轮都适用）

1. **先读后做**：按第零部分顺序读文档。**这不是完整列表**——必须根据任务需要主动搜索仓库。
2. **产出 > 分析**：每个任务有可落盘产物（文件、脚本、配置候选）。
3. **不猜测**：不确定的系统行为，从源码和文档找证据。找不到标注 `[UNVERIFIED]`。
4. **config 变更走 escalation**：pre-snapshot → backup → apply 脚本 → verify → rollback plan。
5. **workspace 更新后提醒 publish**：task-runner/research-coordinator/auditor 无 publish 脚本，必须手动 rsync + 精确 chown（`knowledge/` 是 ro mount，`chown -R` 会失败）。
6. **自行测试**：所有 RPC 调用先用 Node.js WebSocket 脚本验证参数格式，不让用户当测试员。示例：`/tmp/test-all-params.mjs`。
7. **使用 Opus 4.6 subagent**：复杂任务用 `model: "opus"` 的 subagent 并行执行，最多 2-3 个，确保质量。
8. **使用 frontend-design skill**：前端 UI 改进时调用 `Skill` tool 使用 `frontend-design:frontend-design`。

### 踩过的坑（必须牢记）

| 坑 | 教训 |
|-----|------|
| Gateway 响应数据在 `msg.payload` 不是 `msg.result` | 所有 RPC 都用 OpenClaw 协议不是 JSON-RPC |
| `chat.history` 用 `sessionKey` 不是 `key` | sessions.abort/reset/delete 用 `key`，chat.* 用 `sessionKey` |
| `chat.send` 需要 `idempotencyKey` | 用 `crypto.randomUUID()` 生成 |
| `sessions.list` 筛选用 `agentId` 不是 `agent` | 参数名严格，多一个字段会被 schema 拒绝 |
| Health channels 的 `running` 可能 false 但 `probe.ok` 为 true | 判断健康状态要 `ch.running \|\| ch.probe?.ok` |
| `config.set/patch` 返回 EROFS | Gateway 进程无 config 文件写权限 |
| `openclaw-control-ui` client 触发 origin 检查 | 需要 Vite proxy 重写 Origin header 到 localhost |
| `allowInsecureAuth` + token + localhost = 完整 scopes | 四个条件缺一不可 |
| skill 安装后需要 `/reload-plugins` 才生效 | 不要声称 skill 可用而不验证 |
| `scope: "shared"` 时 per-agent docker 配置被忽略 | image 必须在 defaults 级别设 |

---

## 第二部分：已完成事项

### 配置部署（全部已验证 ✅）
- sessions.visibility = "all" + sandbox.sessionToolsVisibility = "all"
- main → duckcoding-gpt/gpt-5.4, RC/auditor/claude-engineer → duckcoding-claude/claude-opus-4-6
- API 迁移：MotChat → DuckCoding (api.duckcoding.ai)
- Provider 清理：只保留 gpt-5.4, claude-opus-4-6, deepseek-chat
- Provider ID：duckcoding-claude, duckcoding-gpt, duckcoding-claude-backup, custom-api-deepseek-com
- Auditor cross-agent 验证通过

### 前端 GUI（gui/ 目录）
- 11 个页面，8 个有实际功能
- Gateway WebSocket 协议完整实现（connect challenge + token auth + scopes）
- 代码审查完成（/simplify 三 agent + 两轮修复）

### 文档
- `docs/current-boundary.md` 全量更新到 2026-03-28
- `docs/map.md` 全量更新
- `docs/planning/README.md` 全量更新
- 6 个过期 planning docs 已归档
- 13 个已部署 candidates 已归档
- Workspace 模板 motchat→duckcoding 全量替换
- `.tmp/` 已清理

---

## 第三部分：本轮待修复问题（严格按优先级）

### P0 — 必须修复

1. **Chat 续接已有 session**：当前只能 new session。应在 Chat 页面加 session 列表或在 Sessions 页面加输入框。
2. **Sessions Reset 行为**：`sessions.reset` 清空历史。用户预期是新建 session 保留旧记录。改按钮标注或改为 "New Session"。
3. **Settings 只读展示**：Gateway 无写权限。改为只读配置一览，提示"修改需通过命令行"。

### P1 — 重要改进

4. **Session 生命周期**：100+ "active" sessions 需要理解。从源码找 session 状态机（active/idle/archived）和 `archiveAfterMinutes` 行为。
5. **Session spawn chain 可视化**：以 task 为视角——main→RC→task-runner 链路，信息流向，Docker 文件关联。用 `childSessions` 字段和 session key 解析构建。
6. **UI 美化**：用 `frontend-design:frontend-design` skill。
7. **消息渲染增强**：tool call 展开（MessageRenderer 已创建待验证）、代码块语法高亮+复制、agent badge+跳转、sessions_spawn 特殊卡片。

### P2 — 后续

8. Docker/Broker/File 实际功能（需 broker actions）
9. Heartbeat 管理 UI
10. MCP 管理 UI（设计文档在 `frontend-gui-design.md`）
11. 安全加固（IPv6 + auth）
12. 日志轮转 + Vault sync

---

## 第四部分：技术参考

### Gateway WebSocket 协议
```
Server → { type: "event", event: "connect.challenge", payload: { nonce, ts } }
Client → { type: "req", method: "connect", id: "1", params: { client: { id: "openclaw-control-ui", mode: "ui", platform: "...", version: "0.1.0" }, minProtocol: 3, maxProtocol: 3, role: "operator", scopes: ["operator.read","operator.write","operator.admin"], auth: { token: "..." } } }
Server → { type: "res", id: "1", ok: true, payload: { type: "hello-ok", ... } }
Client → { type: "req", method: "agents.list", id: "2", params: {} }
Server → { type: "res", id: "2", ok: true, payload: { agents: [...] } }
Server → { type: "event", event: "health", payload: { ok: true, ts: ..., channels: {...} } }
```

### API 参数速查
| Method | 参数 | 注意 |
|--------|------|------|
| sessions.list | `agentId`, limit, includeLastMessage | 不是 `agent` |
| chat.history | `sessionKey` | 不是 `key` |
| chat.send | `sessionKey`, `idempotencyKey`, text | idempotencyKey 必需 |
| sessions.abort/reset/delete | `key` | 不是 `sessionKey` |
| sessions.create | agentId, label → `{ key, sessionId }` | |
| config.get | → `{ raw, parsed, resolved, hash }` | raw 是字符串 |
| config.set | raw(string), baseHash | Gateway 无写权限! |

### 关键文件
| 文件 | 用途 |
|------|------|
| `gui/.env` | VITE_GATEWAY_TOKEN（gitignored） |
| `gui/src/api/rpc-client.ts` | OpenClaw WS 协议实现 |
| `gui/src/components/MessageRenderer.tsx` | 消息渲染器（待验证） |
| `/tmp/test-all-params.mjs` | API 参数测试脚本模板 |

### 陷阱速查（继承自上一轮）
| 陷阱 | 说明 |
|------|------|
| config schema `.strict()` | 未知字段导致 gateway crash loop |
| `scope: "shared"` 忽略 per-agent docker | image 必须在 defaults 设 |
| 切换 image 后旧容器继续跑 | 必须 `docker rm -f openclaw-sbx-shared` |
| `minimal` profile 只有 1 个工具 | 不给需要工作的 agent 用 |
| acpx 默认 strip API key | 用 wrapper 脚本绕过 |
| `queueOwnerTtlSeconds` 默认 0.1s | 必须 override 到 300+ |
