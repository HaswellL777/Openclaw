#!/usr/bin/env bash
# Prepare current-run helper/candidate artifacts for temporary restricted proxy feasibility.
# Safety: repo-side only; no sudo; no live-side execution or deployment.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE_RUN_ID="exp-docker-access-feasibility-20260321-131819"
BASELINE_HELPER="${REPO_ROOT}/artifacts/phase3/temporary-restricted-proxy-feasibility-window-${BASELINE_RUN_ID}/docker_restricted_proxy.py"
BASE_CONFIG="${REPO_ROOT}/openclaw.live.json"

usage() {
  cat <<'EOF'
Usage:
  prepare-temporary-restricted-proxy-feasibility-artifacts.sh --run-id <exp-run-id> [options]

Options:
  --run-id <id>                 Required. Current run id, e.g. exp-docker-access-feasibility-20260322-111033
  --rc-base <dir>               Artifact root. Default: /tmp/openclaw-docker-access-feasibility/<run-id>
  --candidate-live-dir <dir>    Live candidate directory recorded in freeze card only.
                                Default: /var/lib/openclaw/approvals/candidates
  --evidence-record-repo <path> Evidence record path recorded in freeze card.
                                Default: docs/records/temporary-restricted-proxy-feasibility-execution-<run-id>.md
  --force                       Overwrite an existing rc-base directory.
  --help                        Show this help text.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

RUN_ID=""
RC_BASE=""
CANDIDATE_LIVE_DIR="/var/lib/openclaw/approvals/candidates"
EVIDENCE_RECORD_REPO=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)
      [[ $# -ge 2 ]] || die "--run-id requires a value"
      RUN_ID="$2"
      shift 2
      ;;
    --rc-base)
      [[ $# -ge 2 ]] || die "--rc-base requires a value"
      RC_BASE="$2"
      shift 2
      ;;
    --candidate-live-dir)
      [[ $# -ge 2 ]] || die "--candidate-live-dir requires a value"
      CANDIDATE_LIVE_DIR="$2"
      shift 2
      ;;
    --evidence-record-repo)
      [[ $# -ge 2 ]] || die "--evidence-record-repo requires a value"
      EVIDENCE_RECORD_REPO="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$RUN_ID" ]] || {
  usage
  die "--run-id is required"
}

[[ -f "$BASELINE_HELPER" ]] || die "baseline helper missing: $BASELINE_HELPER"
[[ -f "$BASE_CONFIG" ]] || die "base config missing: $BASE_CONFIG"

if [[ -z "$RC_BASE" ]]; then
  RC_BASE="/tmp/openclaw-docker-access-feasibility/${RUN_ID}"
fi
if [[ -z "$EVIDENCE_RECORD_REPO" ]]; then
  EVIDENCE_RECORD_REPO="docs/records/temporary-restricted-proxy-feasibility-execution-${RUN_ID}.md"
fi

RC_BASE="${RC_BASE%/}"
ISOLATED_DIR="${RC_BASE}/"
EVIDENCE_SINK_RAW="${RC_BASE}/evidence/"
RUNTIME_DIR="${RC_BASE}/runtime"
CURRENT_HELPER="${RC_BASE}/docker_restricted_proxy.py"
CURRENT_VALIDATE_ONLY_CFG="${RC_BASE}/openclaw.docker-access-feasibility.${RUN_ID}.validate-only.json"
PROMOTION_VALIDATE_ONLY_CFG="${CANDIDATE_LIVE_DIR%/}/openclaw.docker-access-feasibility.${RUN_ID}.validate-only.json"
CURRENT_MANIFEST="${RC_BASE}/current-run-artifact-manifest.json"
FREEZE_CARD="${RC_BASE}/freeze-card.env"
ENDPOINT_CANDIDATE="unix://${RC_BASE}/docker-proxy.sock"
AUDIT_JSONL_PATH="${RC_BASE}/evidence/docker-restricted-proxy.audit.jsonl"
VALIDATE_ONLY_AGENT_ID="docker-access-feasibility-validate-only"
EXPECTED_LAYOUT_TXT="${RC_BASE}/expected-artifact-layout.txt"

if [[ -e "$RC_BASE" ]]; then
  if [[ "$FORCE" -ne 1 ]]; then
    die "rc-base already exists: $RC_BASE (use --force to overwrite)"
  fi
  rm -rf "$RC_BASE"
fi

mkdir -p "${RC_BASE}" "${RC_BASE}/evidence" "${RUNTIME_DIR}"

cat >"${FREEZE_CARD}" <<EOF
EXP_RUN_ID=${RUN_ID}
BACKEND_CANDIDATE=docker_engine.system_daemon
PROXY_CANDIDATE=docker_api_restricted_proxy
ENDPOINT_CANDIDATE=${ENDPOINT_CANDIDATE}
CANDIDATE_EXP_CFG=${CANDIDATE_LIVE_DIR%/}/openclaw.docker-access-feasibility.${RUN_ID}.json
CANDIDATE_VALIDATE_ONLY_CFG=${PROMOTION_VALIDATE_ONLY_CFG}
ISOLATED_DIR=${ISOLATED_DIR}
RC_BASE=${RC_BASE}
RUNTIME_DIR=${RUNTIME_DIR}
EVIDENCE_SINK_RAW=${EVIDENCE_SINK_RAW}
AUDIT_JSONL_PATH=${AUDIT_JSONL_PATH}
EVIDENCE_RECORD_REPO=${EVIDENCE_RECORD_REPO}
CURRENT_HELPER=${CURRENT_HELPER}
CURRENT_VALIDATE_ONLY_CFG=${CURRENT_VALIDATE_ONLY_CFG}
CURRENT_MANIFEST=${CURRENT_MANIFEST}
BASELINE_HELPER_REPO=${BASELINE_HELPER}
BASE_CONFIG_REPO=${BASE_CONFIG}
VALIDATE_ONLY_AGENT_ID=${VALIDATE_ONLY_AGENT_ID}
EOF

python3 - <<'PY' \
  "${BASELINE_HELPER}" \
  "${CURRENT_HELPER}" \
  "${BASELINE_RUN_ID}" \
  "${RUN_ID}" \
  "${RC_BASE}" \
  "${EVIDENCE_SINK_RAW}"
from pathlib import Path
import sys

baseline_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
baseline_run_id = sys.argv[3]
run_id = sys.argv[4]
rc_base = sys.argv[5].rstrip("/")
evidence_sink = sys.argv[6]

content = baseline_path.read_text()
content = content.replace(baseline_run_id, run_id)
content = content.replace(
    f"/tmp/openclaw-docker-access-feasibility/{run_id}/",
    f"{rc_base}/",
)
content = content.replace(
    f"/tmp/openclaw-docker-access-feasibility/{run_id}/evidence/",
    evidence_sink,
)
target_path.write_text(content)
PY

chmod 700 "${CURRENT_HELPER}"

python3 - <<'PY' \
  "${BASE_CONFIG}" \
  "${CURRENT_VALIDATE_ONLY_CFG}" \
  "${RUN_ID}" \
  "${ENDPOINT_CANDIDATE}" \
  "${VALIDATE_ONLY_AGENT_ID}"
from copy import deepcopy
import json
from pathlib import Path
import sys

base_config = Path(sys.argv[1])
target_path = Path(sys.argv[2])
run_id = sys.argv[3]
endpoint = sys.argv[4]
agent_id = sys.argv[5]

data = json.loads(base_config.read_text())

plugins = data.setdefault("plugins", {})
installs = plugins.get("installs", {})
feishu_install = deepcopy(installs["feishu"]) if "feishu" in installs else {}
plugins["allow"] = ["feishu"]
plugins["entries"] = {"feishu": {"enabled": True}}
plugins["installs"] = {"feishu": feishu_install} if feishu_install else {}

hooks = data.get("hooks")
if isinstance(hooks, dict):
  hooks["internal"] = {"enabled": False, "entries": {}}

agent = {
  "id": agent_id,
  "default": False,
  "workspace": "/var/lib/openclaw/.openclaw/workspace-task-runner",
  "tools": {
    "allow": ["read", "write", "edit", "apply_patch", "exec", "process"],
    "deny": ["sessions_spawn", "elevated"],
    "elevated": {"enabled": False},
  },
  "sandbox": {
    "mode": "all",
    "scope": "session",
    "workspaceAccess": "none",
    "docker": {
      "image": "hello-world",
      "endpoint": endpoint,
      "network": "none",
      "readOnlyRoot": True,
      "tmpfs": ["/tmp", "/var/tmp", "/run"],
    },
  },
  "metadata": {
    "phase3Feasibility": {
      "runId": run_id,
      "kind": "validate-only",
      "repoGenerated": True,
    }
  },
}

agents = data.setdefault("agents", {})
agent_list = agents.setdefault("list", [])
filtered = [item for item in agent_list if item.get("id") != agent_id]
filtered.append(agent)
agents["list"] = filtered

target_path.write_text(json.dumps(data, indent=2, sort_keys=False) + "\n")
PY

python3 - <<'PY' \
  "${CURRENT_HELPER}" \
  "${CURRENT_VALIDATE_ONLY_CFG}" \
  "${FREEZE_CARD}" \
  "${CURRENT_MANIFEST}" \
  "${RUN_ID}" \
  "${RC_BASE}" \
  "${ENDPOINT_CANDIDATE}" \
  "${VALIDATE_ONLY_AGENT_ID}" \
  "${BASELINE_HELPER}" \
  "${BASE_CONFIG}" \
  "${PROMOTION_VALIDATE_ONLY_CFG}"
import hashlib
import json
from pathlib import Path
import sys

helper = Path(sys.argv[1])
candidate = Path(sys.argv[2])
freeze_card = Path(sys.argv[3])
manifest = Path(sys.argv[4])
run_id = sys.argv[5]
rc_base = sys.argv[6]
endpoint = sys.argv[7]
agent_id = sys.argv[8]
baseline_helper = sys.argv[9]
base_config = sys.argv[10]
promotion_candidate = sys.argv[11]

def sha256(path: Path) -> str:
  return hashlib.sha256(path.read_bytes()).hexdigest()

payload = {
  "run_id": run_id,
  "rc_base": rc_base,
  "expected_layout": {
    "root_files": [
      "freeze-card.env",
      "docker_restricted_proxy.py",
      candidate.name,
      "current-run-artifact-manifest.json",
      "expected-artifact-layout.txt",
    ],
    "root_dirs": ["evidence", "runtime"],
  },
  "artifacts": {
    "freeze_card": {
      "path": str(freeze_card),
      "sha256": sha256(freeze_card),
    },
    "helper": {
      "path": str(helper),
      "sha256": sha256(helper),
      "baseline_repo_source": baseline_helper,
    },
    "validate_only_candidate": {
      "path": str(candidate),
      "sha256": sha256(candidate),
      "promotion_candidate_path": promotion_candidate,
      "base_config_repo_source": base_config,
    },
  },
  "alignment": {
    "endpoint_candidate": endpoint,
    "validate_only_agent_id": agent_id,
    "required_docker_image": "hello-world",
  },
  "status": {
    "helper_generated": True,
    "validate_only_generated": True,
    "alignment_precheck_passed": False,
  },
}

manifest.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n")
PY

cat >"${EXPECTED_LAYOUT_TXT}" <<EOF
${RC_BASE}/
|-- current-run-artifact-manifest.json
|-- docker_restricted_proxy.py
|-- expected-artifact-layout.txt
|-- freeze-card.env
|-- openclaw.docker-access-feasibility.${RUN_ID}.validate-only.json
|-- evidence/
\`-- runtime/
EOF

echo "Prepared current-run feasibility artifacts:"
echo "  RUN_ID: ${RUN_ID}"
echo "  RC_BASE: ${RC_BASE}"
echo "  FREEZE_CARD: ${FREEZE_CARD}"
echo "  HELPER: ${CURRENT_HELPER}"
echo "  VALIDATE_ONLY_CFG: ${CURRENT_VALIDATE_ONLY_CFG}"
echo "  PROMOTION_VALIDATE_ONLY_CFG: ${PROMOTION_VALIDATE_ONLY_CFG}"
echo "  MANIFEST: ${CURRENT_MANIFEST}"
