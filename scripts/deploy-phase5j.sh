#!/usr/bin/env bash
set -euo pipefail

# deploy-phase5j.sh
# One-shot deployment script for Phase 5J changes:
#   1. Pre-change snapshot
#   2. Publish all workspace templates
#   3. Deploy gateway-rpc-tool plugin
#   4. Patch openclaw.json to enable plugin
#   5. Restart gateway
#   6. Post-change validation
#
# Usage: sudo bash scripts/deploy-phase5j.sh
# Rollback: sudo btrfs subvolume snapshot will be created before changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SNAP_LABEL="pre-phase5j-deploy"
SNAP_PATH="/.snapshots/root-${SNAP_LABEL}-$(date +%Y%m%d-%H%M)"
CONFIG_PATH="/etc/openclaw/openclaw.json"
CONFIG_BACKUP="/etc/openclaw/openclaw.json.bak-phase5j-$(date +%Y%m%d-%H%M)"
PLUGIN_SRC="$REPO_ROOT/plugins/gateway-rpc-tool"
PLUGIN_DST="/var/lib/openclaw/.openclaw/extensions/gateway-rpc-tool"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Phase 5J Deployment                                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  This script will:"
echo "    1. Create pre-change root snapshot"
echo "    2. Publish all 4 workspace templates to live"
echo "    3. Deploy gateway-rpc-tool plugin to extensions"
echo "    4. Patch openclaw.json to enable the plugin"
echo "    5. Restart openclaw-gateway"
echo "    6. Run post-deploy validation"
echo ""
echo "  Rollback: restore snapshot at $SNAP_PATH"
echo ""
read -r -p "  Continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

# ──────────────────────────────────────────────────────────────────
# Step 1: Pre-change snapshot
# ──────────────────────────────────────────────────────────────────
echo ""
info "Step 1/6: Creating pre-change root snapshot..."
if command -v btrfs &>/dev/null && [[ -d /.snapshots ]]; then
    btrfs subvolume snapshot -r / "$SNAP_PATH"
    ok "Snapshot created: $SNAP_PATH"
else
    warn "btrfs not available or /.snapshots missing — skipping snapshot"
    warn "Proceeding without snapshot. Make sure you have a backup!"
    read -r -p "  Continue without snapshot? (yes/no): " SNAP_CONFIRM
    if [[ "$SNAP_CONFIRM" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# ──────────────────────────────────────────────────────────────────
# Step 2: Publish all workspace templates
# ──────────────────────────────────────────────────────────────────
echo ""
info "Step 2/6: Publishing workspace templates..."

# Non-main workspaces: direct rsync
for ws in task-runner research-coordinator auditor; do
    TEMPLATE="$REPO_ROOT/workspace-${ws}-template"
    TARGET="/var/lib/openclaw/.openclaw/workspace-${ws}"

    if [[ ! -d "$TEMPLATE" ]]; then
        warn "Template not found: $TEMPLATE — skipping $ws"
        continue
    fi

    info "  Publishing $ws..."

    # Validate skills first
    if [[ -x "$SCRIPT_DIR/check-workspace-skills.sh" ]]; then
        "$SCRIPT_DIR/check-workspace-skills.sh" "$TEMPLATE" || {
            err "  Skill validation failed for $ws"
            exit 1
        }
    fi

    mkdir -p "$TARGET"
    rsync -av --delete \
        --exclude='knowledge/' \
        --exclude='.openclaw/' \
        --exclude='.cache/' \
        --exclude='.local/' \
        --exclude='.config/' \
        --exclude='.nv/' \
        --exclude='.ssh/' \
        --exclude='.git/' \
        --exclude='outputs/' \
        --exclude='repo/' \
        --exclude='tasks/' \
        "$TEMPLATE/" "$TARGET/"

    # Fix ownership (skip knowledge/ — read-only bind mount)
    find "$TARGET" -not -path "*/knowledge/*" \( -not -user openclaw -o -not -group openclaw \) \
        -exec chown openclaw:openclaw {} + 2>/dev/null || true

    ok "  $ws published"
done

# Main workspace: delegate to publish-workspace-main.sh
info "  Publishing main workspace..."
"$SCRIPT_DIR/publish-workspace-main.sh" --apply --allow-live-target \
    /var/lib/openclaw/.openclaw/workspace-main
ok "  main published"

# ──────────────────────────────────────────────────────────────────
# Step 3: Deploy gateway-rpc-tool plugin
# ──────────────────────────────────────────────────────────────────
echo ""
info "Step 3/6: Deploying gateway-rpc-tool plugin..."

if [[ ! -d "$PLUGIN_SRC" ]]; then
    err "Plugin source not found: $PLUGIN_SRC"
    exit 1
fi

# Verify plugin has manifest
if [[ ! -f "$PLUGIN_SRC/openclaw.plugin.json" ]]; then
    err "Plugin manifest missing: $PLUGIN_SRC/openclaw.plugin.json"
    exit 1
fi

# Remove old version if exists (don't leave .bak in extensions!)
if [[ -d "$PLUGIN_DST" ]]; then
    info "  Removing old plugin version..."
    rm -rf "$PLUGIN_DST"
fi

cp -r "$PLUGIN_SRC" "$PLUGIN_DST"
chown -R openclaw:openclaw "$PLUGIN_DST"
ok "Plugin deployed to $PLUGIN_DST"

# ──────────────────────────────────────────────────────────────────
# Step 4: Patch openclaw.json to enable plugin
# ──────────────────────────────────────────────────────────────────
echo ""
info "Step 4/6: Patching openclaw.json..."

# Backup current config
cp "$CONFIG_PATH" "$CONFIG_BACKUP"
ok "Config backed up to $CONFIG_BACKUP"

# Use python to safely patch JSON (preserves structure)
python3 - "$CONFIG_PATH" <<'PYEOF'
import json, sys

config_path = sys.argv[1]
with open(config_path, 'r') as f:
    config = json.load(f)

changed = False

# Ensure plugins section exists
if 'plugins' not in config:
    config['plugins'] = {}

# Ensure plugins.allow list includes gateway-rpc-tool
allow = config['plugins'].get('allow', [])
if 'gateway-rpc-tool' not in allow:
    allow.append('gateway-rpc-tool')
    config['plugins']['allow'] = allow
    changed = True
    print("[PATCH] Added 'gateway-rpc-tool' to plugins.allow")

# Ensure plugins.entries has the plugin enabled
entries = config['plugins'].get('entries', {})
if 'gateway-rpc-tool' not in entries:
    entries['gateway-rpc-tool'] = {"enabled": True}
    config['plugins']['entries'] = entries
    changed = True
    print("[PATCH] Added gateway-rpc-tool entry with enabled: true")

# Ensure main agent has gateway_rpc in tools.allow
agents_list = config.get('agents', {}).get('list', [])
for agent in agents_list:
    if agent.get('id') == 'main':
        tools = agent.get('tools', {})
        tools_allow = tools.get('allow', [])
        if 'gateway_rpc' not in tools_allow:
            tools_allow.append('gateway_rpc')
            tools['allow'] = tools_allow
            agent['tools'] = tools
            changed = True
            print("[PATCH] Added 'gateway_rpc' to main agent tools.allow")
        break

if changed:
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print("[OK] Config patched successfully")
else:
    print("[OK] Config already up to date — no changes needed")
PYEOF

# ──────────────────────────────────────────────────────────────────
# Step 5: Restart gateway
# ──────────────────────────────────────────────────────────────────
echo ""
info "Step 5/6: Restarting gateway..."
systemctl restart openclaw-gateway.service
sleep 3

# Check if gateway started
if systemctl is-active --quiet openclaw-gateway.service; then
    ok "Gateway restarted successfully"
else
    err "Gateway failed to start! Check: journalctl -u openclaw-gateway.service -n 30"
    err "Rollback: cp $CONFIG_BACKUP $CONFIG_PATH && systemctl restart openclaw-gateway.service"
    exit 1
fi

# ──────────────────────────────────────────────────────────────────
# Step 6: Post-deploy validation
# ──────────────────────────────────────────────────────────────────
echo ""
info "Step 6/6: Post-deploy validation..."

# Check gateway health
sleep 2
if systemctl is-active --quiet openclaw-gateway.service; then
    ok "Gateway: active"
else
    err "Gateway: inactive!"
fi

# Check GUI
if systemctl is-active --quiet openclaw-gui.service; then
    ok "GUI: active"
else
    warn "GUI: inactive (may need: sudo systemctl restart openclaw-gui.service)"
fi

# Check plugin deployed
if [[ -f "$PLUGIN_DST/openclaw.plugin.json" ]]; then
    ok "Plugin: deployed at $PLUGIN_DST"
else
    err "Plugin: missing!"
fi

# Check workspaces exist
for ws in main task-runner research-coordinator auditor; do
    target="/var/lib/openclaw/.openclaw/workspace-${ws}"
    if [[ -d "$target" ]]; then
        ok "Workspace $ws: exists"
    else
        warn "Workspace $ws: missing"
    fi
done

# ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Deployment Complete                                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Snapshot: $SNAP_PATH"
echo "  Config backup: $CONFIG_BACKUP"
echo ""
echo "  Rollback plan:"
echo "    1. cp $CONFIG_BACKUP $CONFIG_PATH"
echo "    2. rm -rf $PLUGIN_DST"
echo "    3. systemctl restart openclaw-gateway.service"
echo "    4. (optional) btrfs rollback from $SNAP_PATH"
echo ""
echo "  Next: Create cron health check job in GUI → /cron"
echo "    Name: workspace-health-check"
echo "    Schedule: 3 9 * * *"
echo "    Agent: main"
echo "    Message: Run workspace health check: verify all skills load,"
echo "             config is consistent, disk usage is normal."
echo ""
