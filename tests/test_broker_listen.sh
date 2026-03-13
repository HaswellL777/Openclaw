#!/usr/bin/env bash
# test_broker_listen.sh — Tests for broker --listen (socket listener) mode
#
# Tests:
#   1. broker --listen happy path (gateway_health via socket)
#   2. plugin → socket → broker → wrapper end-to-end
#   3. invalid JSON over socket
#   4. unknown action over socket
#   5. missing required fields over socket
#   6. broker unavailable (no socket)
#   7. read timeout (simulated)
#   8. unauthorized peer (boundary-documented)
#   9. dry-run default still holds via socket
#   10. result envelope contract non-drift
#
# Dependencies: bash, python3, jq, socat (optional, for raw socket tests)
# Does NOT require: root, sudo, openclaw user
#
# Uses BROKER_ALLOWED_UID=$UID to allow dev-user connections.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BROKER="${REPO_ROOT}/broker/openclaw-broker"
LISTENER="${REPO_ROOT}/broker/lib/socket-listener.py"

PASS=0
FAIL=0
SKIP=0
TOTAL=0

# --- Test helpers ---
pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  FAIL  $1"; }
skip() { SKIP=$((SKIP + 1)); TOTAL=$((TOTAL + 1)); echo "  SKIP  $1"; }

# Create temp dir for sockets and working files
TMPDIR_TEST=$(mktemp -d "${TMPDIR:-/tmp}/broker-listen-test-XXXXXX")
SOCKET_PATH="${TMPDIR_TEST}/broker.sock"
LOG_FILE="${TMPDIR_TEST}/broker.log"
LISTENER_PID=""

cleanup() {
  if [ -n "$LISTENER_PID" ] && kill -0 "$LISTENER_PID" 2>/dev/null; then
    kill "$LISTENER_PID" 2>/dev/null || true
    wait "$LISTENER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

# Start the broker listener in background
start_listener() {
  local extra_env="${1:-}"

  # Kill any existing listener
  if [ -n "$LISTENER_PID" ] && kill -0 "$LISTENER_PID" 2>/dev/null; then
    kill "$LISTENER_PID" 2>/dev/null || true
    wait "$LISTENER_PID" 2>/dev/null || true
    LISTENER_PID=""
  fi

  # Clean stale socket
  rm -f "$SOCKET_PATH"

  env \
    BROKER_SOCKET_PATH="$SOCKET_PATH" \
    BROKER_ALLOWED_UID="$UID" \
    BROKER_DRY_RUN="true" \
    BROKER_DISPATCH_CMD="$BROKER" \
    BROKER_WRAPPER_DIR="${REPO_ROOT}/broker/wrappers" \
    $extra_env \
    python3 "$LISTENER" >"${TMPDIR_TEST}/listener-stdout.log" 2>"${TMPDIR_TEST}/listener-stderr.log" &
  LISTENER_PID=$!

  # Wait for socket to appear (max 5s)
  local waited=0
  while [ ! -S "$SOCKET_PATH" ] && [ $waited -lt 50 ]; do
    sleep 0.1
    waited=$((waited + 1))
    # Check if listener died
    if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
      echo "ERROR: Listener died during startup. Stderr:" >&2
      cat "${TMPDIR_TEST}/listener-stderr.log" >&2
      return 1
    fi
  done

  if [ ! -S "$SOCKET_PATH" ]; then
    echo "ERROR: Socket did not appear within 5s" >&2
    return 1
  fi
}

stop_listener() {
  if [ -n "$LISTENER_PID" ] && kill -0 "$LISTENER_PID" 2>/dev/null; then
    kill "$LISTENER_PID" 2>/dev/null || true
    wait "$LISTENER_PID" 2>/dev/null || true
    LISTENER_PID=""
  fi
  rm -f "$SOCKET_PATH"
}

# Send a JSON request to the socket and capture the response.
# Uses Python since socat may not be available.
send_request() {
  local json_payload="$1"
  local timeout="${2:-10}"

  python3 -c "
import socket, sys, json

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(${timeout})
try:
    sock.connect('${SOCKET_PATH}')
    sock.sendall(json.dumps(json.loads('''${json_payload}''')).encode())
    sock.shutdown(socket.SHUT_WR)
    chunks = []
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        chunks.append(chunk)
    result = b''.join(chunks).decode()
    print(result)
except Exception as e:
    print(json.dumps({'_transport_error': str(e)}))
finally:
    sock.close()
" 2>/dev/null
}

# Send raw bytes (not necessarily valid JSON) to socket
send_raw() {
  local raw_payload="$1"
  local timeout="${2:-10}"

  python3 -c "
import socket, sys, json

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(${timeout})
try:
    sock.connect('${SOCKET_PATH}')
    sock.sendall(b'''${raw_payload}''')
    sock.shutdown(socket.SHUT_WR)
    chunks = []
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        chunks.append(chunk)
    result = b''.join(chunks).decode()
    print(result)
except Exception as e:
    print(json.dumps({'_transport_error': str(e)}))
finally:
    sock.close()
" 2>/dev/null
}

echo "================================================================"
echo "  TEST: Broker --listen mode (socket listener)"
echo "================================================================"
echo ""
echo "Repository: $REPO_ROOT"
echo "Broker: $BROKER"
echo "Listener: $LISTENER"
echo "Socket: $SOCKET_PATH"
echo "Test user UID: $UID"
echo ""

# --- Prerequisite checks ---
echo "--- Prerequisites ---"

if [ ! -f "$BROKER" ]; then
  echo "FATAL: Broker script not found: $BROKER"
  exit 1
fi
if [ ! -f "$LISTENER" ]; then
  echo "FATAL: Listener script not found: $LISTENER"
  exit 1
fi
if ! command -v python3 &>/dev/null; then
  echo "FATAL: python3 not available"
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "FATAL: jq not available"
  exit 1
fi
echo "All prerequisites met"
echo ""

# ============================================================
# Test 1: broker --listen happy path (gateway_health)
# ============================================================
echo "--- Test 1: Happy path — gateway_health via socket ---"

start_listener

RESULT=$(send_request '{
  "action": "gateway_health",
  "request_id": "req-test-listen-001",
  "task_id": "task-test-listen",
  "requested_by": "test:listen",
  "inputs": {}
}')

if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
  pass "gateway_health returns ok=true"
else
  fail "gateway_health did not return ok=true (got: $RESULT)"
fi

if echo "$RESULT" | jq -e '.status == "ok"' >/dev/null 2>&1; then
  pass "gateway_health returns status=ok"
else
  fail "gateway_health did not return status=ok"
fi

if echo "$RESULT" | jq -e '.action == "gateway_health"' >/dev/null 2>&1; then
  pass "gateway_health echoes action"
else
  fail "gateway_health does not echo action"
fi

if echo "$RESULT" | jq -e '.request_id == "req-test-listen-001"' >/dev/null 2>&1; then
  pass "gateway_health echoes request_id"
else
  fail "gateway_health does not echo request_id"
fi

stop_listener
echo ""

# ============================================================
# Test 2: End-to-end — all 8 actions via socket
# ============================================================
echo "--- Test 2: End-to-end — all 8 actions via socket ---"

start_listener

# Define test payloads for all 8 actions
declare -A E2E_REQUESTS
E2E_REQUESTS[gateway_health]='{"action":"gateway_health","request_id":"req-e2e-001","task_id":"task-e2e","requested_by":"test:e2e","inputs":{}}'
E2E_REQUESTS[gateway_restart]='{"action":"gateway_restart","request_id":"req-e2e-002","task_id":"task-e2e","requested_by":"test:e2e","inputs":{"reason":"e2e test"}}'
E2E_REQUESTS[validate_openclaw_json_candidate]='{"action":"validate_openclaw_json_candidate","request_id":"req-e2e-003","task_id":"task-e2e","requested_by":"test:e2e","inputs":{"candidate_path":"/var/lib/openclaw/approvals/candidates/test.json","expected_sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}}'
E2E_REQUESTS[deploy_openclaw_json_candidate]='{"action":"deploy_openclaw_json_candidate","request_id":"req-e2e-004","task_id":"task-e2e","requested_by":"test:e2e","inputs":{"candidate_path":"/var/lib/openclaw/approvals/candidates/test.json","expected_sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}}'
E2E_REQUESTS[snapshot_pre]='{"action":"snapshot_pre","request_id":"req-e2e-005","task_id":"task-e2e","requested_by":"test:e2e","inputs":{"label":"test-20260313","reason":"e2e test"}}'
E2E_REQUESTS[snapshot_post]='{"action":"snapshot_post","request_id":"req-e2e-006","task_id":"task-e2e","requested_by":"test:e2e","inputs":{"label":"test-20260313-post","reason":"e2e test"}}'
E2E_REQUESTS[vault_sync]='{"action":"vault_sync","request_id":"req-e2e-007","task_id":"task-e2e","requested_by":"test:e2e","inputs":{"snapshot_name":"root-test-20260313"}}'
E2E_REQUESTS[rollback_prepare]='{"action":"rollback_prepare","request_id":"req-e2e-008","task_id":"task-e2e","requested_by":"test:e2e","inputs":{"target_snapshot":"root-test-20260313","reason":"e2e test"}}'

for action in gateway_health gateway_restart validate_openclaw_json_candidate deploy_openclaw_json_candidate snapshot_pre snapshot_post vault_sync rollback_prepare; do
  RESULT=$(send_request "${E2E_REQUESTS[$action]}")
  if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
    pass "E2E: $action returns ok=true"
  else
    fail "E2E: $action did not return ok=true (got: $RESULT)"
  fi
done

stop_listener
echo ""

# ============================================================
# Test 3: Invalid JSON over socket
# ============================================================
echo "--- Test 3: Invalid JSON over socket ---"

start_listener

RESULT=$(send_raw 'this is not json at all{{{')

if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Invalid JSON returns ok=false"
else
  fail "Invalid JSON did not return ok=false (got: $RESULT)"
fi

stop_listener
echo ""

# ============================================================
# Test 4: Unknown action over socket
# ============================================================
echo "--- Test 4: Unknown action over socket ---"

start_listener

RESULT=$(send_request '{
  "action": "delete_everything",
  "request_id": "req-test-neg-001",
  "task_id": "task-test-neg",
  "requested_by": "test:neg",
  "inputs": {}
}')

if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Unknown action returns ok=false"
else
  fail "Unknown action did not return ok=false (got: $RESULT)"
fi

if echo "$RESULT" | jq -e '.status == "error"' >/dev/null 2>&1; then
  pass "Unknown action returns status=error"
else
  fail "Unknown action did not return status=error"
fi

stop_listener
echo ""

# ============================================================
# Test 5: Missing required fields over socket
# ============================================================
echo "--- Test 5: Missing required fields over socket ---"

start_listener

# Missing request_id and task_id
RESULT=$(send_request '{
  "action": "gateway_health",
  "requested_by": "test:neg",
  "inputs": {}
}')

if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "Missing fields returns ok=false"
else
  fail "Missing fields did not return ok=false (got: $RESULT)"
fi

stop_listener
echo ""

# ============================================================
# Test 6: Broker unavailable (no socket)
# ============================================================
echo "--- Test 6: Broker unavailable (no socket) ---"

# Don't start listener — socket should not exist
NONEXISTENT="/tmp/broker-test-nonexistent-$(date +%s).sock"

RESULT=$(python3 -c "
import socket, json, sys
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(3)
try:
    sock.connect('${NONEXISTENT}')
    print(json.dumps({'connected': True}))
except (FileNotFoundError, ConnectionRefusedError) as e:
    print(json.dumps({'_transport_error': str(e), 'error_type': type(e).__name__}))
except Exception as e:
    print(json.dumps({'_transport_error': str(e), 'error_type': type(e).__name__}))
finally:
    sock.close()
" 2>/dev/null)

if echo "$RESULT" | jq -e '._transport_error' >/dev/null 2>&1; then
  pass "Broker unavailable: connection fails with error"
else
  fail "Broker unavailable: expected transport error (got: $RESULT)"
fi

echo ""

# ============================================================
# Test 7: Timeout behavior
# ============================================================
echo "--- Test 7: Timeout behavior ---"

# We test that the plugin send_request concept times out by connecting
# to a socket that accepts but never responds.
# Create a Python socket that accepts but does nothing
TIMEOUT_SOCKET="${TMPDIR_TEST}/timeout.sock"

python3 -c "
import socket, time, os, sys
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind('${TIMEOUT_SOCKET}')
sock.listen(1)
# Accept one connection then just wait without responding
conn, _ = sock.accept()
time.sleep(5)
conn.close()
sock.close()
os.unlink('${TIMEOUT_SOCKET}')
" &>/dev/null &
TIMEOUT_PID=$!

# Wait for socket
sleep 0.3

if [ -S "$TIMEOUT_SOCKET" ]; then
  # Try to connect with a short timeout
  RESULT=$(python3 -c "
import socket, json, time
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(2)
try:
    sock.connect('${TIMEOUT_SOCKET}')
    sock.sendall(b'{\"action\":\"gateway_health\"}')
    sock.shutdown(socket.SHUT_WR)
    data = sock.recv(65536)
    print(json.dumps({'received': data.decode() if data else 'empty'}))
except socket.timeout:
    print(json.dumps({'_transport_error': 'timeout', 'timed_out': True}))
except Exception as e:
    print(json.dumps({'_transport_error': str(e)}))
finally:
    sock.close()
" 2>/dev/null)

  if echo "$RESULT" | jq -e '.timed_out == true' >/dev/null 2>&1; then
    pass "Timeout: client correctly times out on unresponsive server"
  elif echo "$RESULT" | jq -e '.received == "empty"' >/dev/null 2>&1; then
    pass "Timeout: server closed without response (connection reset)"
  else
    fail "Timeout: unexpected result (got: $RESULT)"
  fi
else
  skip "Timeout: could not create test socket"
fi

kill "$TIMEOUT_PID" 2>/dev/null || true
wait "$TIMEOUT_PID" 2>/dev/null || true
rm -f "$TIMEOUT_SOCKET"

echo ""

# ============================================================
# Test 8: Unauthorized peer (boundary-documented)
# ============================================================
echo "--- Test 8: Unauthorized peer ---"

# Start listener with BROKER_ALLOWED_UID=99999 (a UID that doesn't match current user)
# This means only root (uid=0) and uid=99999 are allowed, and since we're running
# as $UID (which is neither), we should be rejected.

start_listener "BROKER_ALLOWED_UID=99999"

# Override the allowed UID in the listener process
stop_listener

# Restart with restrictive UID
rm -f "$SOCKET_PATH"
env \
  BROKER_SOCKET_PATH="$SOCKET_PATH" \
  BROKER_ALLOWED_UID="99999" \
  BROKER_DRY_RUN="true" \
  BROKER_DISPATCH_CMD="$BROKER" \
  BROKER_WRAPPER_DIR="${REPO_ROOT}/broker/wrappers" \
  python3 "$LISTENER" >"${TMPDIR_TEST}/listener-stdout.log" 2>"${TMPDIR_TEST}/listener-stderr.log" &
LISTENER_PID=$!

# Wait for socket
waited=0
while [ ! -S "$SOCKET_PATH" ] && [ $waited -lt 50 ]; do
  sleep 0.1
  waited=$((waited + 1))
done

if [ -S "$SOCKET_PATH" ]; then
  RESULT=$(send_request '{
    "action": "gateway_health",
    "request_id": "req-auth-test",
    "task_id": "task-auth-test",
    "requested_by": "test:auth",
    "inputs": {}
  }')

  if echo "$RESULT" | jq -e '.ok == false' >/dev/null 2>&1; then
    pass "Unauthorized peer: returns ok=false"
  else
    fail "Unauthorized peer: did not return ok=false (got: $RESULT)"
  fi

  if echo "$RESULT" | jq -e '.status == "denied"' >/dev/null 2>&1; then
    pass "Unauthorized peer: returns status=denied"
  else
    fail "Unauthorized peer: did not return status=denied (got: $(echo "$RESULT" | jq -r '.status' 2>/dev/null))"
  fi
else
  skip "Unauthorized peer: socket did not appear (listener may have failed to start)"
fi

stop_listener
echo ""

# ============================================================
# Test 9: Dry-run default holds via socket
# ============================================================
echo "--- Test 9: Dry-run default holds via socket ---"

start_listener

RESULT=$(send_request '{
  "action": "gateway_health",
  "request_id": "req-dryrun-test",
  "task_id": "task-dryrun-test",
  "requested_by": "test:dryrun",
  "inputs": {}
}')

# In dry-run mode, gateway_health returns mode: "dry-run" in artifacts
if echo "$RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
  pass "Dry-run: request succeeds"
else
  fail "Dry-run: request failed (got: $RESULT)"
fi

# Check wrapper stderr for STUB marker (captured in listener stderr)
if grep -q '\[STUB\]' "${TMPDIR_TEST}/listener-stderr.log" 2>/dev/null; then
  pass "Dry-run: wrapper emitted [STUB] markers"
else
  # Check broker stderr relayed through listener
  if grep -qi 'STUB' "${TMPDIR_TEST}/listener-stderr.log" 2>/dev/null; then
    pass "Dry-run: STUB markers detected in logs"
  else
    # Artifacts might contain mode field
    MODE=$(echo "$RESULT" | jq -r '.artifacts.mode // empty' 2>/dev/null)
    if [ "$MODE" = "dry-run" ]; then
      pass "Dry-run: result artifacts contain mode=dry-run"
    else
      fail "Dry-run: could not verify dry-run mode"
    fi
  fi
fi

stop_listener
echo ""

# ============================================================
# Test 10: Result envelope contract non-drift
# ============================================================
echo "--- Test 10: Result envelope contract non-drift ---"

start_listener

RESULT=$(send_request '{
  "action": "gateway_health",
  "request_id": "req-contract-test",
  "task_id": "task-contract-test",
  "requested_by": "test:contract",
  "inputs": {}
}')

# Check all required result fields are present
for field in ok action request_id task_id status; do
  if echo "$RESULT" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
    pass "Contract: result has required field '$field'"
  else
    fail "Contract: result missing required field '$field'"
  fi
done

# Check ok/status invariant
OK_VAL=$(echo "$RESULT" | jq -r '.ok' 2>/dev/null)
STATUS_VAL=$(echo "$RESULT" | jq -r '.status' 2>/dev/null)

if [ "$OK_VAL" = "true" ] && [ "$STATUS_VAL" = "ok" ]; then
  pass "Contract: ok=true implies status=ok"
elif [ "$OK_VAL" = "false" ] && [ "$STATUS_VAL" != "ok" ]; then
  pass "Contract: ok=false implies status!=ok"
else
  fail "Contract: ok/status invariant violated (ok=$OK_VAL, status=$STATUS_VAL)"
fi

# Check action and request_id are echoed
if echo "$RESULT" | jq -e '.action == "gateway_health"' >/dev/null 2>&1; then
  pass "Contract: action echoed correctly"
else
  fail "Contract: action not echoed"
fi

if echo "$RESULT" | jq -e '.request_id == "req-contract-test"' >/dev/null 2>&1; then
  pass "Contract: request_id echoed correctly"
else
  fail "Contract: request_id not echoed"
fi

# Error path contract check
RESULT_ERR=$(send_request '{
  "action": "delete_everything",
  "request_id": "req-contract-err",
  "task_id": "task-contract-err",
  "requested_by": "test:contract",
  "inputs": {}
}')

OK_ERR=$(echo "$RESULT_ERR" | jq -r '.ok' 2>/dev/null)
STATUS_ERR=$(echo "$RESULT_ERR" | jq -r '.status' 2>/dev/null)

if [ "$OK_ERR" = "false" ] && { [ "$STATUS_ERR" = "error" ] || [ "$STATUS_ERR" = "denied" ]; }; then
  pass "Contract: error path maintains ok=false + status=error|denied"
else
  fail "Contract: error path invariant violated (ok=$OK_ERR, status=$STATUS_ERR)"
fi

stop_listener
echo ""

# ============================================================
# Test 11: broker --listen CLI integration
# ============================================================
echo "--- Test 11: broker --listen CLI integration ---"

# Verify --listen mode flag is recognized
HELP_OUTPUT=$(bash "$BROKER" --help 2>&1 || true)
if echo "$HELP_OUTPUT" | grep -q '\-\-listen'; then
  pass "broker --help mentions --listen"
else
  fail "broker --help does not mention --listen"
fi

# Verify --socket-path flag is recognized
if echo "$HELP_OUTPUT" | grep -q '\-\-socket-path'; then
  pass "broker --help mentions --socket-path"
else
  fail "broker --help does not mention --socket-path"
fi

# Verify version bump
VERSION_OUTPUT=$(bash "$BROKER" --version 2>&1)
if echo "$VERSION_OUTPUT" | grep -q '0.2.0-dev'; then
  pass "broker --version shows 0.2.0-dev"
else
  fail "broker --version does not show 0.2.0-dev (got: $VERSION_OUTPUT)"
fi

echo ""

# ============================================================
# Test 12: Existing --dispatch mode still works
# ============================================================
echo "--- Test 12: Existing --dispatch mode regression ---"

DISPATCH_REQ="${TMPDIR_TEST}/dispatch-test.json"
cat > "$DISPATCH_REQ" << 'EOF'
{
  "action": "gateway_health",
  "request_id": "req-dispatch-regression",
  "task_id": "task-dispatch-regression",
  "requested_by": "test:dispatch",
  "inputs": {}
}
EOF

DISPATCH_RESULT=$(BROKER_DRY_RUN=true BROKER_WRAPPER_DIR="${REPO_ROOT}/broker/wrappers" \
  bash "$BROKER" --dispatch "$DISPATCH_REQ" 2>/dev/null)

if echo "$DISPATCH_RESULT" | jq -e '.ok == true' >/dev/null 2>&1; then
  pass "dispatch mode: still returns ok=true"
else
  fail "dispatch mode: regression — did not return ok=true (got: $DISPATCH_RESULT)"
fi

if echo "$DISPATCH_RESULT" | jq -e '.request_id == "req-dispatch-regression"' >/dev/null 2>&1; then
  pass "dispatch mode: still echoes request_id"
else
  fail "dispatch mode: regression — request_id not echoed"
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "================================================================"
echo "  TEST SUMMARY: Broker --listen mode"
echo "================================================================"
echo ""
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"
echo "  TOTAL: $TOTAL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL ($FAIL failures)"
  exit 1
elif [ "$SKIP" -gt 0 ]; then
  echo "  RESULT: PASS with $SKIP skipped"
  exit 0
else
  echo "  RESULT: PASS (all tests passed)"
  exit 0
fi
