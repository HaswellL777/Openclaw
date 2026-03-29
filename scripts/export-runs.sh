#!/usr/bin/env bash
# Export runs.json to a frontend-readable format at gui/public/runs-export.json
# Run with: bash scripts/export-runs.sh
set -euo pipefail

SRC="/var/lib/openclaw/.openclaw/subagents/runs.json"
DEST="$(dirname "$0")/../gui/public/runs-export.json"

if ! sudo test -f "$SRC"; then
  echo "Error: $SRC not found"
  exit 1
fi

sudo cat "$SRC" | python3 -c "
import json, sys

data = json.load(sys.stdin)
runs = data.get('runs', {})

# Export only the fields needed for visualization
export = []
for rid, r in runs.items():
    export.append({
        'runId': r.get('runId', rid),
        'childSessionKey': r.get('childSessionKey', ''),
        'requesterSessionKey': r.get('requesterSessionKey', ''),
        'task': (r.get('task', '') or '')[:200],
        'label': r.get('label', '') or '',
        'createdAt': r.get('createdAt', 0),
        'startedAt': r.get('startedAt', 0),
        'endedAt': r.get('endedAt', 0),
        'status': (r.get('outcome', {}) or {}).get('status', 'unknown'),
        'cleanup': r.get('cleanup', 'keep'),
        'spawnMode': r.get('spawnMode', 'run'),
    })

json.dump(export, sys.stdout, ensure_ascii=False, indent=2)
" > "$DEST"

echo "Exported $(python3 -c "import json; print(len(json.load(open('$DEST'))))"  ) runs to $DEST"
