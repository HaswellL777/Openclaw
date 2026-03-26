#!/usr/bin/env bash
# ACP Claude Code wrapper — all agent-side environment config in one place.
# Used by acpx plugin as "command" override.
# Path: /var/lib/openclaw/.openclaw/acpx-wrapper.sh
#
# When the acpx plugin uses the bundled binary, it strips provider auth
# env vars (ANTHROPIC_API_KEY etc.) from the child process. This wrapper
# bypasses that by being a custom command (≠ bundled path) that explicitly
# sets the variables we need, then execs acpx.
#
# Edit this file to change proxy endpoint, API key, model, telemetry, etc.
# After editing, restart the gateway: sudo systemctl restart openclaw-gateway

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 1. API Proxy / Authentication
# ═══════════════════════════════════════════════════════════════
# MotChat 中转 — 修改这里切换 proxy 或直连 Anthropic
export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-https://new.motchat.com}"
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
# 如果 gateway 进程的 env 中已有这些变量（从 openclaw.env），
# 上面的 ${VAR:-} 会保留已有值。只有当 gateway env 中被 strip 时才需要硬编码。

# ═══════════════════════════════════════════════════════════════
# 2. Model / Thinking
# ═══════════════════════════════════════════════════════════════
# 不设置则用 Claude Code 默认模型（通常是 claude-sonnet-4-20250514）
# 取消注释以覆盖：
# export ANTHROPIC_MODEL="claude-opus-4-20250514"
# export CLAUDE_CODE_MAX_THINKING_TOKENS="16000"

# ═══════════════════════════════════════════════════════════════
# 3. Claude Code Behavior
# ═══════════════════════════════════════════════════════════════
# 禁用非必要网络流量（遥测、更新检查等）
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}"

# 禁用自动更新（ACP 环境中版本应固定）
export CLAUDE_CODE_SKIP_UPDATE_CHECK="${CLAUDE_CODE_SKIP_UPDATE_CHECK:-1}"

# ═══════════════════════════════════════════════════════════════
# 4. Exec acpx
# ═══════════════════════════════════════════════════════════════
# 使用 bundled acpx binary（已安装在插件目录中）
ACPX_BIN="/opt/openclaw/node_modules/openclaw/dist/extensions/acpx/node_modules/.bin/acpx"

exec "$ACPX_BIN" "$@"
