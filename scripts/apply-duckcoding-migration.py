#!/usr/bin/env python3
"""Migrate API endpoints from MotChat to DuckCoding.

Usage: sudo python3 scripts/apply-duckcoding-migration.py

Changes:
  - motchat-claude-4-6: baseUrl → api.duckcoding.ai, apiKey → ${DUCKCODING_CLAUDE_KEY}
  - motchat-gpt-max: baseUrl → api.duckcoding.ai, apiKey → ${DUCKCODING_GPT_KEY}
  - DeepSeek: unchanged
  - Adds backup Claude provider: duckcoding-claude-backup

Pre-requisites: update /etc/openclaw/openclaw.env with new keys first.
"""

import json
import sys
from pathlib import Path

LIVE_CONFIG = Path("/etc/openclaw/openclaw.json")
NEW_BASE_URL = "https://api.duckcoding.ai/v1"


def main():
    if not LIVE_CONFIG.exists():
        print(f"ERROR: {LIVE_CONFIG} not found", file=sys.stderr)
        sys.exit(1)

    with open(LIVE_CONFIG) as f:
        cfg = json.load(f)

    changes = []
    providers = cfg.get("models", {}).get("providers", {})

    # --- Claude provider: motchat-claude-4-6 → duckcoding ---
    claude = providers.get("motchat-claude-4-6")
    if claude:
        old_url = claude.get("baseUrl", "?")
        old_key = claude.get("apiKey", "?")
        claude["baseUrl"] = NEW_BASE_URL
        claude["apiKey"] = "${DUCKCODING_CLAUDE_KEY}"
        changes.append(f"motchat-claude-4-6.baseUrl: {old_url} → {NEW_BASE_URL}")
        changes.append(f"motchat-claude-4-6.apiKey: {old_key} → ${{DUCKCODING_CLAUDE_KEY}}")

    # --- GPT provider: motchat-gpt-max → duckcoding ---
    gpt = providers.get("motchat-gpt-max")
    if gpt:
        old_url = gpt.get("baseUrl", "?")
        old_key = gpt.get("apiKey", "?")
        gpt["baseUrl"] = NEW_BASE_URL
        gpt["apiKey"] = "${DUCKCODING_GPT_KEY}"
        changes.append(f"motchat-gpt-max.baseUrl: {old_url} → {NEW_BASE_URL}")
        changes.append(f"motchat-gpt-max.apiKey: {old_key} → ${{DUCKCODING_GPT_KEY}}")

    # --- Add backup Claude provider ---
    if "duckcoding-claude-backup" not in providers:
        # Copy models from primary claude provider
        claude_models = claude["models"] if claude else []
        providers["duckcoding-claude-backup"] = {
            "baseUrl": NEW_BASE_URL,
            "apiKey": "${DUCKCODING_CLAUDE_BACKUP_KEY}",
            "api": "openai-completions",
            "models": claude_models,
        }
        changes.append("ADDED duckcoding-claude-backup provider (backup Claude key)")

    # --- DeepSeek: unchanged ---
    changes.append("custom-api-deepseek-com: UNCHANGED")

    # Write back
    with open(LIVE_CONFIG, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

    print("=== Config changes applied ===")
    for c in changes:
        print(f"  • {c}")
    print(f"\nWritten to: {LIVE_CONFIG}")
    print("\nNext: sudo systemctl restart openclaw-gateway")


if __name__ == "__main__":
    main()
