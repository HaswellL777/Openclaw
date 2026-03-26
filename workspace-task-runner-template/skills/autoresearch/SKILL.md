# Autoresearch Skill

## Skill identity
- **Name**: `autoresearch`
- **Owner**: `task-runner` (GPU variant) / `claude-engineer` (ACP, Phase 4)
- **Purpose**: Autonomous ML experiment loop — edit code, train, evaluate, iterate
- **Status**: operational (GPU image deployed, nvidia default runtime configured 2026-03-26)

## Prerequisites
- GPU image: `openclaw-task-claude:2026-03-v3-gpu` (Dockerfile.gpu) — deployed
- GPU passthrough: Docker daemon default-runtime=nvidia — configured
- vLLM stopped (frees 14.2GB VRAM) — done (2026-03-25)
- `uv` package manager installed in container — included in GPU image
- Reference repo: `/workspace/knowledge/autoresearch/` (clone from github.com/karpathy/autoresearch)
- Shared scope container (files persist between sessions)

## What this skill does
Implements the autoresearch experiment loop (Karpathy, 2026):
1. Clone autoresearch repo to working directory
2. Install dependencies (`uv sync`)
3. Prepare data (`uv run prepare.py` — downloads ClimbMix dataset, trains BPE tokenizer)
4. Establish baseline (`uv run train.py` — 5 min training, records val_bpb)
5. Enter experiment loop:
   - Read code, form hypothesis for improvement
   - Edit `train.py` (the ONLY editable file)
   - Run experiment (`uv run train.py` — exactly 5 min wall-clock)
   - Evaluate: if val_bpb improved → git commit; else → git reset
   - Log to `results.tsv`
   - Repeat

Each experiment takes ~5 minutes. ~12 experiments/hour, ~100 overnight.

## When to use this skill
- Operator requests ML experiment automation
- Task involves optimizing model training code
- Task involves hyperparameter or architecture search

## RTX 5060 Ti 16GB adaptation
Default autoresearch targets H100 (80GB). For 16GB GPU:
- Reduce model size (smaller vocab_size, lower MAX_SEQ_LEN)
- Replace FlashAttention-3 with `torch.nn.functional.scaled_dot_product_attention`
- Reference: `jsegov/autoresearch-win-rtx` community fork for consumer GPU config

## Workflow
1. Copy autoresearch from /workspace/knowledge/autoresearch/ to /workspace/repo/
2. `cd /workspace/repo && uv sync`
3. `uv run prepare.py` (one-time, ~5 min)
4. `uv run train.py` (baseline, ~5 min)
5. Record baseline val_bpb
6. Begin experiment loop (see program.md in repo for agent instructions)
7. After N experiments, generate report to /workspace/outputs/

## Output format
/workspace/outputs/autoresearch-report.md:
- Number of experiments run
- Best val_bpb achieved (vs baseline)
- Key improvements found (with git commit hashes)
- Failed hypotheses summary

/workspace/repo/results.tsv:
- commit, val_bpb, memory_gb, status (keep/discard/crash), description

## Safety rules
- Only edit `train.py` — never modify `prepare.py` or evaluation code
- Each experiment must complete within 5 minutes wall-clock
- Do not add new dependencies
- Do not modify data pipeline or tokenizer
- Git commit successful experiments, git reset failed ones
- Monitor GPU memory — OOM means model config too large for 16GB

## Related skills
- `coding`: General code editing patterns
- `testing`: Experiment evaluation methodology
- `report`: Final report generation
