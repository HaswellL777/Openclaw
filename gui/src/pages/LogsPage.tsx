import { useState, useEffect, useRef, useCallback } from "react";
import { useGatewayStore } from "@/api/hooks";
import type { LogsResult } from "@/api/types";

// ---------------------------------------------------------------------------
// Color coding
// ---------------------------------------------------------------------------

type LogLevel = "info" | "warn" | "error" | "debug" | "trace";

function detectLevel(line: string): LogLevel {
  const lower = line.toLowerCase();
  if (lower.includes(" error ") || lower.includes("[error]") || lower.includes('"level":"error"'))
    return "error";
  if (lower.includes(" warn") || lower.includes("[warn]") || lower.includes('"level":"warn"'))
    return "warn";
  if (lower.includes(" debug ") || lower.includes("[debug]") || lower.includes('"level":"debug"'))
    return "debug";
  if (lower.includes(" trace ") || lower.includes("[trace]") || lower.includes('"level":"trace"'))
    return "trace";
  return "info";
}

const levelColors: Record<LogLevel, string> = {
  info: "text-emerald-400",
  warn: "text-amber-400",
  error: "text-red-400",
  debug: "text-blue-400",
  trace: "text-zinc-500",
};

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function LogsPage() {
  const client = useGatewayStore((s) => s.client);
  const connected = useGatewayStore((s) => s.connectionState === "connected");

  const [lines, setLines] = useState<string[]>([]);
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [filter, setFilter] = useState("");
  const [autoScroll, setAutoScroll] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);

  const scrollRef = useRef<HTMLDivElement>(null);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Fetch logs
  const fetchLogs = useCallback(
    async (cursorVal?: string) => {
      if (!client || !connected) return;
      setLoading(true);
      setError(null);
      try {
        const res = await client.call<LogsResult>(
          "logs.tail",
          cursorVal ? { cursor: cursorVal } : undefined,
        );
        if (res.reset) {
          setLines(res.lines);
        } else {
          setLines((prev) => [...prev, ...res.lines]);
        }
        setCursor(res.cursor);
        setHasMore(!res.truncated || res.lines.length > 0);
      } catch (err: any) {
        setError(err?.message ?? "Failed to load logs");
      } finally {
        setLoading(false);
      }
    },
    [client, connected],
  );

  // Initial load
  useEffect(() => {
    if (connected && client) {
      fetchLogs();
    }
  }, [connected, client, fetchLogs]);

  // Polling for new logs
  useEffect(() => {
    if (!connected || !client) return;
    pollRef.current = setInterval(() => {
      if (cursor) {
        fetchLogs(cursor);
      }
    }, 5000);
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, [connected, client, cursor, fetchLogs]);

  // Listen for real-time log pushes
  useEffect(() => {
    if (!client) return;
    const off = client.on("logs.append", (params: any) => {
      if (params?.lines) {
        setLines((prev) => [...prev, ...params.lines]);
        if (params.cursor) setCursor(params.cursor);
      }
    });
    return off;
  }, [client]);

  // Auto-scroll
  useEffect(() => {
    if (autoScroll && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [lines, autoScroll]);

  // Handle scroll to detect manual scroll-up
  const handleScroll = useCallback(() => {
    if (!scrollRef.current) return;
    const el = scrollRef.current;
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
    if (autoScroll && !atBottom) {
      setAutoScroll(false);
    }
  }, [autoScroll]);

  // Filtered lines
  const filteredLines = filter
    ? lines.filter((l) => l.toLowerCase().includes(filter.toLowerCase()))
    : lines;

  // Load older
  const handleLoadOlder = () => {
    if (cursor && hasMore) fetchLogs(cursor);
  };

  return (
    <div className="flex flex-col h-screen">
      {/* Header */}
      <div className="px-4 py-3 border-b border-zinc-800 bg-zinc-900 flex items-center gap-3 flex-wrap">
        <h1 className="text-lg font-semibold text-zinc-100">Logs</h1>
        <input
          type="text"
          placeholder="Filter…"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="bg-zinc-800 border border-zinc-700 rounded px-2.5 py-1.5 text-sm text-zinc-200 placeholder:text-zinc-500 w-64 focus:outline-none focus:ring-1 focus:ring-indigo-500"
        />
        <button
          onClick={() => setAutoScroll((v) => !v)}
          className={`px-2.5 py-1.5 text-xs rounded transition-colors ${
            autoScroll
              ? "bg-indigo-600/20 text-indigo-300 border border-indigo-500/30"
              : "bg-zinc-800 text-zinc-400 border border-zinc-700"
          }`}
        >
          Auto-scroll {autoScroll ? "ON" : "OFF"}
        </button>
        <button
          onClick={() => {
            setLines([]);
            setCursor(undefined);
            fetchLogs();
          }}
          className="px-2.5 py-1.5 text-xs bg-zinc-800 text-zinc-400 border border-zinc-700 rounded hover:bg-zinc-700 transition-colors"
        >
          Refresh
        </button>
        <span className="text-xs text-zinc-500 ml-auto">
          {filteredLines.length} line{filteredLines.length !== 1 ? "s" : ""}
          {filter && ` (filtered from ${lines.length})`}
        </span>
      </div>

      {/* Log output */}
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto bg-zinc-950 font-mono text-xs leading-5"
      >
        {error && (
          <div className="px-4 py-2 text-red-400 bg-red-900/20 border-b border-red-800">
            {error}
          </div>
        )}

        {loading && lines.length === 0 && (
          <div className="px-4 py-8 text-zinc-500 text-center">
            Loading logs…
          </div>
        )}

        {!loading && lines.length === 0 && (
          <div className="px-4 py-8 text-zinc-500 text-center">
            No log lines available
          </div>
        )}

        {filteredLines.length > 0 && hasMore && (
          <button
            onClick={handleLoadOlder}
            className="w-full py-1.5 text-xs text-zinc-500 hover:text-zinc-300 hover:bg-zinc-900 transition-colors"
            disabled={loading}
          >
            {loading ? "Loading…" : "Load older"}
          </button>
        )}

        {filteredLines.map((line, i) => {
          const level = detectLevel(line);
          return (
            <div
              key={i}
              className={`px-4 py-px hover:bg-zinc-900 ${levelColors[level]}`}
            >
              <span className="text-zinc-600 select-none mr-3 inline-block w-10 text-right">
                {i + 1}
              </span>
              {line}
            </div>
          );
        })}
      </div>

      {/* Sticky bottom bar when auto-scroll is off */}
      {!autoScroll && (
        <div className="border-t border-zinc-800 bg-zinc-900 px-4 py-2 flex items-center justify-center">
          <button
            onClick={() => {
              setAutoScroll(true);
              if (scrollRef.current) {
                scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
              }
            }}
            className="text-xs text-indigo-400 hover:text-indigo-300 transition-colors"
          >
            ↓ Scroll to bottom & resume auto-scroll
          </button>
        </div>
      )}
    </div>
  );
}
