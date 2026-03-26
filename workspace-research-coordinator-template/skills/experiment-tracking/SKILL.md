# Experiment Tracking Skill

## Skill identity
- **Name**: `experiment-tracking`
- **Owner**: `research-coordinator`
- **Purpose**: Track experiments, maintain state, and make data-driven continuation decisions

## When to use this skill
- Running multiple experiments (ML training, code optimization, A/B tests)
- Need to track which experiments succeeded/failed and why
- Need to decide whether to continue, pivot, or stop a research direction

## State file format

`/workspace/outputs/experiments.tsv`:
```
id	timestamp	hypothesis	metric_before	metric_after	status	notes	commit
001	2026-03-26T10:00	reduce_vocab_size	2.45	2.38	keep	7 bpb improvement	abc123
002	2026-03-26T10:05	add_rope_scaling	2.38	2.41	discard	regression	-
003	2026-03-26T10:10	increase_lr_warmup	2.38	2.35	keep	3 bpb improvement	def456
```

## Decision rules
- **Keep**: metric improved → git commit, update baseline
- **Discard**: metric regressed → git reset, log failure reason
- **Stop**: 5 consecutive failures → report to parent, suggest pivot
- **Escalate**: unexpected crash or OOM → report to parent with diagnostics

## Workflow
1. Before each experiment: record hypothesis and current baseline
2. Spawn task-runner to execute experiment
3. After completion: record result, update experiments.tsv
4. Apply decision rule (keep/discard/stop/escalate)
5. If keep: update baseline, form next hypothesis
6. If stop: generate summary report with all experiments
