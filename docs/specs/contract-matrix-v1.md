# Cross-Layer Contract Matrix v1

> Status: **Dev-repo specification** — Phase 2 repo-only prep
> Created: 2026-03-11
> Purpose: Single-page index of field definitions shared across layers, to prevent cross-layer drift
> This document is a repo-only specification. It does NOT represent live deployment.

---

## 0. Why this document exists

Several fields (action enum, required field names, validation constraints) are defined or mirrored in multiple places. When any single layer changes a definition without updating the others, contract drift occurs. This matrix maps each frozen contract edge to the authoritative source and every layer that mirrors it.

Phase 1 is complete. Phase 2 has not started. The broker is not yet deployed.

---

## 1. Request envelope fields

| Field | Type | Authoritative source | Mirrored in |
|-------|------|---------------------|-------------|
| `action` | string, enum(8) | `broker/schemas/host-ops-request.schema.json` | `common.sh` BROKER_ACTIONS, `index.js` ACTIONS, `build-request.sh` VALID_ACTIONS, `validate-request.sh` VALID_ACTIONS |
| `request_id` | string, minLength:1 | `broker/schemas/host-ops-request.schema.json` | `common.sh` broker_validate_required_fields, `validate-request.sh` empty check, `index.js` validateRequest |
| `task_id` | string, minLength:1 | `broker/schemas/host-ops-request.schema.json` | `common.sh` broker_validate_required_fields, `validate-request.sh` empty check, `index.js` validateRequest |
| `requested_by` | string, minLength:1 | `broker/schemas/host-ops-request.schema.json` | `validate-request.sh` (not checked), `index.js` validateRequest |
| `inputs` | object | `broker/schemas/host-ops-request.schema.json` | per-action schemas, `validate-request.sh`, `index.js` validateActionInputs |

---

## 2. Result envelope fields

| Field | Type | Required | Authoritative source |
|-------|------|----------|---------------------|
| `ok` | boolean | Yes | `broker/schemas/host-ops-result.schema.json` |
| `action` | string, minLength:1 | Yes | `broker/schemas/host-ops-result.schema.json` |
| `request_id` | string, minLength:1 | Yes | `broker/schemas/host-ops-result.schema.json` |
| `task_id` | string, minLength:1 | Yes | `broker/schemas/host-ops-result.schema.json` |
| `status` | string, enum(ok,error,denied) | Yes | `broker/schemas/host-ops-result.schema.json` |
| `message` | string | No | `broker/schemas/host-ops-result.schema.json` |
| `artifacts` | object | No | `broker/schemas/host-ops-result.schema.json` |
| `rollback_hint` | string | No | `broker/schemas/host-ops-result.schema.json` |
| `error_code` | string, minLength:1 | No (reserved) | `broker/schemas/host-ops-result.schema.json` |

**Invariant**: `ok` MUST be `true` if and only if `status` is `"ok"`. Schema-enforced via `if/then/else`.

---

## 3. Action enum (frozen)

All 8 values, sorted. No additions or removals without a protocol version bump.

| # | Action | Per-action schema | Wrapper stub |
|---|--------|-------------------|--------------|
| 1 | `deploy_openclaw_json_candidate` | `deploy-openclaw-json.schema.json` | `ocw-deploy-openclaw-json.sh` |
| 2 | `gateway_health` | `gateway-health.schema.json` | `ocw-gateway-health.sh` |
| 3 | `gateway_restart` | `gateway-restart.schema.json` | `ocw-gateway-restart.sh` |
| 4 | `rollback_prepare` | `rollback-prepare.schema.json` | `ocw-rollback-prepare.sh` |
| 5 | `snapshot_post` | `snapshot-post.schema.json` | `ocw-snapshot-post.sh` |
| 6 | `snapshot_pre` | `snapshot-pre.schema.json` | `ocw-snapshot-pre.sh` |
| 7 | `validate_openclaw_json_candidate` | `validate-openclaw-json.schema.json` | `ocw-validate-openclaw-json.sh` |
| 8 | `vault_sync` | `vault-sync.schema.json` | `ocw-vault-sync.sh` |

---

## 4. Shared validation rules

| Rule | Constraint | Enforced in |
|------|-----------|-------------|
| SHA256 format | `^[a-f0-9]{64}$` | schema pattern, `common.sh` broker_validate_sha256, `validate-request.sh` grep, `index.js` regex |
| Label/name format | `^[a-zA-Z0-9._-]+$` | schema pattern, `common.sh` broker_validate_label, `validate-request.sh` grep, `index.js` regex |
| Label/name maxLength | 128 | schema maxLength, `common.sh` length check, `validate-request.sh` length check, `index.js` length check |
| Candidate path prefix | `/var/lib/openclaw/approvals/candidates/` | schema pattern, `common.sh` broker_validate_path, `validate-request.sh` case match, `index.js` startsWith |
| Path traversal | reject `..` | `common.sh` broker_validate_path, `validate-request.sh` case match, `index.js` includes check |
| Reason minLength | 1 (non-empty) | schema minLength, wrapper empty check, `validate-request.sh` empty check, `index.js` falsy check |

---

## 5. Deprecated field names (frozen ban)

These field names MUST NOT appear as JSON keys in any broker protocol artifact:

| Deprecated name | Replacement | Banned since |
|----------------|-------------|-------------|
| `operation` | `action` | Phase 2 prep, batch 1 |
| `parameters` | `inputs` | Phase 2 prep, batch 1 |
| `approval_id` | `requested_by` | Phase 2 prep, batch 1 |

Note: `"operation"` in the approval system (`pending-approvals.json`) is a separate domain and is not subject to this ban.

---

## 6. Status enum semantics (frozen)

| Status | `ok` value | Retryable | Error code prefix |
|--------|-----------|-----------|-------------------|
| `ok` | `true` | N/A | N/A |
| `error` | `false` | Possibly | `E_*` |
| `denied` | `false` | No | `D_*` |

---

## 7. Verification

This matrix is verified by:
- `tests/test_contract_freeze.sh` — action enum, field sets, types, deprecated names, cross-layer lists
- `scripts/validate-broker-schemas.sh` — schema structure, fixture conformance
- `scripts/validate-phase2-prep.sh` — full cross-layer alignment
- `tests/test_phase2_integration.sh` — runtime validation parity
