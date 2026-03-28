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
  SkillsStatusResult,
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
  init: (url: string, token?: string) => void;
  disconnect: () => void;
}

export const useGatewayStore = create<GatewayStore>((set, get) => ({
  client: null,
  connectionState: "disconnected",
  health: null,
  presence: [],

  init(url: string, token?: string) {
    // Tear down any existing client first
    const prev = get().client;
    if (prev) {
      prev.disconnect();
    }

    const client = new RpcClient(url, token);

    client.onConnectionChange((state) => {
      set({ connectionState: state });
    });

    // Health event: the full health snapshot is the payload
    client.on("health", (params: any) => {
      if (params && typeof params === "object" && "ts" in params) {
        const current = get().health;
        if (current?.ts !== params.ts) {
          set({ health: params as HealthSnapshot });
        }
      }
    });

    // Also listen for the legacy event name in case gateway uses it
    client.on("health.snapshot", (params: any) => {
      if (params && typeof params === "object" && "ts" in params) {
        const current = get().health;
        if (current?.ts !== params.ts) {
          set({ health: params as HealthSnapshot });
        }
      }
    });

    // Presence: comes as array of presence objects from system-presence / connect response
    client.on("presence.update", (params: any) => {
      if (!params) return;
      // params may be an array directly or { entries: [...] }
      const entries: PresenceEntry[] = Array.isArray(params)
        ? params
        : Array.isArray(params.entries)
          ? params.entries
          : [];
      if (entries.length > 0 || get().presence.length > 0) {
        set({ presence: entries });
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
// React hooks -- RPC queries
// ---------------------------------------------------------------------------

export function useAgents() {
  return useRpcCall<AgentListResult>(["agents.list"], "agents.list", undefined, {
    staleTime: 120_000,
  });
}

export function useSessions(params?: { agent?: string; limit?: number; includeLastMessage?: boolean }) {
  return useRpcCall<SessionListResult>(
    ["sessions.list", params],
    "sessions.list",
    params,
    { staleTime: 5_000, refetchInterval: 15_000 },
  );
}

export function useSessionUsage(params?: { agent?: string; startDate?: string; endDate?: string }) {
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

export function useLogs(cursor?: number) {
  return useRpcCall<LogsResult>(
    ["logs.tail", cursor],
    "logs.tail",
    cursor != null ? { cursor } : undefined,
    { staleTime: 2_000, refetchInterval: 5_000 },
  );
}

export function useSkillsStatus(agentId?: string) {
  return useRpcCall<SkillsStatusResult>(
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
// React hooks -- store-derived (real-time via events)
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
