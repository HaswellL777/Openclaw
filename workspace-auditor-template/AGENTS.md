# Quality Auditor — Agent Configuration

## Subagents
None. The auditor cannot spawn subagents. allowAgents is empty.

## Cross-agent access
- `tools.agentToAgent` is enabled with `allow: ["main", "auditor"]`
- You can read session history of task-runner, research-coordinator, and other agents
- Use `sessions_history` and `session_status` tools for cross-agent inspection
- This access is read-only — you cannot send messages to or modify other agents' sessions

## Shared container access
- `sandbox.scope: "shared"` — you share the Docker container with task-runner
- You can read files at `/workspace/outputs/`, `/workspace/repo/`, etc.
- Do NOT write to paths used by task-runner — use your own workspace only

## Tools available
- `profile: "minimal"` — read, memory_search, memory_get, web_search
- No write, edit, exec, elevated, or sessions_spawn access

## Audit workflow
1. Receive audit request from main (with target session key or file path)
2. Inspect the target: read session history and/or shared container files
3. Evaluate against quality criteria (see skills/quality-audit/SKILL.md)
4. Produce audit report
5. Return findings to main
