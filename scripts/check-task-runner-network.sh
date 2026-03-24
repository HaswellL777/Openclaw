#!/usr/bin/env bash
# check-task-runner-network.sh — Verify outbound connectivity from task-runner container.
# Usage: sudo bash scripts/check-task-runner-network.sh
#
# Uses the slim image by default. Override with:
#   IMAGE=openclaw-task-claude:2026-03-v3-full sudo bash scripts/check-task-runner-network.sh

set -euo pipefail

IMAGE="${IMAGE:-openclaw-task-claude:2026-03-v3}"
NETWORK="openclaw-task-net"
GATEWAY_PORT="${GATEWAY_PORT:-17777}"
PASS=0
FAIL=0
SKIP=0

run_in_container() {
  docker run --rm --network "$NETWORK" "$IMAGE" bash -c "$1"
}

report() {
  local label="$1" result="$2"
  if [[ "$result" == "PASS" ]]; then
    printf "  [PASS] %s\n" "$label"
    ((PASS++)) || true
  elif [[ "$result" == "SKIP" ]]; then
    printf "  [SKIP] %s\n" "$label"
    ((SKIP++)) || true
  else
    printf "  [FAIL] %s\n" "$label"
    ((FAIL++)) || true
  fi
}

echo "=== task-runner network connectivity check ==="
echo "Image:   $IMAGE"
echo "Network: $NETWORK"
echo ""

# ── Check 1: DNS resolution ──
echo "--- Check 1: DNS resolution (github.com) ---"
if run_in_container "getent hosts github.com >/dev/null 2>&1"; then
  report "DNS resolves github.com" "PASS"
else
  report "DNS resolves github.com" "FAIL"
fi

# ── Check 2: GitHub HTTPS (git ls-remote) ──
echo "--- Check 2: GitHub access (git ls-remote) ---"
if run_in_container "git ls-remote --exit-code https://github.com/octocat/Hello-World.git HEAD >/dev/null 2>&1"; then
  report "git ls-remote to GitHub" "PASS"
else
  report "git ls-remote to GitHub" "FAIL"
fi

# ── Check 3: PyPI access ──
echo "--- Check 3: PyPI access ---"
if run_in_container "python3 -c \"import urllib.request; urllib.request.urlopen('https://pypi.org/simple/pip/')\" >/dev/null 2>&1"; then
  report "HTTPS fetch from pypi.org" "PASS"
elif run_in_container "which python3 >/dev/null 2>&1"; then
  report "HTTPS fetch from pypi.org" "FAIL"
else
  report "HTTPS fetch from pypi.org (python3 not installed)" "SKIP"
fi

# ── Check 4: npm registry access ──
echo "--- Check 4: npm registry access ---"
if run_in_container "which npm >/dev/null 2>&1 && npm ping --registry https://registry.npmjs.org 2>/dev/null"; then
  report "npm ping to registry" "PASS"
elif run_in_container "which npm >/dev/null 2>&1"; then
  report "npm ping to registry" "FAIL"
else
  report "npm ping to registry (npm not installed in slim image)" "SKIP"
fi

# ── Check 5: Gateway port reachability ──
echo "--- Check 5: Gateway port ($GATEWAY_PORT) reachability ---"
# Use bash /dev/tcp since curl may not be in slim image
if run_in_container "timeout 5 bash -c 'echo > /dev/tcp/host.docker.internal/${GATEWAY_PORT}' 2>/dev/null || timeout 5 bash -c 'echo > /dev/tcp/172.17.0.1/${GATEWAY_PORT}' 2>/dev/null"; then
  report "TCP connect to gateway:$GATEWAY_PORT" "PASS"
else
  # Try the bridge gateway IP (docker inspect the network)
  GATEWAY_IP=$(docker network inspect "$NETWORK" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "")
  if [[ -n "$GATEWAY_IP" ]] && run_in_container "timeout 5 bash -c 'echo > /dev/tcp/${GATEWAY_IP}/${GATEWAY_PORT}' 2>/dev/null"; then
    report "TCP connect to gateway:$GATEWAY_PORT (via bridge gateway $GATEWAY_IP)" "PASS"
  else
    report "TCP connect to gateway:$GATEWAY_PORT" "FAIL"
    echo "       Note: gateway bind=loopback may block container access."
    echo "       Bridge gateway IP: ${GATEWAY_IP:-unknown}"
    echo "       If gateway is bound to 127.0.0.1 only, containers on a bridge"
    echo "       network cannot reach it. Consider binding to 0.0.0.0 or the"
    echo "       bridge gateway IP, or using socat/iptables forwarding."
  fi
fi

echo ""
echo "=== Summary ==="
echo "  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
if [[ "$FAIL" -gt 0 ]]; then
  echo "  Result: SOME CHECKS FAILED"
  exit 1
else
  echo "  Result: ALL CHECKS PASSED"
  exit 0
fi
