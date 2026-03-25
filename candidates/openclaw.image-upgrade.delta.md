# Combined Image Upgrade + Knowledge Binds + Auto-Prune Delta

> Date: 2026-03-25
> Supersedes: `candidates/openclaw.prune.candidate.json5` + `candidates/openclaw.prune.delta.md`

## Change Summary

Three changes in one candidate, applied to the existing live `openclaw.json`:

| # | Section | Change | Old Value | New Value |
|---|---------|--------|-----------|-----------|
| 1 | `agents.list[task-runner].sandbox.docker.image` | Switch from slim to full image | `openclaw-task-claude:2026-03-v3` | `openclaw-task-claude:2026-03-v3-full` |
| 2 | `agents.list[task-runner].sandbox.docker.binds` | Add knowledge repo bind mount | *(not present)* | `["/home/nick/repos:/workspace/knowledge:ro"]` |
| 3 | `agents.defaults.sandbox.prune` | Add sandbox auto-prune | *(not present)* | `{ idleHours: 4, maxAgeDays: 3 }` |

## Rationale

### Change 1: Full Image

The slim image (`2026-03-v3`) lacks Node.js, pip, and build-essential. Real engineering
tasks need these tools. The full image (`2026-03-v3-full`) was built on 2026-03-24 and
includes: Node.js 22, npm, pip, build-essential, plus all slim-image tools (bash, git,
python3, jq, rg, curl).

Both images use UID 997:984 matching the `openclaw` system user. No UID mismatch.

### Change 2: Knowledge Binds

Operator wants reference repositories accessible inside the container. The bind mount
`/home/nick/repos:/workspace/knowledge:ro` gives the agent read-only access to cloned
reference repos at a predictable container-side path. The `:ro` flag prevents any
container-side writes to the host filesystem.

**Prerequisite**: Operator must create `/home/nick/repos/` and clone desired repos there
before this takes effect.

### Change 3: Auto-Prune

Carried forward from the standalone prune candidate (`openclaw.prune.candidate.json5`).
Prevents container accumulation in the one-task-one-container model.

| Parameter | Value | Reasoning |
|-----------|-------|-----------|
| `idleHours` | 4 | Tasks finish in <1h; 4h buffer for long builds |
| `maxAgeDays` | 3 | Hard backstop; no task should run 3 days |

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Full image larger than slim (~500MB vs ~200MB) | Low | Disk space is ample; build already completed |
| Knowledge bind mount exposes host files | Low | Read-only (`:ro`); only `/home/nick/repos/` exposed; container cannot escalate |
| Bind path doesn't exist on host | Low | Docker creates it as empty dir; no crash; operator creates and populates it |
| Active task container pruned early | Low | `idleHours=4` checks idle time, not wall clock; active tasks generate exec activity |
| Container outputs lost to prune | Low | Outputs are in workspace bind mount, not container filesystem |
| Gateway misparses new config fields | Low | P4 probe passed for `sandbox.docker`; `binds` and `prune` are documented features in 2026.3.13 |

## Rollback Note

These three changes are independent and can be rolled back individually:

1. **Image**: Change `image` back to `openclaw-task-claude:2026-03-v3`, restart gateway
2. **Binds**: Remove the `binds` array, restart gateway
3. **Prune**: Remove the `sandbox.prune` block, restart gateway

If full rollback needed, restore from pre-change snapshot.

## Validation Checklist

- [ ] Ensure `/home/nick/repos/` exists (or create it)
- [ ] Ensure `openclaw-task-claude:2026-03-v3-full` image exists: `sudo docker images | grep v3-full`
- [ ] Merge delta into current `openclaw.json` (manually apply the three changes)
- [ ] Save merged file to `/var/lib/openclaw/approvals/candidates/openclaw.json`
- [ ] Validate via broker: `host_ops validate_openclaw_json_candidate`
- [ ] Pre-change snapshot: `sudo btrfs subvolume snapshot -r / /.snapshots/root-pre-image-upgrade-$(date +%Y%m%d-%H%M)`
- [ ] Vault sync (pre): `sudo /usr/local/sbin/vault-backup-root-btrfs`
- [ ] Deploy via broker: `host_ops deploy_openclaw_json_candidate`
- [ ] Restart gateway: `sudo systemctl restart openclaw-gateway.service`
- [ ] Gateway health check: `sudo systemctl status openclaw-gateway.service`
- [ ] Spawn test task-runner and verify:
  - Container uses `v3-full` image: `sudo docker ps --format '{{.Image}}'`
  - Node.js available: `node --version` inside container
  - Knowledge mount exists: `ls /workspace/knowledge/` inside container
- [ ] Post-change snapshot: `sudo btrfs subvolume snapshot -r / /.snapshots/root-post-image-upgrade-$(date +%Y%m%d-%H%M)`
- [ ] Vault sync (post): `sudo /usr/local/sbin/vault-backup-root-btrfs`
- [ ] (Later) Verify prune: idle container removed after ~4 hours

## Operator Commands

```bash
# Step 0: Prepare knowledge directory (if not exists)
mkdir -p /home/nick/repos
# Clone reference repos as needed, e.g.:
# cd /home/nick/repos && git clone https://github.com/example/useful-lib.git

# Step 1: Verify full image exists
sudo docker images | grep openclaw-task-claude

# Step 2: Pre-change snapshot
sudo btrfs subvolume snapshot -r / /.snapshots/root-pre-image-upgrade-$(date +%Y%m%d-%H%M)

# Step 3: Vault sync (pre)
sudo /usr/local/sbin/vault-backup-root-btrfs

# Step 4: Merge the three delta changes into /etc/openclaw/openclaw.json
# Changes:
#   a) agents.list[task-runner].sandbox.docker.image = "openclaw-task-claude:2026-03-v3-full"
#   b) agents.list[task-runner].sandbox.docker.binds = ["/home/nick/repos:/workspace/knowledge:ro"]
#   c) agents.defaults.sandbox.prune = { idleHours: 4, maxAgeDays: 3 }
# Save merged candidate to: /var/lib/openclaw/approvals/candidates/openclaw.json

# Step 5: Validate
# Via main agent: host_ops validate_openclaw_json_candidate
# Or via broker CLI if available

# Step 6: Deploy
# Via main agent: host_ops deploy_openclaw_json_candidate

# Step 7: Restart gateway
sudo systemctl restart openclaw-gateway.service

# Step 8: Health check
sudo systemctl status openclaw-gateway.service

# Step 9: Spawn test task and verify inside container
# (via Feishu or main agent: ask to run a simple task)
# Verify: docker ps shows v3-full image
# Verify: node --version works in container
# Verify: /workspace/knowledge/ is readable

# Step 10: Post-change snapshot
sudo btrfs subvolume snapshot -r / /.snapshots/root-post-image-upgrade-$(date +%Y%m%d-%H%M)

# Step 11: Vault sync (post)
sudo /usr/local/sbin/vault-backup-root-btrfs
```
