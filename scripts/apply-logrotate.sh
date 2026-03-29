#!/usr/bin/env bash
# Apply logrotate config for OpenClaw logs
# Rollback: sudo rm /etc/logrotate.d/openclaw
set -euo pipefail

LOGROTATE_CONF="/etc/logrotate.d/openclaw"

if [[ -f "$LOGROTATE_CONF" ]]; then
  echo "WARNING: $LOGROTATE_CONF already exists. Overwriting."
fi

sudo tee "$LOGROTATE_CONF" > /dev/null <<'EOF'
/var/log/openclaw/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su openclaw openclaw
    size 500M
}
EOF

echo "Created $LOGROTATE_CONF"

# Verify syntax
sudo logrotate -d "$LOGROTATE_CONF" 2>&1 | head -20
echo ""
echo "Logrotate config installed. Rollback: sudo rm $LOGROTATE_CONF"
