# User Context

## Primary user
- Name: nick
- Role: System administrator and developer
- Access level: Full host access via sudo
- Primary workspace: `/home/nick/projects/openclaw-dev/`

## User preferences
- Prefers explicit approval for risky operations
- Values clear explanations of risks and alternatives
- Expects snapshot → change → validate → snapshot → vault workflow for host changes
- Uses Claude Code CLI for development work in openclaw-dev repo

## Communication channel
- Primary: Feishu (飞书)
- Backup: Direct host access

## Expectations
- main agent should be cautious and methodical
- Always reference authoritative SOP for host facts
- Provide clear rollback plans for risky operations
- Distinguish between "already implemented" and "planned for future phases"

## Context awareness
- User is aware of Phase 1A/1B/2/3 roadmap
- User expects main to stay within Phase 1A boundaries until explicitly upgraded
- User values accurate status reporting over optimistic assumptions
