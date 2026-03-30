import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  useAgents,
  useSessions,
  useGatewayStore,
} from "@/api/hooks";
import type { Session, ChatMessage, ChatHistoryResult } from "@/api/types";
import { agentFromKey } from "@/api/types";
import { MessageRenderer } from "@/components/MessageRenderer";
import {
  StatusDot,
  Spinner,
  EmptyState,
  Badge,
} from "@/components/shared";

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

function sessionStatus(s: Session): "active" | "idle" | "error" {
  if (s.status === "error" || s.status === "failed") return "error";
  if (
    s.status === "active" ||
    s.status === "running" ||
    s.status === "streaming"
  )
    return "active";
  return "idle";
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
  const variant = sessionStatus(session);

  return (
    <button
      onClick={onClick}
      className={`w-full text-left px-3 py-2.5 border-b border-zinc-800/60 transition-colors ${
        active
          ? "bg-zinc-800/80 border-l-2 border-l-indigo-500"
          : "hover:bg-zinc-800/30 border-l-2 border-l-transparent"
      }`}
    >
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <StatusDot status={variant} size="xs" />
          <span className="text-sm font-medium text-zinc-200 truncate">
            {session.displayName || session.key.slice(0, 20)}
          </span>
        </div>
        <span className="text-[10px] text-zinc-600 shrink-0 tabular-nums">
          {timeAgo(session.updatedAt)}
        </span>
      </div>
      <div className="text-xs text-zinc-500 mt-1 flex items-center gap-1.5 pl-4">
        <Badge variant="muted" className="!text-[10px] !px-1 !py-0">
          {agentId}
        </Badge>
        {session.status && (
          <span
            className={
              variant === "active"
                ? "text-emerald-400"
                : variant === "error"
                  ? "text-red-400"
                  : "text-zinc-500"
            }
          >
            {session.status}
          </span>
        )}
        {session.model && (
          <span className="truncate text-zinc-600">{session.model}</span>
        )}
      </div>
      {session.lastMessagePreview && (
        <p className="text-xs text-zinc-600 mt-1 truncate pl-4">
          {session.lastMessagePreview}
        </p>
      )}
    </button>
  );
}

// ---------------------------------------------------------------------------
// Tree types & renderer
// ---------------------------------------------------------------------------

interface TreeNode {
  session: Session;
  children: TreeNode[];
}

function TreeNodeRow({
  node,
  depth,
  selectedKey,
  onClick,
}: {
  node: TreeNode;
  depth: number;
  selectedKey: string | null;
  onClick: (key: string) => void;
}) {
  const { session } = node;
  const agentId = agentFromKey(session.key);
  const variant = sessionStatus(session);
  const isActive = session.key === selectedKey;

  return (
    <>
      <button
        onClick={() => onClick(session.key)}
        className={`w-full text-left px-3 py-2 border-b border-zinc-800/60 transition-colors ${
          isActive
            ? "bg-zinc-800/80 border-l-2 border-l-indigo-500"
            : "hover:bg-zinc-800/30 border-l-2 border-l-transparent"
        }`}
        style={{ paddingLeft: `${12 + depth * 16}px` }}
      >
        <div className="flex items-center gap-1.5">
          {depth > 0 && (
            <span className="text-zinc-700 text-xs mr-0.5">{">"}</span>
          )}
          <StatusDot status={variant} size="xs" />
          <Badge variant="muted" className="!text-[10px] !px-1 !py-0">
            {agentId}
          </Badge>
          <span className="text-sm text-zinc-200 truncate">
            {session.displayName || session.key.slice(0, 18)}
          </span>
        </div>
        {session.lastMessagePreview && (
          <p className="text-xs text-zinc-600 mt-0.5 truncate" style={{ paddingLeft: depth > 0 ? "16px" : "0" }}>
            {session.lastMessagePreview}
          </p>
        )}
      </button>
      {node.children.map((child) => (
        <TreeNodeRow
          key={child.session.key}
          node={child}
          depth={depth + 1}
          selectedKey={selectedKey}
          onClick={onClick}
        />
      ))}
    </>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function SessionsPage() {
  const { data: agentData } = useAgents();
  const [searchParams, setSearchParams] = useSearchParams();
  const [agentFilter, setAgentFilter] = useState<string>(searchParams.get("agent") ?? "");
  const [search, setSearch] = useState("");
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [confirmAction, setConfirmAction] = useState<"reset" | "delete" | null>(null);
  const [viewMode, setViewMode] = useState<"list" | "tree">("list");
  const scrollRef = useRef<HTMLDivElement>(null);
  const client = useGatewayStore((s) => s.client);
  const navigate = useNavigate();

  const {
    data: sessionData,
    isLoading,
    refetch,
  } = useSessions(
    agentFilter
      ? { agentId: agentFilter, includeLastMessage: true }
      : { includeLastMessage: true },
  );

  const sessions = sessionData?.sessions ?? [];
  const agents = agentData?.agents ?? [];

  // Filter by search (memoized to avoid recomputation on message updates)
  const filtered = useMemo(
    () =>
      sessions.filter((s) => {
        if (!search) return true;
        const q = search.toLowerCase();
        const agentId = agentFromKey(s.key);
        return (
          s.key.toLowerCase().includes(q) ||
          (s.displayName ?? "").toLowerCase().includes(q) ||
          agentId.toLowerCase().includes(q)
        );
      }),
    [sessions, search],
  );

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
      .call<ChatHistoryResult>("chat.history", { sessionKey: selectedKey })
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
        if (action === "reset") {
          setMessages([]);
        }
        setConfirmAction(null);
        refetch();
      } catch (err: any) {
        console.error(`sessions.${action} failed:`, err);
      }
    },
    [client, selectedKey, refetch],
  );

  // Open session in Chat page
  const handleOpenInChat = useCallback(() => {
    if (!selectedKey) return;
    navigate(`/chat?session=${encodeURIComponent(selectedKey)}`);
  }, [selectedKey, navigate]);

  // Navigate to a session key (from clickable session links in messages)
  const handleSessionClick = useCallback(
    (key: string) => {
      // If the session exists in our list, select it
      const exists = sessions.some((s) => s.key === key);
      if (exists) {
        setSelectedKey(key);
      } else {
        // Clear agent filter and select anyway
        setAgentFilter("");
        setSearch("");
        setSelectedKey(key);
      }
    },
    [sessions],
  );

  // Build spawn tree from sessions
  const spawnTree = useMemo(() => {
    if (viewMode !== "tree") return [];
    const byKey = new Map(filtered.map((s) => [s.key, s]));
    const childMap = new Map<string, Session[]>();
    const roots: Session[] = [];

    for (const s of filtered) {
      let isChild = false;
      // Check parentSessionKey or spawnedBy
      const parentKey = s.parentSessionKey || s.spawnedBy;
      if (parentKey && byKey.has(parentKey)) {
        isChild = true;
        const children = childMap.get(parentKey) ?? [];
        children.push(s);
        childMap.set(parentKey, children);
      }
      if (!isChild) {
        // Also check if any other session lists this as a child
        const parent = filtered.find(
          (p) => p.childSessions?.includes(s.key),
        );
        if (parent) {
          isChild = true;
          const children = childMap.get(parent.key) ?? [];
          children.push(s);
          childMap.set(parent.key, children);
        }
      }
      if (!isChild) roots.push(s);
    }

    function buildChildren(parentKey: string, depth: number): TreeNode[] {
      const children = childMap.get(parentKey) ?? [];
      return children.map((c) => ({
        session: c,
        children: depth < 5 ? buildChildren(c.key, depth + 1) : [],
      }));
    }

    return roots.map((root) => ({
      session: root,
      children: buildChildren(root.key, 0),
    }));
  }, [filtered, viewMode]);

  return (
    <div className="flex h-screen">
      {/* Left panel: session list */}
      <div className="w-[340px] shrink-0 border-r border-zinc-800 bg-zinc-900 flex flex-col">
        <div className="p-3 border-b border-zinc-800 space-y-2">
          <h2 className="text-base font-bold text-zinc-100 tracking-tight">
            Sessions
          </h2>
          {/* Agent filter */}
          <select
            value={agentFilter}
            onChange={(e) => setAgentFilter(e.target.value)}
            className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            <option value="">All agents</option>
            {agents.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name ?? a.id}
              </option>
            ))}
          </select>
          {/* Search */}
          <div className="relative">
            <svg
              className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-zinc-500"
              viewBox="0 0 20 20"
              fill="currentColor"
            >
              <path
                fillRule="evenodd"
                d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z"
                clipRule="evenodd"
              />
            </svg>
            <input
              type="text"
              placeholder="Search sessions..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg pl-8 pr-2.5 py-1.5 text-sm text-zinc-200 placeholder:text-zinc-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
          </div>
          {/* Count + view toggle */}
          <div className="flex items-center justify-between">
            {sessionData && (
              <div className="text-xs text-zinc-500 tabular-nums">
                {sessionData.count} session{sessionData.count !== 1 ? "s" : ""}
                {search && ` (${filtered.length} shown)`}
              </div>
            )}
            <div className="flex gap-1">
              <button
                onClick={() => setViewMode("list")}
                className={`px-1.5 py-0.5 rounded text-[10px] font-medium transition-colors ${
                  viewMode === "list"
                    ? "bg-zinc-700 text-zinc-200"
                    : "text-zinc-500 hover:text-zinc-300"
                }`}
                title="List view"
              >
                List
              </button>
              <button
                onClick={() => setViewMode("tree")}
                className={`px-1.5 py-0.5 rounded text-[10px] font-medium transition-colors ${
                  viewMode === "tree"
                    ? "bg-zinc-700 text-zinc-200"
                    : "text-zinc-500 hover:text-zinc-300"
                }`}
                title="Spawn tree view"
              >
                Tree
              </button>
            </div>
          </div>
        </div>

        <div className="flex-1 overflow-y-auto">
          {isLoading ? (
            <Spinner text="Loading sessions..." />
          ) : filtered.length === 0 ? (
            <EmptyState
              icon={search ? undefined : undefined}
              message={
                search
                  ? `No sessions matching "${search}"`
                  : "No sessions found"
              }
            />
          ) : viewMode === "tree" ? (
            spawnTree.map((node) => (
              <TreeNodeRow
                key={node.session.key}
                node={node}
                depth={0}
                selectedKey={selectedKey}
                onClick={setSelectedKey}
              />
            ))
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
      <div className="flex-1 flex flex-col bg-zinc-950 overflow-hidden">
        {!selectedKey ? (
          <EmptyState
            icon="<>"
            message="Select a session to view its conversation"
          />
        ) : (
          <>
            {/* Header */}
            <div className="px-4 py-3 border-b border-zinc-800 bg-zinc-900 flex items-center justify-between gap-3 shrink-0">
              <div className="min-w-0 overflow-hidden">
                <div className="flex items-center gap-2">
                  <StatusDot
                    status={selectedSession ? sessionStatus(selectedSession) : "idle"}
                    size="sm"
                  />
                  <span className="text-sm font-semibold text-zinc-100 truncate">
                    {selectedSession?.displayName ||
                      selectedKey.slice(0, 28)}
                  </span>
                </div>
                <div className="text-xs text-zinc-500 mt-0.5 flex items-center gap-2">
                  <Badge
                    variant="muted"
                    className="!text-[10px] !px-1.5 !py-0"
                  >
                    {agentFromKey(selectedSession?.key ?? selectedKey)}
                  </Badge>
                  <span className="tabular-nums">
                    {messages.length} messages
                  </span>
                  {selectedSession?.model && (
                    <span className="text-zinc-600">
                      {selectedSession.model}
                    </span>
                  )}
                  {selectedSession?.totalTokens != null && (
                    <span className="text-zinc-600 tabular-nums">
                      {selectedSession.totalTokens.toLocaleString()} tokens
                    </span>
                  )}
                </div>
              </div>
              <div className="flex gap-2 shrink-0">
                <button
                  onClick={handleOpenInChat}
                  className="px-2.5 py-1 text-xs bg-indigo-600/20 text-indigo-400 rounded-lg hover:bg-indigo-600/30 transition-colors font-medium"
                >
                  Open in Chat
                </button>
                <button
                  onClick={() => handleAction("abort")}
                  className="px-2.5 py-1 text-xs bg-amber-600/20 text-amber-400 rounded-lg hover:bg-amber-600/30 transition-colors font-medium"
                >
                  Abort
                </button>
                <button
                  onClick={() => setConfirmAction("reset")}
                  className="px-2.5 py-1 text-xs bg-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-600 transition-colors"
                  title="Permanently clears all message history for this session"
                >
                  Clear History
                </button>
              </div>
            </div>

            {/* Messages */}
            <div
              ref={scrollRef}
              className="flex-1 overflow-y-auto p-4 space-y-3 min-h-0"
            >
              {historyLoading ? (
                <Spinner text="Loading conversation..." />
              ) : historyError ? (
                <div className="text-center text-red-400 text-sm py-8">
                  {historyError}
                </div>
              ) : messages.length === 0 ? (
                <EmptyState message="No messages in this session yet" />
              ) : (
                messages.map((msg, i) => (
                  <MessageRenderer
                    key={`${msg.ts ?? (msg as any).timestamp ?? i}-${i}`}
                    msg={msg}
                    sessionKey={selectedKey}
                    onSessionClick={handleSessionClick}
                    allMessages={messages}
                    messageIndex={i}
                  />
                ))
              )}
            </div>
          </>
        )}
      </div>

      {/* Confirmation dialog */}
      {confirmAction && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
          <div className="bg-zinc-900 border border-zinc-700 rounded-xl p-6 max-w-sm mx-4 shadow-2xl">
            <h3 className="text-base font-semibold text-zinc-100 mb-2">
              {confirmAction === "delete" ? "Delete Session" : "Clear History"}
            </h3>
            <p className="text-sm text-zinc-400 mb-4">
              {confirmAction === "delete"
                ? "This will permanently delete the session and all its message history. This cannot be undone."
                : "This will permanently clear all message history for this session. The session itself will remain. This cannot be undone."}
            </p>
            <div className="flex justify-end gap-2">
              <button
                onClick={() => setConfirmAction(null)}
                className="px-3 py-1.5 text-sm bg-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-600 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={() => handleAction(confirmAction)}
                className={`px-3 py-1.5 text-sm rounded-lg font-medium transition-colors ${
                  confirmAction === "delete"
                    ? "bg-red-600 text-white hover:bg-red-500"
                    : "bg-amber-600 text-white hover:bg-amber-500"
                }`}
              >
                {confirmAction === "delete" ? "Delete" : "Clear History"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
