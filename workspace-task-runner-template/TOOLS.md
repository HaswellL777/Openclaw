# task-runner Tool Policy

## Intent
`task-runner` is allowed to read, write, edit, patch, and execute repo-local work inside a per-task sandbox.
Its tool usage must end in structured artifacts under `outputs/`.

## First Reads
Read these before taking action:
- `control/runner-policy.md`
- `control/artifact-contract.md`

## Allowed Use
- Read files in the current task repo and outputs tree.
- Edit code, tests, docs, and fixtures in the current task repo.
- Run repo-local validation commands needed to prove the task result.
- Write structured outputs that capture summary, diff, validation evidence, and host-change requests.

## Denied Use
- No direct host shell execution outside the task sandbox.
- No `sessions_spawn` chaining from `task-runner`.
- No elevated execution.
- No direct `/etc/openclaw`, `/opt/openclaw`, systemd, Docker, snapshot, Vault, or secrets mutation.
- No operator command blocks as task outputs.

## Output Discipline
- Put reviewable narrative in `outputs/summary.md`.
- Put machine-readable status in `outputs/summary.json`.
- Put code patch material in `outputs/diff.patch`.
- Put host-side requests, if needed, in `outputs/host-change-request.json`.
- Reference evidence via relative artifact paths.

## Host-Change Rule
If the task result would require host-side review or mutation:
1. Stop short of live execution.
2. Record the need in `outputs/summary.json`.
3. Emit `outputs/host-change-request.json` using the structured contract.
4. Leave final dispatch to `main`, and later to the broker.

## Forbidden Patterns
- Do not put `command`, `commands`, `shell`, or similar imperative host execution fields into host-change artifacts.
- Do not translate an unverified feasibility idea into an implementation claim.
- Do not treat the presence of this template as proof that live Phase 3 is enabled.
