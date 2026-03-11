# Post-Deployment Documentation Syncback Template: Phase 2 Broker

> This document provides exact text changes for updating `docs/host-sop.md` and `docs/design-v3.md`
> after a successful Phase 2 broker deployment.
> **Only use this template after the broker has been deployed, validated, and the deployment record is complete.**
> **Do not apply these changes before deployment. Do not apply if deployment was rolled back.**
> This template is a dev-repo artifact. The broker is NOT yet deployed. Phase 2 has NOT started.

---

## 1. host-sop.md changelog: append timeline entry

Append one row to the changelog table in `host-sop.md`:

```markdown
| YYYY-MM-DD | Phase 2 broker deployment: installed host-ops broker daemon, 8 wrapper scripts, shared validation library, and systemd unit (`openclaw-broker.service`); broker listening on `/run/openclaw/broker.sock` (root:openclaw 660); all 8 actions validated (gateway_health, gateway_restart, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, vault_sync, rollback_prepare); negative cases (invalid action, path traversal) correctly rejected; host-ops-tool plugin registered in `/etc/openclaw/openclaw.json`; pre-snapshot `root-pre-phase2-broker-YYYYMMDD`, post-snapshot `root-post-phase2-broker-YYYYMMDD`, Vault sync completed; **Phase 2 broker deployment exit conditions met** |
```

> Replace all `YYYY-MM-DD` and `YYYYMMDD` with actual values. Add anomaly notes if applicable.

---

## 2. host-sop.md phase status: update current phase

### Change the phase description from (approximate — locate the Phase 2 status section):

```markdown
- **Phase 2（broker / wrapper 写入链）尚未开始**
```

### To:

```markdown
- **Phase 2（broker / wrapper 写入链）broker 已部署（YYYY-MM-DD）**：
  - host-ops broker daemon 运行中 (`openclaw-broker.service`, active + enabled)
  - 8 个 wrapper 已安装（production 逻辑，无 STUB 标记）
  - Unix socket `/run/openclaw/broker.sock` (root:openclaw 660)
  - host-ops-tool plugin 已注册
  - **Phase 2 的后续工作（task-runner、Docker 隔离等）尚未开始**
```

---

## 3. host-sop.md path inventory: add broker paths

If host-sop.md has a path inventory or directory boundary section, add:

```markdown
| `/opt/openclaw/broker/` | root:root | 755 | Broker daemon and wrapper scripts |
| `/opt/openclaw/broker/wrappers/` | root:root | 755 | 8 action wrapper scripts |
| `/opt/openclaw/broker/wrappers/lib/` | root:root | 755 | Shared validation library (common.sh) |
| `/run/openclaw/broker.sock` | root:openclaw | 660 | Broker Unix socket (systemd RuntimeDirectory) |
| `/var/log/openclaw/broker/` | root:openclaw | 750 | Broker audit logs |
| `/var/lib/openclaw/broker/` | root:openclaw | 750 | Broker state (minimal) |
```

---

## 4. host-sop.md systemd services: add broker unit

If host-sop.md has a systemd services section, add:

```markdown
| `openclaw-broker.service` | root | Runs host-ops broker; depends on `openclaw-gateway.service`; creates `/run/openclaw/` via RuntimeDirectory |
```

---

## 5. design-v3.md §5.6 broker status: update

### Change (approximate — locate the broker deployment status):

```markdown
> The broker is not yet deployed. This section describes the design target.
```

### To:

```markdown
> The broker was deployed on YYYY-MM-DD. See deployment record for details.
> Deployment layout: `docs/specs/phase2-broker-deployment-layout.md`
```

---

## 6. design-v3.md §8.3 Phase 2 TODO: update broker items

### Change items related to broker deployment from:

```markdown
- [ ] Implement broker daemon
- [ ] Upgrade wrapper stubs to production logic
- [ ] Install systemd unit
- [ ] Register host-ops-tool plugin
```

### To:

```markdown
- [x] ~~Implement broker daemon~~ (YYYY-MM-DD)
- [x] ~~Upgrade wrapper stubs to production logic~~ (YYYY-MM-DD)
- [x] ~~Install systemd unit~~ (YYYY-MM-DD)
- [x] ~~Register host-ops-tool plugin~~ (YYYY-MM-DD)
```

> Only mark items that were actually completed during deployment. Leave remaining Phase 2 items (task-runner, Docker, etc.) unchanged.

---

## 7. design-v3.md document header: update revision date

### Change:

```markdown
> 本次修订日期：PREV-DATE（previous revision description）
```

### To:

```markdown
> 本次修订日期：YYYY-MM-DD（Phase 2 broker deployment completed）
```

---

## 8. design-v3.md §0 conclusions: append

Append after the last numbered conclusion:

```markdown
NN. **Phase 2 broker 已于 YYYY-MM-DD 部署完成：host-ops broker daemon 运行中，8 个 wrapper 已安装（production 逻辑），host-ops-tool plugin 已注册。Phase 2 的后续工作（task-runner、Docker 隔离等）尚未开始。**
```

---

## Syncback discipline

- Replace all `YYYY-MM-DD` and `YYYYMMDD` placeholders with actual deployment date
- Replace `NN` with the next conclusion number
- Do NOT mark Phase 2 as "fully complete" — only the broker deployment portion is done
- Do NOT claim task-runner, Docker isolation, or other Phase 2 items as deployed
- Do NOT mark Phase 3 as started
- Syncback commit message should include "phase2-broker: deployment syncback" and NOT "Phase 2 complete"
- Both `host-sop.md` and `design-v3.md` must be updated in the same commit to maintain consistency
- The deployment record (`docs/templates/phase2-broker-deployment-record-template.md`) must be filled in BEFORE applying this syncback
