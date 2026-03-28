import { useMemo } from "react";
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
} from "@/components/shared";

// ---------------------------------------------------------------------------
// Token usage panel
// ---------------------------------------------------------------------------

function formatTokens(n: number): string {
  if (n >= 1_000_000_000) return `${(n / 1_000_000_000).toFixed(1)}B`;
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(n);
}

function TokenUsagePanel() {
  const { data, isLoading, error } = useSessionUsage();

  return (
    <Card>
      <CardHeader title="Token Usage" />
      <CardBody>
        {isLoading ? (
          <Spinner text="Loading usage data..." />
        ) : error ? (
          <EmptyState message="Failed to load usage data" />
        ) : !data?.totals ? (
          <EmptyState message="No usage data available" />
        ) : (
          <>
            {/* Date range */}
            {data.startDate && data.endDate && (
              <div className="text-xs text-zinc-500 mb-3">
                {data.startDate} to {data.endDate}
              </div>
            )}

            {/* Token totals */}
            <div className="grid grid-cols-2 gap-3 mb-4">
              <div className="rounded-lg bg-zinc-800/60 px-3 py-2.5">
                <div className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1">
                  Input
                </div>
                <div className="text-lg font-bold text-indigo-400 tabular-nums">
                  {formatTokens(data.totals.input)}
                </div>
              </div>
              <div className="rounded-lg bg-zinc-800/60 px-3 py-2.5">
                <div className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1">
                  Output
                </div>
                <div className="text-lg font-bold text-emerald-400 tabular-nums">
                  {formatTokens(data.totals.output)}
                </div>
              </div>
              <div className="rounded-lg bg-zinc-800/60 px-3 py-2.5">
                <div className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1">
                  Cache Read
                </div>
                <div className="text-lg font-bold text-amber-400 tabular-nums">
                  {formatTokens(data.totals.cacheRead)}
                </div>
              </div>
              <div className="rounded-lg bg-zinc-800/60 px-3 py-2.5">
                <div className="text-[10px] uppercase tracking-wider text-zinc-500 mb-1">
                  Total
                </div>
                <div className="text-lg font-bold text-zinc-200 tabular-nums">
                  {formatTokens(data.totals.totalTokens)}
                </div>
              </div>
            </div>

            {/* Message aggregates */}
            {data.aggregates && (
              <>
                <SectionLabel>Messages</SectionLabel>
                <div className="grid grid-cols-3 gap-2 mb-3">
                  <div className="text-xs">
                    <span className="text-zinc-500">Total: </span>
                    <span className="text-zinc-200 font-medium tabular-nums">
                      {data.aggregates.messages.total.toLocaleString()}
                    </span>
                  </div>
                  <div className="text-xs">
                    <span className="text-zinc-500">User: </span>
                    <span className="text-zinc-200 font-medium tabular-nums">
                      {data.aggregates.messages.user.toLocaleString()}
                    </span>
                  </div>
                  <div className="text-xs">
                    <span className="text-zinc-500">Assistant: </span>
                    <span className="text-zinc-200 font-medium tabular-nums">
                      {data.aggregates.messages.assistant.toLocaleString()}
                    </span>
                  </div>
                  <div className="text-xs">
                    <span className="text-zinc-500">Tool Calls: </span>
                    <span className="text-zinc-200 font-medium tabular-nums">
                      {data.aggregates.messages.toolCalls.toLocaleString()}
                    </span>
                  </div>
                  <div className="text-xs">
                    <span className="text-zinc-500">Errors: </span>
                    <span
                      className={`font-medium tabular-nums ${
                        data.aggregates.messages.errors > 0
                          ? "text-red-400"
                          : "text-zinc-200"
                      }`}
                    >
                      {data.aggregates.messages.errors}
                    </span>
                  </div>
                  <div className="text-xs">
                    <span className="text-zinc-500">Unique Tools: </span>
                    <span className="text-zinc-200 font-medium tabular-nums">
                      {data.aggregates.tools.uniqueTools}
                    </span>
                  </div>
                </div>
              </>
            )}

            {/* Cost */}
            {data.totals.totalCost > 0 && (
              <div className="text-xs text-zinc-400 border-t border-zinc-800 pt-2">
                Est. cost:{" "}
                <span className="text-zinc-200 font-medium tabular-nums">
                  ${data.totals.totalCost.toFixed(2)}
                </span>
              </div>
            )}
          </>
        )}
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Health panel
// ---------------------------------------------------------------------------

function HealthPanel() {
  const health = useHealth();
  const { data: channelsData } = useChannelsStatus();

  return (
    <Card>
      <CardHeader title="System Health" />
      <CardBody>
        {!health ? (
          <Spinner text="Waiting for health snapshot..." />
        ) : (
          <>
            {/* Overall status */}
            <div className="flex items-center justify-between text-xs mb-3 pb-2 border-b border-zinc-800">
              <span className="text-zinc-400">Overall</span>
              <span className="flex items-center gap-1.5">
                <StatusDot
                  status={health.ok ? "healthy" : "unhealthy"}
                  size="sm"
                />
                <span
                  className={health.ok ? "text-emerald-400" : "text-red-400"}
                >
                  {health.ok ? "OK" : "unhealthy"}
                </span>
              </span>
            </div>

            {/* Health channels from health snapshot */}
            {health.channels &&
              Object.keys(health.channels).length > 0 && (
                <div className="space-y-1.5 mb-3">
                  <SectionLabel>Channels (health)</SectionLabel>
                  {Object.entries(health.channels).map(([id, ch]) => (
                    <div
                      key={id}
                      className="flex items-center justify-between text-xs"
                    >
                      <span className="text-zinc-400">{id}</span>
                      <span className="flex items-center gap-1.5">
                        <StatusDot
                          status={(ch.running || (ch as any).probe?.ok) ? "running" : "stopped"}
                          size="xs"
                        />
                        <span
                          className={
                            (ch.running || (ch as any).probe?.ok) ? "text-emerald-400" : "text-red-400"
                          }
                        >
                          {ch.running
                            ? ch.probe?.ok
                              ? "running (probe OK)"
                              : "running"
                            : "stopped"}
                        </span>
                      </span>
                    </div>
                  ))}
                </div>
              )}

            {/* Health agents */}
            {health.agents && health.agents.length > 0 && (
              <div className="space-y-1.5 mb-3">
                <SectionLabel>Agents</SectionLabel>
                {health.agents.map((ag) => (
                  <div
                    key={ag.agentId}
                    className="flex items-center justify-between text-xs"
                  >
                    <span className="text-zinc-400">
                      {ag.agentId}
                      {ag.isDefault ? " (default)" : ""}
                    </span>
                    <span className="flex items-center gap-1.5">
                      <StatusDot status="active" size="xs" />
                      <span className="text-emerald-400">active</span>
                    </span>
                  </div>
                ))}
              </div>
            )}

            {/* Health session count */}
            {health.sessions && (
              <div className="text-xs text-zinc-500 tabular-nums">
                {health.sessions.count} active session
                {health.sessions.count !== 1 ? "s" : ""}
              </div>
            )}
          </>
        )}

        {/* Channels from channels.status RPC */}
        {channelsData?.channels &&
          Object.keys(channelsData.channels).length > 0 && (
            <>
              <SectionLabel>Channel Status</SectionLabel>
              <div className="space-y-1.5">
                {Object.entries(channelsData.channels).map(([id, ch]) => {
                  const label = channelsData.channelLabels?.[id] ?? id;
                  return (
                    <div
                      key={id}
                      className="flex items-center justify-between text-xs"
                    >
                      <span className="text-zinc-400">{label}</span>
                      <span className="flex items-center gap-1.5">
                        <StatusDot
                          status={(ch.running || (ch as any).probe?.ok) ? "running" : "stopped"}
                          size="xs"
                        />
                        <span
                          className={
                            (ch.running || (ch as any).probe?.ok) ? "text-emerald-400" : "text-red-400"
                          }
                        >
                          {ch.running
                            ? ch.configured
                              ? "running"
                              : "unconfigured"
                            : "stopped"}
                        </span>
                      </span>
                    </div>
                  );
                })}
              </div>
            </>
          )}
      </CardBody>
    </Card>
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
      const aid = agentFromKey(s.key);
      map.set(aid, (map.get(aid) ?? 0) + 1);
    }
    return map;
  }, [sessions]);

  return (
    <Card>
      <CardHeader
        title="Active Sessions"
        count={sessionData?.count ?? sessions.length}
      />
      <CardBody>
        {isLoading ? (
          <Spinner text="Loading sessions..." />
        ) : sessions.length === 0 ? (
          <EmptyState message="No active sessions" />
        ) : (
          <div className="space-y-2.5">
            {agents.map((a) => {
              const count = countsByAgent.get(a.id) ?? 0;
              if (count === 0) return null;
              const maxBar = Math.max(
                ...Array.from(countsByAgent.values()),
                1,
              );
              const pct = (count / maxBar) * 100;
              return (
                <div key={a.id}>
                  <div className="flex items-center justify-between text-xs mb-0.5">
                    <span className="text-zinc-300 font-medium">
                      {a.name ?? a.id}
                    </span>
                    <span className="text-zinc-500 tabular-nums">{count}</span>
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
            {/* Show agents in sessions but not in agent list */}
            {Array.from(countsByAgent.entries())
              .filter(([aid]) => !agents.some((a) => a.id === aid))
              .map(([aid, count]) => (
                <div key={aid}>
                  <div className="flex items-center justify-between text-xs mb-0.5">
                    <span className="text-zinc-400 italic">{aid}</span>
                    <span className="text-zinc-500 tabular-nums">{count}</span>
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
// System info panel
// ---------------------------------------------------------------------------

function SystemInfoPanel() {
  const presence = usePresence();
  const connState = useConnectionState();

  return (
    <Card>
      <CardHeader title="System Info" />
      <CardBody>
        {/* Connection */}
        <div className="flex items-center gap-2 text-xs mb-3">
          <StatusDot
            status={
              connState === "connected"
                ? "connected"
                : connState === "connecting"
                  ? "connecting"
                  : "disconnected"
            }
            size="sm"
          />
          <span className="text-zinc-300">Gateway: {connState}</span>
        </div>
        {/* Presence list */}
        {presence.length === 0 ? (
          <EmptyState message="No active devices" />
        ) : (
          <div className="space-y-2">
            {presence.map((p: PresenceEntry, i: number) => (
              <div key={p.host ?? `presence-${i}`} className="text-xs space-y-0.5">
                <div className="flex items-center justify-between">
                  <span className="text-zinc-300 font-medium">
                    {p.host ?? "unknown"}
                  </span>
                  <span className="text-zinc-500">{p.mode ?? "--"}</span>
                </div>
                <div className="text-zinc-500">
                  {p.version ?? "--"} / {p.platform ?? "--"} / {p.ip ?? "--"}
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

export default function MonitorPage() {
  return (
    <div className="p-6 space-y-4">
      <PageHeader title="Monitor" subtitle="System health, usage, and presence" />
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <TokenUsagePanel />
        <HealthPanel />
        <SessionsPanel />
        <SystemInfoPanel />
      </div>
    </div>
  );
}
