# Approvals Skill

## Skill identity
- **Name**: `approvals`
- **Owner**: `main` agent
- **Purpose**: Determine when human approval is required before action

## What this skill does
This skill defines approval requirements for different operation categories:
- Which operations require pre-approval?
- Which operations require post-validation?
- What information must be provided for approval?
- What rollback plan must be prepared?

## Authority
The authoritative approval policy is `control/approval-policy.md`.

This skill should:
1. Reference `control/approval-policy.md` for approval requirements
2. Check `control/state/pending-approvals.json` for approval queue
3. Update pending-approvals.json when requesting approval
4. Never skip approval for Category 1 or 2 operations
5. Always provide complete information for approval decisions

## Approval categories

### Category 1: Always require pre-approval (BLOCKING)
- Destructive operations
- Hard to reverse operations
- Visible to others
- Affect shared state
- In prohibited list

**Workflow**:
1. Identify Category 1 operation
2. Prepare approval request with: what, why, rollback plan, validation checklist
3. Write to control/state/pending-approvals.json
4. Present to human via Feishu
5. Wait for explicit approval
6. If approved, proceed; if denied, explain and suggest alternatives

### Category 2: Require plan + approval (ESCALATION)
- Alter /etc/openclaw/openclaw.json
- Alter systemd units
- Alter Docker privilege boundaries
- Alter snapshot/backup behavior
- Alter secrets handling

**Workflow**:
1. Identify Category 2 operation
2. Prepare comprehensive plan with: detailed plan, risk assessment, rollback procedure, validation checklist
3. Write to control/state/pending-approvals.json with plan
4. Present plan to human
5. Wait for explicit approval
6. If approved, route to host-ops broker (Phase 1B+)

### Category 3: Post-validation required (MONITORING)
- Modify configuration files (non-critical)
- Install/upgrade dependencies
- Update documentation

**Workflow**:
1. Execute operation
2. Run validation checks
3. Update control/state/last-health.md
4. Report results to human

### Category 4: No approval required (AUTONOMOUS)
- Read files in workspace-main
- Write/edit files in workspace-main (non-control files)
- Query control files
- Answer questions

**Workflow**:
1. Execute operation
2. Update state if needed

## Prohibited operations (NEVER APPROVE)
See control/SOP.md for complete list. These are NEVER allowed, even with approval:
- Run openclaw onboard as nick user
- Run openclaw doctor --repair as nick user
- Write business config to /var/lib/openclaw/.openclaw/openclaw.json
- Modify /opt/openclaw ownership to openclaw user
- Make changes without pre-change snapshot (for host mutations)

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
      "validation_checklist": ["Check 1", "Check 2"],
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

## Usage patterns

### Example 1: "Delete old snapshots"
- **Category**: 1 (destructive)
- **Approval required**: Yes
- **Action**: Prepare approval request with: which snapshots, why, how to verify no data loss, rollback plan (restore from vault)

### Example 2: "Update OpenClaw config to add new agent"
- **Category**: 2 (alter /etc/openclaw/openclaw.json)
- **Approval required**: Yes (plan + approval)
- **Action**: Prepare comprehensive plan with risk assessment, rollback procedure, validation checklist

### Example 3: "Update workspace-main control files"
- **Category**: 3 (post-validation)
- **Approval required**: No (but validation required)
- **Action**: Make changes, validate, report results

### Example 4: "What is the current phase?"
- **Category**: 4 (no approval)
- **Approval required**: No
- **Action**: Read control/SOP.md and answer

## When in doubt
If uncertain about approval category:
1. Assume Category 1 (require approval)
2. Prepare approval request
3. Escalate to human
4. Wait for explicit guidance

Better to over-escalate than to execute risky operation without approval.

## Phase 1A limitations
- host-ops broker not yet available → Category 2 operations cannot be fully automated
- task-runner not yet available → Some engineering tasks requiring approval cannot be delegated
- Current workaround: Present plan, get approval, suggest manual execution or wait for Phase 1B

## Related skills
- `host-sop`: Provides prohibited operations list
- `routing`: Determines execution context before approval check
- `broker`: Execution target for approved host mutations (Phase 1B+)

## Safety notes
- Always check approval requirements before acting
- Never skip approval for Category 1 or 2 operations
- Always provide complete information for approval decisions
- Always prepare rollback plan before requesting approval
- When in doubt, require approval
