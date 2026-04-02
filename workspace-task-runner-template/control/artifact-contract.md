# task-runner Artifact Contract

## Purpose
This document defines the minimum repo-side artifact contract for future `task-runner -> main -> broker` orchestration.

## Required Outputs

### `outputs/summary.json`
- Machine-readable task result.
- Must record task status, changed files, validation results, evidence refs, forbidden actions, and whether operator approval is required.
- Must point to `outputs/host-change-request.json` when host-side follow-up is needed.

### `outputs/host-change-request.json`
- Structured declaration of proposed host-side follow-up.
- Must be declarative, reviewable, and broker-oriented.
- Must not contain live-side exact commands, shell snippets, or feasibility language presented as implementation.

## Required Fields For Host Change Requests
- `requires_operator_approval`
- `requested_host_ops`
- `forbidden_actions`
- `evidence_refs`
- `handoff`

## `requested_host_ops` Contract
Each requested operation must provide:
- A broker-aligned `action`
- Structured `inputs`
- A `sequence` number
- A short `justification`

The contract exists so that `main` can review and, in future, translate each entry into a broker request without reconstructing intent from prose.

## Evidence Rules
- Evidence refs must point to repo files, output files, logs, schemas, or authoritative docs.
- Evidence refs should use relative paths.
- Evidence refs are part of the contract, not optional commentary.

## Forbidden Action Rules
Artifacts must explicitly preserve the actions that the runner is not allowed to take directly, including:
- direct host shell execution
- direct systemd or Docker control
- direct snapshot or Vault manipulation
- direct config edits under `/etc/openclaw`
- unstructured operator command blocks

## Validation Assets
- Schema: `schemas/task-runner-summary.schema.json`
- Schema: `schemas/host-change-request.schema.json`
- Validator: `scripts/validate-task-runner-summary.py`
- Validator: `scripts/validate-host-change-request.py`

## Status Note
This contract is actively enforced. The task-runner workspace is published to live and task-init skill creates output directories following this contract. Schemas are at `/workspace/schemas/`.
