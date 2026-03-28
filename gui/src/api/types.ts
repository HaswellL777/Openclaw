// Agent
export interface Agent {
  id: string;
  name?: string;
  default?: boolean;
  model?: { primary?: string };
  workspace?: string;
  sandbox?: { scope?: string };
  tools?: any;
}

export interface AgentListResult {
  agents: Agent[];
}

// Session
export interface Session {
  sessionKey: string;
  agent?: string;
  label?: string;
  model?: string;
  spawnedBy?: string;
  createdAt?: string;
  updatedAt?: string;
  lastMessage?: { text?: string; ts?: number };
  metadata?: Record<string, any>;
}

export interface SessionListResult {
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

export interface SessionUsageResult {
  entries: {
    date: string;
    inputTokens: number;
    outputTokens: number;
    cacheReadTokens?: number;
    totalTokens: number;
    sessions?: number;
    cost?: number;
  }[];
}

// Chat
export interface ChatMessage {
  role: "user" | "assistant" | "tool";
  content: string | any[];
  ts?: number;
  tokens?: number;
}

export interface ChatHistoryResult {
  messages: ChatMessage[];
}

// Health
export interface HealthSnapshot {
  ts: number;
  health: Record<string, { healthy: boolean; reason?: string }>;
  stateVersion?: { presence: number; health: number };
}

// Presence
export interface PresenceEntry {
  deviceId: string;
  host?: string;
  ip?: string;
  version?: string;
  mode?: string;
  platform?: string;
  ts: number;
  roles?: string[];
}

// Cron
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
  total?: number;
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

// Skills
export interface SkillStatus {
  installed: any[];
  available?: any[];
}

// Tools
export interface ToolGroup {
  label: string;
  tools: { id: string; label: string }[];
}

export interface ToolsCatalogResult {
  agentId: string;
  profiles: { id: string; label: string }[];
  groups: ToolGroup[];
}

// Config
export interface ConfigResult {
  config: any;
}

// Models
export interface Model {
  id: string;
  name: string;
  provider: string;
  reasoning?: boolean;
  contextWindow?: number;
  maxTokens?: number;
}

export interface ModelsListResult {
  models: Model[];
}

// Logs
export interface LogsResult {
  file: string;
  cursor: string;
  size: number;
  lines: string[];
  truncated: boolean;
  reset?: boolean;
}

// Channels
export interface ChannelStatus {
  id: string;
  healthy: boolean;
  connected?: boolean;
  reason?: string;
}

export interface ChannelsStatusResult {
  channels: ChannelStatus[];
}
