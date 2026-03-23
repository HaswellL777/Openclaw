#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash "$REPO_ROOT/scripts/check-phase3-dispatch-adapter-flow.sh"
