# Host-Ops Broker Error Taxonomy v1

> Status: **Dev-repo specification** — Phase 2 repo-only prep
> Created: 2026-03-11
> Parent spec: `docs/specs/host-ops-broker-protocol-v1.md` §4
> This document is a repo-only error model specification. It does NOT represent live deployment.

---

## 0. Purpose

This document defines the formal error taxonomy for the host-ops broker protocol. It codifies the error categories, result codes, denial reasons, and their mapping to the response envelope fields (`ok`, `status`, `message`).

Phase 1 is complete. Phase 2 has not started. The broker is not yet deployed.

---

## 1. Result status values

The `status` field in the response envelope is an enum with exactly 3 values:

| Status | `ok` value | Meaning |
|--------|-----------|---------|
| `ok` | `true` | Action completed successfully |
| `error` | `false` | Action failed due to error (validation, execution, or system) |
| `denied` | `false` | Action denied by policy (path, authorization, or traversal) |

**Invariant**: `ok` MUST be `true` if and only if `status` is `"ok"`. No other combinations are valid.

---

## 2. Error categories

Each error falls into one of the following categories. The category determines the `status` value and informs the `message` content.

### 2.1 Validation errors (status: `error`)

| Code | Category | Trigger | Example message |
|------|----------|---------|-----------------|
| `E_UNKNOWN_ACTION` | Unknown action | `action` not in the 8-value enum | `"Unknown action: delete_everything"` |
| `E_SCHEMA_VALIDATION` | Schema validation failure | Request does not conform to envelope schema | `"Missing required field: action"` |
| `E_MISSING_FIELD` | Missing required field | A required envelope field is absent or empty | `"Missing required fields: request_id, task_id"` |
| `E_INVALID_SHA256` | SHA256 format invalid | `expected_sha256` is not 64 lowercase hex chars | `"Invalid SHA256 format"` |
| `E_INVALID_LABEL` | Label format invalid | Label/name contains invalid characters | `"Invalid label format: alphanumeric, dots, hyphens, underscores only"` |
| `E_MISSING_INPUT` | Missing action-specific input | A required per-action input field is absent | `"Missing required input: reason"` |
| `E_FILE_NOT_FOUND` | Request file not found | The request JSON file path does not exist | `"Request file not found: /path/to/file.json"` |
| `E_INVALID_JSON` | Invalid JSON | The request file is not valid JSON | `"Request file is not valid JSON"` |

### 2.2 Policy denial errors (status: `denied`)

| Code | Category | Trigger | Example message |
|------|----------|---------|-----------------|
| `D_PATH_WHITELIST` | Path outside whitelist | `candidate_path` does not start with allowed prefix | `"Path not in whitelist: must start with /var/lib/openclaw/approvals/candidates/"` |
| `D_PATH_TRAVERSAL` | Path traversal detected | Path contains `..` component | `"Path traversal detected"` |

### 2.3 Execution errors (status: `error`)

| Code | Category | Trigger | Example message |
|------|----------|---------|-----------------|
| `E_WRAPPER_FAILED` | Wrapper execution failure | Wrapper script exited non-zero after validation passed | `"Wrapper execution failed: <details>"` |
| `E_UNEXPECTED` | Unexpected error | Any error not covered by above categories | `"Unexpected error: <details>"` |
| `E_WRONG_ACTION` | Action/wrapper mismatch | Request action does not match wrapper's expected action | `"Wrong action: expected gateway_restart, got gateway_health"` |

---

## 3. Error code usage

### 3.1 Current status (Phase 2 prep)

Error codes are **informational** in Phase 2 prep. They are:
- Documented in this taxonomy
- Used in negative test fixture `message` fields for human readability
- Not yet emitted as a separate machine-readable field in the response envelope

### 3.2 Future direction (Phase 2 deployment)

When the broker is deployed, error codes MAY be added as an optional `error_code` field in the response envelope:

```json
{
  "ok": false,
  "action": "deploy_openclaw_json_candidate",
  "request_id": "req-...",
  "task_id": "task-...",
  "status": "denied",
  "error_code": "D_PATH_TRAVERSAL",
  "message": "Path traversal detected"
}
```

This field is **reserved but not yet required** in the result schema.

---

## 4. Negative fixture index

Each error category has a corresponding negative fixture pair in `examples/broker/negative/`:

| Error code | Request fixture | Result fixture |
|-----------|----------------|----------------|
| `E_UNKNOWN_ACTION` | `invalid-action-request.json` | `invalid-action-result.json` |
| `E_UNKNOWN_ACTION` (empty) | `empty-action-request.json` | `empty-action-result.json` |
| `E_MISSING_FIELD` (request_id) | `missing-request-id-request.json` | `missing-request-id-result.json` |
| `E_MISSING_FIELD` (task_id) | `missing-task-id-request.json` | `missing-task-id-result.json` |
| `D_PATH_TRAVERSAL` | `path-traversal-request.json` | `path-traversal-result.json` |
| `E_INVALID_SHA256` | `bad-sha256-request.json` | `bad-sha256-result.json` |
| `E_INVALID_SHA256` (empty) | `empty-sha256-request.json` | `empty-sha256-result.json` |
| `E_INVALID_LABEL` | `bad-label-request.json` | `bad-label-result.json` |
| `E_INVALID_LABEL` (empty) | `empty-label-request.json` | `empty-label-result.json` |
| `E_MISSING_INPUT` (reason) | `missing-reason-request.json` | `missing-reason-result.json` |
| `E_MISSING_INPUT` (reason, empty) | `empty-reason-request.json` | `empty-reason-result.json` |
| `E_MISSING_INPUT` (reason, type) | `type-error-reason-request.json` | `type-error-reason-result.json` |
| `E_MISSING_INPUT` (candidate_path) | `missing-candidate-path-request.json` | `missing-candidate-path-result.json` |
| `E_MISSING_INPUT` (label) | `missing-label-request.json` | `missing-label-result.json` |
| `E_MISSING_INPUT` (snapshot_name) | `missing-snapshot-name-request.json` | `missing-snapshot-name-result.json` |
| `E_MISSING_INPUT` (target_snapshot) | `missing-target-snapshot-request.json` | `missing-target-snapshot-result.json` |
| `E_WRONG_ACTION` | `wrong-wrapper-action-request.json` | `wrong-wrapper-action-result.json` |
| `E_FILE_NOT_FOUND` | *(no request file)* | `missing-file-result.json` |
| `D_PATH_WHITELIST` | `../bad-path-request.json` | `../bad-path-result.json` |

---

## 5. Denial vs error distinction

The distinction between `denied` and `error` is intentional:

- **`denied`**: The request was understood but explicitly rejected by a security policy. The caller should NOT retry with the same inputs. These represent hard boundaries.
- **`error`**: The request was malformed, incomplete, or failed during execution. The caller MAY be able to fix the issue and retry.

This distinction matters for the plugin layer: `denied` responses should be surfaced to the human operator with security context; `error` responses may be retryable after correction.

---

## 6. References

- `docs/specs/host-ops-broker-protocol-v1.md` §4 — Error model
- `broker/schemas/host-ops-result.schema.json` — Result envelope schema
- `examples/broker/negative/` — Negative test fixtures
- `tests/test_contract_freeze.sh` — Contract freeze tests
