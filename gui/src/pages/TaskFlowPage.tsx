import { useState, useMemo, useCallback, useEffect } from "react";
import {
  ReactFlow, Background, Controls,
  type Node, type Edge, type NodeProps,
  Handle, Position, MarkerType,
  useNodesState, useEdgesState,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import { useQuery } from "@tanstack/react-query";
import { useSessions, useGatewayStore } from "@/api/hooks";
import type { Session, ChatMessage, ChatHistoryResult, RunRecord, TaskGroup } from "@/api/types";
import { agentFromKey } from "@/api/types";
import { MessageRenderer } from "@/components/MessageRenderer";
import { TaskDetailView } from "@/components/TaskDetailView";
import { StatusDot, Spinner, EmptyState, Badge } from "@/components/shared";

import { AGENT_COLORS, DEFAULT_AGENT_COLOR, agentColor as ac } from "@/api/agent-colors";

// AGENT_C alias for the legend rendering
const AGENT_C = AGENT_COLORS;

// ---------------------------------------------------------------------------
// Fetch runs export
// ---------------------------------------------------------------------------

function useRunsExport() {
  return useQuery<RunRecord[]>({
    queryKey: ["runs-api"],
    queryFn: async () => {
      const res = await fetch("/api/runs");
      if (!res.ok) return [];
      const data = await res.json();
      return Array.isArray(data) ? data : [];
    },
    staleTime: 30_000,
    refetchInterval: 60_000,
  });
}

// ---------------------------------------------------------------------------
// Build task groups from runs
// ---------------------------------------------------------------------------

const HEARTBEAT_RE = /health\s*check|please\s*respond\s*with\s*["']?task/i;
const TASK_GAP_MS = 10 * 60 * 1000; // 10 min gap = new task group

function buildTaskGroups(runs: RunRecord[], rootKey: string): TaskGroup[] {
  // Filter: only runs from this root (direct or indirect), exclude heartbeats
  const rootRuns = runs.filter(r =>
    r.requesterSessionKey === rootKey && !HEARTBEAT_RE.test(r.task)
  );

  if (rootRuns.length === 0) return [];

  // Sort by time
  const sorted = [...rootRuns].sort((a, b) => a.createdAt - b.createdAt);

  // Cluster by time proximity
  const groups: TaskGroup[] = [];
  let current: RunRecord[] = [sorted[0]];

  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].createdAt - current[current.length - 1].createdAt > TASK_GAP_MS) {
      groups.push(makeGroup(groups.length, rootKey, current));
      current = [];
    }
    current.push(sorted[i]);
  }
  if (current.length > 0) groups.push(makeGroup(groups.length, rootKey, current));

  // For each group, find second-level spawns (RC → sub-RC, etc.)
  for (const g of groups) {
    const childKeys = new Set(g.runs.map(r => r.childSessionKey));
    const secondLevel = runs.filter(r =>
      childKeys.has(r.requesterSessionKey) && !HEARTBEAT_RE.test(r.task)
    );
    g.runs.push(...secondLevel);
  }

  return groups;
}

function makeGroup(idx: number, reqKey: string, runs: RunRecord[]): TaskGroup {
  // Summarize: use first non-heartbeat task text
  const summary = runs.find(r => r.task.length > 10)?.task.slice(0, 80) ?? `Task batch ${idx + 1}`;
  return {
    id: `task-${idx}`,
    requesterKey: reqKey,
    runs: [...runs],
    startTime: runs[0].createdAt,
    taskSummary: summary,
  };
}

// ---------------------------------------------------------------------------
// Session node
// ---------------------------------------------------------------------------

type SessNodeData = { run: RunRecord; agentId: string; colors: typeof DEFAULT_AGENT_COLOR };

function SessNode({ data }: NodeProps<Node<SessNodeData>>) {
  const d = data as SessNodeData;
  const r = d.run;
  const statusColor = r.status === "ok" ? "text-emerald-400"
    : r.status === "timeout" ? "text-amber-400"
    : r.status === "error" ? "text-red-400" : "text-zinc-500";

  return (
    <div
      className="rounded-lg border px-3 py-2 shadow-lg shadow-black/30 w-[200px] cursor-pointer hover:brightness-125 transition-all"
      style={{ background: d.colors.bg, borderColor: d.colors.border, borderLeftWidth: 3, borderLeftColor: d.colors.dot }}
    >
      <Handle type="target" position={Position.Top} className="!bg-zinc-500 !w-1.5 !h-1.5 !border-none" />
      <div className="flex items-center gap-1.5 mb-1">
        <span className="w-2 h-2 rounded-full shrink-0" style={{ background: d.colors.dot }} />
        <span className="text-[10px] font-bold" style={{ color: d.colors.dot }}>{d.agentId}</span>
        <span className={`text-[9px] ml-auto ${statusColor}`}>{r.status}</span>
      </div>
      <div className="text-[9px] text-zinc-400 leading-tight line-clamp-2">{r.task.slice(0, 80) || r.label}</div>
      {r.createdAt > 0 && (
        <div className="text-[8px] text-zinc-600 mt-1 font-mono">
          {new Date(r.createdAt).toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })}
        </div>
      )}
      <Handle type="source" position={Position.Bottom} className="!bg-zinc-500 !w-1.5 !h-1.5 !border-none" />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Task group header node
// ---------------------------------------------------------------------------

type TaskHeaderData = { group: TaskGroup; customName?: string; isArchived?: boolean };

function TaskHeaderNode({ data }: NodeProps<Node<TaskHeaderData>>) {
  const g = (data as TaskHeaderData).group;
  const customName = (data as TaskHeaderData).customName;
  const isArchived = (data as TaskHeaderData).isArchived;
  const agents: Record<string, number> = {};
  for (const r of g.runs) {
    const a = agentFromKey(r.childSessionKey);
    agents[a] = (agents[a] ?? 0) + 1;
  }
  const time = new Date(g.startTime).toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });
  const displayName = customName || `Task #${g.id.split("-")[1] ? Number(g.id.split("-")[1]) + 1 : "?"}`;

  return (
    <div className={`rounded-2xl border bg-zinc-900/80 backdrop-blur px-5 py-3 shadow-xl shadow-black/30 w-[280px] cursor-pointer transition-colors ${isArchived ? "border-zinc-800/30 opacity-50" : "border-zinc-700/40 hover:border-indigo-500/40"}`}>
      <Handle type="target" position={Position.Top} className="!bg-zinc-500 !w-2 !h-2 !border-none" />
      <div className="flex items-center gap-2 mb-1">
        <div className="w-3 h-3 rounded-md bg-indigo-500/30 border border-indigo-500/50" />
        <span className="text-sm font-bold text-zinc-100">{displayName}</span>
        {isArchived && <span className="text-[9px] px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-500 border border-zinc-700/40">archived</span>}
        <span className="text-[10px] text-zinc-500 font-mono ml-auto">{time}</span>
      </div>
      <div className="text-[10px] text-zinc-400 leading-tight mb-2 line-clamp-2">{g.taskSummary}</div>
      <div className="flex flex-wrap gap-1 mb-1.5">
        {Object.entries(agents).map(([a, n]) => (
          <span key={a} className="text-[9px] px-1.5 py-0.5 rounded bg-zinc-800/80 border border-zinc-700/40"
            style={{ color: ac(a).dot }}>
            <span className="inline-block w-1.5 h-1.5 rounded-full mr-0.5" style={{ background: ac(a).dot }} />
            {a}{n > 1 ? ` x${n}` : ""}
          </span>
        ))}
      </div>
      <div className="text-[9px] text-indigo-400/60 flex items-center gap-1">
        <svg className="w-3 h-3" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z" clipRule="evenodd" />
        </svg>
        Click to view message flow
      </div>
      <Handle type="source" position={Position.Bottom} className="!bg-zinc-500 !w-2 !h-2 !border-none" />
    </div>
  );
}

// Root node
type RootData = { label: string; key: string; spawnCount: number };
function RootNodeComp({ data }: NodeProps<Node<RootData>>) {
  const d = data as RootData;
  return (
    <div className="rounded-2xl border-2 border-indigo-600/40 bg-indigo-950/60 px-5 py-3 shadow-xl shadow-indigo-500/10 w-[220px]">
      <div className="flex items-center gap-2 mb-1">
        <StatusDot status="active" size="sm" />
        <span className="text-sm font-bold text-indigo-300">{agentFromKey(d.key)}</span>
      </div>
      <div className="text-[10px] text-zinc-400 truncate">{d.label}</div>
      <div className="text-[10px] text-zinc-600 mt-1">{d.spawnCount} tasks</div>
      <Handle type="source" position={Position.Bottom} className="!bg-indigo-500 !w-2 !h-2 !border-none" />
    </div>
  );
}

const nodeTypes = { session: SessNode, taskHeader: TaskHeaderNode, root: RootNodeComp };

// ---------------------------------------------------------------------------
// Layout: root at top → task headers in a row → session nodes under each
// ---------------------------------------------------------------------------

function layoutGraph(rootKey: string, rootLabel: string, groups: TaskGroup[], taskNames?: Record<string, string>, archivedTasks?: Set<string>) {
  const nodes: Node[] = [];
  const edges: Edge[] = [];

  const NODE_W = 220;
  const NODE_GAP_X = 20;
  const NODE_GAP_Y = 90;
  const HEADER_OFFSET_Y = 70;
  const COLS = 3;
  const TASKS_PER_ROW = 2;
  const TASK_INNER_W = (NODE_W + NODE_GAP_X) * COLS;
  const TASK_COL_W = TASK_INNER_W + 80;

  for (let gi = 0; gi < groups.length; gi++) {
    const g = groups[gi];
    const taskCol = gi % TASKS_PER_ROW;
    const baseX = taskCol * TASK_COL_W;

    // Calculate Y based on previous rows' heights
    const taskRow = Math.floor(gi / TASKS_PER_ROW);
    // Estimate row height from max task in that row
    let maxRowH = 300;
    for (let ri = taskRow * TASKS_PER_ROW; ri < Math.min((taskRow + 1) * TASKS_PER_ROW, groups.length); ri++) {
      const rg = groups[ri];
      const first = rg.runs.filter(r => r.requesterSessionKey === rootKey).length;
      const second = rg.runs.filter(r => r.requesterSessionKey !== rootKey).length;
      const h = HEADER_OFFSET_Y + (Math.ceil(first / COLS) + Math.ceil(second / COLS)) * NODE_GAP_Y + 60;
      maxRowH = Math.max(maxRowH, h);
    }
    const baseY = taskRow * (maxRowH + 40);

    // Task header
    nodes.push({
      id: g.id, type: "taskHeader",
      position: { x: baseX, y: baseY },
      data: { group: g, customName: taskNames?.[g.id], isArchived: archivedTasks?.has(g.id) },
    });

    const firstLevel = g.runs.filter(r => r.requesterSessionKey === rootKey);
    const secondLevel = g.runs.filter(r => r.requesterSessionKey !== rootKey);

    // First-level nodes
    let nodeY = baseY + HEADER_OFFSET_Y;
    for (let i = 0; i < firstLevel.length; i++) {
      const r = firstLevel[i];
      const agent = agentFromKey(r.childSessionKey);
      const col = i % COLS;
      const row = Math.floor(i / COLS);

      nodes.push({
        id: r.childSessionKey, type: "session",
        position: { x: baseX + col * (NODE_W + NODE_GAP_X), y: nodeY + row * NODE_GAP_Y },
        data: { run: r, agentId: agent, colors: ac(agent) },
      });
      edges.push({
        id: `${g.id}->${r.childSessionKey}`, source: g.id, target: r.childSessionKey,
        style: { stroke: ac(agent).dot, strokeWidth: 1.5, opacity: 0.35 },
        markerEnd: { type: MarkerType.ArrowClosed, color: ac(agent).dot, width: 8, height: 8 },
      });
    }

    // Second-level nodes
    const secondY = nodeY + Math.ceil(firstLevel.length / COLS) * NODE_GAP_Y + 10;
    for (let i = 0; i < secondLevel.length; i++) {
      const r = secondLevel[i];
      const agent = agentFromKey(r.childSessionKey);
      const col = i % COLS;
      const row = Math.floor(i / COLS);

      nodes.push({
        id: r.childSessionKey, type: "session",
        position: { x: baseX + 20 + col * (NODE_W + NODE_GAP_X), y: secondY + row * NODE_GAP_Y },
        data: { run: r, agentId: agent, colors: ac(agent) },
      });

      const parentInGraph = nodes.some(n => n.id === r.requesterSessionKey);
      edges.push({
        id: `${r.requesterSessionKey}->${r.childSessionKey}`,
        source: parentInGraph ? r.requesterSessionKey : g.id,
        target: r.childSessionKey,
        style: { stroke: ac(agent).dot, strokeWidth: 1.5, opacity: 0.35 },
        markerEnd: { type: MarkerType.ArrowClosed, color: ac(agent).dot, width: 8, height: 8 },
      });
    }
  }

  return { nodes, edges };
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function TaskFlowPage() {
  const { data: sessionData, isLoading: sessionsLoading } = useSessions({ includeLastMessage: true });
  const { data: runsData, isLoading: runsLoading } = useRunsExport();
  const client = useGatewayStore(s => s.client);

  const [selectedRoot, setSelectedRoot] = useState<string | null>(null);
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [activeTaskGroup, setActiveTaskGroup] = useState<TaskGroup | null>(null);

  // Filter state
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [filterAgent, setFilterAgent] = useState<string>("all");
  const [filterSearch, setFilterSearch] = useState<string>("");

  // Task rename state (localStorage-backed)
  const [taskNames, setTaskNames] = useState<Record<string, string>>(() => {
    try { return JSON.parse(localStorage.getItem("openclaw-task-names") ?? "{}"); } catch { return {}; }
  });
  const [renamingTaskId, setRenamingTaskId] = useState<string | null>(null);
  const [renameInput, setRenameInput] = useState("");

  // Persist task names
  const saveTaskName = useCallback((taskId: string, name: string) => {
    setTaskNames(prev => {
      const next = { ...prev, [taskId]: name };
      localStorage.setItem("openclaw-task-names", JSON.stringify(next));
      return next;
    });
  }, []);
  const clearTaskName = useCallback((taskId: string) => {
    setTaskNames(prev => {
      const next = { ...prev };
      delete next[taskId];
      localStorage.setItem("openclaw-task-names", JSON.stringify(next));
      return next;
    });
  }, []);

  // Soft archive state (localStorage-only, no data deletion)
  const [archivedTasks, setArchivedTasks] = useState<Set<string>>(() => {
    try { return new Set(JSON.parse(localStorage.getItem("openclaw-archived-tasks") ?? "[]")); } catch { return new Set(); }
  });
  const [showArchived, setShowArchived] = useState(false);

  const archiveTask = useCallback((taskId: string) => {
    setArchivedTasks(prev => {
      const next = new Set(prev);
      next.add(taskId);
      localStorage.setItem("openclaw-archived-tasks", JSON.stringify([...next]));
      return next;
    });
  }, []);
  const restoreTask = useCallback((taskId: string) => {
    setArchivedTasks(prev => {
      const next = new Set(prev);
      next.delete(taskId);
      localStorage.setItem("openclaw-archived-tasks", JSON.stringify([...next]));
      return next;
    });
  }, []);

  const sessions = sessionData?.sessions ?? [];
  const runs = runsData ?? [];

  // Find root sessions that have spawns in runs.json
  const roots = useMemo(() => {
    const reqKeys = new Set(runs.map(r => r.requesterSessionKey));
    // Roots = sessions that are requesters but not children of anyone
    const childKeys = new Set(runs.map(r => r.childSessionKey));
    return [...reqKeys]
      .filter(k => !childKeys.has(k) && k)
      .map(k => sessions.find(s => s.key === k))
      .filter((s): s is Session => !!s);
  }, [runs, sessions]);

  useEffect(() => {
    if (!selectedRoot && roots.length > 0) setSelectedRoot(roots[0].key);
  }, [roots, selectedRoot]);

  const rootSession = useMemo(() => sessions.find(s => s.key === selectedRoot), [sessions, selectedRoot]);

  const groups = useMemo(() => {
    if (!selectedRoot || runs.length === 0) return [];
    return buildTaskGroups(runs, selectedRoot);
  }, [runs, selectedRoot]);

  // Apply filters
  const filteredGroups = useMemo(() => {
    return groups.filter(g => {
      // Archive filter: hide archived unless showArchived is on
      const isArchived = archivedTasks.has(g.id);
      if (isArchived && !showArchived) return false;
      // Status filter
      if (filterStatus !== "all") {
        const hasStatus = g.runs.some(r => r.status === filterStatus);
        if (!hasStatus) return false;
      }
      // Agent filter
      if (filterAgent !== "all") {
        const hasAgent = g.runs.some(r => agentFromKey(r.childSessionKey) === filterAgent);
        if (!hasAgent) return false;
      }
      // Text search
      if (filterSearch.trim()) {
        const q = filterSearch.toLowerCase();
        const name = taskNames[g.id] ?? "";
        const match = g.taskSummary.toLowerCase().includes(q)
          || name.toLowerCase().includes(q)
          || g.runs.some(r => r.task.toLowerCase().includes(q))
          || g.runs.some(r => agentFromKey(r.childSessionKey).includes(q));
        if (!match) return false;
      }
      return true;
    });
  }, [groups, filterStatus, filterAgent, filterSearch, taskNames, archivedTasks, showArchived]);

  const archivedCount = useMemo(() => groups.filter(g => archivedTasks.has(g.id)).length, [groups, archivedTasks]);

  // All unique agents across groups (for filter dropdown)
  const allAgents = useMemo(() => {
    const s = new Set<string>();
    for (const g of groups) for (const r of g.runs) s.add(agentFromKey(r.childSessionKey));
    return [...s].sort();
  }, [groups]);

  const { nodes: layoutNodes, edges: layoutEdges } = useMemo(() => {
    if (!rootSession || filteredGroups.length === 0) return { nodes: [], edges: [] };
    return layoutGraph(rootSession.key, rootSession.displayName || rootSession.key.slice(0, 30), filteredGroups, taskNames, archivedTasks);
  }, [rootSession, filteredGroups, taskNames, archivedTasks]);

  // Controlled state for dragging
  const [flowNodes, setFlowNodes, onNodesChange] = useNodesState(layoutNodes);
  const [flowEdges, setFlowEdges, onEdgesChange] = useEdgesState(layoutEdges);

  // Sync layout when data changes
  useEffect(() => {
    setFlowNodes(layoutNodes);
    setFlowEdges(layoutEdges);
  }, [layoutNodes, layoutEdges]);

  // Selected task group
  const selectedGroup = useMemo(() => {
    if (!selectedKey) return null;
    return groups.find(g => g.runs.some(r => r.childSessionKey === selectedKey)) ?? null;
  }, [groups, selectedKey]);

  function loadHistory(key: string) {
    if (!client) return;
    setSelectedKey(key);
    setHistoryLoading(true);
    client.call<ChatHistoryResult>("chat.history", { sessionKey: key })
      .then(r => setMessages(r?.messages ?? []))
      .catch(() => setMessages([]))
      .finally(() => setHistoryLoading(false));
  }

  const onNodeClick = useCallback((_: any, node: Node) => {
    if (node.type === "session") loadHistory(node.id);
    if (node.type === "taskHeader") {
      const d = node.data as TaskHeaderData;
      setActiveTaskGroup(d.group);
    }
  }, [client]);

  useEffect(() => {
    if (!client || !selectedKey) return;
    return client.on("chat", (p: any) => {
      if (p?.sessionKey === selectedKey && p?.state === "final" && p?.message)
        setMessages(prev => [...prev, p.message]);
    });
  }, [client, selectedKey]);

  const proOptions = useMemo(() => ({ hideAttribution: true }), []);
  const onInit = useCallback((inst: any) => { setTimeout(() => inst.fitView({ padding: 0.1 }), 100); }, []);
  const loading = sessionsLoading || runsLoading;

  // If a task group is selected, show the detail view
  if (activeTaskGroup) {
    return (
      <TaskDetailView
        group={activeTaskGroup}
        allRuns={runs}
        onBack={() => setActiveTaskGroup(null)}
        customName={taskNames[activeTaskGroup.id]}
        onRename={(name) => saveTaskName(activeTaskGroup.id, name)}
        onClearName={() => clearTaskName(activeTaskGroup.id)}
        isArchived={archivedTasks.has(activeTaskGroup.id)}
        onArchive={() => { archiveTask(activeTaskGroup.id); setActiveTaskGroup(null); }}
        onRestore={() => restoreTask(activeTaskGroup.id)}
      />
    );
  }

  return (
    <div className="flex h-screen">
      <div className="flex-1 flex flex-col">
        {/* Top bar */}
        <div className="px-4 py-2.5 border-b border-zinc-800 bg-zinc-900 flex items-center gap-3 flex-wrap">
          <span className="text-sm font-bold text-zinc-100">Task Flow</span>
          <select
            value={selectedRoot ?? ""}
            onChange={e => { setSelectedRoot(e.target.value); setSelectedKey(null); }}
            className="bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500 max-w-[400px]"
          >
            {roots.map(r => {
              const taskCount = buildTaskGroups(runs, r.key).length;
              return (
                <option key={r.key} value={r.key}>
                  [{agentFromKey(r.key)}] {r.displayName || r.key.slice(0, 35)} ({taskCount} tasks)
                </option>
              );
            })}
          </select>
          <span className="text-xs text-zinc-500">
            {filteredGroups.length}{filteredGroups.length !== groups.length ? `/${groups.length}` : ""} tasks, {filteredGroups.reduce((s, g) => s + g.runs.length, 0)} spawns
          </span>
          {/* Legend */}
          <div className="flex items-center gap-3 ml-auto text-[10px]">
            {Object.entries(AGENT_C).filter(([k]) => k !== "claude").map(([id, c]) => (
              <div key={id} className="flex items-center gap-1">
                <div className="w-2 h-2 rounded-full" style={{ background: c.dot }} />
                <span className="text-zinc-500">{id}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Filter bar */}
        <div className="px-4 py-1.5 border-b border-zinc-800/60 bg-zinc-900/50 flex items-center gap-2 flex-wrap text-[11px]">
          {/* Status filter */}
          <select
            value={filterStatus}
            onChange={e => setFilterStatus(e.target.value)}
            className="bg-zinc-800 border border-zinc-700/50 rounded px-2 py-1 text-zinc-300 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            <option value="all">All status</option>
            <option value="ok">OK</option>
            <option value="error">Error</option>
            <option value="timeout">Timeout</option>
            <option value="unknown">Unknown</option>
          </select>
          {/* Agent filter */}
          <select
            value={filterAgent}
            onChange={e => setFilterAgent(e.target.value)}
            className="bg-zinc-800 border border-zinc-700/50 rounded px-2 py-1 text-zinc-300 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            <option value="all">All agents</option>
            {allAgents.map(a => <option key={a} value={a}>{a}</option>)}
          </select>
          {/* Text search */}
          <input
            type="text"
            placeholder="Search tasks..."
            value={filterSearch}
            onChange={e => setFilterSearch(e.target.value)}
            className="bg-zinc-800 border border-zinc-700/50 rounded px-2 py-1 text-zinc-300 placeholder-zinc-600 focus:outline-none focus:ring-1 focus:ring-indigo-500 w-48"
          />
          {(filterStatus !== "all" || filterAgent !== "all" || filterSearch) && (
            <button
              onClick={() => { setFilterStatus("all"); setFilterAgent("all"); setFilterSearch(""); }}
              className="text-zinc-500 hover:text-zinc-300 transition-colors px-1.5"
            >
              Clear filters
            </button>
          )}
          {/* Archive toggle */}
          <div className="ml-auto flex items-center gap-1.5">
            {archivedCount > 0 && (
              <label className="flex items-center gap-1.5 cursor-pointer text-zinc-500 hover:text-zinc-400 transition-colors">
                <input
                  type="checkbox"
                  checked={showArchived}
                  onChange={e => setShowArchived(e.target.checked)}
                  className="rounded border-zinc-600 bg-zinc-800 text-indigo-500 focus:ring-indigo-500 focus:ring-offset-0 w-3.5 h-3.5"
                />
                <span>Show archived ({archivedCount})</span>
              </label>
            )}
          </div>
        </div>

        {/* Graph */}
        <div className="flex-1 relative">
          {loading ? <div className="absolute inset-0 flex items-center justify-center"><Spinner text="Loading..." /></div> :
           runs.length === 0 ? (
            <div className="absolute inset-0 flex items-center justify-center">
              <EmptyState icon="<>" message="No runs data. Run: bash scripts/export-runs.sh" />
            </div>
          ) : layoutNodes.length === 0 ? (
            <div className="absolute inset-0 flex items-center justify-center">
              <EmptyState icon="<>" message="No task spawns found for this session" />
            </div>
          ) : (
            <ReactFlow
              nodes={flowNodes} edges={flowEdges} nodeTypes={nodeTypes}
              onNodesChange={onNodesChange} onEdgesChange={onEdgesChange}
              proOptions={proOptions} onInit={onInit} onNodeClick={onNodeClick}
              fitView panOnDrag zoomOnScroll minZoom={0.05} maxZoom={2}
              nodesConnectable={false} colorMode="dark"
            >
              <Background color="#18181b" gap={20} />
              <Controls showInteractive={false}
                className="!bg-zinc-800 !border-zinc-700 !shadow-lg [&>button]:!bg-zinc-800 [&>button]:!border-zinc-700 [&>button]:!text-zinc-300 [&>button:hover]:!bg-zinc-700"
              />
            </ReactFlow>
          )}
        </div>
      </div>

      {/* Right panel */}
      {selectedKey && (
        <div className="w-[380px] shrink-0 border-l border-zinc-800 bg-zinc-950 flex flex-col">
          {/* Task group header with rename + delete actions */}
          {selectedGroup && (
            <div className="border-b border-zinc-800 bg-zinc-900/50">
              <div className="px-3 py-2 flex items-center gap-2">
                {renamingTaskId === selectedGroup.id ? (
                  <form className="flex-1 flex items-center gap-1.5" onSubmit={e => {
                    e.preventDefault();
                    if (renameInput.trim()) saveTaskName(selectedGroup.id, renameInput.trim());
                    setRenamingTaskId(null);
                  }}>
                    <input
                      autoFocus
                      value={renameInput}
                      onChange={e => setRenameInput(e.target.value)}
                      className="flex-1 bg-zinc-800 border border-indigo-500/50 rounded px-2 py-0.5 text-xs text-zinc-200 focus:outline-none"
                      placeholder="Task name..."
                    />
                    <button type="submit" className="text-[10px] text-indigo-400 hover:text-indigo-300">Save</button>
                    <button type="button" onClick={() => setRenamingTaskId(null)} className="text-[10px] text-zinc-500 hover:text-zinc-400">Cancel</button>
                  </form>
                ) : (
                  <>
                    <span className="text-[11px] text-zinc-300 font-semibold truncate flex-1">
                      {taskNames[selectedGroup.id] || `Task #${groups.indexOf(selectedGroup) + 1}`}
                    </span>
                    <button
                      onClick={() => { setRenamingTaskId(selectedGroup.id); setRenameInput(taskNames[selectedGroup.id] ?? ""); }}
                      className="text-[10px] text-zinc-500 hover:text-zinc-300 transition-colors px-1.5 py-0.5 rounded hover:bg-zinc-800"
                      title="Rename task"
                    >
                      Rename
                    </button>
                    {taskNames[selectedGroup.id] && (
                      <button
                        onClick={() => clearTaskName(selectedGroup.id)}
                        className="text-[10px] text-zinc-600 hover:text-zinc-400 transition-colors"
                        title="Clear custom name"
                      >
                        Reset
                      </button>
                    )}
                    {archivedTasks.has(selectedGroup.id) ? (
                      <button
                        onClick={() => restoreTask(selectedGroup.id)}
                        className="text-[10px] text-emerald-400/70 hover:text-emerald-400 transition-colors px-1.5 py-0.5 rounded hover:bg-emerald-500/10"
                      >
                        Restore
                      </button>
                    ) : (
                      <button
                        onClick={() => archiveTask(selectedGroup.id)}
                        className="text-[10px] text-zinc-500 hover:text-zinc-300 transition-colors px-1.5 py-0.5 rounded hover:bg-zinc-800"
                      >
                        Archive
                      </button>
                    )}
                  </>
                )}
              </div>
              <div className="px-3 pb-1.5 text-[10px] text-zinc-500">
                {selectedGroup.runs.length} sessions
              </div>
              <div className="max-h-[160px] overflow-y-auto">
                {selectedGroup.runs.map(r => {
                  const agent = agentFromKey(r.childSessionKey);
                  const active = r.childSessionKey === selectedKey;
                  return (
                    <button key={r.childSessionKey} onClick={() => loadHistory(r.childSessionKey)}
                      className={`w-full text-left px-3 py-1.5 flex items-center gap-2 text-[11px] transition-colors ${active ? "bg-zinc-800" : "hover:bg-zinc-800/50"}`}
                    >
                      <span className="w-2 h-2 rounded-full shrink-0" style={{ background: ac(agent).dot }} />
                      <span style={{ color: active ? ac(agent).dot : undefined }} className={active ? "font-medium" : "text-zinc-400"}>{agent}</span>
                      <span className="text-zinc-600 truncate flex-1 text-[10px]">{r.task.slice(0, 30) || r.label}</span>
                    </button>
                  );
                })}
              </div>
            </div>
          )}
          {/* Session header */}
          <div className="px-3 py-2 border-b border-zinc-800 bg-zinc-900">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2 min-w-0">
                <Badge variant={(agentFromKey(selectedKey) === "main" ? "indigo" : agentFromKey(selectedKey) === "research-coordinator" ? "blue" : agentFromKey(selectedKey) === "task-runner" ? "emerald" : agentFromKey(selectedKey) === "auditor" ? "purple" : "amber") as any}>
                  {agentFromKey(selectedKey)}
                </Badge>
                <span className="text-xs text-zinc-300 truncate">{selectedKey.split(":").pop()?.slice(0, 12)}</span>
              </div>
              <div className="flex gap-1.5">
                <a href={`/chat?session=${encodeURIComponent(selectedKey)}`} target="_blank" rel="noopener noreferrer" className="px-2 py-1 text-[10px] bg-indigo-600/20 text-indigo-400 rounded hover:bg-indigo-600/30 inline-flex items-center gap-1">Chat<svg className="w-2.5 h-2.5" viewBox="0 0 20 20" fill="currentColor"><path d="M11 3a1 1 0 100 2h2.586l-6.293 6.293a1 1 0 101.414 1.414L15 6.414V9a1 1 0 102 0V4a1 1 0 00-1-1h-5z" /><path d="M5 5a2 2 0 00-2 2v8a2 2 0 002 2h8a2 2 0 002-2v-3a1 1 0 10-2 0v3H5V7h3a1 1 0 000-2H5z" /></svg></a>
                <button onClick={() => { setSelectedKey(null); setMessages([]); }} className="px-2 py-1 text-[10px] bg-zinc-700 text-zinc-400 rounded hover:bg-zinc-600">Close</button>
              </div>
            </div>
          </div>
          {/* Messages */}
          <div className="flex-1 overflow-y-auto p-3 space-y-2">
            {historyLoading ? <Spinner text="Loading..." /> :
             messages.length === 0 ? <EmptyState message="No messages" /> :
             messages.map((msg, i) => (
              <MessageRenderer key={`${msg.ts ?? i}-${i}`} msg={msg} sessionKey={selectedKey}
                onSessionClick={key => { if (runs.some(r => r.childSessionKey === key)) loadHistory(key); }}
                allMessages={messages} messageIndex={i}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
