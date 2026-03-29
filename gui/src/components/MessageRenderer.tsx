import { useState, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import ReactMarkdown from "react-markdown";
import type { ChatMessage } from "@/api/types";
import { agentFromKey } from "@/api/types";
import { Badge } from "@/components/shared";

// ---------------------------------------------------------------------------
// Agent color mapping — deterministic color per agent ID
// ---------------------------------------------------------------------------

const AGENT_COLORS: Record<string, "indigo" | "amber" | "emerald" | "blue" | "purple" | "cyan" | "red"> = {
  main: "indigo",
  "task-runner": "emerald",
  "research-coordinator": "blue",
  auditor: "purple",
  claude: "cyan",
};

function agentColor(agentId: string) {
  return AGENT_COLORS[agentId] ?? "amber";
}

// ---------------------------------------------------------------------------
// ClickableAgentBadge — navigates to sessions filtered by agent
// ---------------------------------------------------------------------------

function ClickableAgentBadge({ agentId }: { agentId: string }) {
  const navigate = useNavigate();
  return (
    <button
      onClick={() => navigate(`/sessions?agent=${encodeURIComponent(agentId)}`)}
      className="cursor-pointer hover:opacity-80 transition-opacity"
      title={`View ${agentId} sessions`}
    >
      <Badge variant={agentColor(agentId) as any}>{agentId}</Badge>
    </button>
  );
}

// ---------------------------------------------------------------------------
// CodeBlock — language label + copy button + dark bg
// ---------------------------------------------------------------------------

function CodeBlock({
  language,
  children,
}: {
  language?: string;
  children: string;
}) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(() => {
    navigator.clipboard.writeText(children).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }, [children]);

  return (
    <div className="relative group rounded-lg bg-zinc-950 border border-zinc-800 my-2 overflow-hidden">
      {/* Header bar */}
      <div className="flex items-center justify-between px-3 py-1.5 bg-zinc-900/50 border-b border-zinc-800">
        <span className="text-[10px] font-mono text-zinc-500 uppercase tracking-wide">
          {language || "code"}
        </span>
        <button
          onClick={handleCopy}
          className="text-[10px] text-zinc-500 hover:text-zinc-300 transition-colors px-1.5 py-0.5 rounded hover:bg-zinc-800"
        >
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
      {/* Code content */}
      <pre className="px-3 py-2.5 overflow-x-auto text-xs leading-relaxed">
        <code className="font-mono text-zinc-300">{children}</code>
      </pre>
    </div>
  );
}

// ---------------------------------------------------------------------------
// ToolCallCard — expand/collapse tool_use block
// ---------------------------------------------------------------------------

interface ToolUseBlock {
  type: "tool_use";
  id?: string;
  name?: string;
  input?: any;
}

interface ToolResultBlock {
  type: "tool_result";
  tool_use_id?: string;
  content?: any;
  is_error?: boolean;
}

function ToolCallCard({
  toolUse,
  toolResult,
  onSessionClick,
}: {
  toolUse: ToolUseBlock;
  toolResult?: ToolResultBlock;
  onSessionClick?: (key: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const toolName = toolUse.name ?? "unknown_tool";
  const isSpawn = toolName === "sessions_spawn" || toolName === "sessions.spawn";
  const isSend = toolName === "sessions_send" || toolName === "sessions.send";

  // Extract target agent info from spawn/send
  const targetAgent = toolUse.input?.agent ?? toolUse.input?.agentId;
  const targetKey = toolUse.input?.key ?? toolUse.input?.sessionKey;

  const resultText = toolResult?.content
    ? typeof toolResult.content === "string"
      ? toolResult.content
      : JSON.stringify(toolResult.content, null, 2)
    : null;

  const isError = toolResult?.is_error === true;

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900/60 my-1.5 overflow-hidden">
      {/* Header — always visible */}
      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full text-left px-3 py-2 flex items-center gap-2 hover:bg-zinc-800/40 transition-colors"
      >
        <svg
          className={`w-3 h-3 text-zinc-500 transition-transform shrink-0 ${open ? "rotate-90" : ""}`}
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fillRule="evenodd"
            d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
            clipRule="evenodd"
          />
        </svg>
        <Badge variant="amber">{toolName}</Badge>
        {/* Spawn/send target info */}
        {(isSpawn || isSend) && targetAgent && (
          <Badge variant="blue">{isSpawn ? "spawn" : "send"} {targetAgent}</Badge>
        )}
        {/* Result status indicator */}
        {toolResult && (
          <span
            className={`ml-auto text-[10px] font-medium ${
              isError ? "text-red-400" : "text-emerald-400"
            }`}
          >
            {isError ? "error" : "ok"}
          </span>
        )}
      </button>

      {/* Expanded content */}
      {open && (
        <div className="border-t border-zinc-800">
          {/* Input params */}
          <div className="px-3 py-2">
            <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold mb-1.5">
              Input
            </div>
            <pre className="text-xs font-mono text-zinc-400 whitespace-pre-wrap break-all max-h-64 overflow-y-auto bg-zinc-950 rounded-lg p-2.5 border border-zinc-800">
              {JSON.stringify(toolUse.input ?? {}, null, 2)}
            </pre>
          </div>

          {/* Clickable session key for spawn/send */}
          {(isSpawn || isSend) && targetKey && onSessionClick && (
            <div className="px-3 pb-2">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onSessionClick(targetKey);
                }}
                className="text-xs font-mono text-indigo-400 hover:text-indigo-300 hover:underline transition-colors"
              >
                {targetKey}
              </button>
            </div>
          )}

          {/* Tool result */}
          {resultText && (
            <div
              className={`px-3 py-2 border-t ${
                isError ? "border-red-800/50" : "border-emerald-800/30"
              }`}
            >
              <div className="text-[10px] uppercase tracking-wider font-semibold mb-1.5">
                <span className={isError ? "text-red-400" : "text-emerald-400"}>
                  Result
                </span>
              </div>
              <pre
                className={`text-xs font-mono whitespace-pre-wrap break-all max-h-64 overflow-y-auto rounded-lg p-2.5 border ${
                  isError
                    ? "text-red-300 bg-red-950/30 border-red-800/50"
                    : "text-zinc-400 bg-zinc-950 border-zinc-800"
                }`}
              >
                {resultText}
              </pre>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// SpawnCard — specialized card for sessions_spawn results
// ---------------------------------------------------------------------------

function SpawnCard({
  toolUse,
  toolResult,
  onSessionClick,
}: {
  toolUse: ToolUseBlock;
  toolResult?: ToolResultBlock;
  onSessionClick?: (key: string) => void;
}) {
  const targetAgent = toolUse.input?.agent ?? toolUse.input?.agentId ?? "unknown";
  const message = toolUse.input?.message ?? toolUse.input?.text;
  const isError = toolResult?.is_error === true;

  // Try to extract the spawned session key from the result
  let spawnedKey: string | null = null;
  if (toolResult?.content) {
    try {
      const parsed =
        typeof toolResult.content === "string"
          ? JSON.parse(toolResult.content)
          : toolResult.content;
      spawnedKey = parsed?.key ?? parsed?.sessionKey ?? null;
    } catch {
      // not JSON, ignore
    }
  }

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900/60 my-1.5 overflow-hidden">
      <div className="px-3 py-2.5 flex items-center gap-2">
        <svg
          className="w-4 h-4 text-blue-400 shrink-0"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path d="M10 2a1 1 0 011 1v1.323l3.954 1.582 1.599-.8a1 1 0 01.894 1.79l-1.233.617 1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 0114 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346L11 6.618V16h2a1 1 0 110 2H7a1 1 0 110-2h2V6.618L7.214 7.512l1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 016 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346-1.233-.617a1 1 0 01.894-1.79l1.599.8L10 4.323V3a1 1 0 011-1z" />
        </svg>
        <Badge variant="blue">spawn</Badge>
        <Badge variant={agentColor(targetAgent) as any}>{targetAgent}</Badge>
        {isError && <Badge variant="red">failed</Badge>}
      </div>
      {message && (
        <div className="px-3 pb-2 text-xs text-zinc-400 truncate">
          {typeof message === "string"
            ? message.slice(0, 120)
            : JSON.stringify(message).slice(0, 120)}
        </div>
      )}
      {spawnedKey && onSessionClick && (
        <div className="px-3 pb-2.5">
          <button
            onClick={() => onSessionClick(spawnedKey!)}
            className="text-xs font-mono text-indigo-400 hover:text-indigo-300 hover:underline transition-colors"
          >
            {spawnedKey}
          </button>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Custom markdown components
// ---------------------------------------------------------------------------

function createMarkdownComponents() {
  return {
    code(props: any) {
      const { className, children, ...rest } = props;
      const match = /language-(\w+)/.exec(className || "");
      const codeText = String(children ?? "").replace(/\n$/, "");

      // Inline code (no language class, short)
      if (!match && !className) {
        return (
          <code
            className="px-1.5 py-0.5 rounded bg-zinc-800 text-amber-300 text-xs font-mono"
            {...rest}
          >
            {children}
          </code>
        );
      }

      // Block code
      return <CodeBlock language={match?.[1]}>{codeText}</CodeBlock>;
    },
    pre(props: any) {
      // Let CodeBlock handle the wrapper
      const { children } = props;
      return <>{children}</>;
    },
  };
}

const markdownComponents = createMarkdownComponents();

// ---------------------------------------------------------------------------
// Runtime context detection & provenance extraction
// ---------------------------------------------------------------------------

const RUNTIME_PATTERNS = [
  /^\[Subagent Context\]/,
  /^OpenClaw runtime context \(internal\):/,
  /^\[System:/,
  /^\[Internal:/,
];

/** Check if a text block is an OpenClaw runtime injection */
function isRuntimeContext(text: string): boolean {
  const trimmed = text.trim();
  return RUNTIME_PATTERNS.some((p) => p.test(trimmed));
}

/** Extract inter-session provenance info from message */
function extractProvenance(msg: any): { sourceKey?: string; sourceTool?: string } | null {
  const prov = msg?.provenance;
  if (!prov || prov.kind !== "inter_session") return null;
  return { sourceKey: prov.sourceSessionKey, sourceTool: prov.sourceTool };
}

/** Parse [Internal task completion event] blocks from text */
function parseCompletionEvents(text: string): Array<{ sessionKey: string; status: string; task: string }> {
  const events: Array<{ sessionKey: string; status: string; task: string }> = [];
  const regex = /\[Internal task completion event\]\s*\n(?:.*\n)*?session_key:\s*(\S+)\s*\n(?:.*\n)*?task:\s*(.+?)\s*\nstatus:\s*(.+?)(?:\n|$)/g;
  let match;
  while ((match = regex.exec(text)) !== null) {
    events.push({ sessionKey: match[1], task: match[2], status: match[3] });
  }
  return events;
}

/** Detect and render spawn result JSON inline */
function tryRenderSpawnResult(text: string, onSessionClick?: (key: string) => void): React.ReactNode | null {
  // Match { "status": "accepted", "childSessionKey": "..." ... }
  const match = text.match(/\{\s*"status"\s*:\s*"accepted"\s*,\s*"childSessionKey"\s*:\s*"([^"]+)"/);
  if (!match) return null;
  const childKey = match[1];
  const agent = agentFromKey(childKey);

  // Extract other fields
  const modeMatch = text.match(/"mode"\s*:\s*"([^"]+)"/);
  const mode = modeMatch?.[1] ?? "run";

  return (
    <div className="rounded-lg border border-blue-800/30 bg-blue-950/20 px-3 py-2 my-1">
      <div className="flex items-center gap-2 text-[10px]">
        <svg className="w-3.5 h-3.5 text-blue-400 shrink-0" viewBox="0 0 20 20" fill="currentColor">
          <path d="M10 2a1 1 0 011 1v1.323l3.954 1.582 1.599-.8a1 1 0 01.894 1.79l-1.233.617 1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 0114 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346L11 6.618V16h2a1 1 0 110 2H7a1 1 0 110-2h2V6.618L7.214 7.512l1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 016 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346-1.233-.617a1 1 0 01.894-1.79l1.599.8L10 4.323V3a1 1 0 011-1z" />
        </svg>
        <span className="text-blue-300 font-semibold">Spawned</span>
        <Badge variant={agentColor(agent) as any}>{agent}</Badge>
        <span className="text-zinc-500">{mode}</span>
      </div>
      {onSessionClick ? (
        <button
          onClick={() => onSessionClick(childKey)}
          className="text-[9px] font-mono text-indigo-400 hover:text-indigo-300 hover:underline mt-1 transition-colors block"
        >
          {childKey}
        </button>
      ) : (
        <div className="text-[9px] font-mono text-zinc-500 mt-1">{childKey}</div>
      )}
    </div>
  );
}

/** Detect and render external web content blocks more cleanly */
function tryRenderExternalContent(text: string): React.ReactNode | null {
  const match = text.match(/<<<EXTERNAL_UNTRUSTED_CONTENT[^>]*>>>\s*\nSource:\s*(\S+)\s*\n---\n([\s\S]*?)<<<END_EXTERNAL_UNTRUSTED_CONTENT/);
  if (!match) return null;
  const source = match[1];
  const content = match[2].trim();
  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-950 my-1 overflow-hidden">
      <div className="px-3 py-1.5 bg-zinc-900/50 border-b border-zinc-800 flex items-center gap-2">
        <span className="text-[10px] font-mono text-zinc-500">External: {source}</span>
      </div>
      <div className="px-3 py-2 text-xs text-zinc-400 max-h-48 overflow-y-auto whitespace-pre-wrap">{content.slice(0, 2000)}</div>
    </div>
  );
}

/** Compact runtime context block */
function RuntimeContextBlock({ text, defaultOpen }: { text: string; defaultOpen?: boolean }) {
  const [open, setOpen] = useState(defaultOpen ?? false);
  // Extract a one-line summary
  const firstLine = text.trim().split("\n")[0].slice(0, 60);

  return (
    <div className="rounded-lg border border-zinc-800/50 bg-zinc-900/30 my-1 overflow-hidden">
      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full text-left px-2.5 py-1.5 flex items-center gap-2 text-[10px] text-zinc-600 hover:text-zinc-400 transition-colors"
      >
        <svg className={`w-2.5 h-2.5 transition-transform shrink-0 ${open ? "rotate-90" : ""}`} viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />
        </svg>
        <span className="truncate">{firstLine}</span>
      </button>
      {open && (
        <pre className="px-2.5 pb-2 text-[9px] text-zinc-600 whitespace-pre-wrap max-h-40 overflow-y-auto font-mono">
          {text}
        </pre>
      )}
    </div>
  );
}

/** Completion event card */
function CompletionEventCard({
  event,
  onSessionClick,
}: {
  event: { sessionKey: string; status: string; task: string };
  onSessionClick?: (key: string) => void;
}) {
  const agent = agentFromKey(event.sessionKey);
  const statusColor = event.status.includes("completed") ? "text-emerald-400"
    : event.status.includes("failed") ? "text-red-400" : "text-amber-400";

  return (
    <div className="rounded-lg border border-zinc-800/50 bg-zinc-900/40 px-3 py-2 my-1">
      <div className="flex items-center gap-2 text-[10px]">
        <svg className="w-3 h-3 text-blue-400 shrink-0" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
        </svg>
        <Badge variant={agentColor(agent) as any}>{agent}</Badge>
        <span className={statusColor}>{event.status}</span>
      </div>
      <div className="text-[10px] text-zinc-500 mt-1 truncate">{event.task}</div>
      {onSessionClick && (
        <button
          onClick={() => onSessionClick(event.sessionKey)}
          className="text-[9px] font-mono text-indigo-400 hover:text-indigo-300 hover:underline mt-1 transition-colors"
        >
          {event.sessionKey.slice(0, 50)}
        </button>
      )}
    </div>
  );
}

/** Provenance badge — shows where this message came from */
function ProvenanceBadge({ sourceKey, sourceTool, onSessionClick }: {
  sourceKey: string;
  sourceTool?: string;
  onSessionClick?: (key: string) => void;
}) {
  const agent = agentFromKey(sourceKey);
  return (
    <div className="flex items-center gap-1.5 text-[9px] text-zinc-600 mb-1">
      <svg className="w-3 h-3 text-zinc-600" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M12.293 5.293a1 1 0 011.414 0l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-2.293-2.293a1 1 0 010-1.414z" clipRule="evenodd" />
      </svg>
      <span>from</span>
      {onSessionClick ? (
        <button onClick={() => onSessionClick(sourceKey)} className="text-indigo-400 hover:underline">
          {agent}
        </button>
      ) : (
        <span className="text-zinc-400">{agent}</span>
      )}
      {sourceTool && <span className="text-zinc-700">via {sourceTool}</span>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// MessageRenderer — the main exported component
// ---------------------------------------------------------------------------

export interface MessageRendererProps {
  msg: ChatMessage;
  sessionKey?: string;
  onSessionClick?: (key: string) => void;
  /** Companion messages for pairing tool_use with tool_result */
  allMessages?: ChatMessage[];
  messageIndex?: number;
}

export function MessageRenderer({
  msg,
  sessionKey,
  onSessionClick,
  allMessages,
  messageIndex,
}: MessageRendererProps) {
  const isUser = msg.role === "user";
  const isTool = msg.role === "tool";

  // Agent badge from session key
  const agentId = sessionKey ? agentFromKey(sessionKey) : null;
  const provenance = extractProvenance(msg);

  // ---- Tool result messages (role: "tool") ----
  if (isTool) {
    return null;
  }

  // ---- Array content: extract text for display ----
  if (Array.isArray(msg.content)) {
    const extractText = (blocks: any[]): string => {
      return blocks
        .map((b: any) => b.text ?? b.content ?? "")
        .filter(Boolean)
        .join("\n");
    };

    // User messages with array content
    if (isUser) {
      const fullText = extractText(msg.content);

      // Split text into runtime context vs real content
      const segments = fullText.split(/(?=\[Subagent Context\]|(?=OpenClaw runtime context))/);
      const runtimeParts: string[] = [];
      const contentParts: string[] = [];
      for (const seg of segments) {
        if (isRuntimeContext(seg)) runtimeParts.push(seg.trim());
        else contentParts.push(seg.trim());
      }
      const realText = contentParts.join("\n").trim();

      // Parse completion events from the text
      const completionEvents = parseCompletionEvents(fullText);

      return (
        <div>
          {/* Provenance indicator */}
          {provenance && (
            <ProvenanceBadge sourceKey={provenance.sourceKey!} sourceTool={provenance.sourceTool} onSessionClick={onSessionClick} />
          )}
          {/* Completion events get special cards */}
          {completionEvents.length > 0 && (
            <div className="space-y-1 mb-1">
              {completionEvents.map((ev, i) => (
                <CompletionEventCard key={i} event={ev} onSessionClick={onSessionClick} />
              ))}
            </div>
          )}
          {/* Runtime context collapsed */}
          {runtimeParts.map((rt, i) => (
            <RuntimeContextBlock key={`rt-${i}`} text={rt} />
          ))}
          {/* Actual user message content */}
          {realText && (
            <div className="flex justify-end">
              <div className="max-w-[80%] rounded-lg px-3.5 py-2.5 text-sm bg-indigo-600 text-zinc-100">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-[10px] font-semibold uppercase tracking-wider text-indigo-200/60">you</span>
                  {msg.ts && <span className="text-[10px] tabular-nums opacity-50">{formatTimestamp(msg.ts)}</span>}
                </div>
                <span className="whitespace-pre-wrap">{realText}</span>
              </div>
            </div>
          )}
        </div>
      );
    }

    // Assistant messages with array content (may have tool_use blocks)
    const textBlocks: { text: string; index: number }[] = [];
    const toolUseBlocks: { block: ToolUseBlock; index: number }[] = [];

    msg.content.forEach((block: any, i: number) => {
      if (block.type === "tool_use") {
        toolUseBlocks.push({ block, index: i });
      } else if (block.type === "tool_result") {
        // tool_result in content arrays: skip, handled by tool_use pairing
      } else {
        const text = block.text ?? block.content ?? "";
        if (text) {
          textBlocks.push({ text: String(text), index: i });
        }
      }
    });

    // Build tool_use -> tool_result pairs from allMessages
    const toolResultMap = new Map<string, ToolResultBlock>();
    if (allMessages && messageIndex != null) {
      // Look at subsequent messages for tool_result matches
      for (let j = messageIndex + 1; j < allMessages.length; j++) {
        const nextMsg = allMessages[j];
        if (nextMsg.role === "tool") {
          if (Array.isArray(nextMsg.content)) {
            for (const block of nextMsg.content) {
              if (block.type === "tool_result" && block.tool_use_id) {
                toolResultMap.set(block.tool_use_id, block);
              }
            }
          } else if (typeof nextMsg.content === "string") {
            // Flat tool result — try to match with the next unmatched tool_use
            // OpenClaw sends tool results as sequential messages matching tool_use order
            const unmatchedUses = toolUseBlocks.filter(
              ({ block }) => block.id && !toolResultMap.has(block.id),
            );
            if (unmatchedUses.length > 0) {
              const targetId = unmatchedUses[0].block.id!;
              toolResultMap.set(targetId, {
                type: "tool_result",
                tool_use_id: targetId,
                content: nextMsg.content,
              });
            }
          }
        }
        if (nextMsg.role === "assistant") break; // Stop at next assistant
      }
    }

    // Also check for tool_result blocks within the same message's content array
    msg.content.forEach((block: any) => {
      if (block.type === "tool_result" && block.tool_use_id) {
        toolResultMap.set(block.tool_use_id, block);
      }
    });

    return (
      <div className="space-y-1">
        {/* Agent badge */}
        {agentId && (
          <div className="flex items-center gap-1.5 mb-1">
            <ClickableAgentBadge agentId={agentId} />
            {msg.ts && (
              <span className="text-[10px] text-zinc-600 tabular-nums">
                {formatTimestamp(msg.ts)}
              </span>
            )}
          </div>
        )}

        {/* Text blocks */}
        {textBlocks.map(({ text, index }) => (
          <div
            key={index}
            className="rounded-lg px-3 py-2 bg-zinc-800/80 text-zinc-200 text-sm"
          >
            <div className="prose prose-sm prose-invert max-w-none [&_p]:my-1 [&_ul]:my-1 [&_ol]:my-1">
              <ReactMarkdown components={markdownComponents}>
                {text}
              </ReactMarkdown>
            </div>
          </div>
        ))}

        {/* Tool use blocks */}
        {toolUseBlocks.map(({ block, index }) => {
          const isSpawn =
            block.name === "sessions_spawn" || block.name === "sessions.spawn";
          const result = block.id ? toolResultMap.get(block.id) : undefined;

          if (isSpawn) {
            return (
              <SpawnCard
                key={index}
                toolUse={block}
                toolResult={result}
                onSessionClick={onSessionClick}
              />
            );
          }
          return (
            <ToolCallCard
              key={index}
              toolUse={block}
              toolResult={result}
              onSessionClick={onSessionClick}
            />
          );
        })}
      </div>
    );
  }

  // ---- Simple string content ----
  const rawText =
    typeof msg.content === "string"
      ? msg.content
      : JSON.stringify(msg.content, null, 2);

  // Check for runtime context in string content
  if (isRuntimeContext(rawText)) {
    return <RuntimeContextBlock text={rawText} />;
  }

  // Try special renderers for known structured content
  const spawnResult = tryRenderSpawnResult(rawText, onSessionClick);
  if (spawnResult) return <>{provenance && <ProvenanceBadge sourceKey={provenance.sourceKey!} sourceTool={provenance.sourceTool} onSessionClick={onSessionClick} />}{spawnResult}</>;

  const externalContent = tryRenderExternalContent(rawText);

  // Check for completion events embedded in text
  const completionEventsInText = parseCompletionEvents(rawText);
  // Strip the runtime context prefix from displayed text
  const cleanText = rawText
    .replace(/OpenClaw runtime context \(internal\):[\s\S]*?(?=\n\n|\n---|\n\[Internal)/g, "")
    .replace(/---\nQueued #\d+\n/g, "")
    .trim();

  return (
    <div>
      {/* Provenance */}
      {provenance && (
        <ProvenanceBadge sourceKey={provenance.sourceKey!} sourceTool={provenance.sourceTool} onSessionClick={onSessionClick} />
      )}
      {/* Completion event cards */}
      {completionEventsInText.length > 0 && (
        <div className="space-y-1 mb-1">
          {completionEventsInText.map((ev, i) => (
            <CompletionEventCard key={i} event={ev} onSessionClick={onSessionClick} />
          ))}
        </div>
      )}
      {/* External content block */}
      {externalContent && externalContent}
      {/* Regular message bubble */}
      {cleanText && (
      <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
        <div
          className={`max-w-[80%] rounded-lg px-3.5 py-2.5 text-sm ${
            isUser
              ? "bg-indigo-600 text-zinc-100"
              : "bg-zinc-800/80 text-zinc-200"
          }`}
        >
        {/* Header with role + timestamp */}
        <div className="flex items-center gap-2 mb-1">
          {agentId && !isUser && (
            <ClickableAgentBadge agentId={agentId} />
          )}
          {isUser && (
            <span className="text-[10px] font-semibold uppercase tracking-wider text-indigo-200/60">
              you
            </span>
          )}
          {msg.ts && (
            <span className="text-[10px] tabular-nums opacity-50">
              {formatTimestamp(msg.ts)}
            </span>
          )}
        </div>

        {/* Content */}
        {isUser ? (
          <span className="whitespace-pre-wrap">{cleanText}</span>
        ) : (
          <div className="prose prose-sm prose-invert max-w-none [&_p]:my-1 [&_ul]:my-1 [&_ol]:my-1">
            <ReactMarkdown components={markdownComponents}>
              {cleanText}
            </ReactMarkdown>
          </div>
        )}

        {/* Token count */}
        {msg.tokens != null && (
          <div className="text-[10px] text-zinc-500 mt-1.5 text-right tabular-nums">
            {msg.tokens.toLocaleString()} tokens
          </div>
        )}
      </div>
    </div>
    )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

function formatTimestamp(ts?: number): string {
  if (!ts) return "";
  return new Date(ts).toLocaleTimeString();
}
