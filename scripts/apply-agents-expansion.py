#!/usr/bin/env python3
"""Apply the agents-expansion config candidate to /etc/openclaw/openclaw.json.

Usage: sudo python3 scripts/apply-agents-expansion.py

Reads the live config, merges the delta from the candidate, writes back.
Prints a summary of changes made.
"""

import json
import sys
from pathlib import Path

LIVE_CONFIG = Path("/etc/openclaw/openclaw.json")
REPO_ROOT = Path(__file__).resolve().parent.parent

def main():
    if not LIVE_CONFIG.exists():
        print(f"ERROR: {LIVE_CONFIG} not found", file=sys.stderr)
        sys.exit(1)

    with open(LIVE_CONFIG) as f:
        cfg = json.load(f)

    changes = []

    # 1. Set maxSpawnDepth = 2
    defaults_sub = cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("subagents", {})
    old_depth = defaults_sub.get("maxSpawnDepth", "(unset, default 1)")
    defaults_sub["maxSpawnDepth"] = 2
    changes.append(f"agents.defaults.subagents.maxSpawnDepth: {old_depth} → 2")

    # 2. Add research-coordinator and auditor to agents.list
    agents_list = cfg.setdefault("agents", {}).setdefault("list", [])
    existing_ids = {a.get("id") for a in agents_list if isinstance(a, dict)}

    new_agents = [
        {
            "id": "research-coordinator",
            "name": "Research Coordinator",
            "model": {"primary": "custom-api-deepseek-com/deepseek-chat"},
            "workspace": "workspace-research-coordinator",
            "subagents": {"allowAgents": ["task-runner"]},
            "sandbox": {"scope": "shared"},
        },
        {
            "id": "auditor",
            "name": "Quality Auditor",
            "model": {"primary": "motchat-claude-4-6/claude-opus-4-6"},
            "workspace": "workspace-auditor",
            "tools": {"profile": "minimal"},
            "sandbox": {"scope": "shared"},
        },
    ]

    for agent in new_agents:
        if agent["id"] in existing_ids:
            changes.append(f"agents.list: '{agent['id']}' already exists, SKIPPED")
        else:
            agents_list.append(agent)
            changes.append(f"agents.list: ADDED '{agent['id']}'")

    # 3. Update main agent's subagents.allowAgents
    for agent in agents_list:
        if isinstance(agent, dict) and agent.get("id") == "main":
            sub = agent.setdefault("subagents", {})
            old_allow = sub.get("allowAgents", [])
            new_allow = list(set(old_allow) | {"task-runner", "research-coordinator", "auditor"})
            new_allow.sort()
            sub["allowAgents"] = new_allow
            changes.append(f"main.subagents.allowAgents: {old_allow} → {new_allow}")
            break
    else:
        # main might be the default agent (no explicit entry). Check if any agent is default.
        # If no explicit main, we need to find the default agent.
        for agent in agents_list:
            if isinstance(agent, dict) and agent.get("default") is True:
                sub = agent.setdefault("subagents", {})
                old_allow = sub.get("allowAgents", [])
                new_allow = list(set(old_allow) | {"task-runner", "research-coordinator", "auditor"})
                new_allow.sort()
                sub["allowAgents"] = new_allow
                changes.append(f"default agent '{agent['id']}'.subagents.allowAgents: {old_allow} → {new_allow}")
                break
        else:
            changes.append("WARNING: no 'main' or default agent found in agents.list — allowAgents not updated")

    # 4. Enable tools.agentToAgent
    tools = cfg.setdefault("tools", {})
    old_a2a = tools.get("agentToAgent", "(unset)")
    tools["agentToAgent"] = {"enabled": True, "allow": ["main", "auditor"]}
    changes.append(f"tools.agentToAgent: {old_a2a} → {{enabled: true, allow: ['main', 'auditor']}}")

    # Write back
    with open(LIVE_CONFIG, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

    print("=== Config changes applied ===")
    for c in changes:
        print(f"  • {c}")
    print(f"\nWritten to: {LIVE_CONFIG}")
    print("Next: sudo systemctl restart openclaw-gateway")


if __name__ == "__main__":
    main()
