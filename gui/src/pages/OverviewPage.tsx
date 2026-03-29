import { useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  useAgents,
  useSessions,
  useHealth,
  usePresence,
  useConnectionState,
  useConfig,
} from "@/api/hooks";
import { agentColor as ac } from "@/api/agent-colors";
import type { Session, PresenceEntry, HealthSnapshot, RunRecord } from "@/api/types";
import { agentFromKey } from "@/api/types";
import {
  PageHeader,
  Card,
  CardHeader,
  CardBody,
  StatusDot,
  Spinner,
  EmptyState,
  SectionLabel,
  Badge,
} from "@/components/shared";

// ---------------------------------------------------------------------------
// Fetch runs
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
  });
}

// ---------------------------------------------------------------------------
// Agent card
// ---------------------------------------------------------------------------

function AgentCard({ agentId, sessions, health, isDefault, navigate }: {
  agentId: string;
  sessions: Session[];
  health: HealthSnapshot | null;
  isDefault: boolean;
  navigate: (path: string) => void;
}) {
  const colors = ac(agentId);
  const activeSessions = sessions.filter(s => !s.status || s.status === "running");
  const recentSession = sessions.sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0))[0];
  const totalTokens = sessions.reduce((sum, s) => sum + (s.totalTokens ?? 0), 0);

  return (
    <div
      className="rounded-xl border bg-zinc-900/80 p-4 transition-all hover:border-opacity-60 cursor-pointer group"
      style={{ borderColor: colors.border }}
      onClick={() => navigate(`/sessions?agent=${agentId}`)}
    >
      <div className="flex items-center gap-2.5 mb-3">
        <div className="w-3 h-3 rounded-full shrink-0" style={{ background: colors.dot }} />
        <span className="text-sm font-bold" style={{ color: colors.dot }}>{agentId}</span>
        {isDefault && <Badge variant="indigo">default</Badge>}
        <StatusDot status={activeSessions.length > 0 ? "active" : "idle"} size="sm" />
      </div>

      <div className="grid grid-cols-2 gap-x-4 gap-y-1.5 text-[11px]">
        <div className="text-zinc-500">Sessions</div>
        <div className="text-zinc-300 text-right tabular-nums">{sessions.length}</div>
        <div className="text-zinc-500">Active</div>
        <div className="text-zinc-300 text-right tabular-nums">{activeSessions.length}</div>
        {totalTokens > 0 && (
          <>
            <div className="text-zinc-500">Tokens</div>
            <div className="text-zinc-300 text-right tabular-nums">{(totalTokens / 1000).toFixed(0)}k</div>
          </>
        )}
      </div>

      {recentSession && (
        <div className="mt-2.5 pt-2 border-t border-zinc-800/60 text-[10px] text-zinc-600 truncate">
          Last: {recentSession.displayName || recentSession.key.split(":").slice(-1)[0]?.slice(0, 20)}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Recent tasks
// ---------------------------------------------------------------------------

function RecentTasksList({ runs, navigate }: { runs: RunRecord[]; navigate: (path: string) => void }) {
  const recent = useMemo(() => {
    return [...runs]
      .filter(r => r.task && r.createdAt > 0)
      .sort((a, b) => b.createdAt - a.createdAt)
      .slice(0, 8);
  }, [runs]);

  if (recent.length === 0) return <EmptyState message="No recent tasks" />;

  return (
    <div className="space-y-1">
      {recent.map(r => {
        const agent = agentFromKey(r.childSessionKey);
        const colors = ac(agent);
        const time = new Date(r.createdAt).toLocaleString("zh-CN", {
          month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit",
        });
        const dur = r.endedAt > 0 ? `${((r.endedAt - r.startedAt) / 1000).toFixed(0)}s` : "running";

        return (
          <button
            key={r.runId}
            onClick={() => navigate("/tasks")}
            className="w-full text-left rounded-lg px-3 py-2 hover:bg-zinc-800/50 transition-colors flex items-center gap-2.5"
          >
            <span className="w-2 h-2 rounded-full shrink-0" style={{ background: colors.dot }} />
            <span className="text-[11px] font-medium truncate flex-1" style={{ color: colors.dot }}>
              {agent}
            </span>
            <span className="text-[10px] text-zinc-500 truncate max-w-[200px]">{r.task.slice(0, 50)}</span>
            <span className={`text-[10px] shrink-0 ${r.status === "ok" ? "text-emerald-500" : r.status === "error" ? "text-red-400" : "text-zinc-500"}`}>
              {r.status}
            </span>
            <span className="text-[10px] text-zinc-600 tabular-nums shrink-0">{dur}</span>
            <span className="text-[9px] text-zinc-700 tabular-nums shrink-0">{time}</span>
          </button>
        );
      })}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Health panel
// ---------------------------------------------------------------------------

function HealthPanel({ health }: { health: HealthSnapshot | null }) {
  if (!health) return <Card><CardHeader title="Health" /><CardBody><Spinner text="Waiting..." /></CardBody></Card>;

  const channels = Object.entries(health.channels ?? {});
  return (
    <Card>
      <CardHeader title="Health">
        <StatusDot status={health.ok ? "healthy" : "unhealthy"} size="sm" />
      </CardHeader>
      <CardBody>
        {channels.length > 0 && (
          <div className="space-y-1.5">
            {channels.map(([id, ch]) => (
              <div key={id} className="flex items-center justify-between text-xs">
                <span className="text-zinc-400">{id}</span>
                <span className="flex items-center gap-1.5">
                  <StatusDot status={(ch.running || (ch as any).probe?.ok) ? "running" : "stopped"} size="xs" />
                  <span className={(ch.running || (ch as any).probe?.ok) ? "text-emerald-400" : "text-red-400"}>
                    {(ch.running || (ch as any).probe?.ok) ? "running" : "stopped"}
                  </span>
                </span>
              </div>
            ))}
          </div>
        )}
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Presence panel
// ---------------------------------------------------------------------------

function PresencePanel({ presence }: { presence: PresenceEntry[] }) {
  return (
    <Card>
      <CardHeader title="Presence" count={presence.length} />
      <CardBody>
        {presence.length === 0 ? (
          <EmptyState message="No active devices" />
        ) : (
          <div className="space-y-2">
            {presence.map((p, i) => (
              <div key={p.host ?? i} className="rounded-lg bg-zinc-800/60 px-3 py-2 text-xs">
                <div className="flex items-center justify-between">
                  <span className="font-medium text-zinc-200">{p.host ?? "unknown"}</span>
                  <span className="text-zinc-500">{p.mode ?? "--"} / {p.platform ?? "?"}</span>
                </div>
                <div className="text-zinc-500 mt-0.5">
                  {p.version ?? "--"} / {p.ip ?? "--"}
                  {p.roles?.length ? ` / ${p.roles.join(", ")}` : ""}
                </div>
              </div>
            ))}
          </div>
        )}
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function OverviewPage() {
  const { data: agentData, isLoading: agentsLoading } = useAgents();
  const { data: sessionData, isLoading: sessionsLoading } = useSessions({ limit: 500 });
  const { data: runsData } = useRunsExport();
  const health = useHealth();
  const presence = usePresence();
  const connState = useConnectionState();
  const navigate = useNavigate();

  const agents = agentData?.agents ?? [];
  const defaultId = agentData?.defaultId ?? "";
  const sessions = sessionData?.sessions ?? [];
  const runs = runsData ?? [];

  // Group sessions by agent
  const sessionsByAgent = useMemo(() => {
    const map = new Map<string, Session[]>();
    for (const s of sessions) {
      const aid = agentFromKey(s.key);
      if (!map.has(aid)) map.set(aid, []);
      map.get(aid)!.push(s);
    }
    return map;
  }, [sessions]);

  // Quick stats
  const totalSessions = sessions.length;
  const totalRuns = runs.length;
  const okRuns = runs.filter(r => r.status === "ok").length;
  const errRuns = runs.filter(r => r.status === "error").length;
  const totalTokens = sessions.reduce((s, sess) => s + (sess.totalTokens ?? 0), 0);

  const loading = agentsLoading || sessionsLoading;

  if (connState === "disconnected") {
    return (
      <div className="p-6 flex items-center justify-center h-full">
        <EmptyState icon="!" message="Disconnected from gateway. Waiting for connection..." />
      </div>
    );
  }

  return (
    <div className="p-6 h-full overflow-y-auto">
      <PageHeader title="Overview" subtitle="System status and recent activity" />

      {loading ? (
        <Spinner text="Loading..." />
      ) : (
        <>
          {/* Quick stats row */}
          <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6">
            {[
              { label: "Agents", value: agents.length, color: "text-indigo-400" },
              { label: "Sessions", value: totalSessions, color: "text-zinc-300" },
              { label: "Tasks", value: totalRuns, color: "text-blue-400" },
              { label: "OK / Error", value: `${okRuns} / ${errRuns}`, color: errRuns > 0 ? "text-amber-400" : "text-emerald-400" },
              { label: "Tokens", value: totalTokens > 0 ? `${(totalTokens / 1_000_000).toFixed(1)}M` : "--", color: "text-zinc-400" },
            ].map(s => (
              <div key={s.label} className="rounded-xl border border-zinc-800 bg-zinc-900/60 px-4 py-3">
                <div className="text-[10px] text-zinc-500 uppercase tracking-wider font-semibold">{s.label}</div>
                <div className={`text-xl font-bold tabular-nums mt-0.5 ${s.color}`}>{s.value}</div>
              </div>
            ))}
          </div>

          {/* Agent cards */}
          <SectionLabel>Agents</SectionLabel>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3 mb-6">
            {agents.map(a => (
              <AgentCard
                key={a.id}
                agentId={a.id}
                sessions={sessionsByAgent.get(a.id) ?? []}
                health={health}
                isDefault={a.id === defaultId}
                navigate={navigate}
              />
            ))}
          </div>

          {/* Bottom row: recent tasks + health + presence */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <Card className="lg:col-span-2">
              <CardHeader title="Recent Tasks" count={runs.length}>
                <button onClick={() => navigate("/tasks")} className="text-[10px] text-indigo-400 hover:text-indigo-300">
                  View all
                </button>
              </CardHeader>
              <CardBody>
                <RecentTasksList runs={runs} navigate={navigate} />
              </CardBody>
            </Card>
            <div className="space-y-4">
              <HealthPanel health={health} />
              <PresencePanel presence={presence} />
            </div>
          </div>
        </>
      )}
    </div>
  );
}
