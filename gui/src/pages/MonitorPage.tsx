import { useMemo } from "react";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";
import {
  useSessionUsage,
  useHealth,
  useSessions,
  useAgents,
  usePresence,
  useConnectionState,
  useChannelsStatus,
} from "@/api/hooks";
import type { PresenceEntry } from "@/api/types";

// ---------------------------------------------------------------------------
// Token usage chart
// ---------------------------------------------------------------------------

function TokenUsagePanel() {
  const { data, isLoading, error } = useSessionUsage({ days: 7 });

  const chartData = useMemo(() => {
    if (!data?.entries) return [];
    return data.entries.map((e) => ({
      date: e.date,
      input: e.inputTokens,
      output: e.outputTokens,
      cache: e.cacheReadTokens ?? 0,
      total: e.totalTokens,
      cost: e.cost ?? 0,
    }));
  }, [data]);

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <h3 className="text-sm font-semibold text-zinc-300 mb-3">
        Token Usage (7 days)
      </h3>
      {isLoading ? (
        <div className="h-48 flex items-center justify-center text-zinc-500 text-sm">
          Loading…
        </div>
      ) : error ? (
        <div className="h-48 flex items-center justify-center text-red-400 text-sm">
          Failed to load usage data
        </div>
      ) : chartData.length === 0 ? (
        <div className="h-48 flex items-center justify-center text-zinc-500 text-sm">
          No usage data available
        </div>
      ) : (
        <div className="h-48">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart
              data={chartData}
              margin={{ top: 4, right: 4, bottom: 0, left: 0 }}
            >
              <defs>
                <linearGradient id="gradInput" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#818cf8" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#818cf8" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="gradOutput" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#34d399" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#34d399" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#27272a" />
              <XAxis
                dataKey="date"
                tick={{ fill: "#71717a", fontSize: 11 }}
                axisLine={{ stroke: "#3f3f46" }}
                tickLine={false}
              />
              <YAxis
                tick={{ fill: "#71717a", fontSize: 11 }}
                axisLine={{ stroke: "#3f3f46" }}
                tickLine={false}
                tickFormatter={(v: number) =>
                  v >= 1_000_000
                    ? `${(v / 1_000_000).toFixed(1)}M`
                    : v >= 1_000
                      ? `${(v / 1_000).toFixed(0)}k`
                      : `${v}`
                }
              />
              <Tooltip
                contentStyle={{
                  backgroundColor: "#18181b",
                  border: "1px solid #3f3f46",
                  borderRadius: 8,
                  fontSize: 12,
                }}
                labelStyle={{ color: "#a1a1aa" }}
                itemStyle={{ color: "#e4e4e7" }}
                formatter={(value: number, name: string) => [
                  value.toLocaleString(),
                  name,
                ]}
              />
              <Area
                type="monotone"
                dataKey="input"
                name="Input"
                stroke="#818cf8"
                fill="url(#gradInput)"
                strokeWidth={2}
              />
              <Area
                type="monotone"
                dataKey="output"
                name="Output"
                stroke="#34d399"
                fill="url(#gradOutput)"
                strokeWidth={2}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      )}
      {/* Summary row */}
      {chartData.length > 0 && (
        <div className="flex gap-4 mt-3 text-xs text-zinc-400">
          <span>
            Total:{" "}
            <span className="text-zinc-200 font-medium">
              {chartData
                .reduce((s, d) => s + d.total, 0)
                .toLocaleString()}{" "}
              tokens
            </span>
          </span>
          {chartData.some((d) => d.cost > 0) && (
            <span>
              Est. cost:{" "}
              <span className="text-zinc-200 font-medium">
                $
                {chartData
                  .reduce((s, d) => s + d.cost, 0)
                  .toFixed(2)}
              </span>
            </span>
          )}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Health panel
// ---------------------------------------------------------------------------

function HealthPanel() {
  const health = useHealth();
  const { data: channelsData } = useChannelsStatus();

  const healthEntries = health
    ? Object.entries(health.health)
    : [];
  const channels = channelsData?.channels ?? [];

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <h3 className="text-sm font-semibold text-zinc-300 mb-3">
        System Health
      </h3>
      {/* Health entries */}
      <div className="space-y-1.5 mb-3">
        {healthEntries.length === 0 ? (
          <p className="text-xs text-zinc-500">
            Waiting for health snapshot…
          </p>
        ) : (
          healthEntries.map(([key, val]) => (
            <div
              key={key}
              className="flex items-center justify-between text-xs"
            >
              <span className="text-zinc-400">{key}</span>
              <span className="flex items-center gap-1.5">
                <span
                  className={`h-2 w-2 rounded-full ${
                    val.healthy ? "bg-emerald-500" : "bg-red-500"
                  }`}
                />
                <span
                  className={
                    val.healthy ? "text-emerald-400" : "text-red-400"
                  }
                >
                  {val.healthy ? "OK" : val.reason ?? "unhealthy"}
                </span>
              </span>
            </div>
          ))
        )}
      </div>
      {/* Channels */}
      {channels.length > 0 && (
        <>
          <div className="text-xs font-medium text-zinc-400 mb-1.5 mt-3 uppercase tracking-wider">
            Channels
          </div>
          <div className="space-y-1.5">
            {channels.map((ch) => (
              <div
                key={ch.id}
                className="flex items-center justify-between text-xs"
              >
                <span className="text-zinc-400">{ch.id}</span>
                <span className="flex items-center gap-1.5">
                  <span
                    className={`h-2 w-2 rounded-full ${
                      ch.healthy ? "bg-emerald-500" : "bg-red-500"
                    }`}
                  />
                  <span
                    className={
                      ch.healthy ? "text-emerald-400" : "text-red-400"
                    }
                  >
                    {ch.healthy
                      ? ch.connected
                        ? "connected"
                        : "OK"
                      : ch.reason ?? "unhealthy"}
                  </span>
                </span>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Active sessions panel
// ---------------------------------------------------------------------------

function SessionsPanel() {
  const { data: sessionData, isLoading } = useSessions();
  const { data: agentData } = useAgents();

  const sessions = sessionData?.sessions ?? [];
  const agents = agentData?.agents ?? [];

  const countsByAgent = useMemo(() => {
    const map = new Map<string, number>();
    for (const s of sessions) {
      const aid = s.agent ?? "unknown";
      map.set(aid, (map.get(aid) ?? 0) + 1);
    }
    return map;
  }, [sessions]);

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <h3 className="text-sm font-semibold text-zinc-300 mb-3">
        Active Sessions ({sessions.length})
      </h3>
      {isLoading ? (
        <div className="text-xs text-zinc-500">Loading…</div>
      ) : sessions.length === 0 ? (
        <div className="text-xs text-zinc-500">No active sessions</div>
      ) : (
        <div className="space-y-2">
          {agents.map((a) => {
            const count = countsByAgent.get(a.id) ?? 0;
            if (count === 0) return null;
            const maxBar = Math.max(...Array.from(countsByAgent.values()), 1);
            const pct = (count / maxBar) * 100;
            return (
              <div key={a.id}>
                <div className="flex items-center justify-between text-xs mb-0.5">
                  <span className="text-zinc-300 font-medium">{a.id}</span>
                  <span className="text-zinc-500">{count}</span>
                </div>
                <div className="h-1.5 bg-zinc-800 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-indigo-500 rounded-full transition-all"
                    style={{ width: `${pct}%` }}
                  />
                </div>
              </div>
            );
          })}
          {/* Show unknown agent sessions */}
          {countsByAgent.has("unknown") && (
            <div>
              <div className="flex items-center justify-between text-xs mb-0.5">
                <span className="text-zinc-400 italic">unknown</span>
                <span className="text-zinc-500">
                  {countsByAgent.get("unknown")}
                </span>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// System info panel
// ---------------------------------------------------------------------------

function SystemInfoPanel() {
  const presence = usePresence();
  const connState = useConnectionState();

  function renderPresenceRow(p: PresenceEntry) {
    return (
      <div key={p.deviceId} className="text-xs space-y-0.5">
        <div className="flex items-center justify-between">
          <span className="text-zinc-300 font-medium">
            {p.host ?? p.deviceId}
          </span>
          <span className="text-zinc-500">{p.mode ?? "—"}</span>
        </div>
        <div className="text-zinc-500">
          {p.version ?? "—"} · {p.platform ?? "—"} · {p.ip ?? "—"}
          {p.roles?.length ? ` · ${p.roles.join(", ")}` : ""}
        </div>
      </div>
    );
  }

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <h3 className="text-sm font-semibold text-zinc-300 mb-3">System Info</h3>
      {/* Connection */}
      <div className="flex items-center gap-2 text-xs mb-3">
        <span
          className={`h-2 w-2 rounded-full ${
            connState === "connected"
              ? "bg-emerald-500"
              : connState === "connecting"
                ? "bg-amber-500 animate-pulse"
                : "bg-red-500"
          }`}
        />
        <span className="text-zinc-300">Gateway: {connState}</span>
      </div>
      {/* Presence list */}
      {presence.length === 0 ? (
        <p className="text-xs text-zinc-500">No active devices</p>
      ) : (
        <div className="space-y-2">{presence.map(renderPresenceRow)}</div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function MonitorPage() {
  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-semibold text-zinc-100">Monitor</h1>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <TokenUsagePanel />
        <HealthPanel />
        <SessionsPanel />
        <SystemInfoPanel />
      </div>
    </div>
  );
}
