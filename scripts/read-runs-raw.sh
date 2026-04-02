#!/usr/bin/env bash
set -euo pipefail
F="/var/lib/openclaw/.openclaw/subagents/runs.json"
echo "=== First 200 chars ==="
sudo head -c 200 "$F"
echo ""
echo ""
echo "=== Last 200 chars ==="
sudo tail -c 200 "$F"
echo ""
echo ""
echo "=== Key structure ==="
sudo cat "$F" | python3 -c "
import json, sys
raw = sys.stdin.read()
print(f'Total bytes: {len(raw)}')
try:
    data = json.loads(raw)
    print(f'Type: {type(data).__name__}')
    if isinstance(data, dict):
        print(f'Top-level keys: {len(data)}')
        for k in list(data.keys())[:5]:
            v = data[k]
            print(f'  key={k[:60]} type={type(v).__name__}')
            if isinstance(v, dict):
                print(f'    fields: {list(v.keys())[:15]}')
                req = v.get('requesterSessionKey','?')
                child = v.get('childSessionKey','?')
                task = (v.get('task','') or '')[:80]
                print(f'    req={req[:60]}')
                print(f'    child={child[:60]}')
                print(f'    task={task}')
    elif isinstance(data, list):
        print(f'Array length: {len(data)}')
        if data:
            print(f'First item type: {type(data[0]).__name__}')
            if isinstance(data[0], dict):
                print(f'First item keys: {list(data[0].keys())[:15]}')
except Exception as e:
    print(f'Parse error: {e}')
    # Try JSONL
    lines = raw.strip().split('\n')
    print(f'Lines: {len(lines)}')
    for line in lines[:3]:
        try:
            obj = json.loads(line)
            print(f'  Line type: {type(obj).__name__}, keys: {list(obj.keys())[:10] if isinstance(obj, dict) else \"N/A\"}')
        except:
            print(f'  Line not JSON: {line[:80]}')
"
