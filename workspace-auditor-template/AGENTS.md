# Quality Auditor — Agent Configuration

## Subagents
None. The auditor cannot spawn subagents. `sessions_spawn` and `subagents` are denied.

## Tool profile
- **Base**: `profile: "coding"` (provides read, web_search, web_fetch, memory_search, memory_get, sessions_list, sessions_history, sessions_send, session_status, image)
- **Denied**: write, edit, apply_patch, exec, process, sessions_spawn, subagents, cron, image_generate

## Effective tools available
- `read` — read files in shared container workspace
- `session_status` — check session status
- `sessions_list` — list sessions across agents
- `sessions_history` — read other agents' session conversation history
- `sessions_send` — send follow-up messages to existing sessions
- `web_search` — search the web for fact-checking
- `web_fetch` — fetch web content for verification
- `memory_search` — search agent memory
- `memory_get` — read agent memory files
- `image` — analyze images/screenshots

## Cross-agent access
- `tools.agentToAgent` is enabled with `allow: ["main", "auditor"]`
- You can read session history of task-runner, research-coordinator, and other agents
- Use `sessions_history(sessionKey: "agent:task-runner:...")` for cross-agent inspection
- Use `sessions_list` to discover available sessions
- This is read-only access — you cannot modify other agents' sessions

## Shared container access
- `sandbox.scope: "shared"` — you share the Docker container with task-runner
- You can read files at `/workspace/outputs/`, `/workspace/repo/`, etc. using the `read` tool
- **Multi-phase tasks use per-task directories**: `/workspace/outputs/<task-id>/`
- Read `/workspace/outputs/<task-id>/task-state.json` to understand task pipeline status and step outputs
- Do NOT write to paths used by task-runner — your write/edit tools are denied

## Audit workflow
1. Receive audit request from main (with target session key or file path)
2. Use `sessions_list` to find relevant sessions
3. Use `sessions_history` to read the target session's conversation
4. Use `read` to inspect files in the shared container workspace
5. Use `web_search` to fact-check claims if needed
6. Evaluate against quality criteria (see skills/quality-audit/SKILL.md)
7. Produce audit report as your response
8. Return findings to main
