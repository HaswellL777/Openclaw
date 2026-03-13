# Phase 2 Broker Deployment Layout Specification

> Status: **Dev-repo deployment design** — repo-only artifact
> Created: 2026-03-11
> Purpose: Define exact filesystem layout, ownership, permissions, and systemd unit names for Phase 2 broker deployment
> Authority: `docs/design-v3.md` SS5.6, `docs/host-sop.md`
> This document is a deployment design artifact. The broker is NOT yet deployed. Phase 2 has NOT started.

---

## 0. Scope

This specification defines the target filesystem layout for the host-ops broker deployment. It covers:
- Broker daemon installation path and binary
- Unix socket path
- Wrapper installation paths
- Shared library installation
- Log and state directories
- Systemd unit file
- Ownership and permission model
- Relationship to existing host-sop directory boundaries

**This is a design document only.** Nothing described here has been installed or deployed.

---

## 1. Broker daemon

| Attribute | Value | Notes |
|-----------|-------|-------|
| Binary/script | `/opt/openclaw/broker/openclaw-broker` | Root-owned, not writable by openclaw user |
| Owner | `root:root` | Consistent with `/opt/openclaw` ownership model |
| Mode | `0755` | Executable by all, writable only by root |
| Type | Bash script (socket listener: Python 3) | Main daemon is bash; socket listener is Python for SO_PEERCRED |
| Socket listener | `/opt/openclaw/broker/lib/socket-listener.py` | Python 3, launched by broker `--listen` mode |
| Parent directory | `/opt/openclaw/broker/` | New subdirectory under existing `/opt/openclaw` |

**Rationale**: `/opt/openclaw` is already `root:root 755` per host-sop. Placing the broker under `/opt/openclaw/broker/` maintains the existing ownership model and ensures the openclaw user cannot modify broker code.

---

## 2. Unix socket

| Attribute | Value | Notes |
|-----------|-------|-------|
| Socket path | `/run/openclaw/broker.sock` | Under systemd-managed `/run` tmpfs |
| Owner | `root:openclaw` | Root creates socket; openclaw group can connect |
| Mode | `0660` | Owner (root) and group (openclaw) can read/write; others denied |
| Directory | `/run/openclaw/` | Created by systemd RuntimeDirectory directive |

**Rationale**: Using `/run/` ensures the socket is cleaned up on reboot. The `root:openclaw` ownership with `0660` permissions allows the openclaw gateway process (running as `openclaw` user) to connect, while preventing other users from accessing the broker.

**Security note**: The broker authenticates callers via Unix socket peer credentials (`SO_PEERCRED`). Only processes running as `openclaw` user or `root` can connect.

---

## 3. Wrapper scripts

| Attribute | Value | Notes |
|-----------|-------|-------|
| Installation directory | `/opt/openclaw/broker/wrappers/` | Root-owned, alongside broker binary |
| Shared library | `/opt/openclaw/broker/wrappers/lib/common.sh` | Sourced by all wrappers |
| Owner | `root:root` | All wrappers must be root-owned |
| Mode | `0755` | Executable by all, writable only by root |
| Naming convention | `ocw-<action-stem>.sh` | Same names as dev-repo stubs |

### Wrapper file inventory

| Wrapper | Action | Source (dev-repo) |
|---------|--------|-------------------|
| `ocw-gateway-health.sh` | `gateway_health` | `broker/wrappers/ocw-gateway-health.sh` |
| `ocw-gateway-restart.sh` | `gateway_restart` | `broker/wrappers/ocw-gateway-restart.sh` |
| `ocw-validate-openclaw-json.sh` | `validate_openclaw_json_candidate` | `broker/wrappers/ocw-validate-openclaw-json.sh` |
| `ocw-deploy-openclaw-json.sh` | `deploy_openclaw_json_candidate` | `broker/wrappers/ocw-deploy-openclaw-json.sh` |
| `ocw-snapshot-pre.sh` | `snapshot_pre` | `broker/wrappers/ocw-snapshot-pre.sh` |
| `ocw-snapshot-post.sh` | `snapshot_post` | `broker/wrappers/ocw-snapshot-post.sh` |
| `ocw-vault-sync.sh` | `vault_sync` | `broker/wrappers/ocw-vault-sync.sh` |
| `ocw-rollback-prepare.sh` | `rollback_prepare` | `broker/wrappers/ocw-rollback-prepare.sh` |
| `lib/common.sh` | (shared) | `broker/wrappers/lib/common.sh` |

**Upgrade path**: Dev-repo stubs contain `[STUB]` markers and echo-only logic. At deployment time, each wrapper's stub logic is replaced with real execution logic while preserving the same validation pipeline (`common.sh` functions).

---

## 4. Schemas (runtime copy)

| Attribute | Value | Notes |
|-----------|-------|-------|
| Directory | `/opt/openclaw/broker/schemas/` | Optional: broker may embed schema validation |
| Per-action schemas | `/opt/openclaw/broker/schemas/actions/` | Used for runtime request validation |
| Owner | `root:root` | Consistent with broker installation |
| Mode | `0644` | Readable by all, writable only by root |

**Note**: Whether the broker uses file-based schemas or embedded validation is a deployment-time decision. The schemas are authoritative in the dev repo (`broker/schemas/`); the installed copies are for runtime reference.

---

## 5. Log directory

| Attribute | Value | Notes |
|-----------|-------|-------|
| Directory | `/var/log/openclaw/broker/` | Subdirectory under existing log path |
| Owner | `root:openclaw` | Broker runs as root; logs readable by openclaw group |
| Mode | `0750` | Owner+group can access; others denied |
| Log file | `/var/log/openclaw/broker/broker.log` | Main broker audit log |
| Rotation | Managed by logrotate (TBD at deployment) | Consistent with existing `/var/log/openclaw` management |

**Rationale**: Using a subdirectory under the existing `/var/log/openclaw` keeps broker logs co-located with gateway logs while maintaining separate ownership for the root-running broker.

---

## 6. State directory

| Attribute | Value | Notes |
|-----------|-------|-------|
| Directory | `/var/lib/openclaw/broker/` | Under existing openclaw data subvolume |
| Owner | `root:openclaw` | Broker (root) writes; openclaw can read |
| Mode | `0750` | |
| Purpose | Request history, last-result cache, pid file | Minimal state; broker is primarily stateless |

**Note**: `/var/lib/openclaw` is an independent Btrfs subvolume and is NOT covered by root snapshots. Broker state under this path must be treated as volatile / reconstructable.

---

## 7. Candidate file staging

| Attribute | Value | Notes |
|-----------|-------|-------|
| Directory | `/var/lib/openclaw/approvals/candidates/` | Already defined in protocol spec |
| Owner | `openclaw:openclaw` | Created by main agent / approval workflow |
| Mode | `0700` | Only openclaw user can read/write |
| Purpose | Staging area for config candidate files pending deployment |

**Rationale**: Candidate files are created by the openclaw process (main agent), then read and verified by the broker (root). The broker validates the path starts with this prefix and checks SHA256 before deploying.

---

## 8. Systemd unit

| Attribute | Value | Notes |
|-----------|-------|-------|
| Unit file | `/etc/systemd/system/openclaw-broker.service` | System-level service |
| Service type | `simple` | Broker does not require readiness notification |
| User | `root` | Broker needs root to invoke wrappers that modify system state |
| RuntimeDirectory | `openclaw` | Creates `/run/openclaw/` |
| ExecStart | `/opt/openclaw/broker/openclaw-broker` | Main broker process |

### Suggested unit file skeleton (design only, not installed)

```ini
[Unit]
Description=OpenClaw Host-Ops Broker
After=network.target openclaw-gateway.service
Requires=openclaw-gateway.service

[Service]
Type=simple
ExecStart=/opt/openclaw/broker/openclaw-broker
RuntimeDirectory=openclaw
RuntimeDirectoryMode=0755
User=root
Group=root

# Security hardening
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=no
# Note: NoNewPrivileges=no because wrappers may need elevated operations
# Further hardening TBD at deployment based on actual wrapper requirements

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-broker

[Install]
WantedBy=multi-user.target
```

**Note**: This skeleton is a design artifact. The actual unit file will be finalized during Phase 2 deployment based on testing and security review.

---

## 9. Plugin installation

| Attribute | Value | Notes |
|-----------|-------|-------|
| Plugin directory | `/var/lib/openclaw/.openclaw/extensions/host-ops-tool/` | Standard OpenClaw plugin path |
| Manifest | `openclaw.plugin.json` | OpenClaw plugin manifest format |
| Plugin code | `index.js` | From dev-repo `plugins/host-ops-tool/index.js` |
| Owner | `openclaw:openclaw` | Standard plugin ownership |
| Registration | Entry in `/etc/openclaw/openclaw.json` `.plugins` array | Requires config change procedure |

**Note**: Plugin installation requires updating `/etc/openclaw/openclaw.json`, which itself requires the snapshot -> change -> validate -> snapshot -> vault workflow.

---

## 10. Directory tree summary

```
/opt/openclaw/broker/                          # root:root 755
  openclaw-broker                              # root:root 755 — broker daemon (bash)
  lib/                                         # root:root 755
    socket-listener.py                         # root:root 755 — Unix socket listener (Python 3)
  wrappers/                                    # root:root 755
    lib/common.sh                              # root:root 755 — shared validation
    ocw-gateway-health.sh                      # root:root 755
    ocw-gateway-restart.sh                     # root:root 755
    ocw-validate-openclaw-json.sh              # root:root 755
    ocw-deploy-openclaw-json.sh                # root:root 755
    ocw-snapshot-pre.sh                        # root:root 755
    ocw-snapshot-post.sh                       # root:root 755
    ocw-vault-sync.sh                          # root:root 755
    ocw-rollback-prepare.sh                    # root:root 755
  schemas/                                     # root:root 755 (optional)
    host-ops-request.schema.json               # root:root 644
    host-ops-result.schema.json                # root:root 644
    actions/                                   # root:root 755
      *.schema.json                            # root:root 644

/run/openclaw/                                 # root:root 755 (systemd RuntimeDirectory)
  broker.sock                                  # root:openclaw 660

/var/log/openclaw/broker/                      # root:openclaw 750
  broker.log                                   # root:openclaw 640

/var/lib/openclaw/broker/                      # root:openclaw 750
  (minimal state)

/var/lib/openclaw/approvals/candidates/        # openclaw:openclaw 700
  (candidate config files)

/var/lib/openclaw/.openclaw/extensions/host-ops-tool/  # openclaw:openclaw
  openclaw.plugin.json
  index.js

/etc/systemd/system/openclaw-broker.service    # root:root 644
```

---

## 11. Boundary relationship to host-sop

| host-sop path | Broker relationship |
|---------------|---------------------|
| `/opt/openclaw` (root:root 755) | Broker installs under `/opt/openclaw/broker/` — same ownership model |
| `/etc/openclaw` (root:openclaw 750) | Broker wrappers read/write `/etc/openclaw/openclaw.json` via deploy action |
| `/var/lib/openclaw` (openclaw:openclaw 700) | Broker state under `/var/lib/openclaw/broker/` (root:openclaw 750); candidates under existing approvals path |
| `/var/log/openclaw` (openclaw:openclaw) | Broker logs under `/var/log/openclaw/broker/` (root:openclaw 750) |
| `/.snapshots` | Broker wrappers create/manage snapshots via `snapshot_pre`/`snapshot_post` |
| `/mnt/vault` (noauto) | Broker `vault_sync` wrapper mounts/syncs/unmounts vault |

---

## 12. Open design questions (to resolve at deployment time)

| # | Question | Current assumption | Resolution trigger |
|---|----------|-------------------|-------------------|
| 1 | ~~Broker implementation language~~ | Bash script (socket listener: Python 3) | Resolved in Phase 2 impl slice 2 |
| 2 | ~~Service type (simple vs notify)~~ | `simple` | Resolved; broker does not need readiness notification |
| 3 | Schema validation approach | Embedded in wrappers (via common.sh) | Whether broker does pre-dispatch validation |
| 4 | Broker startup dependency ordering | After gateway | Whether broker can operate without gateway |
| 5 | Log rotation policy | Match existing openclaw logrotate | Disk usage patterns |
| 6 | Socket path alternatives | `/run/openclaw/broker.sock` | If `/run/openclaw/` conflicts with gateway |

---

## 13. References

- `docs/design-v3.md` SS5.6 — Authoritative broker design
- `docs/host-sop.md` — Host path boundaries and ownership model
- `docs/specs/host-ops-broker-protocol-v1.md` — Protocol specification
- `broker/wrappers/README.md` — Wrapper inventory and design rules
- `broker/wrappers/lib/common.sh` — Shared validation library (dev-repo version)
