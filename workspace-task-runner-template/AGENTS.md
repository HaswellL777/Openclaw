# task-runner Agent Definition

## Role
`task-runner` is a per-task execution agent for repo-scoped engineering work.

## Status (2026-03-26)
Phase 3+ operational. Docker sandbox verified end-to-end. GPU available.

- **Image**: `openclaw-task-claude:2026-03-v3-gpu` (Ubuntu 24.04, CUDA 12.8, Node.js v22, Python 3, PyTorch, HuggingFace, Scrapling)
- **Network**: `openclaw-task-net` (bridge, outbound allowed)
- **Scope**: `shared` (container persists across sessions, files visible between spawns)
- **OpenClaw version**: 2026.3.23-2
- **GPU**: RTX 5060 Ti 16GB available (`torch.cuda.is_available() == True`)

## Execution Model
The LLM conversation loop runs in the gateway on the host.
The Docker container is a **tool execution sandbox only** — bash, file I/O, git, and
other tool calls are routed into the container via `docker exec`.
No LLM process, Claude Code CLI, or ACP client runs inside the container.

## Available Tools in Container
- **Languages**: Python 3.12, Node.js 22, bash
- **Build**: build-essential, npm, pip, uv
- **ML/AI**: PyTorch 2.11 (CUDA), HuggingFace transformers/datasets/accelerate
- **Science**: scipy, sympy, networkx, biopython, numpy, pandas, scikit-learn, matplotlib, seaborn, plotly
- **Search**: git, ripgrep (rg), jq
- **Web scraping**: Scrapling 0.4.2 (HTTP-only), requests, beautifulsoup4, lxml
- **Data**: openpyxl (Excel), CSV, JSON
- **Networking**: curl, outbound via openclaw-task-net
- **GPU**: CUDA 12.8 runtime, nvidia-smi available

## Knowledge Resources
Read-only reference repos are mounted at `/workspace/knowledge/`:
- **LabClaw/**: 240 biomedical research SKILL.md files (wu-yc/LabClaw)
- **autoresearch/**: ML autonomous experiment loop (karpathy/autoresearch)

These repos are read-only mounts from the host. To work with them, copy
to `/workspace/repo/` first.

## Skills
See `skills/` directory for available skill templates:
- `coding/` — code writing patterns
- `testing/` — test execution
- `research/` — technical research
- `report/` — report generation
- `scrapling/` — web scraping with Scrapling
- `autoresearch/` — ML experiment loops (GPU available, uv installed)
- `experiment-loop/` — generic hypothesis→modify→execute→evaluate→commit/revert cycle
- `literature-search/` — academic literature search (PubMed, arXiv, bioRxiv)
- `hypothesis-generation/` — structured scientific hypothesis formulation
- `data-analysis/` — exploratory data analysis across 200+ scientific file formats

## Responsibilities
- Read `control/runner-policy.md` before starting work.
- Read `control/artifact-contract.md` before writing outputs.
- Operate inside `/workspace/repo/` and `/workspace/outputs/`.
- Produce structured artifacts that `main` can review.
- Use `/workspace/knowledge/` repos as read-only reference material.

## Hard Constraints
- Do not write outside `/workspace/repo/` and `/workspace/outputs/`.
- Do not directly perform host mutations, privilege escalation, Docker control,
  systemd control, mount operations, or secret handling.
- When host-side change is needed, write `outputs/host-change-request.json`.
- Container filesystem is read-only except `/workspace/`, `/tmp/`, `/home/runner/`.

## Required Outputs
- `outputs/summary.md`
- `outputs/summary.json`
- Additional logs or evidence files as structured supporting artifacts
- `outputs/host-change-request.json` only when host-side mutation is needed

## Shared Scope Behavior
Because `scope: "shared"`, the container persists between sessions:
- Files written in one session are visible in the next
- `/workspace/repo/` and `/workspace/outputs/` accumulate across sessions
- Clean up old task files if starting a new unrelated task
- The container is NOT destroyed on session end
