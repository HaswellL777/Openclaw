# Approval Policy

## Purpose
This policy defines when human approval is required before executing operations.

## Approval categories

### Category 1: Always require pre-approval (BLOCKING)

Operations that are:
- **Destructive**: Delete files/branches, drop tables, kill processes, rm -rf, overwrite uncommitted changes
- **Hard to reverse**: Force-push, git reset --hard, amend published commits, remove/downgrade packages
- **Visible to others**: Push code, create/close PRs/issues, send messages (Slack, email, GitHub)
- **Affect shared state**: Modify shared infrastructure, permissions, CI/CD pipelines
- **In prohibited list**: Any operation listed in control/SOP.md prohibited operations section

**Required information for approval**:
- What will be changed (specific paths, commands, scope)
- Why it's needed (user request, bug fix, planned upgrade)
- Rollback plan (how to undo if something goes wrong)
- Validation checklist (how to verify success)
- Pre-change snapshot confirmation (for host mutations)

**Approval workflow**:
1. main agent identifies Category 1 operation
2. Prepare detailed approval request
3. Write to control/state/pending-approvals.json
4. Present to human via Feishu
5. Wait for explicit approval
6. If approved, proceed; if denied, explain and suggest alternatives
7. After execution, update state and report results

### Category 2: Require plan + approval (ESCALATION)

Operations that:
- Alter `/etc/openclaw/openclaw.json`
- Alter systemd units
- Alter Docker privilege boundaries
- Alter snapshot/backup behavior
- Alter secrets handling
- Modify OpenClaw gateway configuration
- Change agent definitions or tool allowlists

**Required information for approval**:
- Detailed implementation plan
- Risk assessment (what could go wrong)
- Rollback procedure (step-by-step undo)
- Validation checklist (how to verify each step)
- Pre-change snapshot confirmation
- Post-change snapshot plan
- Vault sync confirmation

**Approval workflow**:
1. main agent identifies Category 2 operation
2. Prepare comprehensive plan document
3. Write to control/state/pending-approvals.json with plan
4. Present plan to human
5. Wait for explicit approval
6. If approved, route to host-ops broker (Phase 1B+)
7. Monitor execution and report results
8. Update state files

### Category 3: Post-validation required (MONITORING)

Operations that:
- Modify configuration files (non-critical)
- Install/upgrade dependencies
- Modify CI/CD pipelines (non-production)
- Update documentation
- Publish workspace-main updates

**Required information**:
- What was changed
- Validation results (tests passed, services healthy)
- Post-change snapshot confirmation (if applicable)

**Workflow**:
1. Execute operation
2. Run validation checks
3. Update control/state/last-health.md
4. Report results to human
5. If validation fails, escalate for rollback decision

### Category 4: No approval required (AUTONOMOUS)

Operations that:
- Read files in workspace-main
- Write/edit files in workspace-main (non-control files)
- Query control files
- Update state files (routine updates)
- Create documentation
- Answer questions
- Provide information
- Are fully reversible and local

**Workflow**:
1. Execute operation
2. Update state if needed
3. Report results

## Prohibited operations (NEVER APPROVE)

These operations are NEVER allowed, even with approval:
- Run `openclaw onboard` as nick user
- Run `openclaw doctor --repair` as nick user
- Run `openclaw gateway` as nick user
- Write business config to `/var/lib/openclaw/.openclaw/openclaw.json`
- Modify `/opt/openclaw` ownership to openclaw user
- Make changes without pre-change snapshot (for host mutations)
- Use `openclaw config set` to modify configuration

See control/SOP.md for complete prohibited operations list and rationale.

## Approval request format

Write to `control/state/pending-approvals.json`:

```json
{
  "approvals": [
    {
      "id": "approval-YYYYMMDD-HHMMSS-<random>",
      "timestamp": "YYYY-MM-DD HH:MM:SS UTC",
      "category": 1 | 2 | 3,
      "operation": "Brief description",
      "details": {
        "what": "Specific changes",
        "why": "Reason",
        "scope": "Affected systems/files",
        "risk_level": "low | medium | high | critical"
      },
      "rollback_plan": "Step-by-step undo procedure",
      "validation_checklist": [
        "Check 1",
        "Check 2"
      ],
      "pre_snapshot": "snapshot-name or null",
      "status": "pending | approved | denied | completed | failed",
      "approved_by": null,
      "approved_at": null,
      "completed_at": null,
      "result": null
    }
  ]
}
```

## Phase 1A limitations

- host-ops broker not yet available → Category 2 operations cannot be fully automated
- task-runner not yet available → Some engineering tasks requiring approval cannot be delegated
- Current workaround: Present plan, get approval, suggest manual execution or wait for Phase 1B

## Approval examples

### Example 1: Delete old snapshots
- **Category**: 1 (destructive)
- **Approval required**: Yes
- **Information needed**: Which snapshots, why, how to verify no data loss
- **Workflow**: Request approval → Wait → If approved, route to broker (Phase 1B+)

### Example 2: Update OpenClaw config to add new agent
- **Category**: 2 (alter /etc/openclaw/openclaw.json)
- **Approval required**: Yes (plan + approval)
- **Information needed**: Full plan, risk assessment, rollback procedure, validation checklist
- **Workflow**: Prepare plan → Request approval → Wait → If approved, route to broker (Phase 1B+)

### Example 3: Update workspace-main control files
- **Category**: 3 (post-validation)
- **Approval required**: No (but validation required)
- **Workflow**: Make changes → Validate → Report results

### Example 4: Answer "What is the current phase?"
- **Category**: 4 (no approval)
- **Approval required**: No
- **Workflow**: Read control/SOP.md → Answer

## When in doubt

If uncertain about approval category:
1. Assume Category 1 (require approval)
2. Prepare approval request
3. Escalate to human
4. Wait for explicit guidance

Better to over-escalate than to execute risky operation without approval.
