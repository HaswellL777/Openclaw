#!/usr/bin/env bash
# Read-only alignment precheck for current-run temporary restricted proxy feasibility artifacts.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  precheck-temporary-restricted-proxy-artifact-alignment.sh --rc-base <dir>

Options:
  --rc-base <dir>      Required. Current-run artifact root.
  --freeze-card <file> Optional. Defaults to <rc-base>/freeze-card.env
  --help               Show this help text.
EOF
}

pass() {
  echo "  [PASS] $1"
}

fail() {
  echo "  [FAIL] $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
  echo "  [WARN] $1"
  WARN_COUNT=$((WARN_COUNT + 1))
}

RC_BASE=""
FREEZE_CARD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rc-base)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      RC_BASE="$2"
      shift 2
      ;;
    --freeze-card)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      FREEZE_CARD="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -n "$RC_BASE" ]] || {
  usage
  exit 1
}

RC_BASE="${RC_BASE%/}"
if [[ -z "$FREEZE_CARD" ]]; then
  FREEZE_CARD="${RC_BASE}/freeze-card.env"
fi

FAIL_COUNT=0
WARN_COUNT=0

echo "=== Temporary Restricted Proxy Artifact Alignment Precheck ==="
echo "RC_BASE: ${RC_BASE}"
echo "FREEZE_CARD: ${FREEZE_CARD}"
echo ""

[[ -d "$RC_BASE" ]] && pass "rc-base directory exists" || fail "rc-base directory missing: ${RC_BASE}"
[[ -f "$FREEZE_CARD" ]] && pass "freeze card exists" || fail "freeze card missing: ${FREEZE_CARD}"

if [[ ! -f "$FREEZE_CARD" ]]; then
  echo ""
  echo "RESULT: PREFLIGHT FAILED — freeze card missing."
  exit 1
fi

set -a
. "$FREEZE_CARD"
set +a

echo "--- Layout ---"
[[ -d "${EVIDENCE_SINK_RAW%/}" ]] && pass "evidence directory exists" || fail "evidence directory missing: ${EVIDENCE_SINK_RAW%/}"
[[ -d "${RUNTIME_DIR}" ]] && pass "runtime directory exists" || fail "runtime directory missing: ${RUNTIME_DIR}"
[[ -f "${CURRENT_HELPER}" ]] && pass "current-run helper exists" || fail "current-run helper missing: ${CURRENT_HELPER}"
[[ -f "${CURRENT_VALIDATE_ONLY_CFG}" ]] && pass "current-run validate-only candidate exists" || fail "current-run validate-only candidate missing: ${CURRENT_VALIDATE_ONLY_CFG}"
[[ -f "${CURRENT_MANIFEST}" ]] && pass "current-run manifest exists" || fail "current-run manifest missing: ${CURRENT_MANIFEST}"
[[ -f "${RC_BASE}/expected-artifact-layout.txt" ]] && pass "expected layout note exists" || warn "expected layout note missing: ${RC_BASE}/expected-artifact-layout.txt"
echo ""

echo "--- Freeze Card ---"
[[ "${CURRENT_HELPER}" == "${RC_BASE}/docker_restricted_proxy.py" ]] && pass "freeze card helper path aligns with rc-base" || fail "freeze card helper path drift: ${CURRENT_HELPER}"
[[ "${CURRENT_VALIDATE_ONLY_CFG}" == "${RC_BASE}/openclaw.docker-access-feasibility.${EXP_RUN_ID}.validate-only.json" ]] && pass "freeze card validate-only path aligns with run id" || fail "freeze card validate-only path drift: ${CURRENT_VALIDATE_ONLY_CFG}"
[[ "${ENDPOINT_CANDIDATE}" == "unix://${RC_BASE}/docker-proxy.sock" ]] && pass "freeze card endpoint aligns with rc-base" || fail "freeze card endpoint drift: ${ENDPOINT_CANDIDATE}"
[[ "${AUDIT_JSONL_PATH}" == "${RC_BASE}/evidence/docker-restricted-proxy.audit.jsonl" ]] && pass "freeze card audit path aligns with rc-base" || fail "freeze card audit path drift: ${AUDIT_JSONL_PATH}"
[[ "${CANDIDATE_VALIDATE_ONLY_CFG}" == "/var/lib/openclaw/approvals/candidates/openclaw.docker-access-feasibility.${EXP_RUN_ID}.validate-only.json" ]] && pass "freeze card promotion candidate path aligns with run id" || warn "promotion candidate path differs from default live path: ${CANDIDATE_VALIDATE_ONLY_CFG}"
echo ""

echo "--- Helper Content ---"
if [[ -f "${CURRENT_HELPER}" ]]; then
  if python3 - <<'PY' "${CURRENT_HELPER}" "${EXP_RUN_ID}" "${ENDPOINT_CANDIDATE}" "${EVIDENCE_SINK_RAW}"; then
import ast
import sys
from pathlib import Path

helper_path = Path(sys.argv[1])
expected_run_id = sys.argv[2]
expected_endpoint = sys.argv[3]
expected_evidence_sink = sys.argv[4]

tree = ast.parse(helper_path.read_text())
values = {}
for node in tree.body:
    if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
        name = node.targets[0].id
        if name in {"EXP_RUN_ID", "ENDPOINT_CANDIDATE", "EVIDENCE_SINK_RAW"}:
            values[name] = ast.literal_eval(node.value)

assert values["EXP_RUN_ID"] == expected_run_id
assert values["ENDPOINT_CANDIDATE"] == expected_endpoint
assert values["EVIDENCE_SINK_RAW"] == expected_evidence_sink
PY
    pass "helper embeds current run id / endpoint / evidence sink"
  else
    fail "helper constant drift detected"
  fi
else
  fail "helper content checks skipped because helper is missing"
fi
echo ""

echo "--- Candidate Content ---"
if [[ -f "${CURRENT_VALIDATE_ONLY_CFG}" ]]; then
  if python3 - <<'PY' "${CURRENT_VALIDATE_ONLY_CFG}" "${ENDPOINT_CANDIDATE}" "${EXP_RUN_ID}" "${VALIDATE_ONLY_AGENT_ID}"; then
import json
import sys
from pathlib import Path

candidate_path = Path(sys.argv[1])
endpoint = sys.argv[2]
run_id = sys.argv[3]
agent_id = sys.argv[4]

data = json.loads(candidate_path.read_text())
plugins = data.get("plugins", {})
if plugins.get("allow") != ["feishu"]:
    raise SystemExit("plugins.allow drift")
if plugins.get("entries") != {"feishu": {"enabled": True}}:
    raise SystemExit("plugins.entries drift")

agents = data.get("agents", {}).get("list", [])
target = None
for item in agents:
    if item.get("id") == agent_id:
        target = item
        break
if target is None:
    raise SystemExit("validate-only agent missing")

sandbox = target.get("sandbox", {})
docker = sandbox.get("docker", {})
metadata = target.get("metadata", {}).get("phase3Feasibility", {})

assert sandbox.get("mode") == "all"
assert sandbox.get("scope") == "session"
assert sandbox.get("workspaceAccess") == "none"
assert docker.get("image") == "hello-world"
assert docker.get("endpoint") == endpoint
assert docker.get("network") == "none"
assert metadata.get("runId") == run_id
assert metadata.get("kind") == "validate-only"
assert metadata.get("repoGenerated") is True
PY
    pass "validate-only candidate content aligns with current run"
  else
    fail "validate-only candidate content drift detected"
  fi
else
  fail "candidate content checks skipped because validate-only candidate is missing"
fi
echo ""

echo "--- Manifest ---"
if [[ -f "${CURRENT_MANIFEST}" ]]; then
  if python3 - <<'PY' "${CURRENT_MANIFEST}" "${CURRENT_HELPER}" "${CURRENT_VALIDATE_ONLY_CFG}" "${FREEZE_CARD}" "${EXP_RUN_ID}" "${RC_BASE}" "${ENDPOINT_CANDIDATE}" "${VALIDATE_ONLY_AGENT_ID}"; then
import hashlib
import json
import sys
from pathlib import Path

manifest = Path(sys.argv[1])
helper = Path(sys.argv[2])
candidate = Path(sys.argv[3])
freeze_card = Path(sys.argv[4])
run_id = sys.argv[5]
rc_base = sys.argv[6]
endpoint = sys.argv[7]
agent_id = sys.argv[8]

payload = json.loads(manifest.read_text())

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

assert payload["run_id"] == run_id
assert payload["rc_base"] == rc_base
assert payload["artifacts"]["freeze_card"]["path"] == str(freeze_card)
assert payload["artifacts"]["helper"]["path"] == str(helper)
assert payload["artifacts"]["validate_only_candidate"]["path"] == str(candidate)
assert payload["artifacts"]["freeze_card"]["sha256"] == sha256(freeze_card)
assert payload["artifacts"]["helper"]["sha256"] == sha256(helper)
assert payload["artifacts"]["validate_only_candidate"]["sha256"] == sha256(candidate)
assert payload["alignment"]["endpoint_candidate"] == endpoint
assert payload["alignment"]["validate_only_agent_id"] == agent_id
assert payload["status"]["helper_generated"] is True
assert payload["status"]["validate_only_generated"] is True
PY
    pass "manifest paths and sha256 values align"
  else
    fail "manifest drift detected"
  fi
else
  fail "manifest checks skipped because manifest is missing"
fi
echo ""

echo "=== Summary ==="
echo "  WARN: ${WARN_COUNT}"
echo "  FAIL: ${FAIL_COUNT}"
echo ""

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  echo "RESULT: PREFLIGHT FAILED — current-run artifact alignment not established."
  exit 1
fi

echo "RESULT: PREFLIGHT PASSED — current-run artifact alignment established."
