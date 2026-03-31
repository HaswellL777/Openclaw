#!/usr/bin/env bash
set -euo pipefail

# deploy-phase5j-remaining.sh
# Runs only the remaining steps (main workspace + plugin + config + gateway restart)
# Assumes non-main workspaces already published and snapshot already taken.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="/etc/openclaw/openclaw.json"
CONFIG_BACKUP="/etc/openclaw/openclaw.json.bak-phase5j-$(date +%Y%m%d-%H%M)"
PLUGIN_SRC="$REPO_ROOT/plugins/gateway-rpc-tool"
PLUGIN_DST="/var/lib/openclaw/.openclaw/extensions/gateway-rpc-tool"

echo "=== Step 1: Publish main workspace ==="
"$SCRIPT_DIR/publish-workspace-main.sh" --apply --allow-live-target \
    /var/lib/openclaw/.openclaw/workspace-main

echo ""
echo "=== Step 2: Deploy gateway-rpc-tool plugin ==="
[[ -d "$PLUGIN_DST" ]] && rm -rf "$PLUGIN_DST"
cp -r "$PLUGIN_SRC" "$PLUGIN_DST"
chown -R openclaw:openclaw "$PLUGIN_DST"
echo "Plugin deployed to $PLUGIN_DST"

echo ""
echo "=== Step 3: Patch openclaw.json ==="
cp "$CONFIG_PATH" "$CONFIG_BACKUP"
echo "Backup: $CONFIG_BACKUP"

python3 - "$CONFIG_PATH" <<'PYEOF'
import json, sys
config_path = sys.argv[1]
with open(config_path, 'r') as f:
    config = json.load(f)
changed = False
if 'plugins' not in config:
    config['plugins'] = {}
allow = config['plugins'].get('allow', [])
if 'gateway-rpc-tool' not in allow:
    allow.append('gateway-rpc-tool')
    config['plugins']['allow'] = allow
    changed = True
    print("[PATCH] Added 'gateway-rpc-tool' to plugins.allow")
entries = config['plugins'].get('entries', {})
if 'gateway-rpc-tool' not in entries:
    entries['gateway-rpc-tool'] = {"enabled": True}
    config['plugins']['entries'] = entries
    changed = True
    print("[PATCH] Added gateway-rpc-tool entry")
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
    print("[OK] Config patched")
else:
    print("[OK] Config already up to date")
PYEOF

echo ""
echo "=== Step 4: Restart gateway ==="
systemctl restart openclaw-gateway.service
sleep 3
if systemctl is-active --quiet openclaw-gateway.service; then
    echo "[OK] Gateway running"
else
    echo "[ERROR] Gateway failed! Rollback: cp $CONFIG_BACKUP $CONFIG_PATH && systemctl restart openclaw-gateway.service"
    exit 1
fi

echo ""
echo "=== Done ==="
echo "Rollback config: cp $CONFIG_BACKUP $CONFIG_PATH"
