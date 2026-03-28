#!/usr/bin/env python3
"""Full provider cleanup: rename motchat→duckcoding, trim models, fix references.

Usage: sudo python3 scripts/apply-provider-cleanup.py [--dry-run]

Changes:
  1. Rename providers: motchat-claude-4-6 → duckcoding-claude, motchat-gpt-max → duckcoding-gpt
  2. Trim models to only: gpt-5.4, claude-opus-4-6, deepseek-chat
  3. Update all agent model.primary references
  4. Clean up agents.defaults.models aliases
  5. Set main → duckcoding-gpt/gpt-5.4
"""

import json
import sys
from pathlib import Path

LIVE_CONFIG = Path("/etc/openclaw/openclaw.json")


def main():
    dry_run = "--dry-run" in sys.argv

    if not LIVE_CONFIG.exists():
        print(f"ERROR: {LIVE_CONFIG} not found", file=sys.stderr)
        sys.exit(1)

    with open(LIVE_CONFIG) as f:
        cfg = json.load(f)

    changes = []
    providers = cfg.get("models", {}).get("providers", {})

    # ── 1. Rename + trim: motchat-claude-4-6 → duckcoding-claude ──
    old_claude = providers.pop("motchat-claude-4-6", None)
    if old_claude:
        providers["duckcoding-claude"] = {
            "baseUrl": old_claude["baseUrl"],
            "apiKey": old_claude["apiKey"],
            "api": old_claude.get("api", "openai-completions"),
            "models": [
                {
                    "id": "claude-opus-4-6",
                    "name": "Claude Opus 4.6",
                    "reasoning": True,
                    "input": ["text"],
                    "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
                    "contextWindow": 200000,
                    "maxTokens": 32000,
                }
            ],
        }
        changes.append("RENAMED motchat-claude-4-6 → duckcoding-claude (kept only claude-opus-4-6)")

    # ── 2. Rename + trim: motchat-gpt-max → duckcoding-gpt ──
    old_gpt = providers.pop("motchat-gpt-max", None)
    if old_gpt:
        providers["duckcoding-gpt"] = {
            "baseUrl": old_gpt["baseUrl"],
            "apiKey": old_gpt["apiKey"],
            "api": old_gpt.get("api", "openai-completions"),
            "models": [
                {
                    "id": "gpt-5.4",
                    "name": "GPT-5.4",
                    "reasoning": True,
                    "input": ["text"],
                    "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
                    "contextWindow": 1050000,
                    "maxTokens": 128000,
                }
            ],
        }
        changes.append("RENAMED motchat-gpt-max → duckcoding-gpt (kept only gpt-5.4)")

    # ── 3. Trim backup provider ──
    backup = providers.get("duckcoding-claude-backup")
    if backup:
        backup["models"] = [
            {
                "id": "claude-opus-4-6",
                "name": "Claude Opus 4.6 (Backup)",
                "reasoning": True,
                "input": ["text"],
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
                "contextWindow": 200000,
                "maxTokens": 32000,
            }
        ]
        changes.append("TRIMMED duckcoding-claude-backup (kept only claude-opus-4-6)")

    # ── 4. DeepSeek: keep only deepseek-chat ──
    ds = providers.get("custom-api-deepseek-com")
    if ds:
        ds["models"] = [m for m in ds.get("models", []) if m.get("id") == "deepseek-chat"]
        changes.append("TRIMMED custom-api-deepseek-com (kept only deepseek-chat)")

    # ── 5. Update ALL agent model.primary references ──
    RENAME_MAP = {
        "motchat-claude-4-6/": "duckcoding-claude/",
        "motchat-gpt-max/": "duckcoding-gpt/",
    }

    def fix_model_ref(ref):
        if not ref:
            return ref
        for old_prefix, new_prefix in RENAME_MAP.items():
            if ref.startswith(old_prefix):
                return new_prefix + ref[len(old_prefix):]
        return ref

    # Fix defaults
    defaults = cfg.get("agents", {}).get("defaults", {})
    old_default = defaults.get("model", {}).get("primary")
    if old_default:
        new_default = fix_model_ref(old_default)
        if new_default != old_default:
            defaults["model"]["primary"] = new_default
            changes.append(f"defaults.model.primary: {old_default} → {new_default}")

    # Fix per-agent models
    TARGET_MODELS = {
        "main": "duckcoding-gpt/gpt-5.4",
        "claude-engineer": "duckcoding-claude/claude-opus-4-6",
        "research-coordinator": "duckcoding-claude/claude-opus-4-6",
        "auditor": "duckcoding-claude/claude-opus-4-6",
        # task-runner: no override, uses defaults
    }

    for agent in cfg.get("agents", {}).get("list", []):
        aid = agent.get("id")
        if aid in TARGET_MODELS:
            old_model = agent.get("model", {}).get("primary", "(none)")
            new_model = TARGET_MODELS[aid]
            agent["model"] = {"primary": new_model}
            changes.append(f"{aid}.model.primary: {old_model} → {new_model}")
        elif aid == "task-runner":
            # Remove any model override, use defaults
            if "model" in agent:
                changes.append(f"task-runner: removed model override (uses default)")
                del agent["model"]

    # ── 6. Clean up agents.defaults.models (aliases) ──
    old_aliases = defaults.get("models", {})
    new_aliases = {}
    kept = set()
    for ref, alias_obj in old_aliases.items():
        new_ref = fix_model_ref(ref)
        # Only keep aliases for models we still have
        model_id = new_ref.split("/")[-1] if "/" in new_ref else new_ref
        if model_id in ("claude-opus-4-6", "gpt-5.4", "deepseek-chat", "deepseek-reasoner"):
            new_aliases[new_ref] = alias_obj
            kept.add(new_ref)

    # Ensure the 3 main models have aliases
    if "duckcoding-claude/claude-opus-4-6" not in new_aliases:
        new_aliases["duckcoding-claude/claude-opus-4-6"] = {"alias": "opus"}
    if "duckcoding-gpt/gpt-5.4" not in new_aliases:
        new_aliases["duckcoding-gpt/gpt-5.4"] = {"alias": "gpt54"}
    if "custom-api-deepseek-com/deepseek-chat" not in new_aliases:
        new_aliases["custom-api-deepseek-com/deepseek-chat"] = {"alias": "deepchat"}

    removed_aliases = set(old_aliases.keys()) - kept
    if removed_aliases:
        changes.append(f"REMOVED {len(removed_aliases)} stale aliases: {', '.join(sorted(removed_aliases))}")
    defaults["models"] = new_aliases
    changes.append(f"KEPT {len(new_aliases)} aliases: {', '.join(sorted(new_aliases.keys()))}")

    # ── Print summary ──
    print("=== Provider cleanup changes ===")
    for c in changes:
        print(f"  • {c}")

    print(f"\n=== Final provider list ===")
    for pid in sorted(providers.keys()):
        p = providers[pid]
        model_ids = [m["id"] for m in p.get("models", [])]
        print(f"  {pid}: {p.get('baseUrl', '?')} → [{', '.join(model_ids)}]")

    print(f"\n=== Final agent models ===")
    for agent in cfg.get("agents", {}).get("list", []):
        mp = agent.get("model", {}).get("primary", f"(default: {defaults.get('model',{}).get('primary','?')})")
        print(f"  {agent['id']}: {mp}")

    if dry_run:
        print("\n[DRY RUN] No files modified.")
        sys.exit(0)

    with open(LIVE_CONFIG, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

    print(f"\nWritten to: {LIVE_CONFIG}")
    print("Next: sudo systemctl restart openclaw-gateway")


if __name__ == "__main__":
    main()
