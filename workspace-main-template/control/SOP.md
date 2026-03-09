# Host SOP (Runtime Copy)

**This is a published copy, not the authoritative source.**

**Authoritative source**: `openclaw-dev/docs/host-sop.md` (development repo)

**Last published**: [To be filled by publish-sop.sh]

**SHA256**: [To be filled by publish-sop.sh]

---

# Placeholder

This file should be populated by running:
```bash
scripts/publish-workspace-main.sh --apply <target>
```

The publish-workspace-main.sh script will automatically call publish-sop.sh to:
1. Copy content from openclaw-dev/docs/host-sop.md
2. Add SHA256 hash for version tracking
3. Add timestamp
4. Update control/state/last-sop-hash.txt

## Why this is a copy

- OpenClaw sandbox seed copy only accepts regular in-workspace files
- Symlinks to workspace-external paths are ignored
- Therefore, SOP must be published as regular file copies
- Version tracking via SHA256 ensures consistency

## When to republish

- After any change to docs/host-sop.md in development repo
- Before deploying workspace-main updates
- When control/state/last-sop-hash.txt shows mismatch
- As part of regular control plane maintenance

## Authority chain

1. `openclaw-dev/docs/host-sop.md` (authoritative source in development repo)
2. `workspace-main/control/SOP.md` (runtime copy for main agent, published artifact)
3. `tasks/<task-id>/repo/docs/host-sop.md` (task copy, if needed, Phase 2+)

All copies are published from the authoritative source via publish scripts.
