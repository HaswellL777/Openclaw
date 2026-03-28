import { useState, useRef, useEffect, useCallback } from "react";
import ReactMarkdown from "react-markdown";
import {
  useAgents,
  useModels,
  useGatewayStore,
} from "@/api/hooks";
import type { ChatMessage } from "@/api/types";

// ---------------------------------------------------------------------------
// Message display
// ---------------------------------------------------------------------------

function ChatBubble({ msg }: { msg: ChatMessage }) {
  const isUser = msg.role === "user";
  const text =
    typeof msg.content === "string"
      ? msg.content
      : JSON.stringify(msg.content, null, 2);

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[75%] rounded-lg px-4 py-2.5 text-sm ${
          isUser
            ? "bg-indigo-600 text-zinc-100"
            : "bg-zinc-800 text-zinc-200"
        }`}
      >
        {msg.role === "tool" ? (
          <pre className="text-xs font-mono text-amber-300 whitespace-pre-wrap break-all">
            {text}
          </pre>
        ) : isUser ? (
          <span className="whitespace-pre-wrap">{text}</span>
        ) : (
          <div className="prose prose-sm prose-invert max-w-none [&_pre]:bg-zinc-900 [&_pre]:p-2 [&_pre]:rounded [&_code]:text-amber-300">
            <ReactMarkdown>{text}</ReactMarkdown>
          </div>
        )}
        {msg.tokens != null && (
          <div className="text-[10px] text-zinc-500 mt-1 text-right">
            {msg.tokens} tokens
          </div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function ChatPage() {
  const { data: agentData } = useAgents();
  const { data: modelData } = useModels();
  const client = useGatewayStore((s) => s.client);

  const [agentId, setAgentId] = useState("");
  const [modelId, setModelId] = useState("");
  const [sessionKey, setSessionKey] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const [streaming, setStreaming] = useState(false);
  const [streamBuf, setStreamBuf] = useState("");
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  const agents = agentData?.agents ?? [];
  const defaultAgentId = agentData?.defaultId ?? "";
  const models = modelData?.models ?? [];

  // Set defaults
  useEffect(() => {
    if (!agentId && agents.length > 0) {
      // Use defaultId from the API response
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

  // Subscribe to streaming
  useEffect(() => {
    if (!client || !sessionKey) return;
    const offMsg = client.on("chat.message", (params: any) => {
      if (params?.key !== sessionKey && params?.sessionKey !== sessionKey) return;
      if (params?.message) {
        setMessages((prev) => [...prev, params.message]);
        setStreaming(false);
        setStreamBuf("");
      }
    });
    const offChunk = client.on("chat.chunk", (params: any) => {
      if (params?.key !== sessionKey && params?.sessionKey !== sessionKey) return;
      setStreaming(true);
      setStreamBuf((prev) => prev + (params?.text ?? ""));
    });
    return () => {
      offMsg();
      offChunk();
    };
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
      // Response may use 'key' or 'sessionKey'
      const res = await client.call<{ key?: string; sessionKey?: string }>(
        "sessions.create",
        {
          agent: agentId || undefined,
          model: modelId || undefined,
        },
      );
      const newKey = res.key ?? res.sessionKey ?? null;
      setSessionKey(newKey);
      setMessages([]);
      setStreamBuf("");
    } catch (err: any) {
      setError(err?.message ?? "Failed to create session");
    }
  }, [client, agentId, modelId]);

  // Send message
  const handleSend = useCallback(async () => {
    if (!client || !sessionKey || !input.trim() || sending) return;

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
      const res = await client.call<{ message?: ChatMessage }>("chat.send", {
        key: sessionKey,
        text: userMsg.content,
      });
      // If the response includes a direct message (non-streaming), add it
      if (res?.message) {
        setMessages((prev) => [...prev, res.message!]);
      }
    } catch (err: any) {
      setError(err?.message ?? "Send failed");
    } finally {
      setSending(false);
    }
  }, [client, sessionKey, input, sending]);

  // Key handler
  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
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
          <h1 className="text-lg font-semibold text-zinc-100 mr-2">Chat</h1>
          {/* Agent selector */}
          <select
            value={agentId}
            onChange={(e) => setAgentId(e.target.value)}
            className="bg-zinc-800 border border-zinc-700 rounded px-2 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
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
            className="bg-zinc-800 border border-zinc-700 rounded px-2 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
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
            className="px-3 py-1.5 text-sm bg-indigo-600 text-zinc-100 rounded hover:bg-indigo-500 transition-colors font-medium"
          >
            New Session
          </button>
          {sessionKey && (
            <span className="text-xs text-zinc-500 font-mono">
              {sessionKey.slice(0, 24)}...
            </span>
          )}
        </div>
      </div>

      {/* Messages area */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3">
        {!sessionKey ? (
          <div className="flex items-center justify-center h-full text-zinc-500 text-sm">
            <div className="text-center space-y-2">
              <p className="text-lg">Start a conversation</p>
              <p className="text-xs">
                Select an agent and model, then click "New Session"
              </p>
            </div>
          </div>
        ) : messages.length === 0 && !streaming ? (
          <div className="flex items-center justify-center h-full text-zinc-500 text-sm">
            Session started. Send a message below.
          </div>
        ) : (
          <>
            {messages.map((msg, i) => (
              <ChatBubble key={`${msg.ts ?? i}-${i}`} msg={msg} />
            ))}
            {/* Streaming buffer */}
            {streaming && streamBuf && (
              <div className="flex justify-start">
                <div className="max-w-[75%] rounded-lg px-4 py-2.5 text-sm bg-zinc-800 text-zinc-200 border border-zinc-700">
                  <div className="prose prose-sm prose-invert max-w-none">
                    <ReactMarkdown>{streamBuf}</ReactMarkdown>
                  </div>
                  <span className="inline-block w-2 h-4 bg-zinc-400 animate-pulse ml-0.5" />
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* Error display */}
      {error && (
        <div className="mx-4 mb-2 text-xs text-red-400 bg-red-900/20 border border-red-800 rounded px-3 py-2">
          {error}
        </div>
      )}

      {/* Input area */}
      <div className="border-t border-zinc-800 bg-zinc-900 p-4">
        <div className="flex gap-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            disabled={!sessionKey || sending}
            placeholder={
              !sessionKey
                ? "Create a session first..."
                : sending
                  ? "Waiting for response..."
                  : "Type a message... (Shift+Enter for newline)"
            }
            rows={2}
            className="flex-1 bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder:text-zinc-500 resize-none focus:outline-none focus:ring-1 focus:ring-indigo-500 disabled:opacity-50"
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
  );
}
