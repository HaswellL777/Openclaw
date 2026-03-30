# Runbook: Gateway Restart

## Purpose
Safe procedure for restarting openclaw-gateway.service

## Prerequisites
- Reason for restart documented
- No critical operations in progress
- Backup plan if restart fails

## Procedure

### 1. Check current status
```bash
sudo systemctl status openclaw-gateway.service
```

### 2. Check for active sessions
```bash
# List active OpenClaw sessions (if CLI available)
# openclaw sessions list

# Check process tree
ps aux | grep openclaw
```

### 3. Graceful restart
```bash
sudo systemctl restart openclaw-gateway.service
```

### 4. Verify restart
```bash
# Check service status
sudo systemctl status openclaw-gateway.service

# Check logs
sudo journalctl -u openclaw-gateway.service -n 50 --no-pager

# Verify process is running
ps aux | grep openclaw-gateway
```

### 5. Test connectivity
```bash
# Test via Feishu message
# Send test message to main agent

# Or check gateway port (if exposed)
# curl http://localhost:<port>/health
```

### 6. Update state
Update `control/state/last-health.md` with:
- Restart timestamp
- Reason for restart
- Validation results
- Any issues encountered

## Rollback procedure

If gateway fails to start:

### 1. Check logs for errors
```bash
sudo journalctl -u openclaw-gateway.service -n 100 --no-pager
```

### 2. Check configuration
```bash
jq empty /etc/openclaw/openclaw.json
```

### 3. Check file permissions
```bash
ls -l /etc/openclaw/
ls -l /var/lib/openclaw/
```

### 4. Check disk space
```bash
df -h /var/lib/openclaw
```

### 5. Attempt manual start for debugging
```bash
# Stop service
sudo systemctl stop openclaw-gateway.service

# Run manually to see errors
sudo -u openclaw /opt/openclaw/bin/openclaw gateway
```

### 6. If still failing, rollback to previous snapshot
See `rollback.md` runbook

## Validation checklist
- [ ] Current status checked
- [ ] Active sessions noted
- [ ] Service restarted successfully
- [ ] No errors in logs
- [ ] Process running
- [ ] Connectivity verified
- [ ] State files updated

## Common issues

### Service fails to start
- Check config syntax: `jq empty /etc/openclaw/openclaw.json`
- Check file permissions
- Check disk space
- Check logs for specific error

### Service starts but not responding
- Check network configuration
- Check firewall rules
- Check upstream provider connectivity
- Check logs for connection errors

### Active sessions lost
- Expected behavior on restart
- Sessions should reconnect automatically
- If not, may need to restart from main agent side

## Broker automation (operational)

Host-ops broker is available (since 2026-03-17):
- main agent calls broker API for gateway restart
- Broker executes steps automatically
- main agent monitors and reports results

## Notes
- Gateway restart is generally safe
- Active sessions may be interrupted
- Restart should complete in < 30 seconds
- If restart takes longer, investigate logs
