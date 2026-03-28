import { create } from "zustand";
import { useQuery } from "@tanstack/react-query";
import { RpcClient } from "@/api/rpc-client";
import type { ConnectionState } from "@/api/rpc-client";
import type {
  AgentListResult,
  SessionListResult,
  SessionUsageResult,
  CronListResult,
  CronRunsResult,
  ModelsListResult,
  HealthSnapshot,
  PresenceEntry,
  LogsResult,
  SkillStatus,
  ToolsCatalogResult,
  ConfigResult,
  ChannelsStatusResult,
} from "@/api/types";

// ---------------------------------------------------------------------------
// Zustand store
// ---------------------------------------------------------------------------

interface GatewayStore {
  client: RpcClient | null;
  connectionState: ConnectionState;
  health: HealthSnapshot | null;
  presence: PresenceEntry[];
  init: (url: string) => void;
  disconnect: () => void;
}

export const useGatewayStore = create<GatewayStore>((set, get) => ({
  client: null,
  connectionState: "disconnected",
  health: null,
  presence: [],

  init(url: string) {
    // Tear down any existing client first
    const prev = get().client;
    if (prev) {
      prev.disconnect();
    }

    const client = new RpcClient(url);

    client.onConnectionChange((state) => {
      set({ connectionState: state });
    });

    client.on("health.snapshot", (params: HealthSnapshot) => {
      set({ health: params });
    });

    client.on("presence.update", (params: { entries: PresenceEntry[] }) => {
      if (params?.entries) {
        set({ presence: params.entries });
      }
    });

    client.on("sessions.changed", () => {
      // Invalidation is handled by react-query refetch listeners in hooks
    });

    client.connect();
    set({ client });
  },

  disconnect() {
    const c = get().client;
    if (c) {
      c.disconnect();
    }
    set({ client: null, connectionState: "disconnected", health: null, presence: [] });
  },
}));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function useRpcCall<T>(
  queryKey: readonly unknown[],
  method: string,
  params?: any,
  opts?: { enabled?: boolean; staleTime?: number; refetchInterval?: number },
) {
  const client = useGatewayStore((s) => s.client);
  const connected = useGatewayStore((s) => s.connectionState === "connected");

  return useQuery<T>({
    queryKey,
    queryFn: () => {
      if (!client) throw new Error("RPC client not initialized");
      return client.call<T>(method, params);
    },
    enabled: (opts?.enabled ?? true) && connected && !!client,
    staleTime: opts?.staleTime ?? 10_000,
    refetchInterval: opts?.refetchInterval,
  });
}

// ---------------------------------------------------------------------------
// React hooks — RPC queries
// ---------------------------------------------------------------------------

export function useAgents() {
  return useRpcCall<AgentListResult>(["agents.list"], "agents.list");
}

export function useSessions(params?: { agent?: string; limit?: number }) {
  return useRpcCall<SessionListResult>(
    ["sessions.list", params],
    "sessions.list",
    params,
    { staleTime: 5_000, refetchInterval: 15_000 },
  );
}

export function useSessionUsage(params?: { agent?: string; days?: number }) {
  return useRpcCall<SessionUsageResult>(
    ["sessions.usage", params],
    "sessions.usage",
    params,
    { staleTime: 60_000 },
  );
}

export function useCronJobs() {
  return useRpcCall<CronListResult>(["cron.list"], "cron.list", undefined, {
    staleTime: 15_000,
  });
}

export function useCronRuns(jobId?: string) {
  return useRpcCall<CronRunsResult>(
    ["cron.runs", jobId],
    "cron.runs",
    jobId ? { jobId } : undefined,
    { enabled: !!jobId, staleTime: 10_000 },
  );
}

export function useModels() {
  return useRpcCall<ModelsListResult>(["models.list"], "models.list", undefined, {
    staleTime: 300_000,
  });
}

export function useLogs(cursor?: string) {
  return useRpcCall<LogsResult>(
    ["logs.tail", cursor],
    "logs.tail",
    cursor ? { cursor } : undefined,
    { staleTime: 2_000, refetchInterval: 5_000 },
  );
}

export function useSkillsStatus(agentId?: string) {
  return useRpcCall<SkillStatus>(
    ["skills.status", agentId],
    "skills.status",
    agentId ? { agentId } : undefined,
    { staleTime: 30_000 },
  );
}

export function useToolsCatalog(agentId?: string) {
  return useRpcCall<ToolsCatalogResult>(
    ["tools.catalog", agentId],
    "tools.catalog",
    agentId ? { agentId } : undefined,
    { staleTime: 60_000 },
  );
}

export function useConfig() {
  return useRpcCall<ConfigResult>(["config.get"], "config.get", undefined, {
    staleTime: 120_000,
  });
}

export function useChannelsStatus() {
  return useRpcCall<ChannelsStatusResult>(
    ["channels.status"],
    "channels.status",
    undefined,
    { staleTime: 10_000, refetchInterval: 30_000 },
  );
}

// ---------------------------------------------------------------------------
// React hooks — store-derived (real-time via events)
// ---------------------------------------------------------------------------

export function useHealth() {
  return useGatewayStore((s) => s.health);
}

export function usePresence() {
  return useGatewayStore((s) => s.presence);
}

export function useConnectionState() {
  return useGatewayStore((s) => s.connectionState);
}
