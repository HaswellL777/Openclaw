#!/usr/bin/env python3
import json
import sys

def deny(reason, hits=None):
    return {
        "decision": "deny",
        "reason": reason,
        "updated_input": {},
        "risk_level": "high",
        "policy_hits": hits or []
    }

def allow(reason, hits=None):
    return {
        "decision": "allow",
        "reason": reason,
        "updated_input": {},
        "risk_level": "low",
        "policy_hits": hits or []
    }

raw = sys.stdin.read().strip()
if not raw:
    print(json.dumps(deny("empty request", ["empty_input"])))
    sys.exit(0)

try:
    req = json.loads(raw)
except Exception:
    print(json.dumps(deny("invalid json", ["parse_error"])))
    sys.exit(0)

tool = req.get("tool_name", "")
tool_input = req.get("tool_input", {})
cmd = ""

if isinstance(tool_input, dict):
    cmd = str(tool_input.get("command", ""))

danger_markers = [
    "sudo ",
    "systemctl ",
    "mount ",
    "umount ",
    "/etc/openclaw",
    "/opt/openclaw",
    "/mnt/vault"
]

if tool == "Bash" and any(x in cmd for x in danger_markers):
    print(json.dumps(deny("matched deterministic deny markers", ["host_path_or_privileged_cmd"])))
    sys.exit(0)

print(json.dumps(allow("phase0 mock shim default allow", ["phase0_mock"])))
