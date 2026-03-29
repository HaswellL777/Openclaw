import { useState, useEffect, useMemo, useCallback, useId } from "react";
import ReactMarkdown from "react-markdown";
import { PrismLight as SyntaxHighlighter } from "react-syntax-highlighter";
import oneDark from "react-syntax-highlighter/dist/esm/styles/prism/one-dark";
import { useGatewayStore } from "@/api/hooks";
import { agentColor as ac } from "@/api/agent-colors";
import type { ChatMessage, ChatHistoryResult, RunRecord, TaskGroup } from "@/api/types";
import { agentFromKey } from "@/api/types";
import { Badge, Spinner } from "@/components/shared";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Shift a hex color's lightness for same-agent differentiation */
function shiftColor(hex: string, idx: number, total: number): string {
  if (total <= 1) return hex;
  // Parse hex to RGB, adjust lightness
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  // Shift hue-like offset: rotate through brightness variations
  const factor = 1 + (idx - (total - 1) / 2) * 0.2; // ±20% per step
  const clamp = (v: number) => Math.max(60, Math.min(255, Math.round(v * factor)));
  return `rgb(${clamp(r)}, ${clamp(g)}, ${clamp(b)})`;
}

/** Get colors for a column, with same-agent differentiation */
function colColor(col: Column) {
  const base = ac(col.agent);
  if (col.sameAgentTotal <= 1) return base;
  const dot = shiftColor(base.dot, col.sameAgentIdx, col.sameAgentTotal);
  // Derive bg/border from shifted dot
  const opacity = 0.08 + col.sameAgentIdx * 0.03;
  return {
    dot,
    bg: `${dot.replace("rgb", "rgba").replace(")", `, ${opacity})`)}`,
    border: `${dot.replace("rgb", "rgba").replace(")", ", 0.3)")}`,
  };
}

function extractText(msg: ChatMessage): string {
  if (typeof msg.content === "string") return msg.content;
  if (Array.isArray(msg.content)) {
    return msg.content.map((b: any) => b.text ?? b.content ?? "").filter(Boolean).join("\n");
  }
  return "";
}

const RUNTIME_RE = /^\[Subagent Context\]|^OpenClaw runtime context|^\[System:|^\[Internal:/;
const COMPLETION_RE = /\[Internal task completion event\]/;
const SPAWN_RE = /"status"\s*:\s*"accepted"[\s\S]*?"childSessionKey"/;

function isKeyMessage(msg: ChatMessage, visibleIdx: number, visibleTotal: number): boolean {
  const text = extractText(msg).trim();
  if (!text) return false;
  if (RUNTIME_RE.test(text)) return false;
  if (visibleIdx === 0) return true;
  if (visibleIdx === visibleTotal - 1) return true;
  if (msg.role === "user") return true;
  if (COMPLETION_RE.test(text)) return true;
  if (SPAWN_RE.test(text)) return true;
  if ((msg as any).provenance?.kind === "inter_session") return true;
  return false;
}

function formatTime(ts: number): string {
  if (!ts) return "";
  return new Date(ts).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function formatShortTime(ts: number): string {
  if (!ts) return "";
  return new Date(ts).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" });
}

function formatDuration(startMs: number, endMs: number): string {
  const ms = endMs - startMs;
  if (ms <= 0) return "";
  if (ms < 60_000) return `${(ms / 1000).toFixed(0)}s`;
  return `${(ms / 60_000).toFixed(1)}m`;
}

// ---------------------------------------------------------------------------
// Timeline event types
// ---------------------------------------------------------------------------

interface Column {
  key: string;
  agent: string;
  run: RunRecord;
  /** Index among same-agent columns (0-based) for color differentiation */
  sameAgentIdx: number;
  sameAgentTotal: number;
}

interface MsgEvent {
  kind: "msg";
  colIdx: number;
  sessionKey: string;
  msg: ChatMessage;
  ts: number;
}

interface ConnEvent {
  kind: "conn";
  fromCol: number;     // -1 = offscreen (requester not in columns)
  toCol: number;
  ts: number;
  label: string;
  variant: "spawn" | "return";
  color: string;
}

interface GapEvent {
  kind: "gap";
  colIdx: number;
  sessionKey: string;
  count: number;
  messages: ChatMessage[];
  ts: number;
}

interface CollapseEvent {
  kind: "collapse";
  colIdx: number;
  sessionKey: string;
  ts: number;
}

type TLEvent = MsgEvent | ConnEvent | GapEvent | CollapseEvent;

// ---------------------------------------------------------------------------
// Build the unified timeline
// ---------------------------------------------------------------------------

function buildTimeline(
  columns: Column[],
  sessionMsgs: Map<string, ChatMessage[]>,
  group: TaskGroup,
  expandedSessions: Set<string>,
): TLEvent[] {
  const events: TLEvent[] = [];
  const colByKey = new Map<string, number>();
  columns.forEach((c, i) => colByKey.set(c.key, i));

  // 1. Spawn connections (from runs data)
  for (const run of group.runs) {
    const fromCol = colByKey.get(run.requesterSessionKey) ?? -1;
    const toCol = colByKey.get(run.childSessionKey) ?? -1;
    if (toCol === -1) continue; // target not in our columns

    const targetAgent = agentFromKey(run.childSessionKey);
    events.push({
      kind: "conn",
      fromCol,
      toCol,
      ts: run.createdAt,
      label: fromCol === -1
        ? `${agentFromKey(run.requesterSessionKey)} spawned`
        : `spawn`,
      variant: "spawn",
      color: ac(targetAgent).dot,
    });

    // Completion connection
    if (run.endedAt > 0) {
      events.push({
        kind: "conn",
        fromCol: toCol,
        toCol: fromCol,
        ts: run.endedAt,
        label: run.status === "ok" ? "completed" : run.status || "done",
        variant: "return",
        color: run.status === "ok" ? "#10b981"
          : run.status === "error" ? "#ef4444"
          : run.status === "timeout" ? "#f59e0b" : "#71717a",
      });
    }
  }

  // 2. Messages from each session
  for (const [sessionKey, messages] of sessionMsgs) {
    const colIdx = colByKey.get(sessionKey);
    if (colIdx == null) continue;

    const expanded = expandedSessions.has(sessionKey);

    if (expanded) {
      // Show all non-noise messages
      for (const msg of messages) {
        const text = extractText(msg).trim();
        if (!text || RUNTIME_RE.test(text)) continue;
        events.push({
          kind: "msg",
          colIdx,
          sessionKey,
          msg,
          ts: msg.ts ?? 0,
        });
      }
      // Add collapse indicator at the end
      const lastTs = messages[messages.length - 1]?.ts ?? 0;
      events.push({
        kind: "collapse",
        colIdx,
        sessionKey,
        ts: lastTs + 0.1, // slightly after last message
      });
    } else {
      // Pre-filter to get visible messages (skip noise) for correct index-based key detection
      const visible = messages.filter(m => {
        const t = extractText(m).trim();
        return t && !RUNTIME_RE.test(t);
      });

      // Show only key messages, with gap indicators for skipped ones
      let gapBuffer: ChatMessage[] = [];
      let lastKeyTs = 0;

      for (let vi = 0; vi < visible.length; vi++) {
        const msg = visible[vi];

        if (isKeyMessage(msg, vi, visible.length)) {
          // Emit gap if we have buffered supporting messages
          if (gapBuffer.length > 0) {
            events.push({
              kind: "gap",
              colIdx,
              sessionKey,
              count: gapBuffer.length,
              messages: gapBuffer,
              ts: gapBuffer[0].ts ?? lastKeyTs,
            });
            gapBuffer = [];
          }
          events.push({
            kind: "msg",
            colIdx,
            sessionKey,
            msg,
            ts: msg.ts ?? 0,
          });
          lastKeyTs = msg.ts ?? 0;
        } else {
          gapBuffer.push(msg);
        }
      }

      // Trailing gap
      if (gapBuffer.length > 0) {
        events.push({
          kind: "gap",
          colIdx,
          sessionKey,
          count: gapBuffer.length,
          messages: gapBuffer,
          ts: gapBuffer[0].ts ?? lastKeyTs,
        });
      }
    }
  }

  // Sort by timestamp
  events.sort((a, b) => a.ts - b.ts);
  return events;
}

// ---------------------------------------------------------------------------
// Compact message card
// ---------------------------------------------------------------------------

function CompactCard({ msg, agent, selected, onClick }: {
  msg: ChatMessage;
  agent: string;
  selected: boolean;
  onClick: () => void;
}) {
  const text = extractText(msg);
  const isUser = msg.role === "user";
  const colors = ac(agent);

  // Detect special message types
  const isCompletion = COMPLETION_RE.test(text);
  const isSpawn = SPAWN_RE.test(text);

  // Extract clean preview text
  let preview = text
    .replace(/\[Internal task completion event\][\s\S]*?(?=\n\n|$)/g, "")
    .replace(/\{"status":"accepted"[\s\S]*?\}/g, "")
    .replace(/OpenClaw runtime context[\s\S]*?(?=\n\n|$)/g, "")
    .replace(/\[Subagent Context\][\s\S]*?(?=\n\n|$)/g, "")
    .trim();

  // For completion events, show structured info
  if (isCompletion) {
    const skMatch = text.match(/session_key:\s*(\S+)/);
    const stMatch = text.match(/status:\s*(.+?)(?:\n|$)/);
    const agent2 = skMatch ? agentFromKey(skMatch[1]) : "";
    const status = stMatch?.[1]?.trim() ?? "";
    return (
      <button onClick={onClick} className="w-full text-left">
        <div className={`rounded-md border px-2.5 py-1.5 text-[10px] transition-all hover:brightness-125 ${selected ? "ring-1 ring-emerald-400/50" : ""}`}
          style={{ borderColor: "rgba(16,185,129,0.3)", background: "rgba(16,185,129,0.06)" }}>
          <div className="flex items-center gap-1.5">
            <svg className="w-3 h-3 text-emerald-400 shrink-0" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
            </svg>
            <span className="text-emerald-300 font-medium">Task Complete</span>
            {agent2 && <Badge variant="emerald">{agent2}</Badge>}
            <span className="text-zinc-500 ml-auto">{status}</span>
          </div>
        </div>
      </button>
    );
  }

  // For spawn results
  if (isSpawn) {
    const ckMatch = text.match(/"childSessionKey"\s*:\s*"([^"]+)"/);
    const childAgent = ckMatch ? agentFromKey(ckMatch[1]) : "";
    return (
      <button onClick={onClick} className="w-full text-left">
        <div className={`rounded-md border px-2.5 py-1.5 text-[10px] transition-all hover:brightness-125 ${selected ? "ring-1 ring-blue-400/50" : ""}`}
          style={{ borderColor: "rgba(59,130,246,0.3)", background: "rgba(59,130,246,0.06)" }}>
          <div className="flex items-center gap-1.5">
            <svg className="w-3 h-3 text-blue-400 shrink-0" viewBox="0 0 20 20" fill="currentColor">
              <path d="M10 2a1 1 0 011 1v1.323l3.954 1.582 1.599-.8a1 1 0 01.894 1.79l-1.233.617 1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 0114 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346L11 6.618V16h2a1 1 0 110 2H7a1 1 0 110-2h2V6.618L7.214 7.512l1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 016 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346-1.233-.617a1 1 0 01.894-1.79l1.599.8L10 4.323V3a1 1 0 011-1z" />
            </svg>
            <span className="text-blue-300 font-medium">Spawned</span>
            {childAgent && <Badge variant="blue">{childAgent}</Badge>}
          </div>
        </div>
      </button>
    );
  }

  if (!preview) preview = "(empty)";

  return (
    <button onClick={onClick} className="w-full text-left group">
      <div
        className={`rounded-md border px-2.5 py-2 transition-all hover:brightness-125 ${selected ? "ring-1 ring-indigo-400/40 brightness-110" : ""}`}
        style={{
          borderColor: isUser ? "rgba(99,102,241,0.3)" : colors.border,
          background: isUser ? "rgba(99,102,241,0.08)" : colors.bg,
          borderLeftWidth: 3,
          borderLeftColor: isUser ? "#6366f1" : colors.dot,
        }}
      >
        {/* Role + time header */}
        <div className="flex items-center gap-1.5 mb-0.5">
          <span className="text-[9px] font-bold uppercase tracking-wider"
            style={{ color: isUser ? "#818cf8" : colors.dot }}>
            {isUser ? "user" : agent}
          </span>
          {msg.ts && (
            <span className="text-[9px] text-zinc-600 tabular-nums ml-auto">
              {formatTime(msg.ts)}
            </span>
          )}
        </div>

        {/* Always compact preview — full content in detail panel */}
        <div className="text-[11px] text-zinc-400 leading-snug line-clamp-3">
          {preview.slice(0, 200)}
        </div>
      </div>
    </button>
  );
}

// ---------------------------------------------------------------------------
// Connection arrow (rendered as a full-width row)
// ---------------------------------------------------------------------------

function ConnectionArrow({ columns, event }: {
  columns: Column[];
  event: ConnEvent;
}) {
  const N = columns.length;
  const { fromCol, toCol, label, variant, color } = event;
  const markerId = useId();

  // Off-screen endpoints: render as a label-only indicator at the nearest column
  const hasOffscreen = fromCol === -1 || toCol === -1;

  // Same column, both off-screen, or arrow to/from outside: show a label badge
  if ((fromCol === toCol) || (fromCol === -1 && toCol === -1) || hasOffscreen) {
    const anchorCol = fromCol === -1 ? toCol : fromCol;
    const anchorPct = anchorCol >= 0 ? ((anchorCol + 0.5) / N) * 100 : 50;
    const arrowDir = variant === "spawn" ? "incoming" : "outgoing";
    return (
      <div className="relative flex items-center" style={{ height: 28 }}>
        <div className="absolute inset-0 flex">
          {columns.map((col, ci) => (
            <div key={ci} className="flex-1 relative">
              <div className="absolute left-1/2 top-0 bottom-0 w-px" style={{ background: colColor(col).border }} />
            </div>
          ))}
        </div>
        <div
          className="absolute z-10 flex items-center gap-1 px-1.5 py-0.5 rounded-full text-[9px] font-medium"
          style={{
            left: `${anchorPct}%`,
            transform: "translate(-50%, 0)",
            color,
            background: "#09090b",
            border: `1px solid ${color}33`,
          }}
        >
          {hasOffscreen && arrowDir === "incoming" && <span>&#x2190;</span>}
          {variant === "spawn" ? (
            <svg className="w-2.5 h-2.5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
              <path d="M10 2a1 1 0 011 1v1.323l3.954 1.582 1.599-.8a1 1 0 01.894 1.79l-1.233.617 1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 0114 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346L11 6.618V16h2a1 1 0 110 2H7a1 1 0 110-2h2V6.618L7.214 7.512l1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 016 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346-1.233-.617a1 1 0 01.894-1.79l1.599.8L10 4.323V3a1 1 0 011-1z" />
            </svg>
          ) : (
            <svg className="w-2.5 h-2.5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
            </svg>
          )}
          {label}
          {hasOffscreen && arrowDir === "outgoing" && <span>&#x2192;</span>}
        </div>
      </div>
    );
  }

  const fromPct = ((fromCol + 0.5) / N) * 100;
  const toPct = ((toCol + 0.5) / N) * 100;
  const minPct = Math.min(fromPct, toPct);
  const maxPct = Math.max(fromPct, toPct);
  const isLR = fromPct < toPct;

  return (
    <div className="relative" style={{ height: 28 }}>
      {/* Column lifeline borders (background) */}
      <div className="absolute inset-0 flex">
        {columns.map((col, ci) => (
          <div key={ci} className="flex-1 relative">
            <div className="absolute left-1/2 top-0 bottom-0 w-px" style={{ background: colColor(col).border }} />
          </div>
        ))}
      </div>

      {/* Arrow SVG */}
      <svg className="absolute inset-0 w-full h-full" preserveAspectRatio="none">
        <defs>
          <marker
            id={markerId}
            markerWidth="7" markerHeight="5"
            refX={isLR ? 6 : 1} refY="2.5"
            orient="auto"
          >
            <polygon
              points={isLR ? "0 0, 7 2.5, 0 5" : "7 0, 0 2.5, 7 5"}
              fill={color}
              opacity="0.8"
            />
          </marker>
        </defs>
        <line
          x1={`${fromPct}%`} y1="50%"
          x2={`${toPct}%`} y2="50%"
          stroke={color}
          strokeWidth="1.5"
          strokeDasharray={variant === "spawn" ? "none" : "5 3"}
          opacity="0.5"
          markerEnd={`url(#${markerId})`}
        />
      </svg>

      {/* Label */}
      <div
        className="absolute top-1/2 z-10 flex items-center gap-1 px-1.5 py-0.5 rounded-full text-[9px] font-medium"
        style={{
          left: `${(Math.max(0, minPct) + Math.min(100, maxPct)) / 2}%`,
          transform: "translate(-50%, -50%)",
          color,
          background: "#09090b",
          border: `1px solid ${color}33`,
        }}
      >
        {variant === "spawn" ? (
          <svg className="w-2.5 h-2.5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
            <path d="M10 2a1 1 0 011 1v1.323l3.954 1.582 1.599-.8a1 1 0 01.894 1.79l-1.233.617 1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 0114 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346L11 6.618V16h2a1 1 0 110 2H7a1 1 0 110-2h2V6.618L7.214 7.512l1.738 4.346a1 1 0 01-.025.846A3.955 3.955 0 016 15.5a3.955 3.955 0 01-2.927-2.796 1 1 0 01-.025-.846l1.738-4.346-1.233-.617a1 1 0 01.894-1.79l1.599.8L10 4.323V3a1 1 0 011-1z" />
          </svg>
        ) : (
          <svg className="w-2.5 h-2.5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
          </svg>
        )}
        {label}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Gap indicator (collapsed supporting messages)
// ---------------------------------------------------------------------------

function GapIndicator({ count, onClick }: { count: number; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full flex items-center gap-1.5 px-2.5 py-1 text-[10px] text-zinc-600 hover:text-zinc-400 transition-colors rounded hover:bg-zinc-800/30"
    >
      <div className="flex-1 h-px bg-zinc-800" />
      <span className="shrink-0 tabular-nums">{count} messages</span>
      <svg className="w-3 h-3 shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
      </svg>
      <div className="flex-1 h-px bg-zinc-800" />
    </button>
  );
}

// ---------------------------------------------------------------------------
// Detail panel (full message view)
// ---------------------------------------------------------------------------

function DetailPanel({ msg, sessionKey, onClose, onSessionClick }: {
  msg: ChatMessage;
  sessionKey: string;
  onClose: () => void;
  onSessionClick: (key: string) => void;
}) {
  const agent = agentFromKey(sessionKey);
  const text = extractText(msg);
  const isUser = msg.role === "user";

  const mdComponents = useMemo(() => ({
    code(props: any) {
      const { className, children, ...rest } = props;
      const match = /language-(\w+)/.exec(className || "");
      const codeText = String(children ?? "").replace(/\n$/, "");
      if (!match && !className) {
        return <code className="px-1.5 py-0.5 rounded bg-zinc-800 text-amber-300 text-xs font-mono" {...rest}>{children}</code>;
      }
      return (
        <div className="rounded-lg bg-zinc-950 border border-zinc-800 my-2 overflow-hidden">
          <div className="flex items-center px-3 py-1 bg-zinc-900/50 border-b border-zinc-800">
            <span className="text-[10px] font-mono text-zinc-500 uppercase tracking-wide">{match?.[1] || "code"}</span>
          </div>
          <SyntaxHighlighter
            language={match?.[1] || "text"}
            style={oneDark}
            customStyle={{ margin: 0, padding: "10px 12px", background: "transparent", fontSize: "12px", lineHeight: "1.6" }}
            codeTagProps={{ style: { fontFamily: "'IBM Plex Mono', monospace" } }}
          >
            {codeText}
          </SyntaxHighlighter>
        </div>
      );
    },
    pre(props: any) { return <>{props.children}</>; },
  }), []);

  return (
    <div className="border-t border-zinc-800 bg-zinc-900/80 backdrop-blur max-h-[40vh] overflow-y-auto">
      <div className="sticky top-0 z-10 px-4 py-2 bg-zinc-900/95 backdrop-blur border-b border-zinc-800/50 flex items-center gap-2">
        <Badge variant={isUser ? "indigo" : (agent === "task-runner" ? "emerald" : agent === "research-coordinator" ? "blue" : agent === "auditor" ? "purple" : "amber") as any}>
          {isUser ? "user" : agent}
        </Badge>
        <span className="text-[10px] text-zinc-500 font-mono truncate flex-1">{sessionKey.split(":").slice(-1)[0]?.slice(0, 16)}</span>
        {msg.ts && <span className="text-[10px] text-zinc-600 tabular-nums">{formatTime(msg.ts)}</span>}
        <a
          href={`/chat?session=${encodeURIComponent(sessionKey)}`}
          target="_blank"
          rel="noopener noreferrer"
          className="px-2 py-0.5 text-[10px] bg-indigo-600/20 text-indigo-400 rounded hover:bg-indigo-600/30 transition-colors inline-flex items-center gap-1"
        >
          Open Chat
          <svg className="w-2.5 h-2.5" viewBox="0 0 20 20" fill="currentColor">
            <path d="M11 3a1 1 0 100 2h2.586l-6.293 6.293a1 1 0 101.414 1.414L15 6.414V9a1 1 0 102 0V4a1 1 0 00-1-1h-5z" />
            <path d="M5 5a2 2 0 00-2 2v8a2 2 0 002 2h8a2 2 0 002-2v-3a1 1 0 10-2 0v3H5V7h3a1 1 0 000-2H5z" />
          </svg>
        </a>
        <button
          onClick={onClose}
          className="px-2 py-0.5 text-[10px] bg-zinc-700 text-zinc-400 rounded hover:bg-zinc-600 transition-colors"
        >
          Close
        </button>
      </div>
      <div className="px-4 py-3 text-sm text-zinc-300 leading-relaxed prose prose-sm prose-invert max-w-none [&_p]:my-1 [&_ul]:my-1 [&_ol]:my-1">
        <ReactMarkdown components={mdComponents}>{text.slice(0, 8000)}</ReactMarkdown>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// TaskDetailView — main export
// ---------------------------------------------------------------------------

export interface TaskDetailViewProps {
  group: TaskGroup;
  allRuns: RunRecord[];
  onBack: () => void;
  customName?: string;
  onRename?: (name: string) => void;
  onClearName?: () => void;
  /** Soft-archive: hide from default view (localStorage only, no data deleted) */
  onArchive?: () => void;
  /** Restore from archive */
  onRestore?: () => void;
  /** Whether this task is currently archived */
  isArchived?: boolean;
}

export function TaskDetailView({ group, allRuns, onBack, customName, onRename, onClearName, onArchive, onRestore, isArchived }: TaskDetailViewProps) {
  const client = useGatewayStore(s => s.client);
  const [loading, setLoading] = useState(true);
  const [sessionMsgs, setSessionMsgs] = useState<Map<string, ChatMessage[]>>(new Map());
  const [expandedSessions, setExpandedSessions] = useState<Set<string>>(new Set());
  const [selectedMsgKey, setSelectedMsgKey] = useState<string | null>(null);
  const [detailMsg, setDetailMsg] = useState<{ msg: ChatMessage; sessionKey: string } | null>(null);
  const [renaming, setRenaming] = useState(false);
  const [renameInput, setRenameInput] = useState("");

  // Build columns from task group runs
  const columns: Column[] = useMemo(() => {
    const seen = new Set<string>();
    const cols: Column[] = [];
    const sorted = [...group.runs].sort((a, b) => a.createdAt - b.createdAt);
    for (const run of sorted) {
      if (!seen.has(run.childSessionKey)) {
        seen.add(run.childSessionKey);
        cols.push({
          key: run.childSessionKey,
          agent: agentFromKey(run.childSessionKey),
          run,
          sameAgentIdx: 0,
          sameAgentTotal: 0,
        });
      }
    }
    // Count same-agent sessions and assign indices
    const agentCount = new Map<string, number>();
    for (const c of cols) agentCount.set(c.agent, (agentCount.get(c.agent) ?? 0) + 1);
    const agentSeen = new Map<string, number>();
    for (const c of cols) {
      const idx = agentSeen.get(c.agent) ?? 0;
      c.sameAgentIdx = idx;
      c.sameAgentTotal = agentCount.get(c.agent) ?? 1;
      agentSeen.set(c.agent, idx + 1);
    }
    return cols;
  }, [group]);

  // Fetch chat.history for all sessions in parallel
  useEffect(() => {
    if (!client || columns.length === 0) return;
    let cancelled = false;
    setLoading(true);
    const keys = columns.map(c => c.key);
    Promise.all(
      keys.map(k =>
        client.call<ChatHistoryResult>("chat.history", { sessionKey: k })
          .then(r => [k, r?.messages ?? []] as const)
          .catch(() => [k, []] as const)
      )
    ).then(results => {
      if (cancelled) return;
      const map = new Map<string, ChatMessage[]>();
      for (const [key, msgs] of results) {
        map.set(key, msgs);
      }
      setSessionMsgs(map);
      setLoading(false);
    });
    return () => { cancelled = true; };
  }, [client, columns]);

  // Build timeline
  const timeline = useMemo(
    () => buildTimeline(columns, sessionMsgs, group, expandedSessions),
    [columns, sessionMsgs, group, expandedSessions],
  );

  // Stats
  const totalMsgs = useMemo(() => {
    let n = 0;
    for (const msgs of sessionMsgs.values()) n += msgs.length;
    return n;
  }, [sessionMsgs]);

  const duration = useMemo(() => {
    const starts = group.runs.map(r => r.createdAt).filter(t => t > 0);
    const ends = group.runs.map(r => r.endedAt).filter(t => t > 0);
    if (starts.length === 0) return "";
    const s = Math.min(...starts);
    const e = ends.length > 0 ? Math.max(...ends) : Date.now();
    return formatDuration(s, e);
  }, [group]);

  const toggleSessionExpand = useCallback((sessionKey: string) => {
    setExpandedSessions(prev => {
      const next = new Set(prev);
      if (next.has(sessionKey)) next.delete(sessionKey);
      else next.add(sessionKey);
      return next;
    });
  }, []);

  return (
    <div className="flex flex-col h-screen bg-zinc-950">
      {/* Header */}
      <div className="px-4 py-2.5 border-b border-zinc-800 bg-zinc-900 flex items-center gap-3 shrink-0">
        <button
          onClick={onBack}
          className="flex items-center gap-1 text-sm text-zinc-400 hover:text-zinc-200 transition-colors"
        >
          <svg className="w-4 h-4" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clipRule="evenodd" />
          </svg>
          Back
        </button>
        <div className="w-px h-5 bg-zinc-700" />

        {/* Task name — editable */}
        {renaming ? (
          <form className="flex items-center gap-1.5" onSubmit={e => {
            e.preventDefault();
            if (renameInput.trim() && onRename) onRename(renameInput.trim());
            setRenaming(false);
          }}>
            <input
              autoFocus
              value={renameInput}
              onChange={e => setRenameInput(e.target.value)}
              className="bg-zinc-800 border border-indigo-500/50 rounded px-2 py-0.5 text-sm text-zinc-200 focus:outline-none w-56"
              placeholder="Task name..."
            />
            <button type="submit" className="text-[11px] text-indigo-400 hover:text-indigo-300 font-medium">Save</button>
            <button type="button" onClick={() => setRenaming(false)} className="text-[11px] text-zinc-500 hover:text-zinc-400">Cancel</button>
          </form>
        ) : (
          <div className="flex items-center gap-2 min-w-0">
            <div className="w-2.5 h-2.5 rounded bg-indigo-500/40 border border-indigo-500/60 shrink-0" />
            <span className="text-sm font-bold text-zinc-100 truncate">
              {customName || `Task #${group.id.split("-")[1] ? Number(group.id.split("-")[1]) + 1 : "?"}`}
            </span>
            {onRename && (
              <button
                onClick={() => { setRenaming(true); setRenameInput(customName ?? ""); }}
                className="text-[10px] text-zinc-500 hover:text-zinc-300 transition-colors px-1.5 py-0.5 rounded hover:bg-zinc-800"
              >
                Rename
              </button>
            )}
            {customName && onClearName && (
              <button onClick={onClearName} className="text-[10px] text-zinc-600 hover:text-zinc-400 transition-colors">Reset</button>
            )}
          </div>
        )}

        <span className="text-xs text-zinc-500 truncate max-w-[200px]">{group.taskSummary}</span>

        <div className="ml-auto flex items-center gap-3 text-[10px] text-zinc-500 shrink-0">
          <span>{columns.length} sessions</span>
          {totalMsgs > 0 && <span>{totalMsgs} msgs</span>}
          {duration && <span>{duration}</span>}
          {group.startTime > 0 && (
            <span className="font-mono">{formatShortTime(group.startTime)}</span>
          )}
          {isArchived ? (
            onRestore && (
              <button
                onClick={onRestore}
                className="text-[10px] text-emerald-400/70 hover:text-emerald-400 transition-colors px-2 py-0.5 rounded border border-emerald-500/20 hover:border-emerald-500/40 hover:bg-emerald-500/10"
              >
                Restore
              </button>
            )
          ) : (
            onArchive && (
              <button
                onClick={onArchive}
                className="text-[10px] text-zinc-500 hover:text-zinc-300 transition-colors px-2 py-0.5 rounded border border-zinc-700/40 hover:border-zinc-600 hover:bg-zinc-800/60"
              >
                Archive
              </button>
            )
          )}
        </div>
      </div>

      {/* Column headers (sticky) */}
      <div className="flex border-b border-zinc-800 bg-zinc-900/80 backdrop-blur shrink-0 sticky top-0 z-20">
        <div className="w-[56px] shrink-0" /> {/* time column spacer */}
        {columns.map((col, ci) => {
          const colors = colColor(col);
          const isExpanded = expandedSessions.has(col.key);
          const msgCount = sessionMsgs.get(col.key)?.length ?? 0;
          const showIdx = col.sameAgentTotal > 1;
          return (
            <div
              key={ci}
              className="flex-1 px-2 py-2 border-l transition-colors"
              style={{ borderColor: colors.border, background: colors.bg }}
            >
              <div className="flex items-center gap-1.5">
                <span className="w-2 h-2 rounded-full shrink-0" style={{ background: colors.dot }} />
                <span className="text-[11px] font-bold truncate" style={{ color: colors.dot }}>
                  {col.agent}{showIdx ? ` #${col.sameAgentIdx + 1}` : ""}
                </span>
                <span className="text-[9px] text-zinc-600 ml-auto tabular-nums shrink-0">
                  {msgCount > 0 ? `${msgCount}` : ""}
                </span>
              </div>
              <div className="flex items-center gap-1.5 mt-1">
                <span className="text-[9px] text-zinc-600 truncate font-mono">
                  {col.key.split(":").slice(-1)[0]?.slice(0, 10)}
                </span>
                {msgCount > 0 && (
                  <button
                    onClick={() => toggleSessionExpand(col.key)}
                    className={`text-[9px] px-2 py-0.5 rounded-md font-medium transition-all shrink-0 border ${
                      isExpanded
                        ? "bg-indigo-500/20 text-indigo-300 border-indigo-500/30 hover:bg-indigo-500/30"
                        : "bg-zinc-800/60 text-zinc-400 border-zinc-700/40 hover:bg-zinc-700/60 hover:text-zinc-200"
                    }`}
                  >
                    {isExpanded ? "Collapse" : `Expand ${msgCount}`}
                  </button>
                )}
              </div>
              {/* Status badge */}
              {col.run.status && (
                <div className="mt-1">
                  <span className={`text-[9px] px-1 py-0.5 rounded ${
                    col.run.status === "ok" ? "bg-emerald-500/10 text-emerald-400"
                    : col.run.status === "error" ? "bg-red-500/10 text-red-400"
                    : col.run.status === "timeout" ? "bg-amber-500/10 text-amber-400"
                    : "bg-zinc-800 text-zinc-500"
                  }`}>
                    {col.run.status}
                  </span>
                  {col.run.endedAt > 0 && col.run.startedAt > 0 && (
                    <span className="text-[9px] text-zinc-600 ml-1 tabular-nums">
                      {formatDuration(col.run.startedAt, col.run.endedAt)}
                    </span>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Timeline body */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center h-full">
            <Spinner text="Loading message history..." />
          </div>
        ) : timeline.length === 0 ? (
          <div className="flex items-center justify-center h-full text-sm text-zinc-500">
            No messages found
          </div>
        ) : (
          <div className="pb-4">
            {timeline.map((event, i) => {
              if (event.kind === "conn") {
                return (
                  <div key={`conn-${i}`} className="flex">
                    <div className="w-[56px] shrink-0 flex items-center justify-end pr-2">
                      <span className="text-[9px] text-zinc-700 tabular-nums font-mono">
                        {formatTime(event.ts)}
                      </span>
                    </div>
                    <div className="flex-1">
                      <ConnectionArrow columns={columns} event={event} />
                    </div>
                  </div>
                );
              }

              if (event.kind === "gap") {
                return (
                  <div key={`gap-${i}`} className="flex">
                    <div className="w-[56px] shrink-0" />
                    <div className="flex-1 flex">
                      {columns.map((col, ci) => (
                        <div key={ci} className="flex-1 relative px-1">
                          <div className="absolute left-1/2 top-0 bottom-0 w-px" style={{ background: colColor(col).border }} />
                          {ci === event.colIdx && (
                            <div className="relative z-10 py-0.5">
                              <GapIndicator
                                count={event.count}
                                onClick={() => toggleSessionExpand(event.sessionKey)}
                              />
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                );
              }

              if (event.kind === "collapse") {
                return (
                  <div key={`collapse-${i}`} className="flex">
                    <div className="w-[56px] shrink-0" />
                    <div className="flex-1 flex">
                      {columns.map((col, ci) => (
                        <div key={ci} className="flex-1 relative px-1">
                          <div className="absolute left-1/2 top-0 bottom-0 w-px" style={{ background: colColor(col).border }} />
                          {ci === event.colIdx && (
                            <div className="relative z-10 py-0.5">
                              <button
                                onClick={() => toggleSessionExpand(event.sessionKey)}
                                className="w-full flex items-center gap-1.5 px-2.5 py-1 text-[10px] text-zinc-500 hover:text-zinc-300 transition-colors rounded bg-zinc-800/40 hover:bg-zinc-800/70 border border-zinc-700/30"
                              >
                                <svg className="w-3 h-3 shrink-0" viewBox="0 0 20 20" fill="currentColor">
                                  <path fillRule="evenodd" d="M14.707 12.707a1 1 0 01-1.414 0L10 9.414l-3.293 3.293a1 1 0 01-1.414-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 010 1.414z" clipRule="evenodd" />
                                </svg>
                                <span>Show key messages only</span>
                              </button>
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                );
              }

              // Message event
              const msgKey = `msg-${event.sessionKey}-${event.ts}-${i}`;
              const isSelected = selectedMsgKey === msgKey;

              return (
                <div key={msgKey} className="flex">
                  {/* Time column */}
                  <div className="w-[56px] shrink-0 flex items-start justify-end pr-2 pt-1">
                    <span className="text-[9px] text-zinc-700 tabular-nums font-mono">
                      {formatTime(event.ts)}
                    </span>
                  </div>
                  {/* Columns */}
                  <div className="flex-1 flex">
                    {columns.map((col, ci) => (
                      <div key={ci} className="flex-1 relative px-1">
                        {/* Lifeline */}
                        <div className="absolute left-1/2 top-0 bottom-0 w-px" style={{ background: colColor(col).border }} />
                        {ci === event.colIdx && (
                          <div className="relative z-10 py-0.5">
                            <CompactCard
                              msg={event.msg}
                              agent={col.agent}
                              selected={isSelected}
                              onClick={() => {
                                if (isSelected) {
                                  setSelectedMsgKey(null);
                                  setDetailMsg(null);
                                } else {
                                  setSelectedMsgKey(msgKey);
                                  setDetailMsg({ msg: event.msg, sessionKey: event.sessionKey });
                                }
                              }}
                            />
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Detail panel */}
      {detailMsg && (
        <DetailPanel
          msg={detailMsg.msg}
          sessionKey={detailMsg.sessionKey}
          onClose={() => { setDetailMsg(null); setSelectedMsgKey(null); }}
          onSessionClick={(key) => {
            const col = columns.find(c => c.key === key);
            if (col) {
              /* scroll to column — future enhancement */
            }
          }}
        />
      )}
    </div>
  );
}
