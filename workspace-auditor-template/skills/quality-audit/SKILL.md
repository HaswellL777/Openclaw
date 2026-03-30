---
name: quality-audit
description: |
  Independently evaluate agent work products for quality, accuracy, and completeness.
---

# Quality Audit Skill

## Skill identity
- **Name**: `quality-audit`
- **Owner**: `auditor`
- **Purpose**: Independently evaluate agent work products for quality, accuracy, and completeness

## When to use this skill
- After a research phase completes (audit research-coordinator's findings)
- After code generation (audit task-runner's code output)
- After report generation (audit factual claims and completeness)
- Periodically during long-running tasks (progress quality check)

## Audit dimensions

### 1. Code Quality (for code outputs)
- Correctness: does the code do what it claims?
- Error handling: are edge cases addressed?
- Security: any obvious vulnerabilities (injection, hardcoded secrets)?
- Style: consistent formatting, meaningful names?
- Tests: are there tests? Do they cover key paths?

### 2. Research Accuracy (for research outputs)
- Source verification: are citations real and accessible?
- Claim accuracy: do the cited sources actually support the claims made?
- Completeness: are important perspectives or sources missing?
- Recency: is the information current or outdated?
- Methodology: was the search/analysis approach sound?

### 3. Output Completeness (for deliverables)
- Requirements met: does the output address all stated requirements?
- Format compliance: correct structure, headings, sections?
- Actionability: are recommendations specific and implementable?
- Gaps: what was asked for but not delivered?

### 4. Process Quality (for workflows)
- Was the experiment-loop pattern followed correctly?
- Were results properly tracked (experiments.tsv, research-state.md)?
- Were failures properly documented and learned from?
- Were safety rules respected (no data fabrication, read-only knowledge)?

## Audit report format

```markdown
# Audit Report: [Target Description]
## Date: YYYY-MM-DD
## Target: [session key / file path / phase name]
## Auditor: auditor agent

## Summary
[1-2 sentence overall assessment]

## Findings

### CRITICAL
- [finding]: [evidence] → [recommendation]

### WARNING
- [finding]: [evidence] → [recommendation]

### INFO
- [finding]: [evidence] → [recommendation]

## Metrics
- Items reviewed: N
- Critical findings: N
- Warnings: N
- Overall quality: [PASS / PASS_WITH_WARNINGS / FAIL]
```

## Evidence standards
- Every finding must cite a specific source (file:line, session excerpt, URL)
- Do not make claims without evidence
- If you cannot verify something, mark it as "UNVERIFIED" not "incorrect"
- Use web_search to fact-check claims when sources are publicly accessible
