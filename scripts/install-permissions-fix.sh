#!/usr/bin/env bash
# Install tmpfiles.d config and systemd override to persist OpenClaw directory
# permissions (0750) across gateway restarts.
#
# Run as: sudo bash scripts/install-permissions-fix.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF_SRC="$REPO_DIR/scripts/openclaw-permissions.conf"
CONF_DST="/etc/tmpfiles.d/openclaw-permissions.conf"
OVERRIDE_DIR="/etc/systemd/system/openclaw-gateway.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/permissions-fix.conf"

# 1. Install tmpfiles.d config
echo "Installing $CONF_DST ..."
cp "$CONF_SRC" "$CONF_DST"
chmod 0644 "$CONF_DST"

# 2. Apply immediately
echo "Applying tmpfiles rules ..."
systemd-tmpfiles --create

# 3. Add ExecStartPost override if not already present
if [ -f "$OVERRIDE_FILE" ]; then
  echo "Systemd override already exists at $OVERRIDE_FILE — skipping."
else
  echo "Creating systemd override at $OVERRIDE_FILE ..."
  mkdir -p "$OVERRIDE_DIR"
  cat > "$OVERRIDE_FILE" <<'EOF'
[Service]
ExecStartPost=/usr/bin/systemd-tmpfiles --create
EOF
  chmod 0644 "$OVERRIDE_FILE"
  systemctl daemon-reload
  echo "Systemd override installed and daemon reloaded."
fi

# 4. Verify
echo ""
echo "Verifying permissions:"
stat -c '  %n  mode=%a owner=%U group=%G' \
  /var/lib/openclaw/.openclaw/ \
  /var/lib/openclaw/.openclaw/subagents/ 2>/dev/null || echo "  (paths do not exist yet — will apply on next gateway start)"

echo ""
echo "Done. Permissions will be fixed automatically after every gateway restart."
