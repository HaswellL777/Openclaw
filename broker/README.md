# host-ops broker

This directory contains the host-ops broker framework.

Current status (2026-03-11):
- Phase 1 (1A + 1B) completed
- Phase 2 (broker formal deployment) not yet started
- Directory contains: schemas, wrapper contracts, protocol specification
- No live socket, no deployment, no wrapper execution from this repo yet

Design constraints (per design-v3.md §5.6):
- Structured JSON requests only — no free-form shell
- Only root-owned wrappers execute host mutations
- Request-id / task-id must be preserved end-to-end
- Unix socket or root-owned local IPC
- Strict schema validation, parameter whitelisting, path whitelisting
- Failure defaults to deny

Directory layout:
- `schemas/` — JSON schemas for request/response validation
- `schemas/actions/` — Per-action input schemas
- `wrappers/` — Wrapper script stubs and contracts
- `wrappers/lib/common.sh` — Shared validation library (sourced by all wrappers)

Related files outside this directory:
- `docs/specs/host-ops-broker-protocol-v1.md` — Protocol specification
- `plugins/host-ops-tool/` — Plugin skeleton (request builder, validator, index.js)
- `scripts/validate-broker-schemas.sh` — Schema cross-validation
- `scripts/validate-phase2-prep.sh` — Aggregated Phase 2 prep validation
- `tests/test_phase2_integration.sh` — Integration tests (plugin → wrapper pipeline, negative tests, drift detection)
- `tests/test_broker_schemas.sh` — Schema/wrapper/fixture runtime tests
