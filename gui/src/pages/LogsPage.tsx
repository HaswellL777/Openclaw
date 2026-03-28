import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import { useGatewayStore } from "@/api/hooks";
import type { LogsResult, ParsedLogLine } from "@/api/types";

// ---------------------------------------------------------------------------
// Log line parsing and color coding
// ---------------------------------------------------------------------------

type LogLevel = "info" | "warn" | "error" | "debug" | "trace";

function parseLogLine(raw: string): ParsedLogLine {
  try {
    const obj = JSON.parse(raw);
    return {
      time: obj.time ?? obj.timestamp ?? obj.ts,
      level: (obj.level ?? "info").toLowerCase(),
      subsystem: obj.subsystem ?? obj.component ?? obj.module,
      message: obj.message ?? obj.msg,
      raw,
      ...obj,
    };
  } catch {
    // Not JSON, fall back to raw string detection
    return {
      level: detectLevelFromRaw(raw),
      message: raw,
      raw,
    };
  }
}

function detectLevelFromRaw(line: string): string {
  const lower = line.toLowerCase();
  if (lower.includes('"level":"error"') || lower.includes(" error ") || lower.includes("[error]"))
    return "error";
  if (lower.includes('"level":"warn"') || lower.includes(" warn") || lower.includes("[warn]"))
    return "warn";
  if (lower.includes('"level":"debug"') || lower.includes(" debug ") || lower.includes("[debug]"))
    return "debug";
  if (lower.includes('"level":"trace"') || lower.includes(" trace ") || lower.includes("[trace]"))
    return "trace";
  return "info";
}

function normalizeLevel(level?: string): LogLevel {
  const l = (level ?? "info").toLowerCase();
  if (l === "error" || l === "fatal") return "error";
  if (l === "warn" || l === "warning") return "warn";
  if (l === "debug") return "debug";
  if (l === "trace") return "trace";
  return "info";
}

const levelColors: Record<LogLevel, string> = {
  info: "text-emerald-400",
  warn: "text-amber-400",
  error: "text-red-400",
  debug: "text-blue-400",
  trace: "text-zinc-500",
};

const levelBadgeColors: Record<LogLevel, string> = {
  info: "bg-emerald-900/40 text-emerald-400",
  warn: "bg-amber-900/40 text-amber-400",
  error: "bg-red-900/40 text-red-400",
  debug: "bg-blue-900/40 text-blue-400",
  trace: "bg-zinc-800 text-zinc-500",
};

function formatLogTime(time?: string): string {
  if (!time) return "";
  try {
    const d = new Date(time);
    return d.toLocaleTimeString(undefined, { hour12: false, fractionalSecondDigits: 3 });
  } catch {
    return time;
  }
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function LogsPage() {
  const client = useGatewayStore((s) => s.client);
  const connected = useGatewayStore((s) => s.connectionState === "connected");

  const [lines, setLines] = useState<string[]>([]);
  const MAX_LINES = 10_000;
  const [cursor, setCursor] = useState<number | undefined>(undefined);
  const [filter, setFilter] = useState("");
  const [levelFilter, setLevelFilter] = useState<LogLevel | "">("");
  const [autoScroll, setAutoScroll] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [viewMode, setViewMode] = useState<"structured" | "raw">("structured");

  const scrollRef = useRef<HTMLDivElement>(null);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Fetch logs
  const fetchLogs = useCallback(
    async (cursorVal?: number) => {
      if (!client || !connected) return;
      setLoading(true);
      setError(null);
      try {
        const res = await client.call<LogsResult>(
          "logs.tail",
          cursorVal != null ? { cursor: cursorVal } : undefined,
        );
        if (res.reset) {
          setLines(res.lines);
        } else {
          setLines((prev) => {
            const next = [...prev, ...res.lines];
            return next.length > MAX_LINES ? next.slice(next.length - MAX_LINES) : next;
          });
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
      if (cursor != null) {
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
        setLines((prev) => {
          const next = [...prev, ...params.lines];
          return next.length > MAX_LINES ? next.slice(next.length - MAX_LINES) : next;
        });
        if (params.cursor != null) setCursor(params.cursor);
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

  // Parse and filter lines (memoized for performance)
  const processedLines = useMemo(() => {
    return lines.map((raw) => parseLogLine(raw));
  }, [lines]);

  const filteredLines = useMemo(() => {
    return processedLines.filter((parsed) => {
      // Level filter
      if (levelFilter) {
        const lvl = normalizeLevel(parsed.level);
        if (lvl !== levelFilter) return false;
      }
      // Text filter
      if (filter) {
        const q = filter.toLowerCase();
        const searchText = `${parsed.message ?? ""} ${parsed.subsystem ?? ""} ${parsed.raw}`.toLowerCase();
        if (!searchText.includes(q)) return false;
      }
      return true;
    });
  }, [processedLines, filter, levelFilter]);

  // Load older
  const handleLoadOlder = () => {
    if (cursor != null && hasMore) fetchLogs(cursor);
  };

  return (
    <div className="flex flex-col h-screen">
      {/* Header */}
      <div className="px-4 py-3 border-b border-zinc-800 bg-zinc-900 flex items-center gap-3 flex-wrap">
        <h1 className="text-lg font-semibold text-zinc-100">Logs</h1>
        <input
          type="text"
          placeholder="Filter..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="bg-zinc-800 border border-zinc-700 rounded px-2.5 py-1.5 text-sm text-zinc-200 placeholder:text-zinc-500 w-52 focus:outline-none focus:ring-1 focus:ring-indigo-500"
        />
        {/* Level filter */}
        <select
          value={levelFilter}
          onChange={(e) => setLevelFilter(e.target.value as LogLevel | "")}
          className="bg-zinc-800 border border-zinc-700 rounded px-2 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
        >
          <option value="">All levels</option>
          <option value="error">error</option>
          <option value="warn">warn</option>
          <option value="info">info</option>
          <option value="debug">debug</option>
          <option value="trace">trace</option>
        </select>
        {/* View mode */}
        <button
          onClick={() => setViewMode((v) => (v === "structured" ? "raw" : "structured"))}
          className="px-2.5 py-1.5 text-xs bg-zinc-800 text-zinc-400 border border-zinc-700 rounded hover:bg-zinc-700 transition-colors"
        >
          {viewMode === "structured" ? "Raw" : "Structured"}
        </button>
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
          {(filter || levelFilter) && ` (filtered from ${lines.length})`}
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
            Loading logs...
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
            {loading ? "Loading..." : "Load older"}
          </button>
        )}

        {viewMode === "structured"
          ? filteredLines.map((parsed, i) => {
              const level = normalizeLevel(parsed.level);
              return (
                <div
                  key={i}
                  className="px-4 py-0.5 hover:bg-zinc-900 flex items-start gap-2"
                >
                  <span className="text-zinc-600 select-none shrink-0 w-10 text-right">
                    {i + 1}
                  </span>
                  {parsed.time && (
                    <span className="text-zinc-600 shrink-0 w-[90px]">
                      {formatLogTime(parsed.time)}
                    </span>
                  )}
                  <span
                    className={`shrink-0 w-[44px] text-center rounded px-1 py-px text-[10px] font-semibold uppercase ${levelBadgeColors[level]}`}
                  >
                    {level}
                  </span>
                  {parsed.subsystem && (
                    <span className="text-zinc-500 shrink-0 max-w-[120px] truncate">
                      [{parsed.subsystem}]
                    </span>
                  )}
                  <span className={`flex-1 break-all ${levelColors[level]}`}>
                    {parsed.message ?? parsed.raw}
                  </span>
                </div>
              );
            })
          : filteredLines.map((parsed, i) => {
              const level = normalizeLevel(parsed.level);
              return (
                <div
                  key={i}
                  className={`px-4 py-px hover:bg-zinc-900 ${levelColors[level]}`}
                >
                  <span className="text-zinc-600 select-none mr-3 inline-block w-10 text-right">
                    {i + 1}
                  </span>
                  {parsed.raw}
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
            Scroll to bottom and resume auto-scroll
          </button>
        </div>
      )}
    </div>
  );
}
