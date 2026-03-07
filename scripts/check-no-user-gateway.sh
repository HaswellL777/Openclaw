#!/usr/bin/env bash
set -euo pipefail

echo '== ~/.openclaw =='
if [ -d "$HOME/.openclaw" ]; then
  echo 'FOUND: ~/.openclaw'
  ls -la "$HOME/.openclaw"
else
  echo 'OK: ~/.openclaw absent'
fi

echo
echo '== user systemd unit =='
if [ -f "$HOME/.config/systemd/user/openclaw-gateway.service" ]; then
  echo 'FOUND: ~/.config/systemd/user/openclaw-gateway.service'
  ls -l "$HOME/.config/systemd/user/openclaw-gateway.service"
else
  echo 'OK: no user-level unit file'
fi

echo
echo '== user service status =='
if systemctl --user --no-pager --full status openclaw-gateway.service >/dev/null 2>&1; then
  echo 'WARN: user-level openclaw-gateway.service exists or is running'
else
  echo 'OK: no user-level openclaw-gateway.service'
fi

echo
echo '== openclaw listening ports =='
sudo ss -tlnp | grep openclaw || true
