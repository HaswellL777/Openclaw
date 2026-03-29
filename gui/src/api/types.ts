// -------------------------------------------------------------------------
// Agent
// -------------------------------------------------------------------------

export interface Agent {
  id: string;
  name?: string;
}

export interface AgentListResult {
  defaultId: string;
  mainKey: string;
  scope: string;
  agents: Agent[];
}

// -------------------------------------------------------------------------
// Session
// -------------------------------------------------------------------------

export interface SessionOrigin {
  label?: string;
  provider?: string;
  from?: string;
  to?: string;
}

export interface Session {
  key: string;
  kind?: string;
  displayName?: string;
  chatType?: string;
  origin?: SessionOrigin;
  updatedAt?: number;       // epoch ms
  sessionId?: string;
  status?: string;          // subagent only: "running"|"done"|"killed"|"failed"|"timeout"
  modelProvider?: string;
  model?: string;
  inputTokens?: number;
  outputTokens?: number;
  totalTokens?: number;
  childSessions?: string[];
  parentSessionKey?: string;
  spawnedBy?: string;       // parent session key that spawned this one
  lastMessagePreview?: string;
  startedAt?: number;
  endedAt?: number;
  runtimeMs?: number;
}

/** Extract agent ID from a session key like "agent:main:main" or "agent:task-runner:subagent:uuid". */
export function agentFromKey(key: string): string {
  const parts = key.split(":");
  return parts.length >= 2 ? parts[1] : "unknown";
}

export interface SessionListResult {
  ts: number;
  path?: string;
  count: number;
  defaults?: {
    modelProvider?: string;
    model?: string;
    contextTokens?: number;
  };
  sessions: Session[];
}

export interface SessionPreview {
  key: string;
  status?: string;
  items: { role: string; text: string; ts?: number }[];
}

export interface SessionPreviewResult {
  ts: number;
  previews: SessionPreview[];
}

// -------------------------------------------------------------------------
// Session Usage
// -------------------------------------------------------------------------

export interface SessionUsageResult {
  updatedAt: number;
  startDate: string;
  endDate: string;
  sessions?: Session[];
  totals: {
    input: number;
    output: number;
    cacheRead: number;
    totalTokens: number;
    totalCost: number;
  };
  aggregates: {
    messages: {
      total: number;
      user: number;
      assistant: number;
      toolCalls: number;
      errors: number;
    };
    tools: {
      totalCalls: number;
      uniqueTools: number;
    };
  };
}

// -------------------------------------------------------------------------
// Chat
// -------------------------------------------------------------------------

export interface ChatMessage {
  role: "user" | "assistant" | "tool";
  content: string | any[];
  ts?: number;
  tokens?: number;
}

export interface ChatHistoryResult {
  messages: ChatMessage[];
}

// -------------------------------------------------------------------------
// Health
// -------------------------------------------------------------------------

export interface HealthChannelInfo {
  configured: boolean;
  port?: number | null;
  running: boolean;
  lastStartAt?: number;
  probe?: { ok: boolean };
}

export interface HealthAgentEntry {
  agentId: string;
  isDefault?: boolean;
  heartbeat?: Record<string, unknown>;
  sessions?: Record<string, unknown>;
}

export interface HealthSnapshot {
  ok: boolean;
  ts: number;
  durationMs?: number;
  channels: Record<string, HealthChannelInfo>;
  agents: HealthAgentEntry[];
  sessions?: { count: number; recent: unknown[] };
  heartbeatSeconds?: number;
}

// -------------------------------------------------------------------------
// Presence
// -------------------------------------------------------------------------

export interface PresenceEntry {
  host?: string;
  ip?: string;
  version?: string;
  platform?: string;
  mode?: string;
  ts?: number;
  roles?: string[];
}

// -------------------------------------------------------------------------
// Cron
// -------------------------------------------------------------------------

export interface CronJob {
  id: string;
  name: string;
  schedule: any;
  sessionTarget?: any;
  wakeMode?: string;
  state?: {
    enabled: boolean;
    lastRunAtMs?: number;
    nextRunAtMs?: number;
    consecutiveErrors?: number;
  };
}

export interface CronListResult {
  jobs: CronJob[];
  total: number;
  offset?: number;
  limit?: number;
  hasMore?: boolean;
}

export interface CronRun {
  id: string;
  jobId: string;
  status: string;
  startedAtMs: number;
  endedAtMs?: number;
  durationMs?: number;
  tokens?: number;
  error?: string;
}

export interface CronRunsResult {
  runs: CronRun[];
  total?: number;
}

// -------------------------------------------------------------------------
// Skills
// -------------------------------------------------------------------------

export interface Skill {
  name: string;
  description?: string;
  source?: string;
  bundled?: boolean;
  eligible?: boolean;
  [key: string]: unknown;
}

export interface SkillsStatusResult {
  workspaceDir?: string;
  managedSkillsDir?: string;
  skills: Skill[];
}

// -------------------------------------------------------------------------
// Tools
// -------------------------------------------------------------------------

export interface ToolGroup {
  label: string;
  tools: { id: string; label: string }[];
}

export interface ToolsCatalogResult {
  agentId: string;
  profiles: { id: string; label: string }[];
  groups: ToolGroup[];
}

// -------------------------------------------------------------------------
// Config
// -------------------------------------------------------------------------

export interface ConfigResult {
  path: string;
  exists: boolean;
  raw: Record<string, unknown>;
  parsed: Record<string, unknown>;
  resolved: Record<string, unknown>;
  valid: boolean;
  config: Record<string, unknown>;  // redacted version
  hash?: string;
}

// -------------------------------------------------------------------------
// Models
// -------------------------------------------------------------------------

export interface Model {
  id: string;
  name: string;
  provider: string;
  reasoning?: boolean;
  contextWindow?: number;
  maxTokens?: number;
  input?: string[];
}

export interface ModelsListResult {
  models: Model[];
}

// -------------------------------------------------------------------------
// Logs
// -------------------------------------------------------------------------

export interface LogsResult {
  file: string;
  cursor: number;
  size: number;
  lines: string[];
  truncated: boolean;
  reset?: boolean;
}

/** Parsed representation of a single JSON log line. */
export interface ParsedLogLine {
  time?: string;
  level?: string;
  subsystem?: string;
  message?: string;
  raw: string;
  [key: string]: unknown;
}

// -------------------------------------------------------------------------
// Channels
// -------------------------------------------------------------------------

export interface ChannelInfo {
  configured: boolean;
  running: boolean;
  port?: number | null;
  lastStartAt?: number;
  probe?: { ok: boolean };
  [key: string]: unknown;
}

export interface ChannelMeta {
  id: string;
  label: string;
}

export interface ChannelsStatusResult {
  ts: number;
  channels: Record<string, ChannelInfo>;
  channelLabels?: Record<string, string>;
  channelMeta?: ChannelMeta[];
}
