---
name: experiment-loop
description: |
  Iterative code improvement via hypothesis, modify, execute, evaluate, commit/revert cycle.
---

# Experiment Loop Skill

## Skill identity
- **Name**: `experiment-loop`
- **Owner**: `task-runner` / `research-coordinator` (orchestration)
- **Purpose**: Iterative code improvement via hypothesis → modify → execute → evaluate → commit/revert cycle

## When to use this skill
- Optimizing any metric through iterative code changes
- ML training improvement (autoresearch pattern)
- Performance optimization (latency, throughput, memory)
- Code quality improvement (test pass rate, coverage)
- Any task where: you change code, measure a metric, and decide keep/discard

## The pattern

This skill abstracts the autoresearch experiment loop (Karpathy, 2026) into a general pattern:

```
1. ESTABLISH BASELINE
   - Run the evaluation → record metric M₀
   - git commit baseline

2. FORM HYPOTHESIS
   - Read the code, identify potential improvement
   - Write down: "If I change X, metric should improve because Y"

3. MODIFY
   - Edit exactly ONE thing (single variable change)
   - Keep changes minimal and reversible

4. EXECUTE
   - Run the evaluation → record metric M₁
   - Enforce wall-clock timeout (default: 5 minutes)

5. EVALUATE
   - If M₁ < M₀ (improved): git commit, update baseline M₀ = M₁
   - If M₁ >= M₀ (no improvement): git reset --hard, log failure reason
   - If crash/timeout: git reset --hard, log error, reduce change magnitude

6. LOG
   - Append to results.tsv: id, timestamp, hypothesis, M₀, M₁, status, notes

7. REPEAT from step 2
```

## Key principles
- **Single variable changes**: Never change multiple things at once. If the metric improves, you must know WHY.
- **Always measure**: No "I think this is better" — measure the metric every time.
- **Commit or revert**: Never leave uncommitted changes between experiments.
- **Log everything**: Every experiment gets a row in results.tsv, including failures.
- **Know when to stop**: After 5 consecutive failures with no improvement, stop and review approach.

## Canonical example: autoresearch
See `/workspace/knowledge/autoresearch/` for the reference implementation:
- Editable file: `train.py` only
- Metric: `val_bpb` (bits per byte, lower is better)
- Evaluation: `uv run train.py` (5 min wall-clock)
- Dataset: ClimbMix + BPE tokenizer

## Generalized applications
| Domain | Editable | Metric | Evaluation Command |
|--------|----------|--------|--------------------|
| ML training | train.py | val_loss / val_bpb | `python train.py` |
| API latency | handler code | p99 latency ms | `wrk -t4 -c100 -d30s` |
| Test coverage | source code | coverage % | `pytest --cov` |
| Build size | webpack config | bundle KB | `npm run build && du -s dist/` |
| Memory usage | algorithm code | peak RSS MB | `valgrind --tool=massif` |

## Results tracking

`results.tsv` format:
```
id	timestamp	hypothesis	metric_before	metric_after	status	notes	commit
001	2026-03-26T10:00	reduce_vocab	2.45	2.38	keep	worked	abc123
002	2026-03-26T10:05	add_rope	2.38	2.41	discard	regression	-
```

## Safety rules
- Respect wall-clock timeout for each experiment
- Never modify evaluation code (that's your measuring stick)
- Never add new dependencies without explicit approval
- Monitor resource usage (GPU memory, disk space)
- Git commit successful changes, git reset failed ones — no exception
