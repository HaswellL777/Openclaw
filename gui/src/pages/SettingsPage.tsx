import { useMemo } from "react";
import { useConfig, useModels, useAgents } from "@/api/hooks";
import type { Agent, Model } from "@/api/types";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function Spinner() {
  return (
    <div className="flex items-center gap-2 text-zinc-400 text-sm py-8">
      <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z" />
      </svg>
      Loading...
    </div>
  );
}

function ErrorBox({ message }: { message: string }) {
  return (
    <div className="rounded-lg border border-red-800/50 bg-red-950/30 px-4 py-3 text-sm text-red-300">
      {message}
    </div>
  );
}

function SectionHeading({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="text-lg font-semibold text-zinc-100 mb-4">{children}</h2>
  );
}

function Badge({ children, variant = "default" }: { children: React.ReactNode; variant?: "default" | "muted" }) {
  const cls = variant === "muted"
    ? "bg-zinc-800 text-zinc-400"
    : "bg-zinc-700 text-zinc-200";
  return (
    <span className={`inline-block rounded px-2 py-0.5 text-xs font-medium ${cls}`}>
      {children}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Provider row (read-only)
// ---------------------------------------------------------------------------

interface ProviderData {
  baseUrl?: string;
  apiKey?: string;
  apiType?: string;
  models?: Array<{ id?: string; name?: string; contextWindow?: number; maxTokens?: number }>;
  [key: string]: unknown;
}

function ProviderRow({ id, provider }: { id: string; provider: ProviderData }) {
  const maskedKey = useMemo(() => {
    const key = provider.apiKey ?? "";
    if (!key || key === "__OPENCLAW_REDACTED__") return "(redacted)";
    if (key.length <= 8) return "********";
    return key.slice(0, 4) + "****" + key.slice(-4);
  }, [provider.apiKey]);

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <div className="flex items-center gap-3 mb-3">
        <span className="text-sm font-semibold text-zinc-100">{id}</span>
        {provider.apiType && <Badge variant="muted">{provider.apiType}</Badge>}
      </div>

      <div className="grid grid-cols-1 gap-3">
        <div>
          <span className="text-xs text-zinc-500 mb-1 block">Base URL</span>
          <div className="rounded border border-zinc-700/50 bg-zinc-800/60 px-3 py-1.5 text-sm text-zinc-300 font-mono">
            {provider.baseUrl || "(not set)"}
          </div>
        </div>
        <div>
          <span className="text-xs text-zinc-500 mb-1 block">API Key</span>
          <div className="rounded border border-zinc-700/50 bg-zinc-800/60 px-3 py-1.5 text-sm text-zinc-400 font-mono">
            {maskedKey}
          </div>
        </div>
        {provider.models && provider.models.length > 0 && (
          <div>
            <span className="text-xs text-zinc-500 mb-1 block">Models</span>
            <div className="space-y-1">
              {provider.models.map((m, i) => (
                <div key={i} className="flex items-center gap-2 text-xs text-zinc-400">
                  <span className="font-mono text-zinc-300">{m.id ?? m.name}</span>
                  {m.contextWindow && (
                    <span className="text-zinc-600">ctx: {(m.contextWindow / 1000).toFixed(0)}k</span>
                  )}
                  {m.maxTokens && (
                    <span className="text-zinc-600">max: {(m.maxTokens / 1000).toFixed(0)}k</span>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Section 1: Providers (read-only)
// ---------------------------------------------------------------------------

function ProvidersSection({ config }: { config: Record<string, unknown> }) {
  const providers = useMemo(() => {
    const models = config.models as Record<string, unknown> | undefined;
    const raw = models?.providers as Record<string, ProviderData> | undefined;
    return raw ?? {};
  }, [config]);

  const ids = Object.keys(providers);

  if (ids.length === 0) {
    return (
      <section className="mb-8">
        <SectionHeading>Providers</SectionHeading>
        <p className="text-sm text-zinc-500">No providers configured.</p>
      </section>
    );
  }

  return (
    <section className="mb-8">
      <SectionHeading>Providers</SectionHeading>
      <div className="space-y-3">
        {ids.map((id) => (
          <ProviderRow key={id} id={id} provider={providers[id]} />
        ))}
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Section 2: Agent Models (read-only)
// ---------------------------------------------------------------------------

function AgentModelRow({ agent, isDefault, models, currentModelId }: {
  agent: Agent;
  isDefault: boolean;
  models: Model[];
  currentModelId: string;
}) {
  // Try exact match, then provider/model format, then just model name
  const modelInfo = models.find((m) => m.id === currentModelId)
    ?? models.find((m) => currentModelId === `${m.provider}/${m.id}`)
    ?? models.find((m) => currentModelId.endsWith(`/${m.id}`));
  const displayName = modelInfo
    ? `${modelInfo.name} (${modelInfo.provider})`
    : currentModelId || "not configured";

  return (
    <div className="flex items-center gap-4 rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3">
      <div className="min-w-[140px]">
        <span className="text-sm font-medium text-zinc-100">{agent.name ?? agent.id}</span>
        {isDefault && (
          <span className="ml-2 text-[10px] uppercase tracking-wider text-emerald-500 font-semibold">default</span>
        )}
      </div>
      <div className="flex-1 rounded border border-zinc-700/50 bg-zinc-800/60 px-3 py-1.5 text-sm text-zinc-300 font-mono">
        {displayName}
      </div>
    </div>
  );
}

function AgentModelsSection() {
  const { data: agentData, isLoading: agentsLoading } = useAgents();
  const { data: modelsData, isLoading: modelsLoading } = useModels();
  const { data: configData } = useConfig();

  const agents = agentData?.agents ?? [];
  const defaultId = agentData?.defaultId ?? "";
  const models = modelsData?.models ?? [];

  // Extract agent model assignments from the config
  // Config structure: agents.defaults.model.primary + agents.list[].model.primary
  const { agentModelMap, defaultModel } = useMemo(() => {
    const parsed = configData?.parsed ?? configData?.raw ?? {};
    const agentsCfg = parsed.agents as Record<string, unknown> | undefined;

    // Default model from agents.defaults.model.primary
    const defaults = agentsCfg?.defaults as Record<string, unknown> | undefined;
    const defaultModelCfg = defaults?.model as Record<string, unknown> | undefined;
    const defaultModel = (defaultModelCfg?.primary as string) ?? "";

    // Per-agent models from agents.list[]
    const list = agentsCfg?.list as Array<Record<string, unknown>> | undefined;
    const map = new Map<string, string>();
    if (list) {
      for (const entry of list) {
        const id = entry.id as string;
        const modelCfg = entry.model as Record<string, unknown> | undefined;
        const primary = modelCfg?.primary as string | undefined;
        if (id && primary) {
          map.set(id, primary);
        }
      }
    }
    return { agentModelMap: map, defaultModel };
  }, [configData]);

  if (agentsLoading || modelsLoading) return <Spinner />;

  return (
    <section className="mb-8">
      <SectionHeading>Agent Models</SectionHeading>
      {agents.length === 0 ? (
        <p className="text-sm text-zinc-500">No agents configured.</p>
      ) : (
        <div className="space-y-2">
          {agents.map((agent) => {
            const currentModel = agentModelMap.get(agent.id) ?? defaultModel;

            return (
              <AgentModelRow
                key={agent.id}
                agent={agent}
                isDefault={agent.id === defaultId}
                models={models}
                currentModelId={currentModel}
              />
            );
          })}
        </div>
      )}
    </section>
  );
}

// ---------------------------------------------------------------------------
// Section 3: General Info
// ---------------------------------------------------------------------------

function InfoRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between py-2 border-b border-zinc-800/50 last:border-b-0">
      <span className="text-sm text-zinc-400">{label}</span>
      <span className="text-sm text-zinc-200 font-mono">{value ?? <span className="text-zinc-600">--</span>}</span>
    </div>
  );
}

function GeneralInfoSection({ config }: { config: Record<string, unknown> }) {
  const gateway = config.gateway as Record<string, unknown> | undefined;
  const logging = config.logging as Record<string, unknown> | undefined;
  const sandbox = config.sandbox as Record<string, unknown> | undefined;

  return (
    <section className="mb-8">
      <SectionHeading>General Info</SectionHeading>
      <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
        <h3 className="text-xs uppercase tracking-wider text-zinc-500 font-semibold mb-2">Gateway</h3>
        <InfoRow label="Port" value={String(gateway?.port ?? gateway?.wsPort ?? "--")} />
        <InfoRow label="Host" value={String(gateway?.host ?? "0.0.0.0")} />

        <h3 className="text-xs uppercase tracking-wider text-zinc-500 font-semibold mt-4 mb-2">Logging</h3>
        <InfoRow label="Level" value={String(logging?.level ?? "info")} />
        <InfoRow label="File" value={String(logging?.file ?? "--")} />

        <h3 className="text-xs uppercase tracking-wider text-zinc-500 font-semibold mt-4 mb-2">Sandbox</h3>
        {sandbox ? (
          <>
            <InfoRow label="Scope" value={String((sandbox as Record<string, unknown>).scope ?? "--")} />
            <InfoRow label="Image" value={String((sandbox.docker as Record<string, unknown> | undefined)?.image ?? "--")} />
            <InfoRow label="Network" value={String((sandbox.docker as Record<string, unknown> | undefined)?.network ?? "--")} />
          </>
        ) : (
          <p className="text-sm text-zinc-500">No sandbox configured.</p>
        )}
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function SettingsPage() {
  const { data, isLoading, error } = useConfig();

  const configObj = useMemo(() => {
    if (!data) return null;
    return (data.parsed ?? data.raw ?? data.config ?? null) as Record<string, unknown> | null;
  }, [data]);

  return (
    <div className="p-6 max-w-4xl">
      <h1 className="text-2xl font-semibold text-zinc-100 mb-1">Settings</h1>
      <p className="text-sm text-zinc-500 mb-4">
        Configuration overview
        {data?.path && (
          <span className="ml-2 text-zinc-600 font-mono text-xs">({data.path})</span>
        )}
      </p>

      <div className="rounded-lg border border-amber-800/40 bg-amber-950/20 px-4 py-3 text-sm text-amber-300/90 mb-6 flex items-start gap-2.5">
        <svg className="h-4 w-4 shrink-0 mt-0.5 text-amber-500/70" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
        </svg>
        <span>
          Configuration is read-only. To modify settings, edit{" "}
          <code className="text-amber-200 bg-amber-900/30 px-1 py-0.5 rounded text-xs">/etc/openclaw/openclaw.json</code>{" "}
          and restart the gateway.
        </span>
      </div>

      {isLoading && <Spinner />}
      {error && <ErrorBox message={error instanceof Error ? error.message : "Failed to load config"} />}

      {configObj && (
        <>
          <ProvidersSection config={configObj} />
          <AgentModelsSection />
          <GeneralInfoSection config={configObj} />
        </>
      )}
    </div>
  );
}
