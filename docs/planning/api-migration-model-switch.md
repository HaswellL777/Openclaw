# API Endpoint & Key 管理方案 + 模型切换

> 日期：2026-03-27
> close-by：2026-03-29（apply 脚本已产出，等待 operator 提供新 endpoint/key 后立即可部署）
> 状态：**设计完成，待部署**

---

## 1. 当前 API endpoint/key 分布

### 所有涉及 endpoint/key 的位置

| # | 位置 | 内容 | 作用 |
|---|------|------|------|
| 1 | `/etc/openclaw/openclaw.json` → `models.providers.custom-api-deepseek-com` | baseUrl: `https://api.deepseek.com/v1`, apiKey: `${DEEPSEEK_API_KEY}` | DeepSeek 模型的 endpoint |
| 2 | `/etc/openclaw/openclaw.json` → `models.providers.motchat-claude-4-6` | baseUrl: `https://new.motchat.com/v1`, apiKey: `${MOTCHAT_API_KEY}` | Claude 模型（MotChat 中转） |
| 3 | `/etc/openclaw/openclaw.json` → `models.providers.motchat-gpt-max` | baseUrl: `https://new.motchat.com/v1`, apiKey: `${MOTCHAT_API_KEY}` | GPT 模型（MotChat 中转） |
| 4 | `/etc/openclaw/openclaw.env` | `ANTHROPIC_BASE_URL=https://new.motchat.com`, `ANTHROPIC_API_KEY=<key>` | ACP (Claude Code) 环境变量 |
| 5 | `scripts/acpx-wrapper.sh` (部署到 `/var/lib/openclaw/.openclaw/acpx-wrapper.sh`) | `ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-https://new.motchat.com}` | ACP wrapper fallback |

### 关键观察

1. **Gateway agents** 使用 `models.providers` 配置，apiKey 通过 `${VAR}` 语法引用环境变量
2. **ACP (Claude Code)** 使用独立的 `ANTHROPIC_*` 环境变量（由 openclaw.env 和 wrapper 设置）
3. 这两条路径是**独立的**——Gateway 的 models.providers 不影响 ACP 的 env vars

### Schema 事实

**ModelProviderSchema**（`zod-schema.core-BuVz8Rk7.js:157-171`）：
- `baseUrl`: string (required)
- `apiKey`: SecretInputSchema — 支持直接字符串 **或** `{ source: "env", id: "VAR_NAME" }` **或** `{ source: "file", id: "path" }`
- `api`: "openai-completions" | "anthropic-messages" | ... (protocol 类型)
- `models[]`: 每个 provider 下定义可用模型列表

**SecretInputSchema**（`zod-schema.core-BuVz8Rk7.js:51-71`）：支持 3 种引用方式：
1. 直接字符串（当前用的 `"${MOTCHAT_API_KEY}"` 格式）
2. `{ source: "env", id: "ENV_VAR_NAME" }`（结构化引用）
3. `{ source: "file", id: "/path/to/key" }`（文件引用）

---

## 2. 集中管理方案设计

### 核心原则
**Operator 改 key/endpoint 只需改一处**：`/etc/openclaw/openclaw.env`

### 方案：env 文件集中 + config 引用

**单一改动点**：`/etc/openclaw/openclaw.env`
```bash
# === API Provider Keys (唯一需要编辑的地方) ===
# Gateway agents 通过 models.providers.*.apiKey = "${VAR}" 引用
# ACP 通过 wrapper 脚本继承 gateway 进程 env

# 中转站 / 直连 Anthropic
ANTHROPIC_BASE_URL=https://${NEW_ENDPOINT}
ANTHROPIC_API_KEY=${NEW_ANTHROPIC_API_KEY}

# MotChat 中转（Gateway models.providers 用）
MOTCHAT_API_KEY=${NEW_MOTCHAT_API_KEY}

# DeepSeek（Gateway models.providers 用）
DEEPSEEK_API_KEY=${NEW_DEEPSEEK_API_KEY}

# ... 其他 provider keys
```

**Config 引用（已是当前模式，保持不变）**：
```json
"models": {
  "providers": {
    "motchat-claude-4-6": {
      "baseUrl": "https://NEW_ENDPOINT/v1",
      "apiKey": "${MOTCHAT_API_KEY}",
      ...
    }
  }
}
```

**ACP wrapper（简化）**：
```bash
# 从 gateway 进程 env 继承，不再硬编码
export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL}"
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
```

### 为什么不用 secrets.providers

OpenClaw 支持 `secrets.providers` 配置（env/file/exec），但当前的 `"${VAR}"` 字符串模板模式已足够：
- env 文件已经是单一修改点
- 不引入额外的 secrets 配置复杂度
- `"${VAR}"` 在 gateway 进程启动时展开，简单可靠

---

## 3. 迁移操作：替换 MotChat 中转

### 当 operator 获得新 endpoint 和 key 后

**需要修改的文件**（共 2 个文件，1 次 restart）：

| 文件 | 修改内容 |
|------|----------|
| `/etc/openclaw/openclaw.env` | 更新 `ANTHROPIC_BASE_URL`、`ANTHROPIC_API_KEY`、`MOTCHAT_API_KEY`（或替换为新变量名） |
| `/etc/openclaw/openclaw.json` | 更新 `models.providers.*.baseUrl` 到新 endpoint（如果 endpoint 变了） |

**不需要修改**：
- `acpx-wrapper.sh`（已改为从 env 继承，不硬编码）

---

## 4. 模型切换：main agent + research-coordinator（阶段 C）

### main agent

| 字段 | 当前值 | 新值 | 理由 |
|------|--------|------|------|
| 默认模型 (agents.defaults.model.primary) | `motchat-gpt-max/gpt-5.4` | **保持不变** | defaults 影响所有 agent |
| main agent model.primary | (使用 defaults) | **添加 per-agent override: `motchat-claude-4-6/claude-opus-4-6`** | deepseek-chat 不可靠编排；main 需要强 orchestration |

实际上，回顾 live 配置：main agent 在 `agents.list` 中没有 `model` 字段，使用的是 `agents.defaults.model.primary = motchat-gpt-max/gpt-5.4`。handoff 文档说 main 是 deepseek-chat，但 live 配置显示 default 是 gpt-5.4。

**确认方式**：检查 agents.list 中 main 条目是否有 per-agent model override。从 `openclaw.live.json` 看，main 条目没有 model 字段 → 使用 defaults → `motchat-gpt-max/gpt-5.4`。

**建议**：给 main 添加 per-agent model override 为 `motchat-claude-4-6/claude-opus-4-6`，这样：
- main 用 Claude Opus（强 orchestration）
- 其他 agent 继续用各自的 model 设置
- defaults 保持 gpt-5.4（对没有 per-agent override 的 agent 生效）

### research-coordinator

| 字段 | 当前值 | 新值 | 理由 |
|------|--------|------|------|
| model.primary | `custom-api-deepseek-com/deepseek-chat` | **`motchat-claude-4-6/claude-opus-4-6`** | deepseek-chat 无法理解 AGENTS.md 约束，会自 spawn 自己；需要强模型 |

### Agent model schema 事实

**AgentEntrySchema**（`zod-schema.agent-runtime-Dtg4Jy6G.js:502-551`）：
```
model: z.object({
  primary: z.string().optional(),
  fallbacks: z.array(z.string()).optional()
}).strict().optional()
```

Per-agent model override 在 agents.list 中通过 `model.primary` 字段设置，格式为 `"provider/model-id"`。

---

## 5. 产出文件清单

| 产物 | 路径 |
|------|------|
| 本设计文档 | `docs/planning/api-migration-model-switch.md` |
| 候选配置 | `candidates/openclaw.api-migration.candidate.json5` |
| Apply 脚本 | `scripts/apply-api-migration.py` |
| ACP wrapper 更新 | `scripts/acpx-wrapper.sh`（就地更新） |
