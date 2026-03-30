import { useState, useMemo } from "react";
import { useAgents, useSkillsStatus, useToolsCatalog } from "@/api/hooks";
import type { Skill, ToolGroup } from "@/api/types";
import {
  PageHeader,
  Card,
  CardBody,
  StatusDot,
  Spinner,
  EmptyState,
  ErrorBox,
  Badge,
} from "@/components/shared";

// ---------------------------------------------------------------------------
// Agent selector
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
        className="rounded-lg border border-zinc-700 bg-zinc-800 px-3 py-1.5 text-sm text-zinc-200
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

function TabBar({
  active,
  onChange,
}: {
  active: TabId;
  onChange: (tab: TabId) => void;
}) {
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
              ? "border-indigo-500 text-zinc-100"
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

function SkillsTab({ agentId }: { agentId: string }) {
  const { data, isLoading, error, refetch } = useSkillsStatus(
    agentId || undefined,
  );
  const [updating, setUpdating] = useState(false);
  const [sourceFilter, setSourceFilter] = useState("all");
  const [search, setSearch] = useState("");

  const allSkills: Skill[] = useMemo(() => {
    return data?.skills ?? [];
  }, [data]);

  // Unique sources for filter
  const sources = useMemo(() => {
    const s = new Set<string>();
    for (const sk of allSkills) if (sk.source) s.add(sk.source);
    return [...s].sort();
  }, [allSkills]);

  // Filtered skills
  const skills = useMemo(() => {
    return allSkills.filter(sk => {
      if (sourceFilter !== "all" && sk.source !== sourceFilter) return false;
      if (search) {
        const q = search.toLowerCase();
        if (!sk.name.toLowerCase().includes(q) && !(sk.description ?? "").toLowerCase().includes(q)) return false;
      }
      return true;
    });
  }, [allSkills, sourceFilter, search]);

  const handleUpdateAll = async () => {
    setUpdating(true);
    try {
      await refetch();
    } finally {
      setUpdating(false);
    }
  };

  if (isLoading) return <Spinner text="Loading skills..." />;
  if (error)
    return (
      <ErrorBox
        message={
          error instanceof Error ? error.message : "Failed to load skills"
        }
      />
    );

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <select
          value={sourceFilter}
          onChange={e => setSourceFilter(e.target.value)}
          className="bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-xs text-zinc-200"
        >
          <option value="all">All sources ({allSkills.length})</option>
          {sources.map(s => (
            <option key={s} value={s}>{s} ({allSkills.filter(sk => sk.source === s).length})</option>
          ))}
        </select>
        <input
          type="text"
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Search skills..."
          className="bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-xs text-zinc-200 placeholder:text-zinc-600 w-48"
        />
        <p className="text-sm text-zinc-400 tabular-nums ml-auto">
          {skills.length}{skills.length !== allSkills.length ? ` / ${allSkills.length}` : ""} skills
        </p>
        <button
          onClick={handleUpdateAll}
          disabled={updating || allSkills.length === 0}
          className="rounded-lg px-3 py-1.5 text-xs font-medium transition-colors
            bg-zinc-700 hover:bg-zinc-600 text-zinc-200
            disabled:bg-zinc-800 disabled:text-zinc-600 disabled:cursor-not-allowed"
        >
          {updating ? "Updating..." : "Refresh"}
        </button>
      </div>

      {skills.length === 0 ? (
        <EmptyState message="No skills found for this agent." />
      ) : (
        <div className="space-y-1.5">
          {skills.map((skill) => {
            const eligible = skill.eligible ?? true;
            const statusText = skill.bundled
              ? "bundled"
              : eligible
                ? "eligible"
                : "ineligible";

            return (
              <Card key={skill.name}>
                <div className="flex items-center gap-3 px-4 py-3">
                  <StatusDot
                    status={eligible ? "active" : "idle"}
                    size="sm"
                  />
                  <div className="flex-1 min-w-0">
                    <span className="text-sm font-medium text-zinc-100 truncate block">
                      {skill.name}
                    </span>
                    {skill.description && (
                      <span className="text-xs text-zinc-500 truncate block mt-0.5">
                        {skill.description}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    {skill.bundled && (
                      <Badge variant="indigo">bundled</Badge>
                    )}
                    {skill.source === "openclaw-workspace" && (
                      <Badge variant="emerald">workspace</Badge>
                    )}
                    {skill.source?.includes("plugin") && (
                      <Badge variant="purple">plugin</Badge>
                    )}
                    {skill.source?.includes("managed") && (
                      <Badge variant="blue">managed</Badge>
                    )}
                    <span className="text-xs text-zinc-500 capitalize">
                      {statusText}
                    </span>
                  </div>
                  {skill.source && (
                    <span
                      className="text-xs text-zinc-600 font-mono truncate max-w-[120px]"
                      title={skill.source}
                    >
                      {skill.source}
                    </span>
                  )}
                </div>
              </Card>
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
    <Card>
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
        <h3 className="text-sm font-semibold text-zinc-100">{group.label}</h3>
        <span className="text-xs text-zinc-500 tabular-nums">
          {tools.length} tool{tools.length !== 1 ? "s" : ""}
        </span>
      </div>
      <CardBody>
        <div className="space-y-1">
          {visible.map((tool) => (
            <div
              key={tool.id}
              className="flex items-center gap-3 rounded-lg px-3 py-1.5 bg-zinc-800/40"
            >
              <span
                className="text-xs font-mono text-zinc-400 min-w-[160px] truncate"
                title={tool.id}
              >
                {tool.id}
              </span>
              <span className="text-xs text-zinc-300 truncate">
                {tool.label}
              </span>
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
      </CardBody>
    </Card>
  );
}

function ToolsTab({ agentId }: { agentId: string }) {
  const { data, isLoading, error } = useToolsCatalog(agentId || undefined);

  if (isLoading) return <Spinner text="Loading tools catalog..." />;
  if (error)
    return (
      <ErrorBox
        message={
          error instanceof Error
            ? error.message
            : "Failed to load tools catalog"
        }
      />
    );

  const groups = data?.groups ?? [];
  const profiles = data?.profiles ?? [];

  return (
    <div>
      {/* Profile badges */}
      {profiles.length > 0 && (
        <div className="flex items-center gap-2 mb-4">
          <span className="text-xs text-zinc-500">Profiles:</span>
          {profiles.map((p) => (
            <Badge key={p.id} variant="muted">
              {p.label}
            </Badge>
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
          <p className="text-xs text-zinc-600 text-right tabular-nums">
            {groups.reduce((sum, g) => sum + g.tools.length, 0)} tools across{" "}
            {groups.length} group{groups.length !== 1 ? "s" : ""}
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
      <PageHeader
        title="Skills & Tools"
        subtitle="Installed skills and available tool catalog"
      >
        <AgentSelector
          value={agentId}
          onChange={setAgentId}
          agents={agents}
          loading={agentsLoading}
        />
      </PageHeader>

      <TabBar active={activeTab} onChange={setActiveTab} />

      {activeTab === "skills" && <SkillsTab agentId={agentId} />}
      {activeTab === "tools" && <ToolsTab agentId={agentId} />}
    </div>
  );
}
