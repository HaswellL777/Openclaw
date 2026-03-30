# Runbook: System Rollback

## Purpose
Procedure for rolling back to a previous snapshot after failed changes

## When to use
- Configuration change caused gateway failure
- System update broke OpenClaw
- Unrecoverable error after host mutation
- Need to restore to known-good state

## Prerequisites
- Snapshot exists for target state
- Vault has backup of snapshot
- Clear understanding of what will be lost (changes since snapshot)

## Important warnings
⚠️ **Root snapshot rollback does NOT restore `/var/lib/openclaw`**
- `/var/lib/openclaw` is a separate btrfs subvolume
- It is NOT included in root snapshots
- workspace-main must be restored separately via publish scripts

⚠️ **Rollback loses all changes since snapshot**
- Any changes to root filesystem since snapshot will be lost
- Uncommitted work will be lost
- Recent logs will be lost

⚠️ **Vault is offline by default**
- `/mnt/vault` is mounted with `noauto`
- Must be manually mounted before vault operations
- Must be manually unmounted after operations

## Procedure

### 1. Identify target snapshot
```bash
# List available snapshots
sudo ls -la /.snapshots/

# Check vault for backups
sudo mount /mnt/vault
sudo ls -la /mnt/vault/recv/system/
```

### 2. Document current state
```bash
# Capture current state before rollback
sudo journalctl -u openclaw-gateway.service -n 200 > /tmp/pre-rollback-logs.txt
sudo cp /etc/openclaw/openclaw.json /tmp/pre-rollback-config.json
```

### 3. Create emergency snapshot (if possible)
```bash
# If system is still bootable
sudo btrfs subvolume snapshot / /.snapshots/emergency-$(date +%Y%m%d-%H%M%S)
```

### 4. Reboot and select snapshot from grub
```bash
sudo reboot
```

At grub menu:
1. Select "Advanced options for Ubuntu"
2. Select snapshot: `/.snapshots/<target-snapshot>`
3. Boot from snapshot

### 5. Verify system state
```bash
# Check OpenClaw config
cat /etc/openclaw/openclaw.json

# Check gateway status
sudo systemctl status openclaw-gateway.service

# Check logs
sudo journalctl -u openclaw-gateway.service -n 50
```

### 6. Make snapshot permanent (if rollback successful)
```bash
# Current boot is read-only snapshot
# To make permanent, need to restore to main subvolume

# This is DESTRUCTIVE - make sure rollback is correct first
sudo btrfs subvolume delete /.snapshots/BROKEN  # optional: delete broken state
sudo btrfs subvolume snapshot /.snapshots/<target> /  # restore to root
```

**WARNING**: This step is complex and risky. Consider consulting documentation or getting human confirmation.

### 7. Restore workspace-main (if needed)
```bash
# workspace-main is NOT restored by root snapshot
# Must republish from template

cd /home/nick/projects/openclaw-dev
./scripts/publish-workspace-main.sh --apply /var/lib/openclaw/.openclaw/workspace-main
```

### 8. Restart gateway
```bash
sudo systemctl restart openclaw-gateway.service
```

### 9. Verify health
```bash
# Check service
sudo systemctl status openclaw-gateway.service

# Check logs
sudo journalctl -u openclaw-gateway.service -n 50

# Test connectivity via Feishu
```

### 10. Update state
Update `control/state/last-health.md` with:
- Rollback timestamp
- Target snapshot
- Reason for rollback
- Validation results
- What was lost

### 11. Sync to vault
```bash
sudo mount /mnt/vault

# Send current state to vault
sudo btrfs send -p /mnt/vault/recv/system/<previous> /.snapshots/<current> | \
  sudo btrfs receive /mnt/vault/recv/system/

sudo umount /mnt/vault
```

## Validation checklist
- [ ] Target snapshot identified
- [ ] Current state documented
- [ ] Emergency snapshot created (if possible)
- [ ] Booted from target snapshot
- [ ] System state verified
- [ ] workspace-main restored (if needed)
- [ ] Gateway restarted
- [ ] Health verified
- [ ] State files updated
- [ ] Vault synced

## Alternative: Restore from vault

If local snapshots are lost or corrupted:

### 1. Mount vault
```bash
sudo mount /mnt/vault
```

### 2. List available snapshots
```bash
sudo ls -la /mnt/vault/recv/system/
```

### 3. Receive snapshot from vault
```bash
sudo btrfs receive /.snapshots/ < /mnt/vault/recv/system/<snapshot>
```

### 4. Follow steps 4-11 above

## Common issues

### Grub doesn't show snapshots
- Snapshots may not be automatically added to grub
- May need to manually configure grub
- Consult btrfs + grub documentation

### Snapshot restore fails
- Check disk space
- Check btrfs filesystem health: `sudo btrfs check /`
- Check vault connectivity and integrity

### Gateway still fails after rollback
- Verify correct snapshot selected
- Check if issue is in /var/lib/openclaw (not restored by root snapshot)
- Check if issue is in workspace-main (must be republished)

## Broker automation (operational)

Host-ops broker is available (since 2026-03-17):
- main agent calls broker API for rollback
- Broker executes steps automatically with safety checks
- main agent monitors and reports results

## Notes
- Rollback is a last resort
- Always try less destructive fixes first (config restore, gateway restart)
- Document everything before and after rollback
- Keep detailed notes for post-mortem analysis
- Consider what caused the need for rollback and how to prevent it
