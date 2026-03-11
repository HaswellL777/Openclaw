#!/usr/bin/env bash
# common.sh — Shared validation and output helpers for broker wrapper stubs
#
# Status: Phase 2 dev-repo prep — single source of truth for wrapper validation logic
# Sourced by each ocw-*.sh wrapper to eliminate duplication and prevent drift
#
# Usage: source "${SCRIPT_DIR}/lib/common.sh"
#
# Provides:
#   Constants: BROKER_ACTIONS, CANDIDATE_PATH_PREFIX, CONFIG_TARGET_PATH
#   Functions: broker_validate_request_file, broker_parse_common,
#              broker_validate_action, broker_validate_required_fields,
#              broker_validate_sha256, broker_validate_path,
#              broker_validate_label, broker_error, broker_emit_result

# --- Constants (single source of truth) ---

readonly BROKER_ACTIONS=(
  gateway_health
  gateway_restart
  validate_openclaw_json_candidate
  deploy_openclaw_json_candidate
  snapshot_pre
  snapshot_post
  vault_sync
  rollback_prepare
)

readonly CANDIDATE_PATH_PREFIX="/var/lib/openclaw/approvals/candidates/"
readonly CONFIG_TARGET_PATH="/etc/openclaw/openclaw.json"

# --- Internal state (set by broker_parse_common) ---

BROKER_ACTION=""
BROKER_REQUEST_ID=""
BROKER_TASK_ID=""

# --- Error output ---

# Emit structured error JSON to stderr and exit 1
# Usage: broker_error "status" "message"
# Requires BROKER_ACTION, BROKER_REQUEST_ID, BROKER_TASK_ID to be set
broker_error() {
  local status="${1:-error}" msg="${2:-unknown error}"
  cat >&2 <<EOF
{"ok":false,"action":"${BROKER_ACTION}","request_id":"${BROKER_REQUEST_ID}","task_id":"${BROKER_TASK_ID}","status":"${status}","message":"${msg}"}
EOF
  exit 1
}

# --- Validation helpers ---

# Validate request file argument and existence
# Usage: broker_validate_request_file "$@"
# Sets REQUEST_FILE on success; exits 1 on failure
broker_validate_request_file() {
  if [ $# -ne 1 ] || [ -z "${1:-}" ]; then
    echo '{"ok":false,"status":"error","message":"Usage: <wrapper> <request-json-path>"}' >&2
    exit 1
  fi
  if [ ! -f "$1" ]; then
    echo "{\"ok\":false,\"status\":\"error\",\"message\":\"Request file not found: $1\"}" >&2
    exit 1
  fi
  REQUEST_FILE="$1"
}

# Parse common fields from request JSON
# Sets: BROKER_ACTION, BROKER_REQUEST_ID, BROKER_TASK_ID
# Usage: broker_parse_common "$REQUEST_FILE"
broker_parse_common() {
  local req_file="$1"
  BROKER_ACTION=$(jq -r '.action // empty' "$req_file" 2>/dev/null || true)
  BROKER_REQUEST_ID=$(jq -r '.request_id // empty' "$req_file" 2>/dev/null || true)
  BROKER_TASK_ID=$(jq -r '.task_id // empty' "$req_file" 2>/dev/null || true)
}

# Validate action matches expected value
# Usage: broker_validate_action "expected_action"
broker_validate_action() {
  local expected="$1"
  if [ "$BROKER_ACTION" != "$expected" ]; then
    broker_error "error" "Wrong action: expected ${expected}, got ${BROKER_ACTION}"
  fi
}

# Validate request_id and task_id are non-empty
# Usage: broker_validate_required_fields
broker_validate_required_fields() {
  if [ -z "$BROKER_REQUEST_ID" ] || [ -z "$BROKER_TASK_ID" ]; then
    broker_error "error" "Missing required fields: request_id, task_id"
  fi
}

# Validate SHA256 hex string format (exactly 64 lowercase hex chars)
# Usage: broker_validate_sha256 "$sha256_value"
broker_validate_sha256() {
  local sha256="$1"
  if ! echo "$sha256" | grep -qE '^[a-f0-9]{64}$'; then
    broker_error "error" "Invalid SHA256 format"
  fi
}

# Validate path is within allowed prefix and contains no traversal
# Usage: broker_validate_path "$path" "$allowed_prefix"
broker_validate_path() {
  local path="$1" prefix="$2"
  case "$path" in
    "$prefix"*) ;;
    *)
      broker_error "denied" "Path not in whitelist: must start with ${prefix}"
      ;;
  esac
  case "$path" in
    *".."*)
      broker_error "denied" "Path traversal detected"
      ;;
  esac
}

# Validate label/name format (alphanumeric, dots, hyphens, underscores)
# Usage: broker_validate_label "$value" "field_name"
broker_validate_label() {
  local value="$1" field="${2:-label}"
  if ! echo "$value" | grep -qE '^[a-zA-Z0-9._-]+$'; then
    broker_error "error" "Invalid ${field} format: alphanumeric, dots, hyphens, underscores only"
  fi
}

# --- Output helpers ---

# Emit structured success result on stdout
# Usage: broker_emit_result '{"key":"value"}' "message" "rollback_hint"
# Uses BROKER_ACTION, BROKER_REQUEST_ID, BROKER_TASK_ID
broker_emit_result() {
  local artifacts="$1" msg="${2:-}" hint="${3:-}"
  [ -z "$artifacts" ] && artifacts="{}"
  cat <<EOF
{
  "ok": true,
  "action": "${BROKER_ACTION}",
  "request_id": "${BROKER_REQUEST_ID}",
  "task_id": "${BROKER_TASK_ID}",
  "status": "ok",
  "message": "${msg}",
  "artifacts": ${artifacts},
  "rollback_hint": "${hint}"
}
EOF
}
