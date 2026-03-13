# Phase 2 Broker Deployment Record

> This document is a field record template. The operator fills in each section during deployment execution.
> Corresponding execution pack: `docs/execution-pack-phase2-broker-deployment.md`
> Corresponding runbook: `docs/runbook-phase2-broker-deployment.md`
> **This template is a dev-repo artifact. The broker is NOT yet deployed. Phase 2 has NOT started.**

---

## Basic Information

| Item | Value |
|------|-------|
| Operator | _(nick / other)_ |
| Execution date (local) | _YYYY-MM-DD_ |
| Execution time (UTC) | _YYYY-MM-DD HH:MM:SS UTC_ |
| Dev-repo branch | _(e.g. main)_ |
| Git commit (full SHA) | _(git rev-parse HEAD output)_ |
| Git commit summary | _(git log --oneline -1 output)_ |

---

## Preflight Results

### Dev-repo preflight

| Item | Value |
|------|-------|
| `validate-phase2-prep.sh` | _PASS / FAIL_ |
| `test_contract_freeze.sh` | _PASS / FAIL_ |
| `test_phase2_integration.sh` | _PASS / FAIL_ |
| `test_broker_schemas.sh` | _PASS / FAIL_ |
| `preflight-phase2-broker-deployment.sh` | _GO / NO-GO_ |
| PASS count | ___ |
| WARN count | ___ |
| FAIL count | ___ |
| Preflight output file | _/tmp/preflight-phase2-YYYYMMDD-HHMMSS.txt_ |
| Notes (if any WARN) | _(leave blank or record)_ |

### Host preflight

| Check | Result |
|-------|--------|
| Gateway health | _active / inactive / failed_ |
| Disk space sufficient | _OK / insufficient_ |
| `/opt/openclaw/broker/` does NOT exist | _confirmed / already exists_ |
| `openclaw-broker.service` does NOT exist | _confirmed / already exists_ |
| Recent root snapshot exists | _yes (name: ___) / no_ |
| Vault accessible | _yes / no_ |

### Go / No-Go decision

| Item | Value |
|------|-------|
| All entry conditions met (runbook §1) | _yes / no_ |
| No prohibition conditions apply (runbook §2) | _yes / no_ |
| **Decision** | _GO / NO-GO_ |

---

## Pre-change Snapshot

| Item | Value |
|------|-------|
| Snapshot label | _root-pre-phase2-broker-YYYYMMDD_ |
| Snapshot creation time | _YYYY-MM-DD HH:MM_ |
| Verified in listing | _yes / no_ |

---

## Directory Structure Installation

| Directory | Created | Owner:Group | Mode | Verified |
|-----------|---------|-------------|------|----------|
| `/opt/openclaw/broker/` | _yes / already existed_ | _root:root_ | _755_ | _yes / no_ |
| `/opt/openclaw/broker/wrappers/` | _yes / already existed_ | _root:root_ | _755_ | _yes / no_ |
| `/opt/openclaw/broker/wrappers/lib/` | _yes / already existed_ | _root:root_ | _755_ | _yes / no_ |
| `/var/log/openclaw/broker/` | _yes / already existed_ | _root:openclaw_ | _750_ | _yes / no_ |
| `/var/lib/openclaw/broker/` | _yes / already existed_ | _root:openclaw_ | _750_ | _yes / no_ |
| `/var/lib/openclaw/approvals/candidates/` | _yes / already existed_ | _openclaw:openclaw_ | _700_ | _yes / no_ |

---

## Shared Library Installation

| Item | Value |
|------|-------|
| `lib/common.sh` installed | _yes / no_ |
| Owner:group | _root:root_ |
| Mode | _755_ |
| `bash -n` syntax check | _OK / FAIL_ |

---

## Wrapper Installation

| Wrapper | Installed | bash -n | Live path verified | Notes |
|---------|-----------|---------|---------------------|-------|
| `ocw-gateway-health.sh` | _yes / no_ | _OK / FAIL_ | _OK / FAIL_ | _dual-mode; [STUB] in dry-run path expected_ |
| `ocw-gateway-restart.sh` | _yes / no_ | _OK / FAIL_ | _OK / FAIL_ | _dual-mode; [STUB] in dry-run path expected_ |
| `ocw-validate-openclaw-json.sh` | _yes / no_ | _OK / FAIL_ | _OK / FAIL_ | _dual-mode; [STUB] in dry-run path expected_ |
| `ocw-deploy-openclaw-json.sh` | _yes / no_ | _OK / FAIL_ | _OK / FAIL_ | _dual-mode; [STUB] in dry-run path expected_ |
| `ocw-snapshot-pre.sh` | _yes / no_ | _OK / FAIL_ | _OK / FAIL_ | _dual-mode; [STUB] in dry-run path expected_ |
| `ocw-snapshot-post.sh` | _yes / no_ | _OK / FAIL_ | _OK / FAIL_ | _dual-mode; [STUB] in dry-run path expected_ |
| `ocw-vault-sync.sh` | _yes / no_ | _OK / FAIL_ | _OK / FAIL_ | _dual-mode; [STUB] in dry-run path expected_ |
| `ocw-rollback-prepare.sh` | _yes / no_ | _OK / FAIL_ | _OK / FAIL_ | _dual-mode; [STUB] in dry-run path expected_ |

---

## Broker Daemon Installation

| Item | Value |
|------|-------|
| Broker daemon installed at `/opt/openclaw/broker/openclaw-broker` | _yes / no_ |
| Owner:group | _root:root_ |
| Mode | _755_ |
| `bash -n` syntax check (if bash) | _OK / FAIL / N/A_ |

---

## Systemd Unit Installation

| Item | Value |
|------|-------|
| Unit file installed at `/etc/systemd/system/openclaw-broker.service` | _yes / no_ |
| `systemctl daemon-reload` | _OK / FAIL_ |
| Service loaded but NOT active | _confirmed / unexpected state_ |

---

## Broker Start and Verification

| Item | Value |
|------|-------|
| `systemctl start openclaw-broker.service` | _OK / FAIL_ |
| `systemctl is-active` | _active / inactive / failed_ |
| Socket exists at `/run/openclaw/broker.sock` | _yes / no_ |
| Socket permissions | _root:openclaw 660 / other_ |
| Journal logs show startup | _yes / no_ |

---

## Basic Operation Tests

### Positive test: gateway_health

| Item | Value |
|------|-------|
| Request sent | _yes / no_ |
| Response received | _yes / no_ |
| `ok` field | _true / false_ |
| `status` field | _ok / error / denied_ |
| Full response | _(paste or summarize)_ |

### Negative test: invalid action

| Item | Value |
|------|-------|
| Request sent (action: `delete_everything`) | _yes / no_ |
| Response `ok` field | _false (expected) / true (FAIL)_ |
| Response `status` field | _error (expected) / other_ |

### Negative test: path traversal

| Item | Value |
|------|-------|
| Request sent (path traversal candidate_path) | _yes / no_ |
| Response `ok` field | _false (expected) / true (FAIL — IMMEDIATE ROLLBACK)_ |
| Response `status` field | _denied (expected) / other_ |

---

## Plugin Installation

| Item | Value |
|------|-------|
| Plugin directory created | _yes / no_ |
| `index.js` installed | _yes / no_ |
| Plugin manifest created | _yes / no_ |
| Config candidate prepared | _yes / no_ |
| `validate_openclaw_json_candidate` via broker | _ok / error_ |
| `deploy_openclaw_json_candidate` via broker | _ok / error_ |
| `gateway_restart` via broker | _ok / error_ |
| `gateway_health` post-restart | _ok / error_ |

---

## Enable on Boot

| Item | Value |
|------|-------|
| `systemctl enable openclaw-broker.service` | _OK / FAIL_ |
| `systemctl is-enabled` | _enabled / disabled_ |

---

## Post-change Snapshot and Vault Sync

| Item | Value |
|------|-------|
| Post-change snapshot label | _root-post-phase2-broker-YYYYMMDD_ |
| Snapshot creation time | _YYYY-MM-DD HH:MM_ |
| Verified in listing | _yes / no_ |
| Vault mounted | _OK / FAIL_ |
| Pre-change snapshot synced to vault | _OK / FAIL_ |
| Post-change snapshot synced to vault | _OK / FAIL_ |
| Vault unmounted | _OK / FAIL_ |

---

## Final Verification (runbook §6)

| # | Check | Expected | Actual |
|---|-------|----------|--------|
| 1 | `systemctl is-active openclaw-broker.service` | `active` | ___ |
| 2 | `systemctl is-active openclaw-gateway.service` | `active` | ___ |
| 3 | Socket exists with correct permissions | `root:openclaw 660` | ___ |
| 4 | Broker responds to `gateway_health` | `ok: true` | ___ |
| 5 | Broker rejects invalid action | `ok: false, status: error` | ___ |
| 6 | Broker rejects path traversal | `ok: false, status: denied` | ___ |
| 7 | Broker logs contain recent entries | timestamped lines | ___ |
| 8 | Plugin in openclaw.json | host-ops-tool present | ___ |

---

## Conclusion

| Item | Value |
|------|-------|
| Deployment successful | _yes / no_ |
| Rollback triggered | _yes / no (if yes, see Rollback section)_ |
| Phase 2 broker deployment complete | _yes / no_ |

---

## Rollback Record (if applicable)

| Item | Value |
|------|-------|
| Rollback trigger | _(describe what failed)_ |
| Rollback step reached | _(execution pack step #)_ |
| Broker stopped | _yes / N/A_ |
| Broker disabled | _yes / N/A_ |
| Config restored from backup | _yes / N/A_ |
| Gateway restarted | _yes / N/A_ |
| Gateway health post-rollback | _OK / FAIL_ |
| Snapshot rollback used | _yes / no_ |
| Post-rollback snapshot | _root-post-rollback-phase2-broker-YYYYMMDD / N/A_ |

---

## Anomalies and Notes

_(Record any unexpected situations, deviations, or additional actions. Write "None" if no anomalies.)_

---

## Documentation Syncback Confirmation

| Syncback item | Completed |
|---------------|-----------|
| `host-sop.md` changelog entry added | ☐ |
| `host-sop.md` phase status updated | ☐ |
| `design-v3.md` Phase 2 status updated | ☐ |
| `design-v3.md` document header date updated | ☐ |
| Dev-repo git commit submitted | ☐ |
| Syncback commit SHA | _(fill in)_ |

---

> After filling in this record, save it to the dev-repo (e.g. `docs/records/` directory) or include as a commit message supplement.
> Use `docs/templates/phase2-broker-deployment-syncback-template.md` for the actual text changes to host-sop.md and design-v3.md.
