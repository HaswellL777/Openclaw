// Shared agent color palette used across TaskFlowPage, TaskDetailView, etc.

export interface AgentColorSet {
  dot: string;
  bg: string;
  border: string;
}

export const AGENT_COLORS: Record<string, AgentColorSet> = {
  main:                   { dot: "#6366f1", bg: "rgba(99,102,241,0.08)",  border: "rgba(99,102,241,0.3)" },
  "research-coordinator": { dot: "#3b82f6", bg: "rgba(59,130,246,0.08)",  border: "rgba(59,130,246,0.3)" },
  auditor:                { dot: "#a855f7", bg: "rgba(168,85,247,0.08)",  border: "rgba(168,85,247,0.3)" },
  "task-runner":          { dot: "#10b981", bg: "rgba(16,185,129,0.08)",  border: "rgba(16,185,129,0.3)" },
  "claude-engineer":      { dot: "#06b6d4", bg: "rgba(6,182,212,0.08)",   border: "rgba(6,182,212,0.3)" },
  claude:                 { dot: "#06b6d4", bg: "rgba(6,182,212,0.08)",   border: "rgba(6,182,212,0.3)" },
};

export const DEFAULT_AGENT_COLOR: AgentColorSet = {
  dot: "#f59e0b",
  bg: "rgba(245,158,11,0.08)",
  border: "rgba(245,158,11,0.3)",
};

export function agentColor(id: string): AgentColorSet {
  return AGENT_COLORS[id] ?? DEFAULT_AGENT_COLOR;
}
