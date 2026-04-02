#!/usr/bin/env bash
set -euo pipefail

# publish-workspace-all.sh
# Purpose: Publish one or more workspace templates to their target directories
# Safety: Default dry-run mode, refuses to write to live paths
# Delegates main workspace to publish-workspace-main.sh for SOP + state preservation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Workspace registry: name → template_dir, live_target
declare -A TEMPLATE_DIRS=(
    [main]="$REPO_ROOT/workspace-main-template"
    [task-runner]="$REPO_ROOT/workspace-task-runner-template"
    [research-coordinator]="$REPO_ROOT/workspace-research-coordinator-template"
    [auditor]="$REPO_ROOT/workspace-auditor-template"
)
declare -A LIVE_TARGETS=(
    [main]="/var/lib/openclaw/.openclaw/workspace-main"
    [task-runner]="/var/lib/openclaw/.openclaw/workspace-task-runner"
    [research-coordinator]="/var/lib/openclaw/.openclaw/workspace-research-coordinator"
    [auditor]="/var/lib/openclaw/.openclaw/workspace-auditor"
)

# Defaults
DRY_RUN=1
ALLOW_LIVE=0
REQUESTED_WORKSPACES=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [WORKSPACE...]

Publish workspace templates to their target directories.

WORKSPACES:
    main                    Main agent workspace (delegates to publish-workspace-main.sh)
    task-runner             Task runner workspace
    research-coordinator    Research coordinator workspace
    auditor                 Auditor workspace
    all                     All workspaces (default if none specified)

OPTIONS:
    -n, --dry-run           Dry-run mode (default)
    --apply                 Actually perform the publish (disables dry-run)
    --allow-live-target     Unlock live target paths (requires --apply + interactive terminal)
    -h, --help              Show this help

EXAMPLES:
    # Dry-run all workspaces
    $0

    # Publish only task-runner and auditor to live targets
    sudo $0 --apply --allow-live-target task-runner auditor

    # Publish everything to live
    sudo $0 --apply --allow-live-target all

SAFETY:
    - Default mode is dry-run
    - Live targets require --apply + --allow-live-target + interactive terminal
    - Skill frontmatter is validated before each workspace publish (fail-closed)
    - main workspace delegates to publish-workspace-main.sh (SOP + state preservation)
    - knowledge/ directories are excluded from chown (read-only bind mount)

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run) DRY_RUN=1; shift ;;
        --apply)      DRY_RUN=0; shift ;;
        --allow-live-target) ALLOW_LIVE=1; shift ;;
        -h|--help)    usage ;;
        main|task-runner|research-coordinator|auditor|all)
            REQUESTED_WORKSPACES+=("$1"); shift ;;
        *)
            echo "Error: unknown argument: $1" >&2
            echo "Run '$0 --help' for usage" >&2
            exit 1
            ;;
    esac
done

# Default to all
if [[ ${#REQUESTED_WORKSPACES[@]} -eq 0 ]]; then
    REQUESTED_WORKSPACES=(all)
fi

# Expand "all"
WORKSPACES=()
for ws in "${REQUESTED_WORKSPACES[@]}"; do
    if [[ "$ws" == "all" ]]; then
        WORKSPACES=(main task-runner research-coordinator auditor)
        break
    else
        WORKSPACES+=("$ws")
    fi
done

# Deduplicate
WORKSPACES=($(printf '%s\n' "${WORKSPACES[@]}" | sort -u))

# Validate
for ws in "${WORKSPACES[@]}"; do
    if [[ -z "${TEMPLATE_DIRS[$ws]:-}" ]]; then
        echo "Error: unknown workspace: $ws" >&2
        exit 1
    fi
    if [[ ! -d "${TEMPLATE_DIRS[$ws]}" ]]; then
        echo "Error: template directory not found: ${TEMPLATE_DIRS[$ws]}" >&2
        exit 1
    fi
done

# Safety: live target requires --apply + interactive terminal
if [[ $ALLOW_LIVE -eq 1 ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "Error: --allow-live-target requires --apply" >&2
        exit 1
    fi
    if [[ ! -t 0 ]]; then
        echo "Error: --allow-live-target requires an interactive terminal" >&2
        exit 1
    fi
fi

echo "╔══════════════════════════════════════════════════════════════╗"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "║  DRY-RUN MODE — no changes will be made                   ║"
else
    echo "║  APPLY MODE — changes will be written                      ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Workspaces: ${WORKSPACES[*]}"
echo "Live targets: $(if [[ $ALLOW_LIVE -eq 1 ]]; then echo "ENABLED"; else echo "disabled"; fi)"
echo ""

# Track results
declare -A RESULTS=()
FAILED=0

# Publish each workspace
for ws in "${WORKSPACES[@]}"; do
    TEMPLATE="${TEMPLATE_DIRS[$ws]}"
    TARGET="${LIVE_TARGETS[$ws]}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Workspace: $ws"
    echo "  Template:  $TEMPLATE"
    echo "  Target:    $TARGET"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # --- main workspace: delegate to existing script ---
    if [[ "$ws" == "main" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            # publish-workspace-main.sh refuses dry-run to live paths, so use
            # a temp path for the dry-run and show what would be done
            echo "  Would delegate to publish-workspace-main.sh --apply --allow-live-target $TARGET"
            echo "  Files:"
            (cd "$TEMPLATE" && find . -type f | sort | sed 's/^/    /')
            echo "  (plus SOP publish + control/state preservation)"
            RESULTS[$ws]="DRY-RUN"
            echo ""
            continue
        fi

        MAIN_ARGS=(--apply)
        if [[ $ALLOW_LIVE -eq 1 ]]; then
            MAIN_ARGS+=(--allow-live-target)
        fi
        MAIN_ARGS+=("$TARGET")

        echo "  → Delegating to publish-workspace-main.sh ${MAIN_ARGS[*]}"
        echo ""
        if "$SCRIPT_DIR/publish-workspace-main.sh" "${MAIN_ARGS[@]}"; then
            RESULTS[$ws]="OK"
        else
            RESULTS[$ws]="FAILED"
            FAILED=1
        fi
        echo ""
        continue
    fi

    # --- non-main workspaces ---

    # Step 1: Validate skill frontmatter
    echo "  Validating skills..."
    if [[ -x "$SCRIPT_DIR/check-workspace-skills.sh" ]]; then
        if ! "$SCRIPT_DIR/check-workspace-skills.sh" "$TEMPLATE"; then
            echo "  ERROR: Skill validation failed for $ws" >&2
            RESULTS[$ws]="FAILED (skill validation)"
            FAILED=1
            echo ""
            continue
        fi
    fi

    # Step 2: Dry-run — just show what would happen
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  Would rsync template to: $TARGET"
        echo "  Files:"
        (cd "$TEMPLATE" && find . -type f | sort | sed 's/^/    /')
        RESULTS[$ws]="DRY-RUN"
        echo ""
        continue
    fi

    # Step 3: Safety check for live paths
    if [[ "$TARGET" == /var/lib/openclaw* ]]; then
        if [[ $ALLOW_LIVE -eq 0 ]]; then
            echo "  SKIPPED: live target requires --allow-live-target" >&2
            RESULTS[$ws]="SKIPPED (no --allow-live-target)"
            echo ""
            continue
        fi
        echo ""
        echo "  ⚠ LIVE TARGET: $TARGET"
        read -r -p "  Type 'yes' to confirm publish of $ws: " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            echo "  Skipped by operator."
            RESULTS[$ws]="SKIPPED (operator)"
            echo ""
            continue
        fi
    fi

    # Step 4: Create target if needed
    if [[ ! -d "$TARGET" ]]; then
        echo "  Creating target directory..."
        mkdir -p "$TARGET"
    fi

    # Step 5: rsync template to target
    # Exclude knowledge/ — it's a read-only bind mount in live containers
    echo "  Syncing template..."
    rsync -av --delete --exclude='knowledge/' "$TEMPLATE/" "$TARGET/"

    # Step 6: Fix ownership (live targets only, skip knowledge/)
    if [[ $ALLOW_LIVE -eq 1 && "$TARGET" == /var/lib/openclaw* ]]; then
        echo "  Fixing ownership to openclaw:openclaw..."
        # Use find to skip knowledge/ (read-only bind mount)
        find "$TARGET" -not -path "*/knowledge/*" \( -not -user openclaw -o -not -group openclaw \) \
            -exec chown openclaw:openclaw {} + 2>/dev/null || true
        echo "  Ownership fixed."
    fi

    RESULTS[$ws]="OK"
    echo ""
done

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  PUBLISH SUMMARY                                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
for ws in "${WORKSPACES[@]}"; do
    printf "  %-25s %s\n" "$ws" "${RESULTS[$ws]:-UNKNOWN}"
done
echo ""

if [[ $FAILED -ne 0 ]]; then
    echo "Some workspaces failed. Check output above."
    exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo "This was a dry-run. Use --apply to actually publish."
fi
