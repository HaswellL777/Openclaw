#!/usr/bin/env bash
# Read OpenClaw subagent runs.json to understand spawn relationships
set -euo pipefail

RUNS_CANDIDATES=(
  "/var/lib/openclaw/.openclaw/subagents/runs.json"
  "/var/lib/openclaw/.openclaw/workspace/subagents/runs.json"
)

for f in "${RUNS_CANDIDATES[@]}"; do
  if sudo test -f "$f"; then
    echo "=== Found: $f ==="
    echo "Size: $(sudo stat -c '%s' "$f") bytes"
    echo ""
    # Parse and summarize
    sudo cat "$f" | python3 -c "
import json, sys
from collections import defaultdict

data = json.load(sys.stdin)
if isinstance(data, dict):
    runs = list(data.values()) if not isinstance(list(data.values())[0] if data else None, dict) else [v for v in data.values() if isinstance(v, dict)]
elif isinstance(data, list):
    runs = data
else:
    print('Unexpected format:', type(data))
    sys.exit(0)

print(f'Total runs: {len(runs)}')

# Group by requesterSessionKey
by_requester = defaultdict(list)
for r in runs:
    if isinstance(r, dict):
        req = r.get('requesterSessionKey', 'unknown')
        by_requester[req].append(r)

print(f'Unique requesters: {len(by_requester)}')
print()
for req, runs_list in sorted(by_requester.items(), key=lambda x: -len(x[1]))[:10]:
    print(f'  {req[:60]}')
    print(f'    -> {len(runs_list)} spawns')
    for r in runs_list[:3]:
        child = r.get('childSessionKey', '?')[:50]
        task = (r.get('task', '') or '')[:60]
        label = r.get('label', '')
        created = r.get('createdAt', 0)
        print(f'       child={child} label={label} task={task[:40]}')
    if len(runs_list) > 3:
        print(f'       ... +{len(runs_list)-3} more')
    print()
"
    exit 0
  fi
done

# Fallback: search for it
echo "Searching for runs.json..."
sudo find /var/lib/openclaw -name "runs*" -type f 2>/dev/null
sudo find /var/lib/openclaw/.openclaw -maxdepth 3 -type f -name "*.json" 2>/dev/null | head -20
