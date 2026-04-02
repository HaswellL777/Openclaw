#!/usr/bin/env bash
set -euo pipefail

# validate-openclaw.sh
# Purpose: End-to-end validation of OpenClaw host system after backup/restore
#          or any significant change.
#
# Usage:
#   sudo bash scripts/validate-openclaw.sh
#
# Checks performed:
#   1. Gateway service status
#   2. Broker service status
#   3. GUI service status
#   4. Hotfix verification (3 hotfixes)
#   5. runs.json readability
#   6. Directory permissions
#   7. Config file presence and permissions
#   8. Docker container/network status
#   9. Cron job status
#  10. Snapshot directory health
#  11. Log directory health
#
# Exit code: 0 if all checks pass, 1 if any check fails

# --- Constants ---
DATA_DIR="/var/lib/openclaw"
CONFIG_DIR="/etc/openclaw"
CODE_DIR="/opt/openclaw"
LOG_DIR="/var/log/openclaw"
SNAPSHOT_DIR="/.snapshots"
DIST_DIR="${CODE_DIR}/node_modules/openclaw/dist"
STATE_DIR="${DATA_DIR}/.openclaw"

# Hotfix target files
HOTFIX_PI_EMBEDDED="${DIST_DIR}/pi-embedded-CbCYZxIb.js"
HOTFIX_JSON_FILE="${DIST_DIR}/json-file-Dl3Z1jL1.js"

# --- Preflight ---
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo)." >&2
    exit 1
fi

# --- Counters ---
PASS=0
FAIL=0
WARN=0

pass() {
    echo "  [PASS] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  [FAIL] $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo "  [WARN] $1"
    WARN=$((WARN + 1))
}

skip() {
    echo "  [SKIP] $1"
}

echo "=============================================="
echo "  OpenClaw System Validation"
echo "  $(date --iso-8601=seconds)"
echo "=============================================="
echo ""

# =========================================
# Section 1: Service Status
# =========================================
echo "--- 1. Service Status ---"

# Gateway
if systemctl is-active --quiet openclaw-gateway.service 2>/dev/null; then
    pass "openclaw-gateway.service is active"
else
    if systemctl is-enabled --quiet openclaw-gateway.service 2>/dev/null; then
        fail "openclaw-gateway.service is enabled but not active"
    else
        fail "openclaw-gateway.service is not active (and not enabled)"
    fi
fi

# Broker
if systemctl is-active --quiet openclaw-broker.service 2>/dev/null; then
    pass "openclaw-broker.service is active"
else
    if systemctl list-unit-files openclaw-broker.service &>/dev/null; then
        fail "openclaw-broker.service is not active"
    else
        skip "openclaw-broker.service not installed"
    fi
fi

# GUI
if systemctl is-active --quiet openclaw-gui.service 2>/dev/null; then
    pass "openclaw-gui.service is active"
else
    if systemctl is-enabled --quiet openclaw-gui.service 2>/dev/null; then
        fail "openclaw-gui.service is enabled but not active"
    else
        skip "openclaw-gui.service not installed or not enabled"
    fi
fi

# Check for accidental user-level gateway (nick user)
if pgrep -u nick -f 'openclaw gateway' &>/dev/null; then
    fail "User-level gateway detected (nick). This should not exist. See host-sop.md prohibited operations."
else
    pass "No user-level gateway (nick) detected"
fi
echo ""

# =========================================
# Section 2: Hotfix Verification
# =========================================
echo "--- 2. Hotfix Verification ---"

# streamTo noop
if [[ -f "$HOTFIX_PI_EMBEDDED" ]]; then
    if grep -q '\[hotfix\] streamTo guard disabled' "$HOTFIX_PI_EMBEDDED" 2>/dev/null; then
        pass "streamTo noop hotfix applied"
    else
        fail "streamTo noop hotfix NOT applied (pi-embedded exists but marker missing)"
    fi
else
    fail "Hotfix target file not found: $HOTFIX_PI_EMBEDDED"
fi

# json-file chmod
if [[ -f "$HOTFIX_JSON_FILE" ]]; then
    if grep -q 'chmodSync(pathname, 416)' "$HOTFIX_JSON_FILE" 2>/dev/null; then
        pass "json-file chmod hotfix applied (0640)"
    else
        # Check if it has the original 0600 value
        if grep -q 'chmodSync(pathname, 384)' "$HOTFIX_JSON_FILE" 2>/dev/null; then
            fail "json-file chmod hotfix NOT applied (still 0600/384)"
        else
            warn "json-file chmod: unexpected chmod value in $HOTFIX_JSON_FILE"
        fi
    fi
else
    fail "Hotfix target file not found: $HOTFIX_JSON_FILE"
fi

# cleanup force keep
if [[ -f "$HOTFIX_PI_EMBEDDED" ]]; then
    if grep -q '\[hotfix\] force keep' "$HOTFIX_PI_EMBEDDED" 2>/dev/null; then
        pass "cleanup force keep hotfix applied"
    else
        fail "cleanup force keep hotfix NOT applied (pi-embedded exists but marker missing)"
    fi
else
    # Already reported above; don't double-count
    skip "cleanup force keep: pi-embedded file already reported missing"
fi
echo ""

# =========================================
# Section 3: runs.json Readability
# =========================================
echo "--- 3. runs.json Access ---"

RUNS_JSON="${STATE_DIR}/subagents/runs.json"
if [[ -f "$RUNS_JSON" ]]; then
    # Check file exists and is readable
    if [[ -r "$RUNS_JSON" ]]; then
        pass "runs.json exists and is readable (as root)"
    else
        fail "runs.json exists but is not readable"
    fi

    # Check permissions (should be 0640 with hotfix)
    RUNS_PERMS=$(stat -c '%a' "$RUNS_JSON" 2>/dev/null || echo "unknown")
    RUNS_OWNER=$(stat -c '%U:%G' "$RUNS_JSON" 2>/dev/null || echo "unknown")
    if [[ "$RUNS_PERMS" == "640" ]]; then
        pass "runs.json permissions: ${RUNS_PERMS} (owner: ${RUNS_OWNER})"
    elif [[ "$RUNS_PERMS" == "600" ]]; then
        warn "runs.json permissions: ${RUNS_PERMS} — group read missing (chmod hotfix may not be active)"
    else
        warn "runs.json permissions: ${RUNS_PERMS} (expected 640)"
    fi

    # Check if nick user can read via group
    if id -nG nick 2>/dev/null | grep -qw openclaw; then
        pass "nick is in openclaw group (GUI read access)"
    else
        warn "nick is NOT in openclaw group — GUI may not be able to read runs.json"
    fi
else
    warn "runs.json does not exist yet (may be created on first run)"
fi
echo ""

# =========================================
# Section 4: Directory Permissions
# =========================================
echo "--- 4. Directory Permissions ---"

check_dir_perms() {
    local dir="$1"
    local expected_owner="$2"
    local expected_mode="$3"
    local label="$4"

    if [[ ! -d "$dir" ]]; then
        fail "${label}: directory does not exist (${dir})"
        return
    fi

    local actual_owner actual_mode
    actual_owner=$(stat -c '%U:%G' "$dir" 2>/dev/null || echo "unknown")
    actual_mode=$(stat -c '%a' "$dir" 2>/dev/null || echo "unknown")

    if [[ "$actual_owner" == "$expected_owner" && "$actual_mode" == "$expected_mode" ]]; then
        pass "${label}: ${actual_mode} ${actual_owner}"
    else
        if [[ "$actual_owner" != "$expected_owner" ]]; then
            fail "${label}: owner is ${actual_owner} (expected ${expected_owner})"
        fi
        if [[ "$actual_mode" != "$expected_mode" ]]; then
            fail "${label}: mode is ${actual_mode} (expected ${expected_mode})"
        fi
    fi
}

check_dir_perms "$CODE_DIR"   "root:root"       "755" "/opt/openclaw"
check_dir_perms "$CONFIG_DIR" "root:openclaw"    "750" "/etc/openclaw"
check_dir_perms "$DATA_DIR"   "openclaw:openclaw" "700" "/var/lib/openclaw"
check_dir_perms "$LOG_DIR"    "openclaw:openclaw" "755" "/var/log/openclaw"

# State directory — needs 750 for GUI group-read access
if [[ -d "$STATE_DIR" ]]; then
    STATE_MODE=$(stat -c '%a' "$STATE_DIR" 2>/dev/null || echo "unknown")
    if [[ "$STATE_MODE" == "750" ]]; then
        pass "${STATE_DIR}: mode ${STATE_MODE} (group-readable for GUI)"
    elif [[ "$STATE_MODE" == "700" ]]; then
        warn "${STATE_DIR}: mode ${STATE_MODE} — GUI cannot read. Run: sudo chmod 0750 ${STATE_DIR}"
    else
        warn "${STATE_DIR}: mode ${STATE_MODE} (expected 750)"
    fi
fi

# Check config files
if [[ -f "${CONFIG_DIR}/openclaw.json" ]]; then
    JSON_PERMS=$(stat -c '%a' "${CONFIG_DIR}/openclaw.json" 2>/dev/null)
    JSON_OWNER=$(stat -c '%U:%G' "${CONFIG_DIR}/openclaw.json" 2>/dev/null)
    if [[ "$JSON_PERMS" == "640" && "$JSON_OWNER" == "root:openclaw" ]]; then
        pass "openclaw.json: ${JSON_PERMS} ${JSON_OWNER}"
    else
        fail "openclaw.json: ${JSON_PERMS} ${JSON_OWNER} (expected 640 root:openclaw)"
    fi
else
    fail "openclaw.json does not exist at ${CONFIG_DIR}/openclaw.json"
fi

if [[ -f "${CONFIG_DIR}/openclaw.env" ]]; then
    ENV_PERMS=$(stat -c '%a' "${CONFIG_DIR}/openclaw.env" 2>/dev/null)
    ENV_OWNER=$(stat -c '%U:%G' "${CONFIG_DIR}/openclaw.env" 2>/dev/null)
    if [[ "$ENV_PERMS" == "640" && "$ENV_OWNER" == "root:openclaw" ]]; then
        pass "openclaw.env: ${ENV_PERMS} ${ENV_OWNER}"
    else
        fail "openclaw.env: ${ENV_PERMS} ${ENV_OWNER} (expected 640 root:openclaw)"
    fi
else
    fail "openclaw.env does not exist at ${CONFIG_DIR}/openclaw.env"
fi
echo ""

# =========================================
# Section 5: Docker Status
# =========================================
echo "--- 5. Docker Status ---"

if command -v docker &>/dev/null; then
    # Docker daemon
    if systemctl is-active --quiet docker.service 2>/dev/null; then
        pass "docker.service is active"
    else
        warn "docker.service is not active"
    fi

    # openclaw-task-net network
    if docker network inspect openclaw-task-net &>/dev/null; then
        pass "Docker network 'openclaw-task-net' exists"
    else
        warn "Docker network 'openclaw-task-net' not found"
    fi

    # Task runner image
    if docker image inspect openclaw-task-claude:2026-03-v3-full &>/dev/null; then
        pass "Docker image 'openclaw-task-claude:2026-03-v3-full' exists"
    else
        warn "Docker image 'openclaw-task-claude:2026-03-v3-full' not found"
    fi

    # Running containers
    CONTAINER_COUNT=$(docker ps -q --filter "network=openclaw-task-net" 2>/dev/null | wc -l)
    if [[ "$CONTAINER_COUNT" -gt 0 ]]; then
        pass "Active task containers: ${CONTAINER_COUNT}"
    else
        skip "No active task containers (normal if no tasks running)"
    fi

    # openclaw user in docker group
    if id -nG openclaw 2>/dev/null | grep -qw docker; then
        pass "openclaw user is in docker group"
    else
        fail "openclaw user is NOT in docker group"
    fi
else
    warn "Docker not installed or not in PATH"
fi
echo ""

# =========================================
# Section 6: Cron Jobs
# =========================================
echo "--- 6. Cron Jobs ---"

# Check OpenClaw cron state directory
CRON_DIR="${STATE_DIR}/cron"
if [[ -d "$CRON_DIR" ]]; then
    CRON_COUNT=$(find "$CRON_DIR" -name '*.json' -type f 2>/dev/null | wc -l)
    pass "Cron directory exists: ${CRON_DIR} (${CRON_COUNT} job files)"
else
    skip "Cron directory not found (${CRON_DIR}) — may not be initialized yet"
fi

# Check Vault backup timer
if systemctl is-active --quiet vault-backup-root-btrfs.timer 2>/dev/null; then
    pass "vault-backup-root-btrfs.timer is active"
    NEXT_RUN=$(systemctl show vault-backup-root-btrfs.timer --property=NextElapseUSecRealtime --value 2>/dev/null || echo "unknown")
    echo "        Next run: ${NEXT_RUN}"
else
    if systemctl is-enabled --quiet vault-backup-root-btrfs.timer 2>/dev/null; then
        warn "vault-backup-root-btrfs.timer is enabled but not active"
    else
        warn "vault-backup-root-btrfs.timer not found or not enabled"
    fi
fi

# Check logrotate
if [[ -f /etc/logrotate.d/openclaw ]]; then
    pass "Logrotate config exists: /etc/logrotate.d/openclaw"
else
    warn "Logrotate config not found at /etc/logrotate.d/openclaw"
fi
echo ""

# =========================================
# Section 7: Snapshot Directory Health
# =========================================
echo "--- 7. Snapshot Directory ---"

if [[ -d "$SNAPSHOT_DIR" ]]; then
    # Check if it is a btrfs subvolume
    if btrfs subvolume show "$SNAPSHOT_DIR" &>/dev/null; then
        pass "/.snapshots is a btrfs subvolume"
    else
        warn "/.snapshots exists but is not a btrfs subvolume"
    fi

    SNAP_COUNT=$(ls -1d "${SNAPSHOT_DIR}"/root-* 2>/dev/null | wc -l)
    pass "Root snapshots available: ${SNAP_COUNT}"

    DATA_SNAP_COUNT=$(ls -1d "${SNAPSHOT_DIR}"/openclaw-data-* 2>/dev/null | wc -l)
    if [[ "$DATA_SNAP_COUNT" -gt 0 ]]; then
        pass "Data snapshots available: ${DATA_SNAP_COUNT}"
    else
        skip "No openclaw-data-* snapshots (created by backup-openclaw.sh)"
    fi

    # Most recent snapshot
    LATEST_SNAP=$(ls -1d "${SNAPSHOT_DIR}"/root-* 2>/dev/null | sort | tail -1 || echo "none")
    echo "        Latest root snapshot: $(basename "$LATEST_SNAP")"
else
    fail "Snapshot directory ${SNAPSHOT_DIR} does not exist"
fi

# Check Vault is offline (security)
if findmnt /mnt/vault &>/dev/null; then
    warn "Vault is currently MOUNTED at /mnt/vault (should be offline by default)"
else
    pass "Vault is offline (unmounted) — expected state"
fi
echo ""

# =========================================
# Section 8: Extensions and Workspace
# =========================================
echo "--- 8. Extensions & Workspace ---"

EXTENSIONS_DIR="${STATE_DIR}/extensions"
if [[ -d "$EXTENSIONS_DIR" ]]; then
    EXT_COUNT=$(find "$EXTENSIONS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    pass "Extensions directory exists (${EXT_COUNT} plugins)"

    # Check each extension has a manifest
    EXT_ERRORS=0
    while IFS= read -r ext_dir; do
        ext_name=$(basename "$ext_dir")
        if [[ ! -f "${ext_dir}/openclaw.plugin.json" ]]; then
            fail "Extension '${ext_name}' missing openclaw.plugin.json (will crash gateway!)"
            EXT_ERRORS=$((EXT_ERRORS + 1))
        fi
    done < <(find "$EXTENSIONS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

    if [[ "$EXT_ERRORS" -eq 0 && "$EXT_COUNT" -gt 0 ]]; then
        pass "All extensions have openclaw.plugin.json manifests"
    fi

    # Check for .bak directories (prohibited)
    BAK_COUNT=$(find "$EXTENSIONS_DIR" -maxdepth 1 -name '*.bak*' -type d 2>/dev/null | wc -l)
    if [[ "$BAK_COUNT" -gt 0 ]]; then
        fail "Found ${BAK_COUNT} .bak directories in extensions/ (will cause duplicate plugin errors)"
    else
        pass "No .bak directories in extensions/"
    fi
else
    warn "Extensions directory not found (${EXTENSIONS_DIR})"
fi

WORKSPACE_MAIN="${STATE_DIR}/workspace-main"
if [[ -d "$WORKSPACE_MAIN" ]]; then
    pass "workspace-main directory exists"
else
    warn "workspace-main directory not found (may need publish)"
fi

BROKER_SOCK="/run/openclaw/broker.sock"
if [[ -S "$BROKER_SOCK" ]]; then
    SOCK_PERMS=$(stat -c '%a' "$BROKER_SOCK" 2>/dev/null || echo "unknown")
    SOCK_OWNER=$(stat -c '%U:%G' "$BROKER_SOCK" 2>/dev/null || echo "unknown")
    pass "Broker socket exists: ${SOCK_PERMS} ${SOCK_OWNER}"
else
    if systemctl is-active --quiet openclaw-broker.service 2>/dev/null; then
        fail "Broker is active but socket not found at ${BROKER_SOCK}"
    else
        skip "Broker socket not found (broker may not be running)"
    fi
fi
echo ""

# =========================================
# Section 9: Gateway Port Check
# =========================================
echo "--- 9. Network Ports ---"

# Gateway should listen on 127.0.0.1:17777
if ss -tlnp 2>/dev/null | grep -q ':17777'; then
    pass "Port 17777 is listening (gateway WebSocket)"
else
    if systemctl is-active --quiet openclaw-gateway.service 2>/dev/null; then
        warn "Gateway is active but port 17777 not detected (may still be starting)"
    else
        skip "Port 17777 not listening (gateway not running)"
    fi
fi

# Check for accidental user-level gateway on 18789
if ss -tlnp 2>/dev/null | grep -q ':18789'; then
    fail "Port 18789 is listening — possible user-level gateway (nick). This is prohibited."
else
    pass "Port 18789 not listening (no user-level gateway conflict)"
fi
echo ""

# =========================================
# Summary
# =========================================
echo "=============================================="
echo "  Validation Summary"
echo "=============================================="
echo ""
echo "  PASS: ${PASS}"
echo "  FAIL: ${FAIL}"
echo "  WARN: ${WARN}"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "  Result: ALL CHECKS PASSED"
    if [[ "$WARN" -gt 0 ]]; then
        echo "  (${WARN} warnings — review above for details)"
    fi
    echo ""
    exit 0
else
    echo "  Result: ${FAIL} CHECK(S) FAILED"
    echo "  Review failures above and take corrective action."
    echo ""
    exit 1
fi
