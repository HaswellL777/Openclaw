# Phase 1 Main Agent Delta

## Scope
Phase 1A: main bootstrap only (no host_ops broker)

## Change summary
Add `main` agent to OpenClaw config with minimal control-plane permissions.

## Exact merge points

### 1. `agents.defaults.subagents` (new keys)
**Location**: `agents.defaults.subagents`
**Action**: Add new keys to existing object

```json5
subagents: {
  maxConcurrent: 8,  // ← existing
  // ── Phase 1 additions ──
  maxSpawnDepth: 2,
  maxChildrenPerAgent: 3,
  runTimeoutSeconds: 3600,
  archiveAfterMinutes: 120,
}
```

### 2. `agents.list` (new array)
**Location**: `agents.list`
**Action**: Create new top-level key under `agents`

**Current state**: `agents.list` does not exist in live config
**New state**: Add entire `agents.list` array with single `main` agent entry

```json5
agents: {
  defaults: { /* existing */ },
  // ── Phase 1 addition ──
  list: [
    {
      id: "main",
      default: true,
      workspace: "/var/lib/openclaw/.openclaw/workspace-main",
      subagents: {
        allowAgents: ["task-runner"],
      },
      tools: {
        allow: [
          "read",
          "write",
          "edit",
          "sessions_list",
          "sessions_history",
          "sessions_send",
          "sessions_spawn",
          "session_status",
        ],
        deny: [
          "exec",
          "process",
          "apply_patch",
          "elevated",
        ],
        elevated: { enabled: false },
      },
    },
  ],
}
```

## What is NOT changed
- `gateway`: unchanged
- `models`: unchanged
- `agents.defaults.model`: unchanged
- `agents.defaults.models` (aliases): unchanged
- `agents.defaults.workspace`: unchanged (still points to `/var/lib/openclaw/.openclaw/workspace`)
- `agents.defaults.compaction`: unchanged
- `agents.defaults.maxConcurrent`: unchanged
- `tools`: unchanged
- `messages`: unchanged
- `commands`: unchanged
- `session`: unchanged
- `channels`: unchanged
- `plugins`: unchanged
- `logging`: unchanged
- `hooks`: unchanged

## Schema alignment
- Live structure alignment: verified against `/etc/openclaw/openclaw.json`
- Gateway schema acceptance: newly added fields (`agents.list`, `agents.defaults.subagents` extensions) require deployment-time validation to confirm gateway accepts them without error

## Key design decisions

### 1. main has no exec/elevated
`main` is explicitly denied:
- `exec` (no arbitrary shell commands)
- `process` (no process management)
- `apply_patch` (no direct file patching)
- `elevated` (no privilege escalation)

### 2. main can only spawn task-runner
`subagents.allowAgents: ["task-runner"]` restricts main to only spawn the approved worker agent (Phase 3).

### 3. main workspace is separate
`workspace: "/var/lib/openclaw/.openclaw/workspace-main"` isolates main's control files from default workspace.

### 4. host_ops commented out
`host_ops` tool is commented out in the allow list. It will be enabled in Phase 2 after broker implementation.

## Pre-deployment checklist

### Before applying this candidate:
1. ✅ Verify live config at `/etc/openclaw/openclaw.json` matches `candidates/openclaw.live.json`
2. ✅ Create pre-change snapshot BEFORE any host-side writes:
   ```bash
   sudo btrfs subvolume snapshot -r / "/.snapshots/root-pre-main-agent-$(date +%F-%H%M)"
   sudo /usr/local/sbin/vault-backup-root-btrfs
   ```
   **Note**: `/var/lib/openclaw` is a separate btrfs subvolume and is NOT included in root snapshots. Root snapshots capture `/etc/openclaw/openclaw.json` but not runtime workspace state.
3. ⚠️ Create workspace-main directory structure:
   ```bash
   sudo install -d -m 0700 -o openclaw -g openclaw /var/lib/openclaw/.openclaw/workspace-main
   ```
4. ⚠️ Publish workspace-main template files from `workspace-main/*` to `/var/lib/openclaw/.openclaw/workspace-main/`
   **Note**: workspace-main is a reproducible published artifact, not something root snapshots will restore. Treat it as deployment output, not persistent state.
5. ⚠️ Publish SOP from authority source to `workspace-main/control/SOP.md`

### After applying this candidate:
1. ⚠️ Restart gateway:
   ```bash
   sudo systemctl restart openclaw-gateway.service
   ```
2. ⚠️ Health check with retry (see SOP 13.2)
3. ⚠️ Verify main agent is default:
   ```bash
   sudo journalctl -u openclaw-gateway.service -n 50 --no-pager | grep -i "agent.*main"
   ```
4. ⚠️ Test main agent via Feishu (send a simple message, verify response)
5. ⚠️ Verify main cannot exec:
   ```
   # In Feishu, ask main to run a shell command
   # Expected: tool denied or not available
   ```
6. ✅ Create post-change snapshot:
   ```bash
   sudo btrfs subvolume snapshot -r / "/.snapshots/root-post-main-agent-$(date +%F-%H%M)"
   sudo /usr/local/sbin/vault-backup-root-btrfs
   ```

## Rollback procedure
If main agent causes issues:

1. Stop gateway:
   ```bash
   sudo systemctl stop openclaw-gateway.service
   ```

2. Restore previous config:
   ```bash
   sudo cp /etc/openclaw/openclaw.json /etc/openclaw/openclaw.json.main-failed
   sudo cp candidates/openclaw.live.json /etc/openclaw/openclaw.json
   ```

3. Restart gateway:
   ```bash
   sudo systemctl start openclaw-gateway.service
   ```

4. Verify health (SOP 13.2)

5. If needed, rollback to pre-change snapshot (SOP 13.8.1)

## Phase 2 preview
Next phase will add:
- `host_ops` tool to main's allow list
- `host-ops` plugin implementation
- broker service and wrappers
- structured host-side action approval chain
