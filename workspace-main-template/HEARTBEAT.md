# Heartbeat and Health Monitoring

## Purpose
This file defines how main agent monitors and reports system health.

## Health check frequency
- On startup: Always read control/state/last-health.md
- On user request: Run health check and update state
- After significant events: Update health state
- Periodic: Not yet implemented (Phase 1B+)

## Health check components

### Control plane health
- Can read control/SOP.md?
- Can read all policy files?
- Can write to control/state/?
- Are all required control files present?

### SOP version tracking
- Read control/SOP.md
- Compute SHA256 hash
- Compare with control/state/last-sop-hash.txt
- If changed, note in health report

### Workspace integrity
- Are all required directories present?
- Are all required files present?
- Are skills definitions valid?
- Are state files parseable?

### Subagent availability (Phase 1B+)
- Is task-runner available?
- Is host-ops broker available?

## Health report format
Write to `control/state/last-health.md`:

```markdown
# Health Check Report

**Timestamp**: YYYY-MM-DD HH:MM:SS UTC
**Status**: healthy | degraded | unhealthy

## Control Plane
- SOP readable: yes/no
- SOP hash: <sha256>
- SOP changed since last check: yes/no
- Policy files readable: yes/no
- State files writable: yes/no

## Workspace Integrity
- Required directories: present/missing
- Required files: present/missing
- Skills valid: yes/no

## Subagents (Phase 1B+)
- task-runner: available/unavailable
- host-ops broker: available/unavailable

## Issues
- List any issues found
- Suggest remediation if known

## Recommendations
- List any recommended actions
```

## When to report unhealthy
- Cannot read control/SOP.md
- Cannot write to control/state/
- Required control files missing
- SOP hash mismatch without explanation

## When to report degraded
- Optional features unavailable
- Subagents not yet deployed (expected in Phase 1A)
- Non-critical files missing

## Escalation
If unhealthy:
1. Report to user immediately
2. Do not proceed with risky operations
3. Suggest remediation steps
4. Wait for human intervention
