# Research Orchestration Skill

## Skill identity
- **Name**: `research-orchestration`
- **Owner**: `research-coordinator`
- **Purpose**: Manage long-running, multi-phase research tasks with iterative feedback loops

## When to use this skill
- Operator assigns a complex research goal (literature survey, technology evaluation, etc.)
- Task requires multiple data-collection and analysis phases
- Task spans multiple sessions and needs persistent state tracking

## Workflow

### Phase 1: Scoping
1. Understand the research goal and success criteria
2. Identify information sources (web, knowledge repos, code repos)
3. Break goal into 3-5 concrete sub-tasks with measurable deliverables
4. Write initial plan to `/workspace/outputs/research-plan.md`

### Phase 2: Data Collection
1. Spawn task-runner sessions for each data-collection sub-task:
   - Literature search (Scrapling, web_search)
   - Code repository analysis (git clone, code reading)
   - Dataset exploration (Python data analysis)
2. Track progress in `/workspace/outputs/research-state.md`
3. Collect results in `/workspace/outputs/data/`

### Phase 3: Analysis & Synthesis
1. Review collected data (task-runner for computation, report to main for ACP if deep reasoning needed)
2. Identify patterns, gaps, and key findings
3. Update research-state.md with analysis results

### Phase 4: Report Generation
1. Spawn task-runner to generate structured report
2. Report format: `/workspace/outputs/research-report.md`
3. Include: executive summary, methodology, findings, recommendations, references

### Phase 5: Iteration (if needed)
1. Based on findings, identify follow-up questions
2. Return to Phase 2 with refined scope
3. Update research-state.md with iteration notes

## State tracking format

`/workspace/outputs/research-state.md`:
```markdown
# Research: [Goal]
## Status: [scoping|collecting|analyzing|reporting|complete]
## Phases completed: [list]
## Current phase: [name]
## Sub-tasks:
- [ ] task description (session: key, status: pending|running|done)
## Key findings so far:
- finding 1
## Open questions:
- question 1
## Next steps:
- step 1
```

## Safety rules
- Do not fabricate data or citations — only report what task-runner actually found
- Track all sources with URLs/paths
- If uncertain about a finding, flag it as "needs verification"
- Do not modify knowledge repos (read-only mounts)
