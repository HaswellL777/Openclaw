#!/usr/bin/env bash
set -euo pipefail
sudo cat /var/lib/openclaw/.openclaw/subagents/runs.json | python3 -c "
import json, sys
from collections import defaultdict
from datetime import datetime

data = json.load(sys.stdin)
runs = data.get('runs', {})
print(f'Total runs: {len(runs)}')

# Group by requesterSessionKey
by_req = defaultdict(list)
for rid, r in runs.items():
    req = r.get('requesterSessionKey', 'unknown')
    by_req[req].append(r)

print(f'Unique requesters: {len(by_req)}')
print()

for req, rlist in sorted(by_req.items(), key=lambda x: -len(x[1])):
    req_agent = req.split(':')[1] if ':' in req else '?'
    print(f'[{req_agent}] {req[:70]}')
    print(f'  Spawns: {len(rlist)}')
    for r in sorted(rlist, key=lambda x: x.get('createdAt', 0)):
        child = r.get('childSessionKey', '?')
        child_agent = child.split(':')[1] if ':' in child else '?'
        task = (r.get('task', '') or '')[:60]
        label = r.get('label', '') or ''
        ts = r.get('createdAt', 0)
        time_str = datetime.fromtimestamp(ts/1000).strftime('%m/%d %H:%M') if ts else '?'
        status = r.get('outcome', {}).get('status', '?') if isinstance(r.get('outcome'), dict) else '?'
        print(f'    {time_str} -> [{child_agent}] {child[:50]} | {status} | {label or task[:40]}')
    print()
"
