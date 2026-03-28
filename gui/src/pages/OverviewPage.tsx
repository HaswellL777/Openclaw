import { useMemo, useCallback } from "react";
import {
  ReactFlow,
  Background,
  Controls,
  type Node,
  type Edge,
  type NodeProps,
  Handle,
  Position,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import {
  useAgents,
  useSessions,
  useHealth,
  usePresence,
  useConnectionState,
} from "@/api/hooks";
import type { Agent, Session, PresenceEntry, HealthSnapshot } from "@/api/types";
import { agentFromKey } from "@/api/types";

// ---------------------------------------------------------------------------
// Custom node
// ---------------------------------------------------------------------------

type AgentNodeData = {
  agentId: string;
  label: string;
  isActive: boolean;
  sessionCount: number;
  isDefault: boolean;
};

function AgentNode({ data }: NodeProps<Node<AgentNodeData>>) {
  const d = data as AgentNodeData;
  return (
    <div className="rounded-lg border border-zinc-700 bg-zinc-900 px-4 py-3 shadow-lg min-w-[180px]">
      <Handle
        type="target"
        position={Position.Top}
        className="!bg-zinc-600 !w-2 !h-2 !border-none"
      />
      <div className="flex items-center gap-2 mb-1">
        <span
          className={`inline-block h-2.5 w-2.5 rounded-full shrink-0 ${
            d.isActive ? "bg-emerald-500" : "bg-zinc-600"
          }`}
        />
        <span className="text-sm font-semibold text-zinc-100 truncate">
          {d.label}
        </span>
        {d.isDefault && (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-indigo-500/20 text-indigo-300 font-medium">
            default
          </span>
        )}
      </div>
      <div className="text-xs text-zinc-500 mt-1">
        {d.sessionCount} session{d.sessionCount !== 1 ? "s" : ""}
      </div>
      <Handle
        type="source"
        position={Position.Bottom}
        className="!bg-zinc-600 !w-2 !h-2 !border-none"
      />
    </div>
  );
}

const nodeTypes = { agent: AgentNode };

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------

function buildTopology(
  agents: Agent[],
  defaultId: string,
  sessions: Session[],
): { nodes: Node<AgentNodeData>[]; edges: Edge[] } {
  const sessionCountByAgent = new Map<string, number>();

  for (const s of sessions) {
    const aid = agentFromKey(s.key);
    sessionCountByAgent.set(aid, (sessionCountByAgent.get(aid) ?? 0) + 1);
  }

  // Active = has at least one session
  const activeAgents = new Set(sessions.map((s) => agentFromKey(s.key)));

  // Simple layout: lay out all agents in a grid
  const COL_W = 240;
  const ROW_H = 120;
  const COLS = 4;
  const nodes: Node<AgentNodeData>[] = [];
  const edges: Edge[] = [];

  for (let i = 0; i < agents.length; i++) {
    const a = agents[i];
    const row = Math.floor(i / COLS);
    const col = i % COLS;
    const totalW = Math.min(agents.length, COLS) * COL_W;
    const startX = -totalW / 2 + COL_W / 2;

    nodes.push({
      id: a.id,
      type: "agent",
      position: { x: startX + col * COL_W, y: row * ROW_H },
      data: {
        agentId: a.id,
        label: a.name ?? a.id,
        isActive: activeAgents.has(a.id),
        sessionCount: sessionCountByAgent.get(a.id) ?? 0,
        isDefault: a.id === defaultId,
      },
    });
  }

  return { nodes, edges };
}

// ---------------------------------------------------------------------------
// Sub-panels
// ---------------------------------------------------------------------------

function HealthPanel({ health }: { health: HealthSnapshot | null }) {
  if (!health) {
    return (
      <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
        <h3 className="text-sm font-semibold text-zinc-300 mb-2">Health</h3>
        <p className="text-xs text-zinc-500">Waiting for health snapshot...</p>
      </div>
    );
  }

  const overallOk = health.ok;
  const channelEntries = Object.entries(health.channels ?? {});
  const agentEntries = health.agents ?? [];

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <h3 className="text-sm font-semibold text-zinc-300 mb-3">Health</h3>

      {/* Overall status */}
      <div className="flex items-center justify-between text-xs mb-3">
        <span className="text-zinc-400">Overall</span>
        <span className="flex items-center gap-1.5">
          <span
            className={`inline-block h-2 w-2 rounded-full ${
              overallOk ? "bg-emerald-500" : "bg-red-500"
            }`}
          />
          <span className={overallOk ? "text-emerald-400" : "text-red-400"}>
            {overallOk ? "healthy" : "unhealthy"}
          </span>
        </span>
      </div>

      {/* Channels */}
      {channelEntries.length > 0 && (
        <div className="space-y-1.5 mb-2">
          <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold">
            Channels
          </div>
          {channelEntries.map(([id, ch]) => (
            <div key={id} className="flex items-center justify-between text-xs">
              <span className="text-zinc-400">{id}</span>
              <span className="flex items-center gap-1.5">
                <span
                  className={`inline-block h-2 w-2 rounded-full ${
                    ch.running ? "bg-emerald-500" : "bg-red-500"
                  }`}
                />
                <span className={ch.running ? "text-emerald-400" : "text-red-400"}>
                  {ch.running ? "running" : "stopped"}
                </span>
              </span>
            </div>
          ))}
        </div>
      )}

      {/* Agents */}
      {agentEntries.length > 0 && (
        <div className="space-y-1.5">
          <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold">
            Agents
          </div>
          {agentEntries.map((ag) => (
            <div key={ag.agentId} className="flex items-center justify-between text-xs">
              <span className="text-zinc-400">
                {ag.agentId}
                {ag.isDefault ? " (default)" : ""}
              </span>
              <span className="text-emerald-400">active</span>
            </div>
          ))}
        </div>
      )}

      {channelEntries.length === 0 && agentEntries.length === 0 && (
        <p className="text-xs text-zinc-500">No health entries</p>
      )}
    </div>
  );
}

function PresencePanel({ presence }: { presence: PresenceEntry[] }) {
  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <h3 className="text-sm font-semibold text-zinc-300 mb-3">
        Presence ({presence.length})
      </h3>
      {presence.length === 0 ? (
        <p className="text-xs text-zinc-500">No active devices</p>
      ) : (
        <div className="space-y-2">
          {presence.map((p, i) => (
            <div
              key={p.host ?? `presence-${i}`}
              className="rounded bg-zinc-800 px-3 py-2 text-xs"
            >
              <div className="flex items-center justify-between">
                <span className="font-medium text-zinc-200">
                  {p.host ?? "unknown"}
                </span>
                <span className="text-zinc-500">
                  {p.mode ?? "--"} · {p.platform ?? "?"}
                </span>
              </div>
              <div className="text-zinc-500 mt-0.5">
                {p.version ?? "--"} · {p.ip ?? "--"}
                {p.roles?.length ? ` · ${p.roles.join(", ")}` : ""}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function OverviewPage() {
  const { data: agentData, isLoading: agentsLoading } = useAgents();
  const { data: sessionData, isLoading: sessionsLoading } = useSessions();
  const health = useHealth();
  const presence = usePresence();
  const connState = useConnectionState();

  const { nodes, edges } = useMemo(() => {
    if (!agentData?.agents) return { nodes: [], edges: [] };
    return buildTopology(
      agentData.agents,
      agentData.defaultId ?? "",
      sessionData?.sessions ?? [],
    );
  }, [agentData, sessionData]);

  const loading = agentsLoading || sessionsLoading;

  const proOptions = useMemo(() => ({ hideAttribution: true }), []);

  const defaultEdgeOptions = useMemo(
    () => ({ style: { stroke: "#3f3f46", strokeWidth: 2 } }),
    [],
  );

  const onInit = useCallback((instance: any) => {
    setTimeout(() => instance.fitView({ padding: 0.3 }), 50);
  }, []);

  if (connState === "disconnected") {
    return (
      <div className="p-6 flex items-center justify-center h-full">
        <div className="text-center">
          <div className="text-red-400 text-lg font-semibold mb-2">
            Disconnected
          </div>
          <p className="text-zinc-500 text-sm">
            Waiting for gateway connection...
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 h-full flex flex-col gap-4">
      <h1 className="text-2xl font-semibold text-zinc-100">Overview</h1>

      {/* Topology */}
      <div className="rounded-lg border border-zinc-800 bg-zinc-900 flex-1 min-h-[320px] relative overflow-hidden">
        {loading ? (
          <div className="absolute inset-0 flex items-center justify-center text-zinc-500 text-sm">
            Loading agents...
          </div>
        ) : nodes.length === 0 ? (
          <div className="absolute inset-0 flex items-center justify-center text-zinc-500 text-sm">
            No agents configured
          </div>
        ) : (
          <ReactFlow
            nodes={nodes}
            edges={edges}
            nodeTypes={nodeTypes}
            proOptions={proOptions}
            defaultEdgeOptions={defaultEdgeOptions}
            onInit={onInit}
            fitView
            panOnDrag
            zoomOnScroll
            minZoom={0.3}
            maxZoom={2}
            nodesDraggable={false}
            nodesConnectable={false}
            elementsSelectable={false}
            colorMode="dark"
          >
            <Background color="#27272a" gap={20} />
            <Controls
              showInteractive={false}
              className="!bg-zinc-800 !border-zinc-700 !shadow-lg [&>button]:!bg-zinc-800 [&>button]:!border-zinc-700 [&>button]:!text-zinc-300 [&>button:hover]:!bg-zinc-700"
            />
          </ReactFlow>
        )}
      </div>

      {/* Bottom panels */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <HealthPanel health={health} />
        <PresencePanel presence={presence} />
      </div>
    </div>
  );
}
