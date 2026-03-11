#!/usr/bin/env bash
# validate-request.sh — Validate a broker request JSON file against protocol rules
#
# Status: Phase 2 dev-repo prep — shell-based validator for testing
# Mirrors the validation logic in index.js and broker/wrappers/lib/common.sh
#
# Usage: plugins/host-ops-tool/lib/validate-request.sh <request-json-path>
#
# Exit codes:
#   0 — Valid request
#   1 — Invalid request (errors printed to stderr)
#
# Dependencies: jq

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

CANDIDATE_PATH_PREFIX="/var/lib/openclaw/approvals/candidates/"

ERRORS=0

err() {
  echo "INVALID: $1" >&2
  ERRORS=$((ERRORS + 1))
}

if [ $# -ne 1 ]; then
  echo "Usage: $0 <request-json-path>" >&2
  exit 1
fi

REQUEST_FILE="$1"

if [ ! -f "$REQUEST_FILE" ]; then
  echo "Error: file not found: $REQUEST_FILE" >&2
  exit 1
fi

if ! jq empty "$REQUEST_FILE" 2>/dev/null; then
  echo "Error: not valid JSON: $REQUEST_FILE" >&2
  exit 1
fi

# --- Required fields ---
for field in action request_id task_id requested_by inputs; do
  if ! jq -e ".$field" "$REQUEST_FILE" >/dev/null 2>&1; then
    err "Missing required field: $field"
  fi
done

# --- No extra top-level fields (mirrors additionalProperties: false) ---
KNOWN_FIELDS='["action","request_id","task_id","requested_by","inputs"]'
EXTRA_FIELDS=$(jq -r --argjson known "$KNOWN_FIELDS" '[keys[] | select(. as $k | $known | index($k) | not)] | .[]' "$REQUEST_FILE" 2>/dev/null)
if [ -n "$EXTRA_FIELDS" ]; then
  for ef in $EXTRA_FIELDS; do
    err "Unknown top-level field: $ef"
  done
fi

# --- inputs must be an object (not array, string, number, etc.) ---
INPUTS_TYPE=$(jq -r '.inputs | type' "$REQUEST_FILE" 2>/dev/null)
if [ "$INPUTS_TYPE" != "object" ] && [ "$INPUTS_TYPE" != "null" ]; then
  err "inputs must be an object, got $INPUTS_TYPE"
fi

# --- Action enum ---
ACTION=$(jq -r '.action // empty' "$REQUEST_FILE")
if [ -z "$ACTION" ]; then
  err "action is empty"
else
  ACTION_VALID=0
  for a in "${VALID_ACTIONS[@]}"; do
    if [ "$a" = "$ACTION" ]; then
      ACTION_VALID=1
      break
    fi
  done
  if [ "$ACTION_VALID" -ne 1 ]; then
    err "Invalid action: $ACTION"
  fi
fi

# --- Type checks ---
REQUEST_ID=$(jq -r '.request_id // empty' "$REQUEST_FILE")
TASK_ID=$(jq -r '.task_id // empty' "$REQUEST_FILE")

if [ -z "$REQUEST_ID" ]; then
  err "request_id is empty"
fi
if [ -z "$TASK_ID" ]; then
  err "task_id is empty"
fi

# --- Action-specific input validation ---
if [ "$ERRORS" -eq 0 ] && [ -n "$ACTION" ]; then
  case "$ACTION" in
    gateway_health)
      # No required inputs
      ;;
    gateway_restart)
      REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE")
      if [ -z "$REASON" ]; then
        err "gateway_restart requires inputs.reason"
      fi
      ;;
    validate_openclaw_json_candidate|deploy_openclaw_json_candidate)
      CANDIDATE_PATH=$(jq -r '.inputs.candidate_path // empty' "$REQUEST_FILE")
      EXPECTED_SHA256=$(jq -r '.inputs.expected_sha256 // empty' "$REQUEST_FILE")
      if [ -z "$CANDIDATE_PATH" ]; then
        err "$ACTION requires inputs.candidate_path"
      else
        case "$CANDIDATE_PATH" in
          "$CANDIDATE_PATH_PREFIX"*) ;;
          *) err "candidate_path must start with $CANDIDATE_PATH_PREFIX" ;;
        esac
        case "$CANDIDATE_PATH" in
          *".."*) err "candidate_path must not contain path traversal (..)" ;;
        esac
      fi
      if [ -z "$EXPECTED_SHA256" ]; then
        err "$ACTION requires inputs.expected_sha256"
      elif ! echo "$EXPECTED_SHA256" | grep -qE '^[a-f0-9]{64}$'; then
        err "expected_sha256 must be 64 lowercase hex characters"
      fi
      ;;
    snapshot_pre|snapshot_post)
      LABEL=$(jq -r '.inputs.label // empty' "$REQUEST_FILE")
      REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE")
      if [ -z "$LABEL" ]; then
        err "$ACTION requires inputs.label"
      elif [ "${#LABEL}" -gt 128 ]; then
        err "label exceeds 128 character limit"
      elif ! echo "$LABEL" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        err "label must be alphanumeric with dots, hyphens, underscores"
      fi
      if [ -z "$REASON" ]; then
        err "$ACTION requires inputs.reason"
      fi
      ;;
    vault_sync)
      SNAPSHOT_NAME=$(jq -r '.inputs.snapshot_name // empty' "$REQUEST_FILE")
      if [ -z "$SNAPSHOT_NAME" ]; then
        err "vault_sync requires inputs.snapshot_name"
      elif [ "${#SNAPSHOT_NAME}" -gt 128 ]; then
        err "snapshot_name exceeds 128 character limit"
      elif ! echo "$SNAPSHOT_NAME" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        err "snapshot_name must be alphanumeric with dots, hyphens, underscores"
      fi
      ;;
    rollback_prepare)
      TARGET=$(jq -r '.inputs.target_snapshot // empty' "$REQUEST_FILE")
      REASON=$(jq -r '.inputs.reason // empty' "$REQUEST_FILE")
      if [ -z "$TARGET" ]; then
        err "rollback_prepare requires inputs.target_snapshot"
      elif [ "${#TARGET}" -gt 128 ]; then
        err "target_snapshot exceeds 128 character limit"
      elif ! echo "$TARGET" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        err "target_snapshot must be alphanumeric with dots, hyphens, underscores"
      fi
      if [ -z "$REASON" ]; then
        err "rollback_prepare requires inputs.reason"
      fi
      ;;
  esac
fi

# --- Summary ---
if [ "$ERRORS" -gt 0 ]; then
  echo "Validation failed: $ERRORS error(s)" >&2
  exit 1
else
  echo "VALID" >&1
  exit 0
fi
