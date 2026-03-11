# Broker Wrappers

Each wrapper is a single-purpose, root-owned script that performs exactly one host mutation.

Current status (2026-03-11):
- Phase 2 not yet started
- This directory contains **stub scripts** for local validation and protocol testing
- Stubs validate inputs and echo intended actions but do NOT execute live operations
- Production deployment requires: root ownership, controlled install path, Phase 2 deployment runbook

## Wrapper inventory

| Wrapper | Action | Phase 2 scope |
|---------|--------|---------------|
| `ocw-gateway-health.sh` | `gateway_health` | Yes |
| `ocw-gateway-restart.sh` | `gateway_restart` | Yes |
| `ocw-validate-openclaw-json.sh` | `validate_openclaw_json_candidate` | Yes |
| `ocw-deploy-openclaw-json.sh` | `deploy_openclaw_json_candidate` | Yes |
| `ocw-snapshot-pre.sh` | `snapshot_pre` | Yes |
| `ocw-snapshot-post.sh` | `snapshot_post` | Yes |
| `ocw-vault-sync.sh` | `vault_sync` | Yes |
| `ocw-rollback-prepare.sh` | `rollback_prepare` | Yes |

## Shared validation library

All wrappers source `lib/common.sh`, which provides:
- `broker_validate_request_file` — argument count and file existence check
- `broker_parse_common` — extract action, request_id, task_id from JSON
- `broker_validate_action` — verify action matches expected value
- `broker_validate_required_fields` — verify request_id and task_id non-empty
- `broker_validate_sha256` — 64-char lowercase hex validation
- `broker_validate_path` — candidate path whitelist + traversal detection
- `broker_validate_label` — alphanumeric format check
- `broker_error` — emit structured error JSON to stderr and exit 1
- `broker_emit_result` — emit structured success JSON to stdout

## Design rules (per design-v3.md §5.6.4)

1. Each wrapper does exactly one thing
2. Validates inputs before acting (via common.sh shared functions)
3. Verifies candidate file hashes where applicable
4. Returns structured JSON result on stdout
5. Never executes free-form shell or user-supplied commands
6. Logs all actions
7. Failure exits non-zero with structured error JSON
