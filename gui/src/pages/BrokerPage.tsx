import { useState, useCallback, useMemo } from "react";
import { useQueryClient } from "@tanstack/react-query";
import {
  useHealth,
  useSessions,
  useAgents,
  useChannelsStatus,
  useConfig,
  useGatewayStore,
} from "@/api/hooks";
import type { HealthSnapshot } from "@/api/types";
import {
  PageHeader,
  Card,
  CardHeader,
  CardBody,
  StatusDot,
  Spinner,
  ErrorBox,
  Badge,
  EmptyState,
} from "@/components/shared";
import { AGENT_COLORS } from "@/api/agent-colors";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function relativeTime(ts: number): string {
  if (!ts) return "--";
  const diff = Date.now() - ts;
  if (diff < 0) return "just now";
  if (diff < 60_000) return `${Math.round(diff / 1000)}s ago`;
  if (diff < 3_600_000) return `${Math.round(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.round(diff / 3_600_000)}h ago`;
  return new Date(ts).toLocaleString();
}

function InfoRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between py-2 border-b border-zinc-800/50 last:border-b-0">
      <span className="text-sm text-zinc-400">{label}</span>
      <span className="text-sm text-zinc-200 font-mono">
        {value ?? <span className="text-zinc-600">--</span>}
      </span>
    </div>
  );
}

function agentFromKey(key: string): string {
  const parts = key.split(":");
  return parts[1] ?? parts[0] ?? "unknown";
}

// ---------------------------------------------------------------------------
// Health section
// ---------------------------------------------------------------------------

function HealthSection({ health }: { health: HealthSnapshot }) {
  return (
    <Card>
      <CardHeader title="Gateway Health">
        <div className="flex items-center gap-2">
          <StatusDot status={health.ok ? "healthy" : "unhealthy"} size="sm" />
          <span className={`text-xs font-medium ${health.ok ? "text-emerald-400" : "text-red-400"}`}>
            {health.ok ? "Healthy" : "Unhealthy"}
          </span>
        </div>
      </CardHeader>
      <CardBody>
        <InfoRow label="Status" value={health.ok ? "OK" : "ERROR"} />
        <InfoRow label="Last Check" value={relativeTime(health.ts)} />
        {health.durationMs != null && (
          <InfoRow label="Response Time" value={`${health.durationMs}ms`} />
        )}
        {health.heartbeatSeconds != null && (
          <InfoRow label="Heartbeat Interval" value={`${health.heartbeatSeconds}s`} />
        )}
        {health.sessions && (
          <InfoRow label="Session Count" value={String(health.sessions.count)} />
        )}
        <InfoRow label="Agents" value={String(health.agents?.length ?? 0)} />
        <InfoRow label="Channels" value={String(Object.keys(health.channels ?? {}).length)} />
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Active sessions section
// ---------------------------------------------------------------------------

interface SessionEntry {
  key: string;
  label?: string;
  displayName?: string;
  model?: string;
  updatedAt?: number;
  totalTokens?: number;
}

function ActiveSessionsSection() {
  const { data, isLoading } = useSessions({ limit: 50, includeLastMessage: false });
  const { data: agentData } = useAgents();
  const client = useGatewayStore((s) => s.client);
  const qc = useQueryClient();
  const [aborting, setAborting] = useState<string | null>(null);

  const sessions = useMemo(() => {
    const list = (data?.sessions ?? []) as SessionEntry[];
    // Sort by updatedAt descending, filter recently active (10 min)
    const cutoff = Date.now() - 10 * 60_000;
    return list
      .filter((s) => (s.updatedAt ?? 0) > cutoff)
      .sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0));
  }, [data]);

  const handleAbort = useCallback(async (key: string) => {
    if (!client) return;
    setAborting(key);
    try {
      await client.call("sessions.abort", { key });
      qc.invalidateQueries({ queryKey: ["sessions.list"] });
    } catch (err: any) {
      alert(`Abort failed: ${err.message}`);
    } finally {
      setAborting(null);
    }
  }, [client, qc]);

  const agentNames = useMemo(() => {
    const map = new Map<string, string>();
    for (const a of agentData?.agents ?? []) {
      map.set(a.id, a.name ?? a.id);
    }
    return map;
  }, [agentData]);

  return (
    <Card className="mt-4">
      <CardHeader title="Active Sessions" count={sessions.length}>
        <span className="text-[10px] text-zinc-600">last 10 min</span>
      </CardHeader>
      <CardBody className="space-y-2">
        {isLoading && <Spinner />}
        {!isLoading && sessions.length === 0 && (
          <EmptyState message="No active sessions" />
        )}
        {sessions.map((s) => {
          const agent = agentFromKey(s.key);
          const color = AGENT_COLORS[agent] ?? AGENT_COLORS.default;
          return (
            <div
              key={s.key}
              className="flex items-center gap-3 rounded-lg border border-zinc-800 bg-zinc-950/50 px-4 py-2.5"
            >
              <StatusDot status="active" size="sm" />
              <div
                className="w-1 h-8 rounded-full shrink-0"
                style={{ backgroundColor: color }}
              />
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-zinc-200 truncate">
                    {s.displayName ?? s.label ?? s.key.slice(0, 32)}
                  </span>
                  <Badge variant="muted">{agentNames.get(agent) ?? agent}</Badge>
                </div>
                <div className="text-xs text-zinc-500 flex gap-3 mt-0.5">
                  {s.model && <span className="font-mono">{s.model}</span>}
                  <span>{relativeTime(s.updatedAt ?? 0)}</span>
                  {s.totalTokens != null && (
                    <span className="tabular-nums">{s.totalTokens.toLocaleString()} tokens</span>
                  )}
                </div>
              </div>
              <button
                onClick={() => handleAbort(s.key)}
                disabled={aborting === s.key}
                className="px-2.5 py-1 text-xs bg-amber-600/20 text-amber-400 rounded-lg hover:bg-amber-600/30 transition-colors disabled:opacity-50 shrink-0"
              >
                {aborting === s.key ? "..." : "Abort"}
              </button>
            </div>
          );
        })}
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Channels section
// ---------------------------------------------------------------------------

function ChannelsSection() {
  const { data: channelsData, isLoading } = useChannelsStatus();

  const channels = useMemo(() => {
    if (!channelsData) return [];
    // channelsData could be an object of channel entries or have a channels key
    const raw = (channelsData as any).channels ?? channelsData;
    if (typeof raw !== "object") return [];
    return Object.entries(raw).map(([id, info]) => {
      const ch = info as Record<string, unknown>;
      return {
        id,
        type: String(ch.type ?? ch.kind ?? "--"),
        status: String(ch.status ?? ch.state ?? "unknown"),
        connected: ch.status === "connected" || ch.state === "connected" ||
                   ch.status === "active" || ch.state === "active" ||
                   ch.status === "ok",
      };
    });
  }, [channelsData]);

  return (
    <Card className="mt-4">
      <CardHeader title="Channels" count={channels.length} />
      <CardBody className="space-y-2">
        {isLoading && <Spinner />}
        {!isLoading && channels.length === 0 && (
          <EmptyState message="No channels configured" />
        )}
        {channels.map((ch) => (
          <div
            key={ch.id}
            className="flex items-center gap-3 rounded-lg border border-zinc-800 bg-zinc-950/50 px-4 py-2.5"
          >
            <StatusDot status={ch.connected ? "connected" : "disconnected"} size="sm" />
            <span className="text-sm font-medium text-zinc-200 flex-1">{ch.id}</span>
            <Badge variant="muted">{ch.type}</Badge>
            <Badge variant={ch.connected ? "emerald" : "red"}>{ch.status}</Badge>
          </div>
        ))}
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Agent-to-Agent config
// ---------------------------------------------------------------------------

function AgentToAgentSection() {
  const { data: configData } = useConfig();

  const { enabled, allowed } = useMemo(() => {
    if (!configData) return { enabled: false, allowed: [] };
    const parsed = (configData.parsed ?? configData.raw ?? configData.config ?? {}) as Record<string, unknown>;
    const a2a = parsed.agentToAgent as Record<string, unknown> | undefined;
    if (!a2a) return { enabled: false, allowed: [] };
    return {
      enabled: a2a.enabled !== false,
      allowed: (a2a.allowedCallers ?? a2a.allowed ?? []) as string[],
    };
  }, [configData]);

  return (
    <Card className="mt-4">
      <CardHeader title="Agent-to-Agent Orchestration">
        <div className="flex items-center gap-2">
          <StatusDot status={enabled ? "active" : "stopped"} size="sm" />
          <span className={`text-xs ${enabled ? "text-emerald-400" : "text-zinc-500"}`}>
            {enabled ? "Enabled" : "Disabled"}
          </span>
        </div>
      </CardHeader>
      {enabled && allowed.length > 0 && (
        <CardBody>
          <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold mb-2">
            Allowed Callers
          </div>
          <div className="flex flex-wrap gap-2">
            {allowed.map((agent) => (
              <Badge key={agent} variant="indigo">{agent}</Badge>
            ))}
          </div>
        </CardBody>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function BrokerPage() {
  const health = useHealth();

  return (
    <div className="p-6 max-w-5xl">
      <PageHeader title="Broker" subtitle="Message broker and session orchestration" />

      {health ? (
        <HealthSection health={health} />
      ) : (
        <Card>
          <CardBody>
            <Spinner text="Connecting to gateway..." />
          </CardBody>
        </Card>
      )}

      <ActiveSessionsSection />
      <ChannelsSection />
      <AgentToAgentSection />
    </div>
  );
}
