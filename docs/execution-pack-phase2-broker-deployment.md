# Phase 2 Broker Deployment Execution Pack

> Status: **Dev-repo deployment design** — repo-only artifact
> Created: 2026-03-11
> Purpose: Step-by-step command blocks for human-led Phase 2 broker deployment
> Authority: `docs/runbook-phase2-broker-deployment.md`, `docs/specs/phase2-broker-deployment-layout.md`
> This document is an execution pack. The broker is NOT yet deployed. Phase 2 has NOT started.
> **DO NOT execute these commands.** This pack is for future human-led deployment only.

---

## 0. How to use this document

Each step below contains:
- **What**: Description of the action
- **Command block**: Exact commands to run (in a fenced block)
- **Confirm**: What the human operator must verify before proceeding
- **Blocker**: What would stop progression at this step

The operator should execute commands one block at a time, verifying each step before proceeding.

---

## Step 0: Dev-repo preflight (run as nick, no sudo)

**What**: Verify all dev-repo prep artifacts are valid.

```bash
cd ~/projects/openclaw-dev

# Verify clean working tree
git status

# Run all validation scripts
bash scripts/validate-phase2-prep.sh
bash tests/test_contract_freeze.sh
bash tests/test_phase2_integration.sh
bash scripts/validate-broker-schemas.sh
bash tests/test_broker_schemas.sh

# Run preflight script
bash scripts/preflight-phase2-broker-deployment.sh
```

**Confirm**: All scripts exit 0. Working tree is clean. All tests pass.
**Blocker**: Any script failure. Fix in dev-repo first, commit, then retry.

---

## Step 1: Host preflight (requires sudo)

**What**: Verify host is ready for deployment.

```bash
# Gateway health
sudo systemctl status openclaw-gateway.service

# Disk space
df -h /opt/openclaw /var/lib/openclaw /var/log/openclaw

# Current snapshots
sudo btrfs subvolume list /.snapshots | tail -5

# Verify target directories do not already exist
ls -la /opt/openclaw/broker/ 2>/dev/null && echo "WARNING: broker dir already exists" || echo "OK: broker dir does not exist"
ls -la /etc/systemd/system/openclaw-broker.service 2>/dev/null && echo "WARNING: unit already exists" || echo "OK: unit does not exist"

# Verify required tools
command -v socat >/dev/null && echo "OK: socat available" || echo "WARNING: socat not installed (needed for broker socket testing)"
command -v jq >/dev/null && echo "OK: jq available" || echo "FAIL: jq not installed"
command -v python3 >/dev/null && echo "OK: python3 available" || echo "FAIL: python3 not installed (needed for socket listener)"
```

**Confirm**: Gateway is active. Sufficient disk space. No pre-existing broker installation.
**Blocker**: Gateway unhealthy, insufficient disk space, or broker already partially installed.

---

## Step 2: Pre-change snapshot (requires sudo)

**What**: Create rollback anchor.

```bash
# Create labeled pre-change snapshot
SNAP_LABEL="root-pre-phase2-broker-$(date +%Y%m%d)"
sudo btrfs subvolume snapshot -r / "/.snapshots/${SNAP_LABEL}"

# Verify snapshot was created
sudo btrfs subvolume list /.snapshots | grep "${SNAP_LABEL}"
echo "Pre-change snapshot: ${SNAP_LABEL}"
```

**Confirm**: Snapshot appears in listing. Record snapshot name in deployment record.
**Blocker**: Snapshot creation fails (disk full, btrfs error).

---

## Step 3: Create directory structure (requires sudo)

**What**: Create all directories per deployment-layout spec.

```bash
# Broker installation directories
sudo mkdir -p /opt/openclaw/broker/wrappers/lib
sudo chown -R root:root /opt/openclaw/broker
sudo chmod 755 /opt/openclaw/broker /opt/openclaw/broker/wrappers /opt/openclaw/broker/wrappers/lib

# Log directory
sudo mkdir -p /var/log/openclaw/broker
sudo chown root:openclaw /var/log/openclaw/broker
sudo chmod 750 /var/log/openclaw/broker

# State directory
sudo mkdir -p /var/lib/openclaw/broker
sudo chown root:openclaw /var/lib/openclaw/broker
sudo chmod 750 /var/lib/openclaw/broker

# Candidate staging directory (if not exists)
sudo mkdir -p /var/lib/openclaw/approvals/candidates
sudo chown openclaw:openclaw /var/lib/openclaw/approvals /var/lib/openclaw/approvals/candidates
sudo chmod 700 /var/lib/openclaw/approvals/candidates

# Verify
echo "=== Directory verification ==="
ls -la /opt/openclaw/broker/
ls -la /opt/openclaw/broker/wrappers/
ls -la /opt/openclaw/broker/wrappers/lib/
ls -la /var/log/openclaw/broker/
ls -la /var/lib/openclaw/broker/
ls -la /var/lib/openclaw/approvals/candidates/
```

**Confirm**: All directories exist with correct ownership and permissions per layout spec.
**Blocker**: Permission errors, parent directory missing.

---

## Step 4: Install shared validation library (requires sudo)

**What**: Install `common.sh` to production path.

```bash
# Copy common.sh from dev-repo
sudo cp ~/projects/openclaw-dev/broker/wrappers/lib/common.sh /opt/openclaw/broker/wrappers/lib/common.sh
sudo chown root:root /opt/openclaw/broker/wrappers/lib/common.sh
sudo chmod 755 /opt/openclaw/broker/wrappers/lib/common.sh

# Syntax check
sudo bash -n /opt/openclaw/broker/wrappers/lib/common.sh && echo "OK: syntax valid" || echo "FAIL: syntax error"
```

**Confirm**: File installed, ownership correct, syntax valid.
**Blocker**: Syntax error in common.sh.

---

## Step 5: Install wrapper scripts (requires sudo)

**What**: Install all 8 wrapper scripts. Dev-repo wrappers are dual-mode: they contain both dry-run (`[STUB]`) and live execution paths. The live code path is already implemented. At deployment, ensure `BROKER_DRY_RUN=false` is set in the production environment.

```bash
# List of wrappers to install
WRAPPERS=(
  ocw-gateway-health.sh
  ocw-gateway-restart.sh
  ocw-validate-openclaw-json.sh
  ocw-deploy-openclaw-json.sh
  ocw-snapshot-pre.sh
  ocw-snapshot-post.sh
  ocw-vault-sync.sh
  ocw-rollback-prepare.sh
)

# IMPORTANT: Dev-repo wrappers are dual-mode (dry-run + live).
# The live code path (BROKER_DRY_RUN=false) already contains real execution logic.
# [STUB] markers exist only in the dry-run code path and are expected.
# Production wrappers are installed directly from dev-repo; no rewriting needed.

for wrapper in "${WRAPPERS[@]}"; do
  # Copy production version from dev-repo (wrappers have dual-mode: dry-run + live)
  sudo cp "${HOME}/projects/openclaw-dev/broker/wrappers/${wrapper}" "/opt/openclaw/broker/wrappers/${wrapper}"
  sudo chown root:root "/opt/openclaw/broker/wrappers/${wrapper}"
  sudo chmod 755 "/opt/openclaw/broker/wrappers/${wrapper}"

  # Syntax check
  sudo bash -n "/opt/openclaw/broker/wrappers/${wrapper}" && echo "OK: ${wrapper}" || echo "FAIL: ${wrapper}"

  # Verify no STUB-only markers remain in live execution paths.
  # Note: Wrappers are dual-mode (dry-run + live). [STUB] markers in the dry-run
  # code path are expected and harmless. Verify the live code path has real execution logic.
  if grep -q '\[STUB\]' "/opt/openclaw/broker/wrappers/${wrapper}"; then
    echo "NOTE: ${wrapper} contains [STUB] markers (expected in dry-run path for dual-mode wrappers)"
  else
    echo "OK: ${wrapper} has no STUB markers"
  fi
done
```

**Confirm**: All 8 wrappers installed, syntax valid. [STUB] markers in dry-run paths are expected for dual-mode wrappers.
**Blocker**: Any wrapper has syntax errors. Verify live code path (BROKER_DRY_RUN=false branch) has real execution logic.

---

## Step 6: Install broker daemon (requires sudo)

**What**: Install the broker daemon script and socket listener.

```bash
# Install broker daemon from dev-repo
sudo cp ~/projects/openclaw-dev/broker/openclaw-broker /opt/openclaw/broker/openclaw-broker
sudo chown root:root /opt/openclaw/broker/openclaw-broker
sudo chmod 755 /opt/openclaw/broker/openclaw-broker

# Install socket listener
sudo mkdir -p /opt/openclaw/broker/lib
sudo cp ~/projects/openclaw-dev/broker/lib/socket-listener.py /opt/openclaw/broker/lib/socket-listener.py
sudo chown root:root /opt/openclaw/broker/lib/socket-listener.py
sudo chmod 755 /opt/openclaw/broker/lib/socket-listener.py

# Syntax check
sudo bash -n /opt/openclaw/broker/openclaw-broker && echo "OK: broker syntax valid" || echo "FAIL: broker syntax error"
sudo python3 -c "import py_compile; py_compile.compile('/opt/openclaw/broker/lib/socket-listener.py', doraise=True)" && echo "OK: listener syntax valid" || echo "FAIL: listener syntax error"

# Verify
ls -la /opt/openclaw/broker/openclaw-broker
ls -la /opt/openclaw/broker/lib/socket-listener.py
```

**Confirm**: Broker daemon and socket listener installed, ownership correct, syntax valid.
**Blocker**: Syntax errors in broker or listener.

---

## Step 7: Install systemd unit (requires sudo)

**What**: Install the broker service unit file.

```bash
# Install unit file
sudo tee /etc/systemd/system/openclaw-broker.service > /dev/null << 'UNIT_EOF'
[Unit]
Description=OpenClaw Host-Ops Broker
After=network.target openclaw-gateway.service
Requires=openclaw-gateway.service

[Service]
Type=simple
ExecStart=/opt/openclaw/broker/openclaw-broker --listen --log-file /var/log/openclaw/broker/broker.log
RuntimeDirectory=openclaw
RuntimeDirectoryMode=0755
User=root
Group=root
Environment=BROKER_DRY_RUN=false
ProtectHome=yes
PrivateTmp=yes
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-broker

[Install]
WantedBy=multi-user.target
UNIT_EOF

# Reload systemd
sudo systemctl daemon-reload

# Verify unit is loaded but NOT active
sudo systemctl status openclaw-broker.service
# Expected: loaded but inactive
```

**Confirm**: Unit file installed. `daemon-reload` succeeded. Service is loaded but inactive.
**Blocker**: Systemd errors.

**Note**: The unit file content above is a design draft. Review and adjust security hardening directives based on actual wrapper requirements before installing.

---

## Step 8: Start broker and verify (requires sudo)

**What**: Start the broker service and run basic validation.

```bash
# Start broker
sudo systemctl start openclaw-broker.service

# Verify running
sudo systemctl is-active openclaw-broker.service
# Expected: active

# Verify socket
ls -la /run/openclaw/broker.sock
# Expected: srw-rw---- root openclaw

# Verify broker log
sudo tail -5 /var/log/openclaw/broker/broker.log 2>/dev/null || echo "NOTE: check journal — sudo journalctl -u openclaw-broker.service -n 20"
```

**Confirm**: Broker is active. Socket exists with correct permissions.
**Blocker**: Broker fails to start. Check `journalctl -u openclaw-broker.service`.

---

## Step 9: Test broker basic operations (requires sudo)

**What**: Test the simplest broker action (gateway_health).

```bash
# Create test request
TMPFILE=$(mktemp)
cat > "$TMPFILE" << 'EOF'
{
  "action": "gateway_health",
  "request_id": "req-deploy-test-001",
  "task_id": "task-deploy-test",
  "requested_by": "cli:nick",
  "inputs": {}
}
EOF

# Method A: Send via Unix socket (production path)
echo "Sending test request via socket..."
RESPONSE=$(socat - UNIX-CONNECT:/run/openclaw/broker.sock < "$TMPFILE")
echo "Response: $RESPONSE"
echo "$RESPONSE" | jq .

# Method B (alternative): CLI dispatch mode for debugging
# sudo /opt/openclaw/broker/openclaw-broker --dispatch "$TMPFILE"

rm -f "$TMPFILE"
echo "Verify response contains: ok=true, status=ok"
```

**Confirm**: Broker returns `{"ok": true, "status": "ok", ...}` for gateway_health.
**Blocker**: Broker returns error or does not respond. Investigate logs. Consider rollback.

---

## Step 10: Test broker negative cases (requires sudo)

**What**: Verify broker correctly rejects invalid inputs.

```bash
# Test 1: Invalid action
TMPFILE=$(mktemp)
cat > "$TMPFILE" << 'EOF'
{
  "action": "delete_everything",
  "request_id": "req-neg-test-001",
  "task_id": "task-neg-test",
  "requested_by": "cli:nick",
  "inputs": {}
}
EOF
echo "Test 1: Invalid action — expect ok=false, status=error"
RESPONSE=$(socat - UNIX-CONNECT:/run/openclaw/broker.sock < "$TMPFILE")
echo "Response: $RESPONSE"
echo "$RESPONSE" | jq .
rm -f "$TMPFILE"

# Test 2: Path traversal
TMPFILE=$(mktemp)
cat > "$TMPFILE" << 'EOF'
{
  "action": "deploy_openclaw_json_candidate",
  "request_id": "req-neg-test-002",
  "task_id": "task-neg-test",
  "requested_by": "cli:nick",
  "inputs": {
    "candidate_path": "/var/lib/openclaw/approvals/candidates/../../etc/shadow",
    "expected_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
EOF
echo "Test 2: Path traversal — expect ok=false, status=denied"
RESPONSE=$(socat - UNIX-CONNECT:/run/openclaw/broker.sock < "$TMPFILE")
echo "Response: $RESPONSE"
echo "$RESPONSE" | jq .
rm -f "$TMPFILE"
```

**Confirm**: Invalid action returns `status: error`. Path traversal returns `status: denied`.
**Blocker**: Broker accepts invalid inputs. **Immediate rollback required.**

---

## Step 11: Install plugin (requires sudo for config change)

**What**: Install host-ops-tool plugin and register in openclaw.json.

```bash
# Create plugin directory
sudo -u openclaw mkdir -p /var/lib/openclaw/.openclaw/extensions/host-ops-tool

# Install plugin files
sudo -u openclaw cp ~/projects/openclaw-dev/plugins/host-ops-tool/index.js \
  /var/lib/openclaw/.openclaw/extensions/host-ops-tool/index.js

# Create plugin manifest (content TBD — depends on OpenClaw plugin format)
# sudo -u openclaw tee /var/lib/openclaw/.openclaw/extensions/host-ops-tool/openclaw.plugin.json ...

echo "Plugin files installed. Now prepare openclaw.json candidate with plugin registration."
echo "This requires the snapshot -> validate -> deploy -> restart workflow via broker."
```

**Confirm**: Plugin files installed. Manifest created.
**Blocker**: Plugin directory creation fails.

**Note**: The config change (adding plugin to `openclaw.json`) should ideally go through the broker's own `validate_openclaw_json_candidate` + `deploy_openclaw_json_candidate` actions, demonstrating the broker works end-to-end.

---

## Step 12: Enable broker on boot (requires sudo)

**What**: Make broker persistent across reboots.

```bash
sudo systemctl enable openclaw-broker.service
sudo systemctl is-enabled openclaw-broker.service
# Expected: enabled
```

**Confirm**: Service is enabled.
**Blocker**: None expected.

---

## Step 13: Post-change snapshot (requires sudo)

**What**: Create post-deployment snapshot.

```bash
SNAP_LABEL="root-post-phase2-broker-$(date +%Y%m%d)"
sudo btrfs subvolume snapshot -r / "/.snapshots/${SNAP_LABEL}"
sudo btrfs subvolume list /.snapshots | grep "${SNAP_LABEL}"
echo "Post-change snapshot: ${SNAP_LABEL}"
```

**Confirm**: Post-change snapshot created. Record in deployment record.
**Blocker**: Snapshot creation fails.

---

## Step 14: Vault sync (requires sudo)

**What**: Sync snapshots to offline vault.

```bash
# Mount vault
sudo mount /mnt/vault

# Verify vault is mounted
mountpoint /mnt/vault

# PREFERRED: Use the unified backup script (handles auto snapshot, incremental
# detection, last_sent update, mount/unmount automatically):
# sudo /usr/local/sbin/vault-backup-root-btrfs

# MANUAL ALTERNATIVE (only if script is unavailable):
# Note: Vault receive path is /mnt/vault/recv/system (NOT /mnt/vault/snapshots/)
# sudo btrfs send /.snapshots/root-pre-phase2-broker-YYYYMMDD | sudo btrfs receive /mnt/vault/recv/system
# (or incremental send if parent exists)
# sudo btrfs send -p /.snapshots/root-pre-phase2-broker-YYYYMMDD /.snapshots/root-post-phase2-broker-YYYYMMDD | sudo btrfs receive /mnt/vault/recv/system

# Unmount vault
sudo umount /mnt/vault
```

**Confirm**: Both snapshots synced to vault. Vault unmounted.
**Blocker**: Vault mount fails, send/receive fails.

---

## Step 15: Final verification

**What**: Comprehensive post-deployment health check.

```bash
echo "=== Final Verification ==="

echo "--- Broker service ---"
sudo systemctl is-active openclaw-broker.service
sudo systemctl is-enabled openclaw-broker.service

echo "--- Gateway service ---"
sudo systemctl is-active openclaw-gateway.service

echo "--- Socket ---"
ls -la /run/openclaw/broker.sock

echo "--- Installed files ---"
ls -la /opt/openclaw/broker/
ls -la /opt/openclaw/broker/wrappers/
ls -la /opt/openclaw/broker/wrappers/lib/

echo "--- Logs ---"
sudo tail -3 /var/log/openclaw/broker/broker.log 2>/dev/null || echo "Check: sudo journalctl -u openclaw-broker.service -n 10"

echo "--- Snapshots ---"
sudo btrfs subvolume list /.snapshots | grep phase2-broker
```

**Confirm**: Everything healthy. Record final state in deployment record.
**Blocker**: Any check fails. Investigate or consider rollback.

---

## Rollback procedure

If rollback is needed at any point:

```bash
# 1. Stop and disable broker
sudo systemctl stop openclaw-broker.service 2>/dev/null || true
sudo systemctl disable openclaw-broker.service 2>/dev/null || true

# 2. If config was changed, restore backup
# sudo cp /etc/openclaw/openclaw.json.bak /etc/openclaw/openclaw.json
# sudo systemctl restart openclaw-gateway.service

# 3. Remove installed files (if partial rollback)
sudo rm -rf /opt/openclaw/broker
sudo rm -f /etc/systemd/system/openclaw-broker.service
sudo systemctl daemon-reload

# 4. Verify gateway health
sudo systemctl is-active openclaw-gateway.service

# 5. If full rollback needed, use pre-change snapshot
# (btrfs snapshot rollback procedure — see host-sop.md)

# 6. Record rollback in deployment record
```

---

## References

- `docs/runbook-phase2-broker-deployment.md` — Runbook with decision framework
- `docs/specs/phase2-broker-deployment-layout.md` — Target filesystem layout
- `docs/templates/phase2-broker-deployment-record-template.md` — Deployment record
- `docs/host-sop.md` — Host operational constraints
