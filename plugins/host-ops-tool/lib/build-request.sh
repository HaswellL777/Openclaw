#!/usr/bin/env bash
# build-request.sh — Generate schema-conformant broker request JSON fixtures
#
# Status: Phase 2 dev-repo prep — for testing only, no live broker connection
#
# Usage: plugins/host-ops-tool/lib/build-request.sh <action> [key=value ...]
#
# Examples:
#   build-request.sh gateway_health
#   build-request.sh gateway_restart reason="Post config deploy"
#   build-request.sh deploy_openclaw_json_candidate \
#     candidate_path=/var/lib/openclaw/approvals/candidates/openclaw.json \
#     expected_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
#   build-request.sh snapshot_pre label=pre-config-20260311 reason="Pre-change snapshot"
#
# Output: JSON request on stdout

set -euo pipefail

VALID_ACTIONS=(
  gateway_health
  gateway_restart
  validate_openclaw_json_candidate
  deploy_openclaw_json_candidate
  snapshot_pre
  snapshot_post
  vault_sync
  rollback_prepare
)

if [ $# -lt 1 ]; then
  echo "Usage: $0 <action> [key=value ...]" >&2
  echo "Valid actions: ${VALID_ACTIONS[*]}" >&2
  exit 1
fi

ACTION="$1"
shift

# Validate action
ACTION_VALID=0
for a in "${VALID_ACTIONS[@]}"; do
  if [ "$a" = "$ACTION" ]; then
    ACTION_VALID=1
    break
  fi
done

if [ "$ACTION_VALID" -ne 1 ]; then
  echo "Error: unknown action '$ACTION'" >&2
  echo "Valid actions: ${VALID_ACTIONS[*]}" >&2
  exit 1
fi

# Generate IDs
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
RANDOM_SUFFIX=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 6)
REQUEST_ID="req-${TIMESTAMP}-${RANDOM_SUFFIX}"
TASK_ID="task-${TIMESTAMP}-${RANDOM_SUFFIX}"
REQUESTED_BY="agent:main"

# Build inputs object from key=value pairs
INPUTS="{}"
for kv in "$@"; do
  KEY="${kv%%=*}"
  VALUE="${kv#*=}"
  # Auto-detect booleans
  if [ "$VALUE" = "true" ] || [ "$VALUE" = "false" ]; then
    INPUTS=$(echo "$INPUTS" | jq --arg k "$KEY" --argjson v "$VALUE" '. + {($k): $v}')
  else
    INPUTS=$(echo "$INPUTS" | jq --arg k "$KEY" --arg v "$VALUE" '. + {($k): $v}')
  fi
done

# Emit request JSON
jq -n \
  --arg action "$ACTION" \
  --arg request_id "$REQUEST_ID" \
  --arg task_id "$TASK_ID" \
  --arg requested_by "$REQUESTED_BY" \
  --argjson inputs "$INPUTS" \
  '{
    action: $action,
    request_id: $request_id,
    task_id: $task_id,
    requested_by: $requested_by,
    inputs: $inputs
  }'
