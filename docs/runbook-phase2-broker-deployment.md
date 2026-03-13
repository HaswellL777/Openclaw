# Phase 2 Broker Deployment Runbook

> Status: **Dev-repo deployment design** — repo-only artifact
> Created: 2026-03-11
> Purpose: Structured runbook for human-led Phase 2 broker deployment
> Authority: `docs/design-v3.md` SS5.6, `docs/host-sop.md`, `docs/specs/phase2-broker-deployment-layout.md`
> This document is a deployment design artifact. The broker is NOT yet deployed. Phase 2 has NOT started.

---

## 0. Document purpose

This runbook defines the complete deployment procedure for the host-ops broker. It is designed for human-led execution with explicit confirmation points. No step in this runbook should be executed automatically or without human review.

---

## 1. Entry conditions (all must be true)

| # | Condition | How to verify |
|---|-----------|---------------|
| 1 | Phase 1 (1A + 1B) is complete | `docs/host-sop.md` confirms Phase 1 complete |
| 2 | Phase 2 repo-only prep gate is satisfied | Run `scripts/validate-phase2-prep.sh` — must pass |
| 3 | All contract freeze tests pass | Run `tests/test_contract_freeze.sh` — must pass |
| 4 | All integration tests pass | Run `tests/test_phase2_integration.sh` — must pass |
| 5 | All schema validation passes | Run `scripts/validate-broker-schemas.sh` — must pass |
| 6 | Preflight script passes | Run `scripts/preflight-phase2-broker-deployment.sh` — must pass |
| 7 | Deployment layout spec is reviewed and agreed | `docs/specs/phase2-broker-deployment-layout.md` reviewed by operator |
| 8 | Gateway is healthy | `sudo systemctl is-active openclaw-gateway.service` returns `active` |
| 9 | Recent root snapshot exists | `sudo btrfs subvolume list /.snapshots` shows recent entry |
| 10 | Vault is accessible (for post-deployment sync) | `/mnt/vault` can be mounted when needed |

---

## 2. Prohibition conditions (any one blocks deployment)

| # | Condition | Why it blocks |
|---|-----------|---------------|
| 1 | Gateway is unhealthy or in degraded state | Must not compound failures |
| 2 | Unresolved config drift between `/etc/openclaw/openclaw.json` and design | Must resolve drift first |
| 3 | No recent root snapshot (>24h since last) | Must have rollback anchor |
| 4 | Vault offline and cannot be mounted | Cannot complete snapshot discipline |
| 5 | Ongoing unrelated host change in progress | Must not overlap changes |
| 6 | Any prep gate criterion not met | Prep is prerequisite |
| 7 | Dev-repo has uncommitted changes | Must deploy from clean, committed state |

---

## 3. Go / No-Go checklist

Before proceeding, the operator must complete this checklist:

- [ ] All entry conditions verified (Section 1)
- [ ] No prohibition conditions apply (Section 2)
- [ ] Deployment layout spec reviewed (`docs/specs/phase2-broker-deployment-layout.md`)
- [ ] Execution pack reviewed (`docs/execution-pack-phase2-broker-deployment.md`)
- [ ] Deployment record template prepared (`docs/templates/phase2-broker-deployment-record-template.md`)
- [ ] Estimated maintenance window allocated (suggest 60-90 minutes)
- [ ] Rollback procedure understood (Section 8)
- [ ] Operator has sudo/root access on target host

**Decision**: GO / NO-GO (human decision, not automated)

---

## 4. Preflight phase

### 4.1 Dev-repo preflight (non-root, non-live)

1. Run all validation scripts from dev repo
2. Verify dev repo is on correct branch with clean working tree
3. Verify deployment layout spec matches current host-sop path boundaries

### 4.2 Host preflight (requires sudo)

1. Verify gateway health: `sudo systemctl status openclaw-gateway.service`
2. Verify disk space: sufficient space in `/opt/openclaw`, `/var/log/openclaw`, `/var/lib/openclaw`
3. Verify current root snapshot: `sudo btrfs subvolume list /.snapshots | tail -5`
4. Verify `/opt/openclaw/broker/` does NOT already exist (clean install)
5. Verify `/etc/systemd/system/openclaw-broker.service` does NOT already exist
6. Verify `/run/openclaw/` directory status

---

## 5. Deployment sequence

The deployment is divided into ordered stages. Each stage has a human confirmation gate.

### Stage 1: Pre-change snapshot

**Purpose**: Create rollback anchor before any changes.

1. Create labeled pre-change root snapshot
2. Record snapshot name in deployment record
3. **Human confirmation**: snapshot exists and is named correctly

### Stage 2: Install broker directory structure

**Purpose**: Create directory layout per deployment-layout spec.

1. Create `/opt/openclaw/broker/` (root:root 755)
2. Create `/opt/openclaw/broker/wrappers/` (root:root 755)
3. Create `/opt/openclaw/broker/wrappers/lib/` (root:root 755)
4. Create `/var/log/openclaw/broker/` (root:openclaw 750)
5. Create `/var/lib/openclaw/broker/` (root:openclaw 750)
6. Create `/var/lib/openclaw/approvals/candidates/` (openclaw:openclaw 700) if not exists
7. **Human confirmation**: all directories created with correct ownership/permissions

### Stage 3: Install wrapper scripts (production versions)

**Purpose**: Install root-owned wrapper scripts.

1. Copy wrapper scripts from dev repo to `/opt/openclaw/broker/wrappers/`
2. Copy `lib/common.sh` to `/opt/openclaw/broker/wrappers/lib/`
3. **Note**: Dev-repo wrappers are dual-mode (dry-run + live). They contain real execution logic in their `BROKER_DRY_RUN=false` code path. The `[STUB]` markers in the dry-run code path are expected and harmless.
4. Set `BROKER_DRY_RUN=false` in the production environment (systemd unit or broker config)
5. Set ownership: `root:root`
6. Set mode: `0755`
7. Verify each wrapper passes `bash -n` syntax check
8. **Human confirmation**: all 8 wrappers + common.sh installed, live code path has real execution logic

### Stage 4: Install broker daemon

**Purpose**: Install the broker daemon script/binary.

1. Install broker daemon to `/opt/openclaw/broker/openclaw-broker`
2. Set ownership: `root:root`
3. Set mode: `0755`
4. Verify `bash -n` syntax check (if bash)
5. **Human confirmation**: broker binary/script installed and syntax-valid

### Stage 5: Install systemd unit

**Purpose**: Create the broker systemd service.

1. Install `/etc/systemd/system/openclaw-broker.service`
2. Run `systemctl daemon-reload`
3. Do NOT enable or start yet
4. **Human confirmation**: unit file installed, daemon-reload complete, service not yet active

### Stage 6: Start and verify broker service

**Purpose**: Start broker and verify basic health.

1. Start broker: `sudo systemctl start openclaw-broker.service`
2. Verify broker is running: `sudo systemctl is-active openclaw-broker.service`
3. Verify socket exists: `ls -la /run/openclaw/broker.sock`
4. Verify socket permissions: `root:openclaw 660`
5. Test gateway_health via broker (simplest action, read-only)
6. **Human confirmation**: broker running, socket accessible, health check returns `ok`

### Stage 7: Install plugin and register

**Purpose**: Install host-ops-tool plugin and register in openclaw.json.

1. Create plugin directory: `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/`
2. Install plugin files (index.js, manifest)
3. Prepare candidate `openclaw.json` with plugin registration
4. Stage candidate to `/var/lib/openclaw/approvals/candidates/`
5. Validate candidate via broker: `validate_openclaw_json_candidate`
6. Deploy candidate via broker: `deploy_openclaw_json_candidate`
7. Restart gateway via broker: `gateway_restart`
8. Verify gateway health via broker: `gateway_health`
9. **Human confirmation**: plugin installed, config deployed, gateway healthy

### Stage 8: Validation suite

**Purpose**: Comprehensive post-deployment validation.

1. Verify broker service status
2. Test all 8 actions via broker (at least gateway_health, gateway_restart validation)
3. Test negative cases: invalid action, bad path, path traversal — all must be rejected
4. Verify broker logs are being written to `/var/log/openclaw/broker/`
5. Verify main agent can access host_ops tool (if applicable at this stage)
6. **Human confirmation**: all validation checks pass

### Stage 9: Enable broker on boot

**Purpose**: Make broker persistent across reboots.

1. Enable broker: `sudo systemctl enable openclaw-broker.service`
2. **Human confirmation**: broker enabled

### Stage 10: Post-change snapshot and vault sync

**Purpose**: Create post-change anchor and sync to vault.

1. Create labeled post-change root snapshot
2. Record snapshot name in deployment record
3. Mount vault: `sudo mount /mnt/vault`
4. Sync snapshot to vault
5. Unmount vault: `sudo umount /mnt/vault`
6. **Human confirmation**: post-change snapshot created and synced to vault

---

## 6. Verification sequence

After Stage 10, verify end-to-end:

| # | Check | Expected result |
|---|-------|----------------|
| 1 | `sudo systemctl is-active openclaw-broker.service` | `active` |
| 2 | `sudo systemctl is-active openclaw-gateway.service` | `active` |
| 3 | `ls -la /run/openclaw/broker.sock` | `srw-rw---- root openclaw` |
| 4 | Broker responds to `gateway_health` | `ok: true, status: ok` |
| 5 | Broker rejects invalid action | `ok: false, status: error` |
| 6 | Broker rejects path traversal | `ok: false, status: denied` |
| 7 | Broker logs contain recent entries | Timestamped log lines in `/var/log/openclaw/broker/broker.log` |
| 8 | Plugin registered in openclaw.json | `jq '.plugins' /etc/openclaw/openclaw.json` shows host-ops-tool |

---

## 7. Rollback trigger conditions

Rollback to pre-change snapshot if ANY of the following occur:

| # | Trigger | Action |
|---|---------|--------|
| 1 | Broker service fails to start | Rollback |
| 2 | Gateway becomes unhealthy after plugin registration | Rollback |
| 3 | Socket not created or wrong permissions | Investigate; rollback if unfixable |
| 4 | Wrapper script execution error on valid input | Rollback |
| 5 | Any security boundary violation detected | Immediate rollback |
| 6 | Operator judges deployment unsafe at any confirmation gate | Rollback |

---

## 8. Rollback procedure

### 8.1 Ordered rollback steps

1. Stop broker: `sudo systemctl stop openclaw-broker.service`
2. Disable broker: `sudo systemctl disable openclaw-broker.service`
3. If gateway was affected, restore pre-change openclaw.json from backup
4. Restart gateway if config was changed: `sudo systemctl restart openclaw-gateway.service`
5. Verify gateway health
6. If filesystem changes need full reversal: use pre-change btrfs snapshot
7. Record rollback in deployment record

### 8.2 Fail-closed principle

- If rollback itself fails, **do not attempt further automated recovery**
- Document the failure state
- Escalate to manual investigation
- The pre-change snapshot is the safety net; btrfs snapshot rollback is the last resort

---

## 9. Steps requiring human sudo/TTY

| Step | Requires sudo | Requires TTY | Why |
|------|--------------|-------------|-----|
| Pre-change snapshot | Yes | Yes | `btrfs subvolume snapshot` requires root |
| Directory creation under /opt | Yes | Yes | Root-owned paths |
| Wrapper installation | Yes | Yes | Root-owned files |
| Systemd unit installation | Yes | Yes | System service management |
| Broker start/enable | Yes | Yes | Service management |
| Plugin config deployment | Yes (via broker) | No (broker runs as root) | Broker handles elevation |
| Post-change snapshot | Yes | Yes | `btrfs subvolume snapshot` requires root |
| Vault mount/sync | Yes | Yes | Mount operations require root |

---

## 10. Snapshot discipline checkpoints

| When | Snapshot type | Label convention | Required |
|------|-------------|-----------------|----------|
| Before any change | Pre-change | `root-pre-phase2-broker-YYYYMMDD` | **Mandatory** |
| After broker installed + validated | Post-change | `root-post-phase2-broker-YYYYMMDD` | **Mandatory** |
| After rollback (if triggered) | Post-rollback | `root-post-rollback-phase2-broker-YYYYMMDD` | If applicable |

**Vault sync**: Required after each snapshot creation. Vault must be mounted, synced, and unmounted for each sync operation.

---

## 11. References

- `docs/specs/phase2-broker-deployment-layout.md` — Filesystem layout
- `docs/execution-pack-phase2-broker-deployment.md` — Step-by-step commands
- `docs/templates/phase2-broker-deployment-record-template.md` — Deployment record
- `docs/templates/phase2-broker-deployment-syncback-template.md` — Post-deployment doc updates
- `docs/design-v3.md` SS5.6 — Authoritative broker design
- `docs/host-sop.md` — Host path boundaries and operational constraints
- `docs/specs/host-ops-broker-protocol-v1.md` — Protocol specification
