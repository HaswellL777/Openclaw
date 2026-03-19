#!/usr/bin/env bash
# preflight-capability-probe.sh — Repo-side only-read preflight check
# Purpose: Verify that all probe documentation and prerequisites are in place
#          before operator begins live capability probe execution.
# Safety:  No sudo, no live-side, no system state changes. Read-only.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN + 1)); }

echo "=== Post-Upgrade Capability Probe Preflight ==="
echo "Repo: ${REPO_ROOT}"
echo "Date: $(date --iso-8601=seconds)"
echo ""

# --- Section 1: Probe design documents ---
echo "--- Section 1: Probe design documents ---"

PROBE_DESIGN="${REPO_ROOT}/docs/planning/post-upgrade-capability-probe-2026.3.13-slice-design-2026-03-18.md"
if [[ -f "$PROBE_DESIGN" ]]; then pass "Probe slice design exists"; else fail "Missing: $PROBE_DESIGN"; fi

PROBE_MATRIX="${REPO_ROOT}/docs/checklists/post-upgrade-capability-probe-matrix-2026.3.13.md"
if [[ -f "$PROBE_MATRIX" ]]; then pass "Probe matrix exists"; else fail "Missing: $PROBE_MATRIX"; fi

PROBE_RUNBOOK="${REPO_ROOT}/docs/runbook-post-upgrade-capability-probe-2026.3.13.md"
if [[ -f "$PROBE_RUNBOOK" ]]; then pass "Probe operator runbook exists"; else fail "Missing: $PROBE_RUNBOOK"; fi

PROBE_TEMPLATE="${REPO_ROOT}/docs/templates/post-upgrade-capability-probe-record-template.md"
if [[ -f "$PROBE_TEMPLATE" ]]; then pass "Probe record template exists"; else fail "Missing: $PROBE_TEMPLATE"; fi

echo ""

# --- Section 2: Prerequisite authority documents ---
echo "--- Section 2: Authority documents accessible ---"

for DOC in \
  "docs/current-boundary.md" \
  "docs/design-v3.md" \
  "docs/host-sop.md" \
  "docs/map.md" \
  "docs/records/README.md" \
  "docs/records/openclaw-2026.3.13-upgrade-activation-2026-03-18.md" \
  "workspace-main-template/control/host-ops-api.md" \
  "docs/adr/adr-scrapling-placement.md"
do
  if [[ -f "${REPO_ROOT}/${DOC}" ]]; then
    pass "${DOC}"
  else
    fail "Missing: ${DOC}"
  fi
done

echo ""

# --- Section 3: Upgrade baseline confirmed ---
echo "--- Section 3: Upgrade baseline in docs ---"

if grep -q "2026.3.13" "${REPO_ROOT}/docs/current-boundary.md" 2>/dev/null; then
  pass "current-boundary.md references 2026.3.13"
else
  fail "current-boundary.md does not reference 2026.3.13"
fi

if grep -q "2026.3.13" "${REPO_ROOT}/docs/records/openclaw-2026.3.13-upgrade-activation-2026-03-18.md" 2>/dev/null; then
  pass "Upgrade activation record exists and references 2026.3.13"
else
  fail "Upgrade activation record missing or does not reference 2026.3.13"
fi

if grep -q "19/19 PASS" "${REPO_ROOT}/docs/records/openclaw-2026.3.13-upgrade-activation-2026-03-18.md" 2>/dev/null; then
  pass "Focused regression 19/19 PASS confirmed in activation record"
else
  warn "Cannot confirm 19/19 PASS in activation record"
fi

echo ""

# --- Section 4: Cross-reference consistency ---
echo "--- Section 4: Cross-reference consistency ---"

if grep -q "capability probe" "${REPO_ROOT}/docs/planning/README.md" 2>/dev/null; then
  pass "planning/README.md references capability probe"
else
  fail "planning/README.md does not reference capability probe"
fi

if grep -q "capability-probe" "${REPO_ROOT}/docs/map.md" 2>/dev/null; then
  pass "map.md references capability probe artifacts"
else
  fail "map.md does not reference capability probe artifacts"
fi

echo ""

# --- Summary ---
echo "=== Summary ==="
echo "  PASS: ${PASS}"
echo "  WARN: ${WARN}"
echo "  FAIL: ${FAIL}"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "RESULT: PREFLIGHT FAILED — ${FAIL} issue(s) must be resolved before probe execution."
  exit 1
else
  echo "RESULT: PREFLIGHT PASSED — all probe documents and prerequisites in place."
  exit 0
fi
