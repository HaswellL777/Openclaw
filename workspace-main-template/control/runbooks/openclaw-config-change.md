# Runbook: OpenClaw Configuration Change

## Purpose
Safe procedure for updating `/etc/openclaw/openclaw.json`

## Prerequisites
- Human approval (Category 2)
- Pre-change snapshot created
- Vault sync completed
- Configuration patch prepared and validated

## Procedure

### 1. Pre-change snapshot
```bash
sudo btrfs subvolume snapshot / /.snapshots/pre-config-$(date +%Y%m%d-%H%M%S)
```

### 2. Backup current config
```bash
sudo cp /etc/openclaw/openclaw.json /etc/openclaw/openclaw.json.backup.$(date +%Y%m%d-%H%M%S)
```

### 3. Validate current config
```bash
# Check if gateway is running
sudo systemctl status openclaw-gateway.service

# Verify config is valid JSON
jq empty /etc/openclaw/openclaw.json
```

### 4. Apply configuration change
```bash
# Edit config (use prepared patch)
sudo nano /etc/openclaw/openclaw.json

# Or apply JSON patch
sudo jq '. + <patch>' /etc/openclaw/openclaw.json > /tmp/openclaw.json.new
sudo mv /tmp/openclaw.json.new /etc/openclaw/openclaw.json
```

### 5. Validate new config
```bash
# Verify JSON syntax
jq empty /etc/openclaw/openclaw.json

# Check file permissions
ls -l /etc/openclaw/openclaw.json
# Should be: -rw-r----- 1 root openclaw

# Dry-run validation (if available)
# openclaw config validate /etc/openclaw/openclaw.json
```

### 6. Restart gateway
```bash
sudo systemctl restart openclaw-gateway.service
```

### 7. Verify gateway health
```bash
# Check service status
sudo systemctl status openclaw-gateway.service

# Check logs for errors
sudo journalctl -u openclaw-gateway.service -n 50 --no-pager

# Verify gateway is responding
# (test via Feishu or API)
```

### 8. Post-change snapshot
```bash
sudo btrfs subvolume snapshot / /.snapshots/post-config-$(date +%Y%m%d-%H%M%S)
```

### 9. Vault sync
```bash
# Mount vault (if not already mounted)
sudo mount /mnt/vault

# Send incremental snapshot
sudo btrfs send -p /.snapshots/<previous> /.snapshots/post-config-<timestamp> | \
  sudo btrfs receive /mnt/vault/snapshots/

# Unmount vault
sudo umount /mnt/vault
```

### 10. Update state
Update `control/state/last-health.md` with:
- Configuration change timestamp
- Snapshot names
- Validation results
- Any issues encountered

## Rollback procedure

If gateway fails to start or behaves incorrectly:

### Option 1: Restore backup config
```bash
sudo cp /etc/openclaw/openclaw.json.backup.<timestamp> /etc/openclaw/openclaw.json
sudo systemctl restart openclaw-gateway.service
```

### Option 2: Rollback to pre-change snapshot
```bash
# Boot from pre-change snapshot
# (requires reboot and grub menu selection)
sudo reboot
# Select /.snapshots/pre-config-<timestamp> from grub menu
```

## Validation checklist
- [ ] Pre-change snapshot created
- [ ] Vault sync completed
- [ ] Current config backed up
- [ ] New config is valid JSON
- [ ] File permissions correct (root:openclaw 0640)
- [ ] Gateway restarted successfully
- [ ] Gateway responding to requests
- [ ] No errors in logs
- [ ] Post-change snapshot created
- [ ] Vault sync completed
- [ ] State files updated

## Common issues

### Gateway fails to start
- Check logs: `sudo journalctl -u openclaw-gateway.service -n 100`
- Validate config syntax: `jq empty /etc/openclaw/openclaw.json`
- Check file permissions
- Restore backup config and retry

### Config syntax error
- Use `jq` to validate before applying
- Use `jq` to pretty-print and review changes
- Keep backup config for quick restore

### Vault sync fails
- Check vault mount: `mount | grep vault`
- Check disk space: `df -h /mnt/vault`
- Check btrfs send/receive errors in logs
- Retry sync after fixing issue

## Phase 1B+ automation

When host-ops broker is available:
- This runbook becomes input to broker automation
- main agent calls broker API with config patch
- Broker executes steps automatically
- main agent monitors and reports results

## Notes
- Never skip pre-change snapshot
- Never skip vault sync
- Always validate config before restart
- Always check logs after restart
- Keep detailed notes of changes for audit trail
