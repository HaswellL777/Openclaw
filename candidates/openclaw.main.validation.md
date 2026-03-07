# Phase 1 Main Agent Validation Checklist

## Scope
Phase 1A: main bootstrap only (no host_ops broker)

## Pre-deployment validation

### 1. Config structure verification
- [ ] Live config at `/etc/openclaw/openclaw.json` matches `candidates/openclaw.live.json`
- [ ] Candidate config at `candidates/openclaw.main.candidate.json5` is valid JSON5
- [ ] No syntax errors in candidate (trailing commas, quotes, braces)
- [ ] All environment variable references preserved: `${OPENCLAW_GATEWAY_TOKEN}`, `${DEEPSEEK_API_KEY}`, `${FEISHU_APP_SECRET}`, `${MOTCHAT_API_KEY}`

### 2. Workspace preparation
- [ ] Directory `/var/lib/openclaw/.openclaw/workspace-main` created with mode 0700, owner openclaw:openclaw
- [ ] **Important**: workspace-main is a reproducible published artifact, not something root snapshots will restore. Treat it as deployment output.
- [ ] Template files published from `workspace-main/*` to workspace-main directory:
  - [ ] `AGENTS.md`
  - [ ] `TOOLS.md`
  - [ ] `IDENTITY.md`
  - [ ] `SOUL.md`
  - [ ] `USER.md`
  - [ ] `HEARTBEAT.md`
  - [ ] `control/SOP.md`
  - [ ] `control/routing-policy.md`
  - [ ] `control/approval-policy.md`
  - [ ] `control/allowed-workers.md`
  - [ ] `control/host-ops-api.md`
  - [ ] `control/state/` directory structure
  - [ ] `control/runbooks/` directory structure
  - [ ] `skills/` directory structure
- [ ] All workspace-main files owned by openclaw:openclaw
- [ ] SOP published from authority source (`/srv/openclaw-control/docs/host-sop.md` or equivalent) to `workspace-main/control/SOP.md`
- [ ] SOP hash recorded in `workspace-main/control/state/last-sop-hash.txt`

### 3. Snapshot preparation
- [ ] Pre-change snapshot created BEFORE any host-side writes (including workspace-main creation): `/.snapshots/root-pre-main-agent-YYYY-MM-DD-HHMM`
- [ ] Pre-change snapshot is read-only (verify with `sudo btrfs property get`)
- [ ] Pre-change snapshot sent to Vault: `system/root-auto-YYYY-MM-DD-HHMM`
- [ ] Vault unmounted after backup: `findmnt /mnt/vault` returns empty
- [ ] `last_sent` updated in `/var/lib/openclaw/backup/last_sent`
- [ ] **Important**: `/var/lib/openclaw` is a separate btrfs subvolume and is NOT included in root snapshots. Root snapshots capture `/etc/openclaw/openclaw.json` but not runtime workspace state.

### 4. Safety checks
- [ ] No user-level gateway running (port 18789 not listening)
- [ ] System gateway is active: `sudo systemctl is-active openclaw-gateway.service` returns `active`
- [ ] Current config passes health check (SOP 13.2)
- [ ] Feishu channel is connected and responsive
- [ ] No pending config changes in `/var/lib/openclaw/.openclaw/openclaw.json` (state dir should not have config)

## Deployment validation

### 5. Config merge verification
- [ ] Candidate config copied to `/etc/openclaw/openclaw.json`
- [ ] File permissions: 0640 root:openclaw
- [ ] Syntax check: `sudo -u openclaw node -e "require('/etc/openclaw/openclaw.json')"` (if using .js) or manual JSON5 validation
- [ ] Diff review: `sudo diff -u candidates/openclaw.live.json /etc/openclaw/openclaw.json` shows only expected changes

### 6. Gateway restart
- [ ] Gateway stopped cleanly: `sudo systemctl stop openclaw-gateway.service`
- [ ] No orphaned processes: `pgrep -f openclaw` returns empty
- [ ] Gateway started: `sudo systemctl start openclaw-gateway.service`
- [ ] Gateway status is active: `sudo systemctl is-active openclaw-gateway.service`
- [ ] No crash loop: `sudo journalctl -u openclaw-gateway.service -n 50 --no-pager` shows successful startup

### 7. Health check (with retry)
- [ ] Health check passes within 20 attempts (SOP 13.2 retry template)
- [ ] Gateway WebSocket listening on 127.0.0.1:17777
- [ ] Gateway HTTP listening on 127.0.0.1:17779
- [ ] No error 97 (AF_NETLINK) in logs
- [ ] No plugin manifest errors in logs
- [ ] No Zod schema validation errors in logs (validates gateway schema acceptance of newly added fields)

### 8. Agent registration verification
- [ ] Logs show "agent registered: main" or similar
- [ ] Logs show main agent workspace: `/var/lib/openclaw/.openclaw/workspace-main`
- [ ] Logs show main is default agent
- [ ] No errors about missing workspace files
- [ ] Feishu channel reconnected successfully

## Functional validation

### 9. Main agent basic functionality
- [ ] Send simple message to main via Feishu: "hello"
- [ ] Main responds (not error/timeout)
- [ ] Main can read its own workspace files
- [ ] Main can write to its own workspace (test with simple file creation request)

### 10. Main agent permission boundaries
- [ ] Main CANNOT execute shell commands (test: ask main to run `ls`)
  - Expected: tool denied, not available, or explicit refusal
- [ ] Main CANNOT use elevated tools (test: ask main to use sudo)
  - Expected: tool denied or not available
- [ ] Main CANNOT apply patches directly (test: ask main to apply a patch)
  - Expected: tool denied or not available
- [ ] Main CAN read files in its workspace
- [ ] Main CAN write files in its workspace
- [ ] Main CAN list sessions (if sessions exist)

### 11. Main agent SOP awareness
- [ ] Ask main: "What is the host SOP?"
- [ ] Main should reference or read `control/SOP.md`
- [ ] Main should demonstrate awareness of host constraints (no direct exec, no Vault access, etc.)

### 12. Main agent routing awareness
- [ ] Ask main: "What workers can you spawn?"
- [ ] Main should reference `task-runner` (even though it doesn't exist yet in Phase 1)
- [ ] Main should NOT attempt to spawn task-runner (it's not defined yet)
- [ ] Main should explain it can route tasks to approved workers

## Post-deployment validation

### 13. Snapshot and audit
- [ ] Post-change snapshot created: `/.snapshots/root-post-main-agent-YYYY-MM-DD-HHMM`
- [ ] Post-change snapshot is read-only
- [ ] Post-change snapshot sent to Vault: `system/root-auto-YYYY-MM-DD-HHMM`
- [ ] Vault unmounted after backup
- [ ] `last_sent` updated
- [ ] Deployment notes recorded in SOP change log (section 15)

### 14. Stability check (24-hour soak)
- [ ] Gateway remains active for 24 hours without crash
- [ ] No memory leaks observed: `ps aux | grep openclaw` shows stable RSS
- [ ] No log spam or repeated errors
- [ ] Feishu channel remains connected
- [ ] Main agent responds consistently to test messages

### 15. Rollback readiness
- [ ] Rollback procedure documented in `openclaw.main.delta.md`
- [ ] Pre-change snapshot verified accessible: `sudo btrfs subvolume list /.snapshots | grep pre-main-agent`
- [ ] Backup config saved: `candidates/openclaw.live.json` preserved
- [ ] Team aware of rollback procedure

## Failure modes and responses

### If health check fails after restart:
1. Check logs: `sudo journalctl -u openclaw-gateway.service -n 100 --no-pager`
2. Look for:
   - Syntax errors in config
   - Missing workspace directory
   - Permission errors (openclaw user cannot read workspace-main)
   - Plugin errors
   - Schema validation errors
3. If unfixable within 5 minutes, execute rollback procedure

### If main agent doesn't respond:
1. Verify agent registered: `sudo journalctl -u openclaw-gateway.service | grep -i "agent.*main"`
2. Verify workspace exists and is readable by openclaw user
3. Verify workspace files (AGENTS.md, TOOLS.md) are present
4. Check for errors in agent bootstrap: `sudo journalctl -u openclaw-gateway.service | grep -i bootstrap`
5. If unfixable, execute rollback procedure

### If main agent has unexpected permissions:
1. Verify tools.deny list in config
2. Verify elevated.enabled is false
3. Test specific denied tools (exec, process, apply_patch)
4. If main can execute shell commands, IMMEDIATELY execute rollback procedure (security boundary violated)

### If Feishu disconnects:
1. Check if issue is Feishu-specific or gateway-wide
2. Verify channels.feishu config unchanged
3. Verify `${FEISHU_APP_SECRET}` still resolves correctly
4. Check Feishu webhook/websocket logs
5. If Feishu worked before change and fails after, consider rollback

## Sign-off

### Pre-deployment sign-off
- [ ] All pre-deployment validation items checked
- [ ] Workspace-main prepared and verified
- [ ] Pre-change snapshot created and sent to Vault
- [ ] Rollback procedure understood and documented
- [ ] Deployment window scheduled (low-traffic time recommended)

**Signed**: ________________  **Date**: ________________

### Post-deployment sign-off
- [ ] All deployment validation items checked
- [ ] All functional validation items checked
- [ ] Post-change snapshot created and sent to Vault
- [ ] Main agent functional and permission-bounded
- [ ] No security boundary violations observed
- [ ] 24-hour stability check passed (or scheduled)

**Signed**: ________________  **Date**: ________________

## Notes and observations
(Record any unexpected behavior, warnings, or deviations from expected results)

---

**Phase 1 validation complete**: Main agent deployed with minimal control-plane permissions, no direct exec, no elevated capability, ready for Phase 2 broker integration.
