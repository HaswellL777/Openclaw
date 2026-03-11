# Phase 2 Repo-Only Prep Gate

> Status: **Dev-repo assessment** — Phase 2 repo-only prep
> Created: 2026-03-11
> Purpose: Define exit criteria for repo-only prep and deferred items for real Phase 2 deployment

---

## 0. What this document is

A hard-boundary checklist. It answers two questions:
1. What must be true before repo-only prep can be considered **sufficient**?
2. What is **explicitly deferred** to real Phase 2 deployment?

Phase 1 is complete. Phase 2 has not started. The broker is not yet deployed.

---

## 1. Repo-only prep exit criteria

All items must be true before repo-only prep is considered converged.

| # | Criterion | Status |
|---|-----------|--------|
| 1 | 8 action enum frozen, consistent across schema / common.sh / index.js / build-request.sh / validate-request.sh | Done |
| 2 | Request schema with `additionalProperties: false` and 5 required fields | Done |
| 3 | Result schema with `additionalProperties: false`, 5 required fields, ok/status invariant | Done |
| 4 | Per-action input schemas (8), all with `additionalProperties: false` | Done |
| 5 | Wrapper stubs (8), all sourcing common.sh, all passing syntax check | Done |
| 6 | Plugin skeleton (index.js) with build/validate parity | Done |
| 7 | Shell validators (validate-request.sh, build-request.sh) with action parity | Done |
| 8 | Happy-path fixtures (8 request + 8 result pairs) | Done |
| 9 | Negative fixtures (22+ cases) covering envelope, action-input, policy, execution | Done |
| 10 | Deprecated field ban enforced (operation, parameters, approval_id) | Done |
| 11 | Protocol spec (host-ops-broker-protocol-v1.md) with clear "not deployed" language | Done |
| 12 | Error taxonomy spec (error-taxonomy-v1.md) | Done |
| 13 | Contract matrix (contract-matrix-v1.md) with cross-layer index | Done |
| 14 | Contract freeze test (test_contract_freeze.sh) passing | Done |
| 15 | Integration test (test_phase2_integration.sh) passing | Done |
| 16 | Phase 2 prep validator (validate-phase2-prep.sh) passing | Done |
| 17 | Action inventory single-source file (action-inventory.json) | Done |
| 18 | Fixture registry (fixture-registry.json) | Done |
| 19 | All shell files pass `bash -n` | Done |
| 20 | All JSON files pass `jq empty` | Done |
| 21 | No file uses language implying broker is deployed or live | Done |

---

## 2. Explicitly deferred to real Phase 2 deployment

These items are **not** part of repo-only prep and must not be attempted until Phase 2 begins.

| # | Item | Reason |
|---|------|--------|
| 1 | Broker daemon / Unix socket service | Requires root, systemd unit, live host |
| 2 | Wrapper real execution logic (replacing stubs) | Requires root, live services |
| 3 | Transport path freeze (socket path) | TBD at deployment time |
| 4 | error_code mandatory enforcement | Optional/reserved in prep; mandatory in deployment |
| 5 | Plugin installation into OpenClaw runtime | Requires live /var/lib/openclaw |
| 6 | Workspace template publish with broker skill active | Requires deployed broker |
| 7 | Approval-policy integration with broker | Requires live approval chain |
| 8 | Audit log format and retention | Requires live logging infrastructure |
| 9 | Timeout/retry policy | Requires live performance data |
| 10 | Security hardening review (ownership, permissions, SELinux) | Requires live deployment context |

---

## 3. Known residual items (low priority, non-blocking)

| # | Item | Notes |
|---|------|-------|
| 1 | Result validation in shell (validate-result.sh) | JS has it; shell is request-only. Acceptable asymmetry for prep. |
| 2 | Systematic negative fixture wrapper execution testing | Fixtures exist; wrapper execution tests cover key cases but not all 22+. |
| 3 | error_code field semantics documentation | Reserved in schema, taxonomy defined, API doc updated. Full enumeration at Phase 2. |
