#!/usr/bin/env python3
"""Apply API migration + model switch + sessions.visibility to /etc/openclaw/openclaw.json.

Usage:
  sudo python3 scripts/apply-api-migration.py
  sudo python3 scripts/apply-api-migration.py --base-url https://new-proxy.example.com/v1

Combines three config changes into one deployment:
  Phase A: tools.sessions.visibility = "all"
  Phase B: (optional) models.providers baseUrl update
  Phase C: main + research-coordinator model → claude-opus-4-6

Schema evidence:
  zod-schema.agent-runtime-Dtg4Jy6G.js:502-551 (AgentEntrySchema.model)
  zod-schema.agent-runtime-Dtg4Jy6G.js:558-563 (ToolsSchema.sessions)
  zod-schema.core-BuVz8Rk7.js:157-171 (ModelProviderSchema)
"""

import argparse
import json
import sys
from pathlib import Path

LIVE_CONFIG = Path("/etc/openclaw/openclaw.json")


def main():
    parser = argparse.ArgumentParser(description="Apply API migration + model switch")
    parser.add_argument(
        "--base-url",
        help="New base URL for motchat providers (e.g., https://new-proxy.example.com/v1). "
             "If not provided, baseUrl is left unchanged.",
    )
    parser.add_argument(
        "--api-type",
        choices=["openai-completions", "anthropic-messages"],
        help="API protocol type for Claude provider (change if switching from proxy to direct Anthropic)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print changes without writing to config file",
    )
    args = parser.parse_args()

    if not LIVE_CONFIG.exists():
        print(f"ERROR: {LIVE_CONFIG} not found", file=sys.stderr)
        sys.exit(1)

    with open(LIVE_CONFIG) as f:
        cfg = json.load(f)

    changes = []

    # ── Phase A: sessions.visibility ──
    tools = cfg.setdefault("tools", {})
    sessions = tools.setdefault("sessions", {})
    old_vis = sessions.get("visibility", "(unset, default: tree)")
    if old_vis != "all":
        sessions["visibility"] = "all"
        changes.append(f"tools.sessions.visibility: {old_vis} → 'all'")
    else:
        changes.append("tools.sessions.visibility: already 'all' — no change")

    # Phase A (cont): lift sandbox visibility cap for sandboxed agents
    # Without this, scope:"shared" agents get capped to "tree" even with visibility="all"
    # Source: pi-embedded-CbCYZxIb.js:80954-80958
    defaults_sandbox = cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("sandbox", {})
    old_sandbox_vis = defaults_sandbox.get("sessionToolsVisibility", "(unset, default: spawned)")
    if old_sandbox_vis != "all":
        defaults_sandbox["sessionToolsVisibility"] = "all"
        changes.append(f"agents.defaults.sandbox.sessionToolsVisibility: {old_sandbox_vis} → 'all'")

    # ── Phase B: baseUrl update (optional) ──
    if args.base_url:
        providers = cfg.get("models", {}).get("providers", {})
        for provider_id in ["motchat-claude-4-6", "motchat-gpt-max"]:
            provider = providers.get(provider_id)
            if provider:
                old_url = provider.get("baseUrl", "(unset)")
                provider["baseUrl"] = args.base_url
                changes.append(f"models.providers.{provider_id}.baseUrl: {old_url} → {args.base_url}")

    if args.api_type:
        providers = cfg.get("models", {}).get("providers", {})
        provider = providers.get("motchat-claude-4-6")
        if provider:
            old_api = provider.get("api", "(unset)")
            provider["api"] = args.api_type
            changes.append(f"models.providers.motchat-claude-4-6.api: {old_api} → {args.api_type}")

    # ── Phase C: model switch ──
    agents_list = cfg.get("agents", {}).get("list", [])

    model_updates = {
        "main": "motchat-claude-4-6/claude-opus-4-6",
        "research-coordinator": "motchat-claude-4-6/claude-opus-4-6",
    }

    for agent in agents_list:
        if not isinstance(agent, dict):
            continue
        agent_id = agent.get("id")
        if agent_id in model_updates:
            new_model = model_updates[agent_id]
            old_model = agent.get("model", {}).get("primary", "(unset, using defaults)")
            agent.setdefault("model", {})["primary"] = new_model
            changes.append(f"agents.list['{agent_id}'].model.primary: {old_model} → {new_model}")

    if not changes:
        print("No changes needed.")
        sys.exit(0)

    print("=== Planned config changes ===")
    for c in changes:
        print(f"  • {c}")

    if args.dry_run:
        print("\n[DRY RUN] No files modified.")
        sys.exit(0)

    # Write back
    with open(LIVE_CONFIG, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

    print(f"\nWritten to: {LIVE_CONFIG}")
    print("\nNext steps:")
    print("  1. If endpoint changed: update /etc/openclaw/openclaw.env with new API keys")
    print("  2. Update acpx-wrapper.sh if ACP endpoint changed")
    print("  3. sudo systemctl restart openclaw-gateway")
    print("  4. Verify: check gateway status, test agent responses")
    print("  5. sudo docker rm -f openclaw-sbx-shared  (force container recreation if image/env changed)")


if __name__ == "__main__":
    main()
