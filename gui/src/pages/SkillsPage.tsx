import { useState, useMemo } from "react";
import { useAgents, useSkillsStatus, useToolsCatalog } from "@/api/hooks";
import type { ToolGroup } from "@/api/types";

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

function Spinner() {
  return (
    <div className="flex items-center gap-2 text-zinc-400 text-sm py-8">
      <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z" />
      </svg>
      Loading…
    </div>
  );
}

function ErrorBox({ message }: { message: string }) {
  return (
    <div className="rounded-lg border border-red-800/50 bg-red-950/30 px-4 py-3 text-sm text-red-300">
      {message}
    </div>
  );
}

function EmptyState({ message }: { message: string }) {
  return <p className="text-sm text-zinc-500 py-4">{message}</p>;
}

// ---------------------------------------------------------------------------
// Agent selector (shared between tabs)
// ---------------------------------------------------------------------------

interface AgentSelectorProps {
  value: string;
  onChange: (id: string) => void;
  agents: { id: string; name?: string }[];
  loading?: boolean;
}

function AgentSelector({ value, onChange, agents, loading }: AgentSelectorProps) {
  return (
    <div className="flex items-center gap-3">
      <label className="text-sm text-zinc-400">Agent:</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={loading || agents.length === 0}
        className="rounded border border-zinc-700 bg-zinc-800 px-3 py-1.5 text-sm text-zinc-200
          focus:border-zinc-500 focus:outline-none focus:ring-1 focus:ring-zinc-500
          disabled:opacity-50 disabled:cursor-not-allowed"
      >
        <option value="">All agents</option>
        {agents.map((a) => (
          <option key={a.id} value={a.id}>
            {a.name ?? a.id}
          </option>
        ))}
      </select>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tab bar
// ---------------------------------------------------------------------------

type TabId = "skills" | "tools";

function TabBar({ active, onChange }: { active: TabId; onChange: (tab: TabId) => void }) {
  const tabs: { id: TabId; label: string }[] = [
    { id: "skills", label: "Skills" },
    { id: "tools", label: "Tools" },
  ];

  return (
    <div className="flex gap-1 border-b border-zinc-800 mb-4">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          onClick={() => onChange(tab.id)}
          className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px ${
            active === tab.id
              ? "border-emerald-500 text-zinc-100"
              : "border-transparent text-zinc-500 hover:text-zinc-300"
          }`}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Skills tab
// ---------------------------------------------------------------------------

function StatusDot({ status }: { status: string }) {
  const color =
    status === "active" || status === "installed" || status === "enabled"
      ? "bg-emerald-500"
      : status === "error" || status === "failed"
        ? "bg-red-500"
        : status === "updating" || status === "loading"
          ? "bg-amber-500 animate-pulse"
          : "bg-zinc-600";

  return <span className={`inline-block h-2 w-2 rounded-full ${color}`} />;
}

function SkillsTab({ agentId }: { agentId: string }) {
  const { data, isLoading, error, refetch } = useSkillsStatus(agentId || undefined);
  const [updating, setUpdating] = useState(false);

  const installed = useMemo(() => {
    if (!data?.installed) return [];
    return data.installed as { name?: string; id?: string; status?: string; version?: string; [k: string]: unknown }[];
  }, [data]);

  const handleUpdateAll = async () => {
    setUpdating(true);
    // Trigger refetch as a proxy for "update" — the gateway handles skill updates
    // In a real implementation this would call skills.updateAll RPC
    try {
      await refetch();
    } finally {
      setUpdating(false);
    }
  };

  if (isLoading) return <Spinner />;
  if (error) return <ErrorBox message={error instanceof Error ? error.message : "Failed to load skills"} />;

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <p className="text-sm text-zinc-400">
          {installed.length} skill{installed.length !== 1 ? "s" : ""} installed
        </p>
        <button
          onClick={handleUpdateAll}
          disabled={updating || installed.length === 0}
          className="rounded px-3 py-1.5 text-xs font-medium transition-colors
            bg-zinc-700 hover:bg-zinc-600 text-zinc-200
            disabled:bg-zinc-800 disabled:text-zinc-600 disabled:cursor-not-allowed"
        >
          {updating ? "Updating…" : "Update All"}
        </button>
      </div>

      {installed.length === 0 ? (
        <EmptyState message="No skills installed for this agent." />
      ) : (
        <div className="space-y-1">
          {installed.map((skill, i) => {
            const name = skill.name ?? skill.id ?? `skill-${i}`;
            const status = (typeof skill.status === "string" ? skill.status : "installed").toLowerCase();

            return (
              <div
                key={name}
                className="flex items-center gap-3 rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3"
              >
                <StatusDot status={status} />
                <div className="flex-1 min-w-0">
                  <span className="text-sm font-medium text-zinc-100 truncate block">{name}</span>
                </div>
                <span className="text-xs text-zinc-500 capitalize">{status}</span>
                {skill.version && (
                  <span className="text-xs text-zinc-600 font-mono">{skill.version}</span>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tools tab
// ---------------------------------------------------------------------------

function ToolGroupCard({ group }: { group: ToolGroup }) {
  const [expanded, setExpanded] = useState(false);
  const tools = group.tools;
  const showToggle = tools.length > 6;
  const visible = expanded ? tools : tools.slice(0, 6);

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-semibold text-zinc-100">{group.label}</h3>
        <span className="text-xs text-zinc-500">{tools.length} tool{tools.length !== 1 ? "s" : ""}</span>
      </div>

      <div className="space-y-1">
        {visible.map((tool) => (
          <div
            key={tool.id}
            className="flex items-center gap-3 rounded px-3 py-1.5 bg-zinc-800/50"
          >
            <span className="text-xs font-mono text-zinc-400 min-w-[160px] truncate" title={tool.id}>
              {tool.id}
            </span>
            <span className="text-xs text-zinc-300 truncate">{tool.label}</span>
          </div>
        ))}
      </div>

      {showToggle && (
        <button
          onClick={() => setExpanded((v) => !v)}
          className="mt-2 text-xs text-zinc-500 hover:text-zinc-300 transition-colors"
        >
          {expanded ? "Show less" : `Show all ${tools.length}`}
        </button>
      )}
    </div>
  );
}

function ToolsTab({ agentId }: { agentId: string }) {
  const { data, isLoading, error } = useToolsCatalog(agentId || undefined);

  if (isLoading) return <Spinner />;
  if (error) return <ErrorBox message={error instanceof Error ? error.message : "Failed to load tools catalog"} />;

  const groups = data?.groups ?? [];
  const profiles = data?.profiles ?? [];

  return (
    <div>
      {/* Profile badges */}
      {profiles.length > 0 && (
        <div className="flex items-center gap-2 mb-4">
          <span className="text-xs text-zinc-500">Profiles:</span>
          {profiles.map((p) => (
            <span
              key={p.id}
              className="inline-block rounded bg-zinc-800 border border-zinc-700 px-2 py-0.5 text-xs text-zinc-300"
            >
              {p.label}
            </span>
          ))}
        </div>
      )}

      {groups.length === 0 ? (
        <EmptyState message="No tool groups found for this agent." />
      ) : (
        <div className="space-y-4">
          {groups.map((group) => (
            <ToolGroupCard key={group.label} group={group} />
          ))}

          {/* Total tool count */}
          <p className="text-xs text-zinc-600 text-right">
            {groups.reduce((sum, g) => sum + g.tools.length, 0)} tools across {groups.length} group{groups.length !== 1 ? "s" : ""}
          </p>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function SkillsPage() {
  const [activeTab, setActiveTab] = useState<TabId>("skills");
  const [agentId, setAgentId] = useState("");

  const { data: agentData, isLoading: agentsLoading } = useAgents();
  const agents = agentData?.agents ?? [];

  return (
    <div className="p-6 max-w-4xl">
      <div className="flex items-center justify-between mb-1">
        <h1 className="text-2xl font-semibold text-zinc-100">Skills &amp; Tools</h1>
        <AgentSelector
          value={agentId}
          onChange={setAgentId}
          agents={agents}
          loading={agentsLoading}
        />
      </div>
      <p className="text-sm text-zinc-500 mb-4">
        Installed skills and available tool catalog
      </p>

      <TabBar active={activeTab} onChange={setActiveTab} />

      {activeTab === "skills" && <SkillsTab agentId={agentId} />}
      {activeTab === "tools" && <ToolsTab agentId={agentId} />}
    </div>
  );
}
