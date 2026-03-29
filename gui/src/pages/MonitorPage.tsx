import { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  useHealth,
  useSessions,
  useAgents,
  usePresence,
  useConnectionState,
  useConfig,
  useGatewayStore,
} from "@/api/hooks";
import { agentColor } from "@/api/agent-colors";
import type { RunRecord } from "@/api/types";
import { agentFromKey } from "@/api/types";
import { PrismLight as SyntaxHighlighter } from "react-syntax-highlighter";
import oneDark from "react-syntax-highlighter/dist/esm/styles/prism/one-dark";
import jsonLang from "react-syntax-highlighter/dist/esm/languages/prism/json";
import {
  PageHeader, Card, CardHeader, CardBody,
  StatusDot, Spinner, EmptyState, Badge, SectionLabel,
} from "@/components/shared";

SyntaxHighlighter.registerLanguage("json", jsonLang);

// ---------------------------------------------------------------------------
// Runs fetch
// ---------------------------------------------------------------------------

function useRuns() {
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
// Gateway Status section
// ---------------------------------------------------------------------------

function GatewayStatusSection() {
  const health = useHealth();
  const presence = usePresence();
  const connState = useConnectionState();
  const client = useGatewayStore(s => s.client);
  const connected = useGatewayStore(s => s.connectionState === "connected");

  const { data: statusData } = useQuery({
    queryKey: ["status"],
    queryFn: () => client!.call("status", {}),
    enabled: connected && !!client,
    staleTime: 60_000,
  });

  const channels = Object.entries(health?.channels ?? {});

  return (
    <Card>
      <CardHeader title="Gateway Status">
        <div className="flex items-center gap-2">
          <StatusDot status={connState === "connected" ? (health?.ok ? "healthy" : "unhealthy") : "disconnected"} size="sm" />
          <span className={`text-xs ${health?.ok ? "text-emerald-400" : "text-red-400"}`}>
            {connState === "connected" ? (health?.ok ? "Healthy" : "Unhealthy") : "Disconnected"}
          </span>
        </div>
      </CardHeader>
      <CardBody>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
          {[
            { label: "Version", value: (statusData as any)?.version ?? "—" },
            { label: "Channels", value: channels.length },
            { label: "Presence", value: presence.length },
            { label: "Health TS", value: health?.ts ? new Date(health.ts).toLocaleTimeString("zh-CN") : "—" },
          ].map(s => (
            <div key={s.label} className="rounded-lg bg-zinc-800/40 px-3 py-2">
              <div className="text-[9px] text-zinc-500 uppercase tracking-wider">{s.label}</div>
              <div className="text-sm font-bold text-zinc-200 tabular-nums">{s.value}</div>
            </div>
          ))}
        </div>
        {channels.length > 0 && (
          <>
            <SectionLabel>Channels</SectionLabel>
            <div className="space-y-1">
              {channels.map(([id, ch]) => (
                <div key={id} className="flex items-center justify-between text-xs px-2 py-1 rounded bg-zinc-800/30">
                  <span className="text-zinc-300">{id}</span>
                  <div className="flex items-center gap-1.5">
                    <StatusDot status={((ch as any).running || (ch as any).probe?.ok) ? "running" : "stopped"} size="xs" />
                    <span className={((ch as any).running || (ch as any).probe?.ok) ? "text-emerald-400" : "text-red-400"}>
                      {((ch as any).running || (ch as any).probe?.ok) ? "running" : "stopped"}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Config Viewer section
// ---------------------------------------------------------------------------

function ConfigViewerSection() {
  const { data: config, isLoading } = useConfig();
  const [open, setOpen] = useState(false);

  const rawStr = useMemo(() => {
    if (!config) return "";
    const raw = (config as any).raw;
    if (typeof raw === "string") return raw;
    if (raw && typeof raw === "object") return JSON.stringify(raw, null, 2);
    return JSON.stringify((config as any).parsed ?? (config as any).resolved ?? {}, null, 2);
  }, [config]);

  return (
    <Card>
      <CardHeader title="Configuration">
        <div className="flex items-center gap-2">
          {config && <Badge variant="muted">{(config as any).hash?.slice(0, 8) ?? "—"}</Badge>}
          <button onClick={() => setOpen(!open)} className="text-[10px] text-zinc-500 hover:text-zinc-300 transition-colors">
            {open ? "Collapse" : "Expand"}
          </button>
        </div>
      </CardHeader>
      {open && (
        <CardBody className="p-0">
          {isLoading ? <Spinner text="Loading..." /> : (
            <SyntaxHighlighter
              language="json" style={oneDark} showLineNumbers
              customStyle={{ margin: 0, padding: "12px", background: "transparent", fontSize: "11px", lineHeight: "1.5", maxHeight: "500px" }}
              codeTagProps={{ style: { fontFamily: "'IBM Plex Mono', monospace" } }}
            >{rawStr}</SyntaxHighlighter>
          )}
        </CardBody>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Usage & Cost section
// ---------------------------------------------------------------------------

function UsageCostSection() {
  const client = useGatewayStore(s => s.client);
  const connected = useGatewayStore(s => s.connectionState === "connected");

  const { data: usageData } = useQuery({
    queryKey: ["usage.status"],
    queryFn: () => client!.call("usage.status", {}),
    enabled: connected && !!client,
    staleTime: 60_000,
  });
  const { data: costData } = useQuery({
    queryKey: ["usage.cost"],
    queryFn: () => client!.call("usage.cost", {}),
    enabled: connected && !!client,
    staleTime: 60_000,
  });

  return (
    <Card>
      <CardHeader title="Usage & Cost" />
      <CardBody>
        {!usageData && !costData ? <EmptyState message="No usage data" /> : (
          <pre className="text-xs font-mono text-zinc-400 whitespace-pre-wrap max-h-64 overflow-y-auto">
            {JSON.stringify({ usage: usageData, cost: costData }, null, 2)}
          </pre>
        )}
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Memory Status section
// ---------------------------------------------------------------------------

function MemoryStatusSection() {
  const client = useGatewayStore(s => s.client);
  const connected = useGatewayStore(s => s.connectionState === "connected");

  const { data } = useQuery({
    queryKey: ["doctor.memory.status"],
    queryFn: () => client!.call("doctor.memory.status", {}),
    enabled: connected && !!client,
    staleTime: 60_000,
  });

  return (
    <Card>
      <CardHeader title="Vector Memory" />
      <CardBody>
        {!data ? <EmptyState message="No memory data" /> : (
          <pre className="text-xs font-mono text-zinc-400 whitespace-pre-wrap max-h-48 overflow-y-auto">
            {JSON.stringify(data, null, 2)}
          </pre>
        )}
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Runs Table section
// ---------------------------------------------------------------------------

function RunsTableSection() {
  const { data: runsData, isLoading } = useRuns();
  const [sortBy, setSortBy] = useState<"created" | "duration">("created");
  const [filterStatus, setFilterStatus] = useState("all");

  const runs = useMemo(() => {
    let list = runsData ?? [];
    if (filterStatus !== "all") list = list.filter(r => r.status === filterStatus);
    list = [...list].sort((a, b) => {
      if (sortBy === "duration") return ((b.endedAt - b.startedAt) || 0) - ((a.endedAt - a.startedAt) || 0);
      return (b.createdAt || 0) - (a.createdAt || 0);
    });
    return list.slice(0, 100);
  }, [runsData, sortBy, filterStatus]);

  return (
    <Card>
      <CardHeader title="Subagent Runs" count={runsData?.length}>
        <div className="flex items-center gap-2 text-[11px]">
          <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)}
            className="bg-zinc-800 border border-zinc-700/50 rounded px-1.5 py-0.5 text-zinc-300">
            <option value="all">All</option>
            <option value="ok">OK</option>
            <option value="error">Error</option>
            <option value="timeout">Timeout</option>
          </select>
          <select value={sortBy} onChange={e => setSortBy(e.target.value as any)}
            className="bg-zinc-800 border border-zinc-700/50 rounded px-1.5 py-0.5 text-zinc-300">
            <option value="created">Newest</option>
            <option value="duration">Longest</option>
          </select>
        </div>
      </CardHeader>
      <CardBody className="p-0">
        {isLoading ? <Spinner text="Loading..." /> : runs.length === 0 ? <div className="p-4"><EmptyState message="No runs" /></div> : (
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-zinc-800 text-zinc-500 text-left">
                  <th className="px-3 py-2">Agent</th>
                  <th className="px-3 py-2">Task</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Created</th>
                  <th className="px-3 py-2">Duration</th>
                </tr>
              </thead>
              <tbody>
                {runs.map(r => {
                  const agent = agentFromKey(r.childSessionKey);
                  const colors = agentColor(agent);
                  const dur = r.endedAt > 0 && r.startedAt > 0 ? `${((r.endedAt - r.startedAt) / 1000).toFixed(0)}s` : "—";
                  return (
                    <tr key={r.runId} className="border-b border-zinc-800/40 hover:bg-zinc-800/20">
                      <td className="px-3 py-1.5">
                        <span className="flex items-center gap-1.5">
                          <span className="w-2 h-2 rounded-full" style={{ background: colors.dot }} />
                          <span style={{ color: colors.dot }}>{agent}</span>
                        </span>
                      </td>
                      <td className="px-3 py-1.5 text-zinc-400 truncate max-w-[300px]">{r.task.slice(0, 80)}</td>
                      <td className="px-3 py-1.5">
                        <Badge variant={r.status === "ok" ? "emerald" : r.status === "error" ? "red" : r.status === "timeout" ? "amber" : "muted"}>
                          {r.status}
                        </Badge>
                      </td>
                      <td className="px-3 py-1.5 text-zinc-500 tabular-nums">
                        {r.createdAt > 0 ? new Date(r.createdAt).toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }) : "—"}
                      </td>
                      <td className="px-3 py-1.5 text-zinc-500 tabular-nums">{dur}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Session Stats section
// ---------------------------------------------------------------------------

function SessionStatsSection() {
  const { data: sessionData } = useSessions({ limit: 500 });
  const { data: agentData } = useAgents();
  const sessions = sessionData?.sessions ?? [];
  const agents = agentData?.agents ?? [];

  const perAgent = useMemo(() => {
    const map = new Map<string, number>();
    for (const s of sessions) {
      const a = agentFromKey(s.key);
      map.set(a, (map.get(a) ?? 0) + 1);
    }
    return [...map.entries()].sort((a, b) => b[1] - a[1]);
  }, [sessions]);

  const activeIn5m = sessions.filter(s => s.updatedAt && s.updatedAt > Date.now() - 5 * 60_000).length;

  return (
    <Card>
      <CardHeader title="Session Store" count={sessions.length} />
      <CardBody>
        <div className="grid grid-cols-3 gap-3 mb-4">
          {[
            { label: "Total", value: sessions.length },
            { label: "Active (5m)", value: activeIn5m },
            { label: "Agents", value: agents.length },
          ].map(s => (
            <div key={s.label} className="rounded-lg bg-zinc-800/40 px-3 py-2 text-center">
              <div className="text-[9px] text-zinc-500 uppercase tracking-wider">{s.label}</div>
              <div className="text-lg font-bold text-zinc-200 tabular-nums">{s.value}</div>
            </div>
          ))}
        </div>
        <SectionLabel>Per Agent</SectionLabel>
        <div className="space-y-1.5">
          {perAgent.map(([agent, count]) => {
            const colors = agentColor(agent);
            const pct = sessions.length > 0 ? (count / sessions.length) * 100 : 0;
            return (
              <div key={agent} className="flex items-center gap-2 text-xs">
                <span className="w-2 h-2 rounded-full shrink-0" style={{ background: colors.dot }} />
                <span className="w-32 truncate" style={{ color: colors.dot }}>{agent}</span>
                <div className="flex-1 h-2 bg-zinc-800 rounded-full overflow-hidden">
                  <div className="h-full rounded-full" style={{ width: `${pct}%`, background: colors.dot, opacity: 0.6 }} />
                </div>
                <span className="text-zinc-500 tabular-nums w-8 text-right">{count}</span>
              </div>
            );
          })}
        </div>
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function MonitorPage() {
  const connState = useConnectionState();

  if (connState === "disconnected") {
    return (
      <div className="p-6 flex items-center justify-center h-full">
        <EmptyState icon="!" message="Disconnected from gateway" />
      </div>
    );
  }

  return (
    <div className="p-6 h-full overflow-y-auto">
      <PageHeader title="System Inspector" subtitle="Gateway health, configuration, usage, and session analytics" />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        <GatewayStatusSection />
        <SessionStatsSection />
      </div>

      <div className="mb-4">
        <ConfigViewerSection />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        <UsageCostSection />
        <MemoryStatusSection />
      </div>

      <RunsTableSection />
    </div>
  );
}
