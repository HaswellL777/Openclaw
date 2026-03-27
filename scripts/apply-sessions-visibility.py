#!/usr/bin/env python3
"""Apply sessions.visibility config to /etc/openclaw/openclaw.json.

Usage: sudo python3 scripts/apply-sessions-visibility.py

Adds tools.sessions.visibility = "all" AND
agents.defaults.sandbox.sessionToolsVisibility = "all"
to enable cross-agent session access for sandboxed agents.

Schema evidence:
  zod-schema.agent-runtime-Dtg4Jy6G.js:558-563 (tools.sessions.visibility)
  zod-schema.agent-runtime-Dtg4Jy6G.js:364 (sandbox.sessionToolsVisibility)
  pi-embedded-CbCYZxIb.js:80948-80952 (resolveSessionToolsVisibility)
  pi-embedded-CbCYZxIb.js:80954-80958 (resolveEffectiveSessionToolsVisibility — sandbox cap)
  pi-embedded-CbCYZxIb.js:81036-81072 (createSessionVisibilityGuard)
"""

import json
import sys
from pathlib import Path

LIVE_CONFIG = Path("/etc/openclaw/openclaw.json")


def main():
    if not LIVE_CONFIG.exists():
        print(f"ERROR: {LIVE_CONFIG} not found", file=sys.stderr)
        sys.exit(1)

    with open(LIVE_CONFIG) as f:
        cfg = json.load(f)

    changes = []

    # Ensure tools block exists
    tools = cfg.setdefault("tools", {})

    # Check if sessions.visibility already set
    sessions = tools.get("sessions", {})
    old_visibility = sessions.get("visibility", "(unset, default: tree)")

    if old_visibility == "all":
        print("tools.sessions.visibility is already 'all'. No changes needed.")
        sys.exit(0)

    # Set sessions.visibility = "all"
    tools.setdefault("sessions", {})["visibility"] = "all"
    changes.append(f"tools.sessions.visibility: {old_visibility} → 'all'")

    # CRITICAL: lift sandbox visibility cap
    # Without this, sandboxed agents (scope: "shared") get capped to "tree"
    # even when tools.sessions.visibility = "all"
    # Source: pi-embedded-CbCYZxIb.js:80954-80958
    defaults_sandbox = cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("sandbox", {})
    old_sandbox_vis = defaults_sandbox.get("sessionToolsVisibility", "(unset, default: spawned)")
    if old_sandbox_vis != "all":
        defaults_sandbox["sessionToolsVisibility"] = "all"
        changes.append(f"agents.defaults.sandbox.sessionToolsVisibility: {old_sandbox_vis} → 'all'")

    # Verify agentToAgent is configured (required companion)
    a2a = tools.get("agentToAgent", {})
    if not a2a.get("enabled"):
        print("WARNING: tools.agentToAgent.enabled is not true.", file=sys.stderr)
        print("  Cross-agent access requires BOTH visibility='all' AND agentToAgent.enabled=true.", file=sys.stderr)
        print("  Proceeding, but sessions_history will still fail without agentToAgent.", file=sys.stderr)
        changes.append("WARNING: agentToAgent not enabled — cross-agent access will remain blocked")

    # Write back
    with open(LIVE_CONFIG, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

    print("=== Config changes applied ===")
    for c in changes:
        print(f"  • {c}")
    print(f"\nWritten to: {LIVE_CONFIG}")
    print("\nNext steps:")
    print("  1. sudo systemctl restart openclaw-gateway")
    print("  2. Verify: send a message to auditor asking it to read main's session history")


if __name__ == "__main__":
    main()
