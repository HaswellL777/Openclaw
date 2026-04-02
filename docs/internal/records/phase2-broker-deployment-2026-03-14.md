# Phase 2 Broker Deployment Field Record — 2026-03-14

> Operator: nick
> Execution date: 2026-03-14
> Dev-repo branch: `feat/phase1b-workspace-foundation`
> Baseline commit: `b969145`
> Verdict: **PASS**

---

## 1. Deployment summary

Phase 2 broker live deployment completed successfully on 2026-03-14.
Acceptance boundary per runbook:

- plugin installed: **yes**
- config deployed: **yes**
- gateway healthy: **yes**
- `host_ops` tool accessibility by agent: **not a hard acceptance criterion at this stage**

---

## 2. Final live state

| Item | Value |
|------|-------|
| `openclaw-broker.service` | active, enabled |
| `openclaw-gateway.service` | active |
| Broker socket | `/run/openclaw/broker.sock`, `root:openclaw 660` |
| Broker ExecStart | `/opt/openclaw/broker/openclaw-broker --listen --log-file /var/log/openclaw/broker/broker.log` |
| `BROKER_DRY_RUN` | `false` |

---

## 3. Configuration

| Item | Value |
|------|-------|
| Live config path | `/etc/openclaw/openclaw.json` |
| Live config SHA256 | `04f11b9b23b80d1c469c45fb56a43bb462013a31f778d09afbb834cbd41dcc41` |
| Config backup | `/etc/openclaw/openclaw.json.bak` |
| Candidate used | `/var/lib/openclaw/approvals/candidates/openclaw-phase2-broker.json` |
| Candidate SHA256 | same as live config SHA256 above |

### plugins section (post-deploy)

- `allow`: `feishu`, `tool-audit-plugin`, `host-ops-tool`
- `entries["host-ops-tool"].enabled = true`

---

## 4. Validation results

### Positive test

- `gateway_health` via broker: `ok: true, status: ok`

### Negative tests

- Invalid action (`delete_everything`): `ok: false, status: error`
- Bad path (non-whitelisted path): `ok: false, status: denied, message: "Path not in whitelist"`
- Path traversal (`../` in path): `ok: false, status: denied`

---

## 5. Snapshots and Vault

| Item | Value |
|------|-------|
| Pre-change snapshot | `root-pre-phase2-broker-20260314`, ID `309` |
| Post-change snapshot | `root-post-phase2-broker-20260314`, ID `310` |
| Vault auto snapshot | `root-auto-2026-03-14-1454`, ID `311` |
| Vault sync type | Incremental send (parent: `root-auto-2026-03-14-0340`) |
| `last_sent` | `root-auto-2026-03-14-1454` |
| Vault post-sync state | Unmounted / offline |
| Vault receive path | `/mnt/vault/recv/system` |

---

## 6. Key runtime findings (lessons learned)

These findings were discovered or confirmed during this deployment and should be treated as authoritative operational facts going forward.

### 6.1 Vault receive path semantics

- **Correct** receive path: `/mnt/vault/recv/system`
- **Incorrect** (previously seen in some docs): `/mnt/vault/snapshots/`
- Path drift occurred during execution and was corrected.

### 6.2 Vault sync correct execution method

- All Vault sync operations should go through: `/usr/local/sbin/vault-backup-root-btrfs`
- This script handles:
  - Creating new `root-auto-*` snapshot
  - Mounting vault
  - Determining incremental vs full send based on `last_sent`
  - `btrfs receive` to `/mnt/vault/recv/system`
  - Updating `last_sent`
  - Unmounting vault
- This deployment:
  - parent = `root-auto-2026-03-14-0340`
  - new = `root-auto-2026-03-14-1454`
  - Incremental send

### 6.3 gateway_restart success criteria

- When `gateway_restart` is triggered via broker, the broker request itself may return `E_BROKER_INTERNAL`.
- Root cause: broker unit has `Requires=openclaw-gateway.service`; when gateway restarts, broker is SIGTERM'd by systemd and then restarted.
- **The broker request return value is NOT the sole success criterion.**
- Correct success criteria after `gateway_restart`:
  1. `systemctl is-active openclaw-gateway.service` → `active`
  2. `systemctl is-active openclaw-broker.service` → `active`
  3. `gateway_health` via broker → `ok: true`
  4. Journal shows clean restart sequence
- This deployment: all 4 criteria met after restart.

### 6.4 Live config format facts

- Pre-deploy `/etc/openclaw/openclaw.json` was **JS-style / JSON5-like** — not strict JSON.
- It cannot be parsed directly by `jq`.
- The candidate workflow requires strict JSON candidates staged to `/var/lib/openclaw/approvals/candidates/`.
- Post-deploy, if the live config has been replaced by a strict JSON candidate, it becomes `jq`-parseable.
- Safe candidate generation approach used in this deployment: avoid `eval`, reuse `/opt/openclaw/node_modules/json5` for reading the pre-deploy config.

### 6.5 Plugin status — precise definition

- `host-ops-tool` has been:
  - Installed to extensions directory (`/var/lib/openclaw/.openclaw/extensions/host-ops-tool/`)
  - Registered in `openclaw.json` (`plugins.entries`, `plugins.allow`)
  - Accepted by gateway (gateway started healthy with this config)
- Gateway logs contain known warnings:
  - `host-ops-tool missing register/activate export`
  - `plugin export missing register/activate (plugin=host-ops-tool, source=...)`
- These warnings are **non-blocking** — gateway runs normally.
- But this does **NOT** mean:
  - Agent can call `host_ops` tool (agent-facing activation is pending)
  - Plugin has completed its full lifecycle activation (register/activate exports missing from `index.js`)
- Current status is:
  - **Broker backend deployment: COMPLETE**
  - **Plugin registration in config: COMPLETE**
  - **Plugin activation / agent-facing tool availability: PENDING** (requires `index.js` register/activate exports + `tools.allow` update)

---

## 7. Anomalies

1. Vault path drift: execution initially used incorrect Vault path, corrected during run (see §6.1).
2. `gateway_restart` broker request returned `E_BROKER_INTERNAL` due to `Requires=` dependency (see §6.3). Final state was healthy.
3. Gateway warning about `host-ops-tool missing register/activate export` (see §6.5). Non-blocking.

---

## 8. What this deployment did NOT complete

- `host-ops-tool` `index.js` register/activate export implementation（最小 `openclaw.plugin.json` manifest 已落地，但 `index.js` 缺少 register/activate export，gateway 无法完成 plugin lifecycle activation）
- Agent-side `host_ops` tool activation (`tools.allow` update)
- Automated deployment script (this deployment was manual/operator-led)

These remain as subsequent work items.
