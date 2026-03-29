#!/usr/bin/env bash
# Grant nick read access to OpenClaw subagent runs data
set -euo pipefail

OCDIR="/var/lib/openclaw/.openclaw"
SUBDIR="$OCDIR/subagents"
RUNS="$SUBDIR/runs.json"

# Method 1: ACL (preferred)
if command -v setfacl &>/dev/null; then
  echo "Trying ACL method..."
  sudo setfacl -m u:nick:x /var/lib/openclaw
  sudo setfacl -m u:nick:x "$OCDIR"
  sudo setfacl -m u:nick:rx "$SUBDIR"
  sudo setfacl -m u:nick:r "$RUNS"

  if cat "$RUNS" > /dev/null 2>&1; then
    echo "ACL method: OK"
    exit 0
  fi
  echo "ACL method failed, trying alternative..."
fi

# Method 2: Add nick to openclaw group + ensure group read
echo "Adding nick to openclaw group..."
sudo usermod -aG openclaw nick
sudo chmod g+rx /var/lib/openclaw "$OCDIR" "$SUBDIR"
sudo chmod g+r "$RUNS"
echo "Added nick to openclaw group. You need to log out and back in (or run 'newgrp openclaw') for group changes to take effect."
echo "After that, verify with: cat $RUNS | head -c 50"
