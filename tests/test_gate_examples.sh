#!/usr/bin/env bash
set -euo pipefail

python3 -m json.tool examples/gate/gate-request.sample.json >/dev/null
python3 -m json.tool examples/gate/gate-response.sample.json >/dev/null

printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"/workspace/repo","task_id":"t1","request_id":"r1"}' \
  | python3 scripts/mock-gate-shim.py \
  | python3 -m json.tool >/dev/null

printf '%s' '{"tool_name":"Bash","tool_input":{"command":"sudo systemctl restart openclaw-gateway.service"},"cwd":"/workspace/repo","task_id":"t2","request_id":"r2"}' \
  | python3 scripts/mock-gate-shim.py \
  | python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["decision"]=="deny"'

echo "PASS: gate examples and mock shim are consistent"
