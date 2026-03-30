import { useState, useRef, useEffect, useCallback, useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import ReactMarkdown from "react-markdown";
import {
  useAgents,
  useModels,
  useSessions,
  useGatewayStore,
} from "@/api/hooks";
import type { ChatMessage, ChatHistoryResult, Session } from "@/api/types";
import { agentFromKey } from "@/api/types";
import { MessageRenderer } from "@/components/MessageRenderer";
import { Spinner, EmptyState, Badge, StatusDot } from "@/components/shared";

/** crypto.randomUUID fallback for non-secure (HTTP) contexts */
function uuid(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  // Fallback: manual v4 UUID
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}

// ---------------------------------------------------------------------------
// Session picker dropdown
// ---------------------------------------------------------------------------

function SessionPicker({
  sessions,
  currentKey,
  onSelect,
}: {
  sessions: Session[];
  currentKey: string | null;
  onSelect: (key: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  if (sessions.length === 0) return null;

  // Show at most 20 recent sessions
  const recent = sessions.slice(0, 20);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((v) => !v)}
        className="px-3 py-1.5 text-sm bg-zinc-800 border border-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-700 transition-colors font-medium flex items-center gap-1.5"
      >
        <svg className="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
          <path d="M2 4a1 1 0 011-1h2a1 1 0 011 1v12a1 1 0 01-1 1H3a1 1 0 01-1-1V4zM8 4a1 1 0 011-1h2a1 1 0 011 1v12a1 1 0 01-1 1H9a1 1 0 01-1-1V4zM15 3a1 1 0 00-1 1v12a1 1 0 001 1h2a1 1 0 001-1V4a1 1 0 00-1-1h-2z" />
        </svg>
        Continue Session
      </button>
      {open && (
        <div className="absolute top-full mt-1 left-0 z-50 w-[360px] max-h-[400px] overflow-y-auto bg-zinc-900 border border-zinc-700 rounded-lg shadow-2xl">
          {recent.map((s) => {
            const agentId = agentFromKey(s.key);
            const isActive = s.key === currentKey;
            return (
              <button
                key={s.key}
                onClick={() => { onSelect(s.key); setOpen(false); }}
                className={`w-full text-left px-3 py-2 border-b border-zinc-800/60 transition-colors ${
                  isActive ? "bg-zinc-800" : "hover:bg-zinc-800/50"
                }`}
              >
                <div className="flex items-center gap-2">
                  <Badge variant="muted" className="!text-[10px] !px-1 !py-0">
                    {agentId}
                  </Badge>
                  <span className="text-sm text-zinc-200 truncate">
                    {s.displayName || s.key.slice(0, 24)}
                  </span>
                </div>
                {s.lastMessagePreview && (
                  <p className="text-xs text-zinc-500 mt-0.5 truncate pl-0.5">
                    {s.lastMessagePreview}
                  </p>
                )}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function ChatPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const { data: agentData } = useAgents();
  const { data: modelData } = useModels();
  const { data: sessionData } = useSessions({ includeLastMessage: true });
  const client = useGatewayStore((s) => s.client);
  const connected = useGatewayStore((s) => s.connectionState === "connected");

  const [agentId, setAgentId] = useState("");
  const [modelId, setModelId] = useState("");
  const [sessionKey, setSessionKey] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const [streaming, setStreaming] = useState(false);
  const [streamBuf, setStreamBuf] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [historyLoading, setHistoryLoading] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  const agents = agentData?.agents ?? [];
  const defaultAgentId = agentData?.defaultId ?? "";
  const models = modelData?.models ?? [];
  const sessions = sessionData?.sessions ?? [];

  // Set defaults
  useEffect(() => {
    if (!agentId && agents.length > 0) {
      const defaultAgent = defaultAgentId
        ? agents.find((a) => a.id === defaultAgentId)
        : undefined;
      const def = defaultAgent ?? agents[0];
      setAgentId(def.id);
    }
  }, [agents, agentId, defaultAgentId]);

  useEffect(() => {
    if (!modelId && models.length > 0) {
      setModelId(models[0].id);
    }
  }, [models, modelId]);

  // Handle ?session= URL param (on mount or param change)
  useEffect(() => {
    const paramKey = searchParams.get("session");
    if (paramKey && client && connected && paramKey !== sessionKey) {
      openExistingSession(paramKey);
      // Clear the URL param so it doesn't re-trigger
      setSearchParams({}, { replace: true });
    }
  }, [searchParams, client, connected]); // eslint-disable-line react-hooks/exhaustive-deps

  // Open an existing session by key
  const openExistingSession = useCallback(
    async (key: string) => {
      if (!client || !connected) return;
      setSessionKey(key);
      setMessages([]);
      setStreamBuf("");
      setError(null);
      setHistoryLoading(true);

      // Update agent selector to match the session
      const sessAgent = agentFromKey(key);
      if (sessAgent && agents.some((a) => a.id === sessAgent)) {
        setAgentId(sessAgent);
      }

      try {
        const res = await client.call<ChatHistoryResult>("chat.history", {
          sessionKey: key,
        });
        setMessages(res?.messages ?? []);
      } catch (err: any) {
        setError(err?.message ?? "Failed to load session history");
      } finally {
        setHistoryLoading(false);
        // Focus input after loading
        setTimeout(() => inputRef.current?.focus(), 100);
      }
    },
    [client, connected, agents],
  );

  // Subscribe to streaming — event is "chat" with state: "delta"|"final"|"error"
  useEffect(() => {
    if (!client || !sessionKey) return;
    const off = client.on("chat", (params: any) => {
      if (params?.sessionKey !== sessionKey) return;
      if (params?.state === "delta" && params?.message) {
        // Streaming delta — extract text from content array
        const text = Array.isArray(params.message.content)
          ? params.message.content.map((b: any) => b.text ?? "").join("")
          : params.message.content ?? "";
        setStreaming(true);
        setStreamBuf(text); // full accumulated text, not delta
      } else if (params?.state === "final") {
        setStreaming(false);
        setSending(false);
        setStreamBuf("");
        if (params?.message) {
          setMessages((prev) => [...prev, params.message]);
        }
      } else if (params?.state === "error") {
        setStreaming(false);
        setSending(false);
        setStreamBuf("");
        setError(params?.errorMessage ?? "Agent run failed");
      }
    });
    return off;
  }, [client, sessionKey]);

  // Auto-scroll
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, streamBuf]);

  // New session
  const handleNewSession = useCallback(async () => {
    if (!client) return;
    setError(null);
    try {
      const res = await client.call<{ key?: string; sessionKey?: string }>(
        "sessions.create",
        {
          agentId: agentId || undefined,
          model: modelId || undefined,
        },
      );
      const newKey = res.key ?? res.sessionKey ?? null;
      setSessionKey(newKey);
      setMessages([]);
      setStreamBuf("");
      setTimeout(() => inputRef.current?.focus(), 100);
    } catch (err: any) {
      setError(err?.message ?? "Failed to create session");
    }
  }, [client, agentId, modelId]);

  // Slash command definitions (matching official OpenClaw UI)
  const SLASH_COMMANDS = useMemo(() => [
    { name: "new", description: "新建 session", category: "session" },
    { name: "clear", description: "清空聊天历史", category: "session" },
    { name: "reset", description: "重置当前 session", category: "session" },
    { name: "compact", description: "压缩 session 上下文", category: "session" },
    { name: "stop", description: "停止当前运行", category: "session" },
    { name: "model", description: "显示/设置模型", category: "model" },
    { name: "think", description: "设置思考级别", category: "model" },
    { name: "fast", description: "切换快速模式", category: "model" },
    { name: "help", description: "显示可用命令", category: "tools" },
    { name: "status", description: "显示 session 状态", category: "tools" },
    { name: "usage", description: "显示 token 用量", category: "tools" },
    { name: "agents", description: "列出所有 agent", category: "agents" },
    { name: "skill", description: "运行 skill", category: "tools" },
  ], []);

  // Slash menu state
  const [slashMenuOpen, setSlashMenuOpen] = useState(false);
  const [slashMenuItems, setSlashMenuItems] = useState<typeof SLASH_COMMANDS>([]);
  const [slashMenuIndex, setSlashMenuIndex] = useState(0);

  // Update slash menu when input changes
  const updateSlashMenu = useCallback((text: string) => {
    const match = text.match(/^\/(\S*)$/);
    if (match) {
      const query = match[1].toLowerCase();
      const items = query
        ? SLASH_COMMANDS.filter(c => c.name.startsWith(query) || c.description.includes(query))
        : SLASH_COMMANDS;
      setSlashMenuItems(items);
      setSlashMenuOpen(items.length > 0);
      setSlashMenuIndex(0);
    } else {
      setSlashMenuOpen(false);
    }
  }, [SLASH_COMMANDS]);

  const selectSlashCommand = useCallback((cmd: typeof SLASH_COMMANDS[0]) => {
    setSlashMenuOpen(false);
    setInput(`/${cmd.name}`);
    // Auto-send commands that don't need args
    if (!["model", "think", "fast", "skill", "steer"].includes(cmd.name)) {
      // Defer send so input state updates first
      setTimeout(() => {
        const fakeInput = `/${cmd.name}`;
        if (!client || !sessionKey) return;
        setSending(true);
        setError(null);
        client.call("chat.send", {
          sessionKey,
          idempotencyKey: uuid(),
          message: fakeInput,
        }).then((res: any) => {
          if (res?.message) setMessages(prev => [...prev, res.message]);
          // After /clear or /reset, clear local messages too
          if (cmd.name === "clear" || cmd.name === "reset" || cmd.name === "new") setMessages([]);
        }).catch((err: any) => setError(err?.message ?? "Command failed"))
          .finally(() => setSending(false));
        setInput("");
      }, 0);
    }
  }, [client, sessionKey]);

  // Send message — slash commands are sent to gateway like any other message
  const handleSend = useCallback(async () => {
    if (!client || !sessionKey || !input.trim() || sending) return;
    setSlashMenuOpen(false);

    const userMsg: ChatMessage = {
      role: "user",
      content: input.trim(),
      ts: Date.now(),
    };
    setMessages((prev) => [...prev, userMsg]);
    setInput("");
    setSending(true);
    setError(null);

    try {
      await client.call("chat.send", {
        sessionKey: sessionKey,
        idempotencyKey: uuid(),
        message: userMsg.content as string,
      });
      // Response comes via streaming events ("chat" event with state: delta/final)
      // Don't add message here — the streaming listener handles it
      // Keep sending=true until streaming "final" event arrives
    } catch (err: any) {
      setError(err?.message ?? "Send failed");
      setSending(false);
    }
  }, [client, sessionKey, input, sending]);

  // Key handler with slash menu navigation
  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (slashMenuOpen) {
      if (e.key === "ArrowDown") { e.preventDefault(); setSlashMenuIndex(i => Math.min(i + 1, slashMenuItems.length - 1)); return; }
      if (e.key === "ArrowUp") { e.preventDefault(); setSlashMenuIndex(i => Math.max(i - 1, 0)); return; }
      if (e.key === "Enter" || e.key === "Tab") { e.preventDefault(); if (slashMenuItems[slashMenuIndex]) selectSlashCommand(slashMenuItems[slashMenuIndex]); return; }
      if (e.key === "Escape") { e.preventDefault(); setSlashMenuOpen(false); return; }
    }
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  return (
    <div className="flex flex-col h-screen">
      {/* Header */}
      <div className="px-4 py-3 border-b border-zinc-800 bg-zinc-900">
        <div className="flex items-center gap-3 flex-wrap">
          <h1 className="text-base font-bold text-zinc-100 tracking-tight mr-1">
            Chat
          </h1>
          {/* Agent selector */}
          <select
            value={agentId}
            onChange={(e) => setAgentId(e.target.value)}
            className="bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            {agents.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name ?? a.id}
                {a.id === defaultAgentId ? " (default)" : ""}
              </option>
            ))}
          </select>
          {/* Model selector */}
          <select
            value={modelId}
            onChange={(e) => setModelId(e.target.value)}
            className="bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            {models.map((m) => (
              <option key={m.id} value={m.id}>
                {m.name} ({m.provider})
              </option>
            ))}
          </select>
          {/* New session */}
          <button
            onClick={handleNewSession}
            className="px-3 py-1.5 text-sm bg-indigo-600 text-zinc-100 rounded-lg hover:bg-indigo-500 transition-colors font-medium"
          >
            New Session
          </button>
          {/* Continue existing session */}
          <SessionPicker
            sessions={sessions}
            currentKey={sessionKey}
            onSelect={openExistingSession}
          />
          {sessionKey && (
            <span className="text-xs text-zinc-600 font-mono tabular-nums">
              {sessionKey.slice(0, 24)}...
            </span>
          )}
        </div>
      </div>

      {/* Messages area */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3">
        {!sessionKey ? (
          <div className="flex items-center justify-center h-full">
            <EmptyState
              icon="<>"
              message="Start a new conversation or continue an existing session"
            />
          </div>
        ) : historyLoading ? (
          <div className="flex items-center justify-center h-full">
            <Spinner text="Loading conversation..." />
          </div>
        ) : messages.length === 0 && !streaming ? (
          <div className="flex items-center justify-center h-full">
            <EmptyState message="Session started. Send a message below." />
          </div>
        ) : (
          <>
            {messages.map((msg, i) => (
              <MessageRenderer
                key={`${msg.ts ?? (msg as any).timestamp ?? i}-${i}`}
                msg={msg}
                sessionKey={sessionKey}
                allMessages={messages}
                messageIndex={i}
              />
            ))}
            {/* Streaming buffer */}
            {streaming && streamBuf && (
              <div className="flex justify-start">
                <div className="max-w-[75%] rounded-lg px-4 py-2.5 text-sm bg-zinc-800/80 text-zinc-200 border border-zinc-700/50">
                  <div className="prose prose-sm prose-invert max-w-none [&_p]:my-1">
                    <ReactMarkdown>{streamBuf}</ReactMarkdown>
                  </div>
                  <span className="inline-block w-1.5 h-4 bg-zinc-400 animate-pulse ml-0.5 rounded-sm" />
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* Error display */}
      {error && (
        <div className="mx-4 mb-2 text-xs text-red-400 bg-red-950/30 border border-red-900/50 rounded-lg px-3 py-2 flex items-center gap-2">
          <svg
            className="h-3.5 w-3.5 shrink-0"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fillRule="evenodd"
              d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z"
              clipRule="evenodd"
            />
          </svg>
          {error}
        </div>
      )}

      {/* Input area */}
      <div className="border-t border-zinc-800 bg-zinc-900 p-4">
        <div className="relative">
          {/* Slash command menu */}
          {slashMenuOpen && (
            <div className="absolute bottom-full left-0 right-0 mb-1 bg-zinc-800 border border-zinc-700 rounded-lg shadow-xl max-h-64 overflow-y-auto z-30">
              {slashMenuItems.map((cmd, i) => (
                <button
                  key={cmd.name}
                  onClick={() => selectSlashCommand(cmd)}
                  className={`w-full text-left px-3 py-1.5 flex items-center gap-2 text-sm transition-colors ${
                    i === slashMenuIndex ? "bg-indigo-600/20 text-indigo-300" : "text-zinc-300 hover:bg-zinc-700/50"
                  }`}
                >
                  <span className="text-indigo-400 font-mono text-xs w-16 shrink-0">/{cmd.name}</span>
                  <span className="text-zinc-500 text-xs truncate">{cmd.description}</span>
                  <span className="text-zinc-700 text-[10px] ml-auto shrink-0">{cmd.category}</span>
                </button>
              ))}
            </div>
          )}
          <div className="flex gap-2">
            <textarea
              ref={inputRef}
              value={input}
              onChange={(e) => {
                setInput(e.target.value);
                updateSlashMenu(e.target.value);
                // Auto-resize
                e.target.style.height = "auto";
                e.target.style.height = Math.min(e.target.scrollHeight, 200) + "px";
              }}
              onKeyDown={handleKeyDown}
              disabled={!sessionKey || sending}
              placeholder={
                !sessionKey
                  ? "Create or select a session first..."
                  : sending
                    ? "Waiting for response..."
                    : 'Type a message or / for commands... (Shift+Enter for newline)'
              }
              rows={1}
              className="flex-1 bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder:text-zinc-500 resize-none focus:outline-none focus:ring-1 focus:ring-indigo-500 disabled:opacity-50 min-h-[38px] max-h-[200px]"
            />
          <button
            onClick={handleSend}
            disabled={!sessionKey || sending || !input.trim()}
            className="self-end px-4 py-2 bg-indigo-600 text-zinc-100 rounded-lg text-sm font-medium hover:bg-indigo-500 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {sending ? (
              <span className="inline-block w-4 h-4 border-2 border-zinc-300 border-t-transparent rounded-full animate-spin" />
            ) : (
              "Send"
            )}
          </button>
          </div>
        </div>
      </div>
    </div>
  );
}
