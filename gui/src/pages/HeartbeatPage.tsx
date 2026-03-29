import { useState, useEffect, useCallback } from "react";
import { useQuery } from "@tanstack/react-query";
import { useGatewayStore, useHealth } from "@/api/hooks";
import {
  PageHeader, Card, CardHeader, CardBody,
  StatusDot, Spinner, EmptyState, Badge,
} from "@/components/shared";

export default function HeartbeatPage() {
  const client = useGatewayStore(s => s.client);
  const connected = useGatewayStore(s => s.connectionState === "connected");
  const health = useHealth();

  // Last heartbeat
  const { data: lastHb, refetch: refetchHb } = useQuery<any>({
    queryKey: ["last-heartbeat"],
    queryFn: () => client!.call("last-heartbeat", {}),
    enabled: connected && !!client,
    staleTime: 5_000,
    refetchInterval: 10_000,
  });

  // Heartbeat enabled state (derive from health)
  const [enabled, setEnabled] = useState<boolean | null>(null);
  const heartbeatSeconds = (health as any)?.heartbeatSeconds;

  useEffect(() => {
    if (enabled === null && heartbeatSeconds != null) {
      setEnabled(heartbeatSeconds > 0);
    }
  }, [heartbeatSeconds, enabled]);

  const toggleEnabled = useCallback(async () => {
    if (!client) return;
    const next = !enabled;
    try {
      await client.call("set-heartbeats", { enabled: next });
      setEnabled(next);
    } catch (err: any) {
      console.error("set-heartbeats failed:", err);
    }
  }, [client, enabled]);

  // Wake
  const [wakeText, setWakeText] = useState("");
  const [wakeMode, setWakeMode] = useState<"now" | "next-heartbeat">("now");
  const [wakeSending, setWakeSending] = useState(false);
  const [wakeResult, setWakeResult] = useState<string | null>(null);

  const sendWake = useCallback(async () => {
    if (!client || !wakeText.trim()) return;
    setWakeSending(true);
    setWakeResult(null);
    try {
      await client.call("wake", { mode: wakeMode, text: wakeText.trim() });
      setWakeResult("Sent");
      setWakeText("");
      setTimeout(() => setWakeResult(null), 3000);
    } catch (err: any) {
      setWakeResult("Error: " + (err?.message ?? "unknown"));
    } finally {
      setWakeSending(false);
    }
  }, [client, wakeText, wakeMode]);

  // Live heartbeat events
  const [events, setEvents] = useState<any[]>([]);
  useEffect(() => {
    if (!client) return;
    return client.on("heartbeat", (payload: any) => {
      setEvents(prev => [{ ts: Date.now(), payload }, ...prev].slice(0, 20));
    });
  }, [client]);

  const lastHbTs = lastHb?.ts ?? lastHb?.timestamp;

  return (
    <div className="p-6 h-full overflow-y-auto">
      <PageHeader title="Heartbeat" subtitle="Gateway heartbeat monitoring and wake control" />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        {/* Last Heartbeat */}
        <Card>
          <CardHeader title="Last Heartbeat">
            <StatusDot status={lastHbTs ? "active" : "idle"} size="sm" />
          </CardHeader>
          <CardBody>
            {lastHbTs ? (
              <div className="space-y-2 text-xs">
                <div className="flex justify-between">
                  <span className="text-zinc-500">Timestamp</span>
                  <span className="text-zinc-300 tabular-nums">{new Date(lastHbTs).toLocaleString("zh-CN")}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-500">Interval</span>
                  <span className="text-zinc-300">{heartbeatSeconds ? `${heartbeatSeconds}s` : "—"}</span>
                </div>
                <pre className="text-[10px] text-zinc-500 bg-zinc-800/40 rounded p-2 mt-2 whitespace-pre-wrap max-h-32 overflow-y-auto">
                  {JSON.stringify(lastHb, null, 2)}
                </pre>
              </div>
            ) : (
              <EmptyState message="No heartbeat received yet" />
            )}
          </CardBody>
        </Card>

        {/* Control */}
        <Card>
          <CardHeader title="Heartbeat Control" />
          <CardBody>
            <div className="space-y-4">
              {/* Enable/disable toggle */}
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-sm text-zinc-200">Broadcasting</div>
                  <div className="text-[10px] text-zinc-500">Enable or disable heartbeat event broadcasting</div>
                </div>
                <button
                  onClick={toggleEnabled}
                  className={`relative w-11 h-6 rounded-full transition-colors ${enabled ? "bg-emerald-600" : "bg-zinc-700"}`}
                >
                  <span className={`absolute top-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform ${enabled ? "left-[22px]" : "left-0.5"}`} />
                </button>
              </div>

              {/* Wake */}
              <div className="border-t border-zinc-800 pt-4">
                <div className="text-sm text-zinc-200 mb-2">Wake</div>
                <div className="flex gap-2 mb-2">
                  {(["now", "next-heartbeat"] as const).map(m => (
                    <button key={m} onClick={() => setWakeMode(m)}
                      className={`px-3 py-1 text-[11px] rounded transition-colors ${wakeMode === m ? "bg-indigo-600/20 text-indigo-300 border border-indigo-500/30" : "bg-zinc-800 text-zinc-400 border border-zinc-700/40"}`}>
                      {m}
                    </button>
                  ))}
                </div>
                <div className="flex gap-2">
                  <input
                    value={wakeText} onChange={e => setWakeText(e.target.value)}
                    placeholder="Wake message..."
                    className="flex-1 bg-zinc-800 border border-zinc-700 rounded px-2.5 py-1.5 text-sm text-zinc-200 placeholder-zinc-600 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                    onKeyDown={e => { if (e.key === "Enter") sendWake(); }}
                  />
                  <button onClick={sendWake} disabled={wakeSending || !wakeText.trim()}
                    className="px-3 py-1.5 text-sm bg-indigo-600/20 text-indigo-400 rounded hover:bg-indigo-600/30 disabled:opacity-40 transition-colors font-medium">
                    {wakeSending ? "..." : "Send"}
                  </button>
                </div>
                {wakeResult && (
                  <div className={`text-[10px] mt-1.5 ${wakeResult.startsWith("Error") ? "text-red-400" : "text-emerald-400"}`}>
                    {wakeResult}
                  </div>
                )}
              </div>
            </div>
          </CardBody>
        </Card>
      </div>

      {/* Live event log */}
      <Card>
        <CardHeader title="Live Heartbeat Events" count={events.length}>
          {events.length > 0 && (
            <button onClick={() => setEvents([])} className="text-[10px] text-zinc-500 hover:text-zinc-300">Clear</button>
          )}
        </CardHeader>
        <CardBody className="p-0">
          {events.length === 0 ? (
            <div className="p-4"><EmptyState message="Listening for heartbeat events..." /></div>
          ) : (
            <div className="max-h-[400px] overflow-y-auto">
              {events.map((e, i) => (
                <div key={i} className="px-3 py-1.5 border-b border-zinc-800/30 flex items-center gap-3 text-xs">
                  <span className="text-zinc-600 tabular-nums shrink-0">{new Date(e.ts).toLocaleTimeString("zh-CN")}</span>
                  <span className="text-zinc-400 truncate">{JSON.stringify(e.payload).slice(0, 120)}</span>
                </div>
              ))}
            </div>
          )}
        </CardBody>
      </Card>
    </div>
  );
}
