import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import ReactMarkdown from "react-markdown";
import {
  useAgents,
  useSessions,
  useGatewayStore,
} from "@/api/hooks";
import type { Session, ChatMessage, ChatHistoryResult } from "@/api/types";
import { agentFromKey } from "@/api/types";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function timeAgo(ts?: number): string {
  if (!ts) return "--";
  const diff = Date.now() - ts;
  if (diff < 60_000) return "just now";
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  return `${Math.floor(diff / 86_400_000)}d ago`;
}

function formatTimestamp(ts?: number): string {
  if (!ts) return "";
  return new Date(ts).toLocaleTimeString();
}

// ---------------------------------------------------------------------------
// Tool call rendering
// ---------------------------------------------------------------------------

function ToolCallBlock({ content }: { content: string }) {
  const [open, setOpen] = useState(false);
  // Attempt to detect JSON tool call blocks
  let parsed: { name?: string; input?: any; output?: any } | null = null;
  try {
    parsed = JSON.parse(content);
  } catch {
    // Not JSON, render as plain
  }

  const label = parsed?.name ?? "Tool Call";

  return (
    <div className="rounded border border-zinc-700 bg-zinc-800/50 my-1">
      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full text-left px-3 py-1.5 text-xs flex items-center gap-2 hover:bg-zinc-800 transition-colors"
      >
        <span className={`transition-transform ${open ? "rotate-90" : ""}`}>
          &#9654;
        </span>
        <span className="font-mono text-amber-400">{label}</span>
      </button>
      {open && (
        <div className="px-3 pb-2">
          <pre className="text-xs text-zinc-400 whitespace-pre-wrap break-all max-h-64 overflow-y-auto">
            {parsed ? JSON.stringify(parsed, null, 2) : content}
          </pre>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

function MessageBubble({ msg }: { msg: ChatMessage }) {
  const isUser = msg.role === "user";
  const isTool = msg.role === "tool";

  if (isTool) {
    const text =
      typeof msg.content === "string"
        ? msg.content
        : JSON.stringify(msg.content);
    return <ToolCallBlock content={text} />;
  }

  // Assistant may have array content with tool_use blocks
  if (Array.isArray(msg.content)) {
    return (
      <div className="space-y-1">
        {msg.content.map((block: any, i: number) => {
          if (block.type === "tool_use" || block.type === "tool_result") {
            return <ToolCallBlock key={i} content={JSON.stringify(block)} />;
          }
          const text = block.text ?? block.content ?? JSON.stringify(block);
          return (
            <div
              key={i}
              className="rounded-lg px-3 py-2 bg-zinc-800 text-zinc-200 text-sm"
            >
              <div className="prose prose-sm prose-invert max-w-none [&_pre]:bg-zinc-900 [&_pre]:p-2 [&_pre]:rounded [&_code]:text-amber-300">
                <ReactMarkdown>{text}</ReactMarkdown>
              </div>
            </div>
          );
        })}
      </div>
    );
  }

  const text = typeof msg.content === "string" ? msg.content : JSON.stringify(msg.content);

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[80%] rounded-lg px-3 py-2 text-sm ${
          isUser
            ? "bg-indigo-600 text-zinc-100"
            : "bg-zinc-800 text-zinc-200"
        }`}
      >
        <div className="flex items-center gap-2 mb-1">
          <span className="text-[10px] font-semibold uppercase tracking-wider opacity-60">
            {msg.role}
          </span>
          {msg.ts && (
            <span className="text-[10px] opacity-40">
              {formatTimestamp(msg.ts)}
            </span>
          )}
        </div>
        {isUser ? (
          <span className="whitespace-pre-wrap">{text}</span>
        ) : (
          <div className="prose prose-sm prose-invert max-w-none [&_pre]:bg-zinc-900 [&_pre]:p-2 [&_pre]:rounded [&_code]:text-amber-300">
            <ReactMarkdown>{text}</ReactMarkdown>
          </div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Session list item
// ---------------------------------------------------------------------------

function SessionRow({
  session,
  active,
  onClick,
}: {
  session: Session;
  active: boolean;
  onClick: () => void;
}) {
  const agentId = agentFromKey(session.key);

  return (
    <button
      onClick={onClick}
      className={`w-full text-left px-3 py-2.5 border-b border-zinc-800 transition-colors ${
        active ? "bg-zinc-800" : "hover:bg-zinc-800/50"
      }`}
    >
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-zinc-200 truncate">
          {session.displayName || session.key.slice(0, 20)}
        </span>
        <span className="text-[10px] text-zinc-500 shrink-0 ml-2">
          {timeAgo(session.updatedAt)}
        </span>
      </div>
      <div className="text-xs text-zinc-500 mt-0.5 flex items-center gap-1.5">
        <span className="bg-zinc-700 text-zinc-300 px-1.5 py-0.5 rounded text-[10px]">
          {agentId}
        </span>
        {session.status && (
          <span className={`${session.status === "idle" ? "text-zinc-500" : "text-amber-400"}`}>
            {session.status}
          </span>
        )}
        {session.model && (
          <span className="truncate">{session.model}</span>
        )}
      </div>
      {session.lastMessagePreview && (
        <p className="text-xs text-zinc-500 mt-1 truncate">
          {session.lastMessagePreview}
        </p>
      )}
    </button>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function SessionsPage() {
  const { data: agentData } = useAgents();
  const [agentFilter, setAgentFilter] = useState<string>("");
  const [search, setSearch] = useState("");
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const client = useGatewayStore((s) => s.client);

  const { data: sessionData, isLoading, refetch } = useSessions(
    agentFilter
      ? { agent: agentFilter, includeLastMessage: true }
      : { includeLastMessage: true },
  );

  const sessions = sessionData?.sessions ?? [];
  const agents = agentData?.agents ?? [];

  // Filter by search (memoized to avoid recomputation on message updates)
  const filtered = useMemo(() => sessions.filter((s) => {
    if (!search) return true;
    const q = search.toLowerCase();
    const agentId = agentFromKey(s.key);
    return (
      s.key.toLowerCase().includes(q) ||
      (s.displayName ?? "").toLowerCase().includes(q) ||
      agentId.toLowerCase().includes(q)
    );
  }), [sessions, search]);

  const selectedSession = useMemo(
    () => filtered.find((s) => s.key === selectedKey),
    [filtered, selectedKey],
  );

  // Load history when selection changes
  useEffect(() => {
    if (!selectedKey || !client) {
      setMessages([]);
      return;
    }
    setHistoryLoading(true);
    setHistoryError(null);
    client
      .call<ChatHistoryResult>("chat.history", { key: selectedKey })
      .then((res) => {
        setMessages(res?.messages ?? []);
      })
      .catch((err) => {
        setHistoryError(err?.message ?? "Failed to load history");
        setMessages([]);
      })
      .finally(() => setHistoryLoading(false));
  }, [selectedKey, client]);

  // Listen for real-time messages
  useEffect(() => {
    if (!client || !selectedKey) return;
    const off = client.on("sessions.messages", (params: any) => {
      if (params?.key === selectedKey && params?.messages) {
        setMessages((prev) => [...prev, ...params.messages]);
      }
    });
    return off;
  }, [client, selectedKey]);

  // Auto-scroll
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  // Actions
  const handleAction = useCallback(
    async (action: "abort" | "reset" | "delete") => {
      if (!client || !selectedKey) return;
      try {
        await client.call(`sessions.${action}`, { key: selectedKey });
        if (action === "delete") {
          setSelectedKey(null);
          setMessages([]);
        }
        refetch();
      } catch (err: any) {
        console.error(`sessions.${action} failed:`, err);
      }
    },
    [client, selectedKey, refetch],
  );

  return (
    <div className="flex h-screen">
      {/* Left panel: session list */}
      <div className="w-[340px] shrink-0 border-r border-zinc-800 bg-zinc-900 flex flex-col">
        <div className="p-3 border-b border-zinc-800 space-y-2">
          <h2 className="text-lg font-semibold text-zinc-100">Sessions</h2>
          {/* Agent filter */}
          <select
            value={agentFilter}
            onChange={(e) => setAgentFilter(e.target.value)}
            className="w-full bg-zinc-800 border border-zinc-700 rounded px-2 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            <option value="">All agents</option>
            {agents.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name ?? a.id}
              </option>
            ))}
          </select>
          {/* Search */}
          <input
            type="text"
            placeholder="Search sessions..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full bg-zinc-800 border border-zinc-700 rounded px-2 py-1.5 text-sm text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
          {/* Count */}
          {sessionData && (
            <div className="text-xs text-zinc-500">
              {sessionData.count} total session{sessionData.count !== 1 ? "s" : ""}
            </div>
          )}
        </div>

        <div className="flex-1 overflow-y-auto">
          {isLoading ? (
            <div className="p-4 text-sm text-zinc-500">Loading...</div>
          ) : filtered.length === 0 ? (
            <div className="p-4 text-sm text-zinc-500">No sessions found</div>
          ) : (
            filtered.map((s) => (
              <SessionRow
                key={s.key}
                session={s}
                active={s.key === selectedKey}
                onClick={() => setSelectedKey(s.key)}
              />
            ))
          )}
        </div>
      </div>

      {/* Right panel: conversation */}
      <div className="flex-1 flex flex-col bg-zinc-950">
        {!selectedKey ? (
          <div className="flex-1 flex items-center justify-center text-zinc-500 text-sm">
            Select a session to view conversation
          </div>
        ) : (
          <>
            {/* Header */}
            <div className="px-4 py-3 border-b border-zinc-800 bg-zinc-900 flex items-center justify-between">
              <div>
                <div className="text-sm font-semibold text-zinc-100">
                  {selectedSession?.displayName ||
                    selectedKey.slice(0, 24)}
                </div>
                <div className="text-xs text-zinc-500 mt-0.5">
                  {selectedSession
                    ? agentFromKey(selectedSession.key)
                    : "--"}{" "}
                  · {messages.length} messages
                  {selectedSession?.status && ` · ${selectedSession.status}`}
                </div>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => handleAction("abort")}
                  className="px-2.5 py-1 text-xs bg-amber-600/20 text-amber-400 rounded hover:bg-amber-600/30 transition-colors"
                >
                  Abort
                </button>
                <button
                  onClick={() => handleAction("reset")}
                  className="px-2.5 py-1 text-xs bg-zinc-700 text-zinc-300 rounded hover:bg-zinc-600 transition-colors"
                >
                  Reset
                </button>
                <button
                  onClick={() => handleAction("delete")}
                  className="px-2.5 py-1 text-xs bg-red-600/20 text-red-400 rounded hover:bg-red-600/30 transition-colors"
                >
                  Delete
                </button>
              </div>
            </div>

            {/* Messages */}
            <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3">
              {historyLoading ? (
                <div className="text-center text-zinc-500 text-sm py-8">
                  Loading history...
                </div>
              ) : historyError ? (
                <div className="text-center text-red-400 text-sm py-8">
                  {historyError}
                </div>
              ) : messages.length === 0 ? (
                <div className="text-center text-zinc-500 text-sm py-8">
                  No messages yet
                </div>
              ) : (
                messages.map((msg, i) => (
                  <MessageBubble key={`${msg.ts ?? i}-${i}`} msg={msg} />
                ))
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
