# Sandbox Auto-Prune Configuration Delta

## Change Summary

Add `agents.defaults.sandbox.prune` to `openclaw.json` with:
- `idleHours: 4` — remove containers idle for 4+ hours
- `maxAgeDays: 3` — hard cap at 3 days regardless of activity

## Rationale

The current task-runner is designed as "one task, one container" (`scope: "session"`).
Containers should be short-lived. Without prune config, orphaned containers from
interrupted sessions or abandoned tasks accumulate disk and memory.

## Values Justification

| Parameter | Value | Reasoning |
|-----------|-------|-----------|
| `idleHours` | 4 | Tasks typically finish in <1h. 4h gives ample buffer for long-running builds while preventing overnight idle accumulation. |
| `maxAgeDays` | 3 | Aligns with `archiveAfterMinutes: 120` (session archive) while providing a hard backstop. No task should legitimately run for 3 days in the current model. |

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Active long-running task pruned early | Low | `idleHours=4` checks for *idle* time, not wall-clock time. An actively executing task generates exec activity. |
| Prune removes container with unsaved outputs | Low | Outputs dir is on a bind mount (`workspaceAccess`) or within the workspace, which persists independently of the container. |
| Gateway misparses new config field | Low | P4 probe confirmed that `sandbox.docker` structure is accepted by OpenClaw 2026.3.13. `sandbox.prune` is a documented feature. |

## Rollback Note

If prune behavior causes unexpected container removal:
1. Remove the `sandbox.prune` block from `openclaw.json`
2. Restart gateway: `sudo systemctl restart openclaw-gateway.service`
3. Verify with `sudo systemctl status openclaw-gateway.service`

If full rollback needed, restore from pre-change snapshot (created in step 1 of deployment).

## Validation Checklist

- [ ] Generate full candidate file (merge delta into current `openclaw.json`)
- [ ] `broker validate_openclaw_json_candidate` passes
- [ ] Pre-change snapshot: `btrfs subvolume snapshot -r / /snapshots/root-pre-prune-config-YYYYMMDD-HHMM`
- [ ] Vault sync (pre)
- [ ] Deploy candidate via `broker deploy_openclaw_json_candidate`
- [ ] Restart gateway
- [ ] Gateway health check passes
- [ ] Verify prune config in gateway logs: `journalctl -u openclaw-gateway.service | grep -i prune`
- [ ] Post-change snapshot
- [ ] Vault sync (post)
- [ ] Spawn a test task-runner, wait for it to idle, confirm it gets pruned after `idleHours`

## Operator Commands

```bash
# Step 1: Pre-change snapshot
sudo btrfs subvolume snapshot -r / /snapshots/root-pre-prune-config-$(date +%Y%m%d-%H%M)

# Step 2: Vault sync (pre)
sudo /usr/local/sbin/vault-backup-root-btrfs

# Step 3: Merge the prune config into openclaw.json
# (Manually add the agents.defaults.sandbox.prune block shown in the candidate file)
# Save the result to: /var/lib/openclaw/approvals/candidates/openclaw.json

# Step 4: Validate
# Via main agent or direct broker call:
#   host_ops validate_openclaw_json_candidate

# Step 5: Deploy
#   host_ops deploy_openclaw_json_candidate

# Step 6: Restart gateway
sudo systemctl restart openclaw-gateway.service

# Step 7: Health check
sudo systemctl status openclaw-gateway.service

# Step 8: Post-change snapshot
sudo btrfs subvolume snapshot -r / /snapshots/root-post-prune-config-$(date +%Y%m%d-%H%M)

# Step 9: Vault sync (post)
sudo /usr/local/sbin/vault-backup-root-btrfs
```
