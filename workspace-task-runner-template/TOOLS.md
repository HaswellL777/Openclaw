# task-runner Tool Policy

## Intent
`task-runner` is allowed to read, write, edit, and execute repo-local work
inside a shared Docker sandbox. Its tool usage must produce structured
artifacts under `outputs/`.

## First Reads
Read these before taking action:
- `control/runner-policy.md`
- `control/artifact-contract.md`

## Available Tools in Sandbox

### Languages & Runtimes
- `python3` (3.12) — general scripting, data analysis, ML
- `node` (v22) + `npm` — JavaScript/TypeScript execution
- `bash` — shell scripting

### Installed Packages
- **Scrapling** (`import scrapling`) — web scraping framework (HTTP-only mode)
- **pip** — install additional Python packages as needed
- **build-essential** — C/C++ compilation
- **curl** — HTTP requests
- **git** — version control
- **jq** — JSON processing
- **rg** (ripgrep) — fast code search

### Reference Resources (read-only)
- `/workspace/knowledge/LabClaw/` — 240 biomedical research skill definitions
- `/workspace/knowledge/autoresearch/` — ML experiment loop framework
- Copy to `/workspace/repo/` before modifying

## Allowed Use
- Read/write files in `/workspace/repo/` and `/workspace/outputs/`.
- Execute commands: python3, node, npm, git, bash, curl, pip, etc.
- Install Python packages with pip (use `--break-system-packages` flag).
- Use Scrapling for web scraping (respect robots.txt, add delays).
- Run tests, builds, and analysis scripts.

## Denied Use
- No direct host shell execution outside the container.
- No `sessions_spawn` chaining from `task-runner`.
- No elevated execution.
- No direct `/etc/openclaw`, `/opt/openclaw`, systemd, Docker, snapshot,
  Vault, or secrets mutation.

## Output Discipline
- `outputs/summary.md` — human-readable narrative
- `outputs/summary.json` — machine-readable status
- `outputs/report.md` — detailed findings (for research tasks)
- `outputs/host-change-request.json` — if host mutation needed

## Host-Change Rule
If the task result requires host-side mutation:
1. Stop short of live execution.
2. Record the need in `outputs/summary.json`.
3. Emit `outputs/host-change-request.json`.
4. Leave dispatch to `main` and broker.

## Shared Scope Notes
Container persists between sessions (`scope: "shared"`):
- Previous session files remain in `/workspace/`
- Clean up old task artifacts before starting unrelated work
- Use `/workspace/outputs/` for current task deliverables
