#!/usr/bin/env bash
# preflight-upgrade-openclaw.sh
# Repo-side preflight check for OpenClaw upgrade readiness.
# This script only checks that repo-side documents and artifacts exist.
# It does NOT perform any live-side operations, does NOT require sudo,
# and does NOT modify any files.
#
# Usage: bash scripts/preflight-upgrade-openclaw.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
WARN=0

check_file() {
    local label="$1"
    local path="$2"
    if [ -f "${REPO_ROOT}/${path}" ]; then
        echo "  [PASS] ${label}: ${path}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${label}: ${path} — not found"
        FAIL=$((FAIL + 1))
    fi
}

check_dir() {
    local label="$1"
    local path="$2"
    if [ -d "${REPO_ROOT}/${path}" ]; then
        echo "  [PASS] ${label}: ${path}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${label}: ${path} — not found"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== OpenClaw Upgrade Preflight Check ==="
echo "Repo: ${REPO_ROOT}"
echo "Date: $(date --iso-8601=seconds)"
echo ""

# --- 1. Upgrade planning documents ---
echo "--- 1. Upgrade planning documents ---"
check_file "Upgrade readiness assessment" \
    "docs/planning/openclaw-upgrade-readiness-2026-03-18.md"
check_file "Upgrade slice design" \
    "docs/planning/openclaw-2026.3.13-upgrade-slice-design-2026-03-18.md"
check_file "Rollback design" \
    "docs/planning/openclaw-2026.3.13-upgrade-rollback-design-2026-03-18.md"
echo ""

# --- 2. Operator runbook ---
echo "--- 2. Operator runbook ---"
check_file "Upgrade runbook" \
    "docs/runbook-openclaw-upgrade-2026.3.13.md"
echo ""

# --- 3. Regression checklist ---
echo "--- 3. Regression checklist ---"
check_file "Focused regression checklist" \
    "docs/checklists/openclaw-upgrade-focused-regression-2026.3.13.md"
echo ""

# --- 4. Authority documents ---
echo "--- 4. Authority documents ---"
check_file "Host SOP" "docs/host-sop.md"
check_file "Design v3" "docs/design-v3.md"
check_file "Current boundary" "docs/current-boundary.md"
check_file "Document map" "docs/map.md"
echo ""

# --- 5. Existing records ---
echo "--- 5. Phase 2 records (evidence base) ---"
check_file "Broker deployment record" \
    "docs/records/phase2-broker-deployment-2026-03-14.md"
check_file "Plugin activation record" \
    "docs/records/phase2-plugin-activation-2026-03-15.md"
check_file "vault_sync activation record" \
    "docs/records/phase2-hostops-vault-sync-activation-2026-03-17.md"
check_dir  "Records directory" "docs/records"
echo ""

# --- 6. Broker/plugin artifacts ---
echo "--- 6. Broker/plugin artifacts ---"
check_file "host-ops-tool plugin" "plugins/host-ops-tool/index.js"
check_dir  "Broker wrappers" "broker/wrappers"
check_file "Broker request schema" "broker/schemas/host-ops-request.schema.json"
echo ""

# --- 7. host-ops-api contract ---
echo "--- 7. Host-ops API contract ---"
check_file "host-ops-api.md" \
    "workspace-main-template/control/host-ops-api.md"
echo ""

# --- 8. Deploy checklist ---
echo "--- 8. Existing checklists ---"
check_file "Route C deploy checklist" \
    "docs/checklists/deploy-candidate-route-c-checklist.md"
echo ""

# --- 9. Git status ---
echo "--- 9. Git status ---"
BRANCH=$(cd "${REPO_ROOT}" && git branch --show-current 2>/dev/null || echo "unknown")
echo "  Current branch: ${BRANCH}"
if [ "${BRANCH}" = "feat/phase1b-workspace-foundation" ]; then
    echo "  [PASS] On expected branch"
    PASS=$((PASS + 1))
else
    echo "  [WARN] Not on expected branch (feat/phase1b-workspace-foundation)"
    WARN=$((WARN + 1))
fi

DIRTY=$(cd "${REPO_ROOT}" && git status --porcelain --untracked-files=no 2>/dev/null | wc -l)
if [ "${DIRTY}" -eq 0 ]; then
    echo "  [PASS] No uncommitted tracked changes"
    PASS=$((PASS + 1))
else
    echo "  [WARN] ${DIRTY} uncommitted tracked changes detected"
    WARN=$((WARN + 1))
fi
echo ""

# --- Summary ---
echo "=== Summary ==="
echo "  PASS: ${PASS}"
echo "  FAIL: ${FAIL}"
echo "  WARN: ${WARN}"
echo ""

if [ "${FAIL}" -gt 0 ]; then
    echo "RESULT: NOT READY — ${FAIL} required item(s) missing"
    exit 1
else
    echo "RESULT: READY — all required repo-side artifacts present"
    if [ "${WARN}" -gt 0 ]; then
        echo "  (${WARN} warning(s) — review before proceeding)"
    fi
    exit 0
fi
