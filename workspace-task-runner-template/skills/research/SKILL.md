---
name: research
description: |
  Conduct technical research via web search, documentation reading, and summarization.
---

# Research Skill

## Skill identity
- **Name**: `research`
- **Owner**: `task-runner`
- **Purpose**: Conduct technical research via web search, documentation reading, and summarization
- **Status**: operational

## Prerequisites
- Network access via openclaw-task-net
- curl available in container
- /workspace/knowledge/ for reference repos (if mounted)

## What this skill does
Researches technical topics by searching the web, reading documentation,
analyzing reference codebases in /workspace/knowledge/, and producing
structured summaries. Useful for technology evaluation, API documentation
lookup, and competitive analysis.

## When to use this skill
- User asks for technology comparison or evaluation
- Task requires understanding an unfamiliar API or library
- Need to verify current best practices or find solutions

## Workflow
1. Clarify research question from task inputs
2. Search web for relevant sources
3. Read and analyze reference repos in /workspace/knowledge/ (if relevant)
4. Cross-reference multiple sources
5. Write structured research report to /workspace/outputs/

## Output format
Research report in /workspace/outputs/research-report.md:
```markdown
# Research: <topic>

## Question
<research question>

## Findings
<structured findings with source citations>

## Recommendation
<actionable recommendation with reasoning>

## Sources
- [Source 1](url)
- [Source 2](url)
```

## Safety rules
- Cite all sources
- Distinguish between verified facts and inference
- Do not access authenticated or private resources
- Respect robots.txt and Terms of Service of target sites
