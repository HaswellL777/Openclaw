import { useState, useMemo, useCallback } from "react";
import { useConfig, useModels, useAgents, useGatewayStore } from "@/api/hooks";
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
      Loading…
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

function SaveFeedback({ status }: { status: "idle" | "saving" | "saved" | "error" }) {
  if (status === "idle") return null;
  if (status === "saving") return <span className="text-xs text-amber-400">Saving…</span>;
  if (status === "saved") return <span className="text-xs text-emerald-400">Saved ✓</span>;
  return <span className="text-xs text-red-400">Save failed</span>;
}

// ---------------------------------------------------------------------------
// Provider row
// ---------------------------------------------------------------------------

interface ProviderData {
  baseUrl?: string;
  apiKey?: string;
  apiType?: string;
  [key: string]: unknown;
}

interface ProviderRowProps {
  id: string;
  provider: ProviderData;
  onSave: (id: string, changes: Partial<ProviderData>) => Promise<void>;
}

function ProviderRow({ id, provider, onSave }: ProviderRowProps) {
  const [baseUrl, setBaseUrl] = useState(provider.baseUrl ?? "");
  const [showKey, setShowKey] = useState(false);
  const [saveStatus, setSaveStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");

  const maskedKey = useMemo(() => {
    const key = provider.apiKey ?? "";
    if (!key) return "(not set)";
    if (key.length <= 8) return "••••••••";
    return key.slice(0, 4) + "••••" + key.slice(-4);
  }, [provider.apiKey]);

  const dirty = baseUrl !== (provider.baseUrl ?? "");

  const handleSave = useCallback(async () => {
    if (!dirty) return;
    setSaveStatus("saving");
    try {
      await onSave(id, { baseUrl });
      setSaveStatus("saved");
      setTimeout(() => setSaveStatus("idle"), 2000);
    } catch {
      setSaveStatus("error");
      setTimeout(() => setSaveStatus("idle"), 3000);
    }
  }, [dirty, id, baseUrl, onSave]);

  return (
    <div className="rounded-lg border border-zinc-800 bg-zinc-900 p-4">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-3">
          <span className="text-sm font-semibold text-zinc-100">{id}</span>
          {provider.apiType && <Badge variant="muted">{provider.apiType}</Badge>}
        </div>
        <div className="flex items-center gap-2">
          <SaveFeedback status={saveStatus} />
          <button
            disabled={!dirty || saveStatus === "saving"}
            onClick={handleSave}
            className="rounded px-3 py-1 text-xs font-medium transition-colors
              bg-emerald-700 hover:bg-emerald-600 text-white
              disabled:bg-zinc-700 disabled:text-zinc-500 disabled:cursor-not-allowed"
          >
            Save
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3">
        {/* Base URL */}
        <label className="block">
          <span className="text-xs text-zinc-400 mb-1 block">Base URL</span>
          <input
            type="text"
            value={baseUrl}
            onChange={(e) => setBaseUrl(e.target.value)}
            placeholder="https://api.example.com/v1"
            className="w-full rounded border border-zinc-700 bg-zinc-800 px-3 py-1.5 text-sm text-zinc-100
              placeholder:text-zinc-600 focus:border-zinc-500 focus:outline-none focus:ring-1 focus:ring-zinc-500"
          />
        </label>

        {/* API Key */}
        <label className="block">
          <span className="text-xs text-zinc-400 mb-1 block">API Key</span>
          <div className="flex items-center gap-2">
            <div className="flex-1 rounded border border-zinc-700 bg-zinc-800/60 px-3 py-1.5 text-sm text-zinc-400 font-mono">
              {showKey ? (provider.apiKey ?? "(not set)") : maskedKey}
            </div>
            <button
              onClick={() => setShowKey((v) => !v)}
              className="rounded border border-zinc-700 bg-zinc-800 px-2 py-1.5 text-xs text-zinc-400
                hover:bg-zinc-700 hover:text-zinc-200 transition-colors"
              title={showKey ? "Hide key" : "Show key"}
            >
              {showKey ? "Hide" : "Show"}
            </button>
          </div>
        </label>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Section 1: Providers
// ---------------------------------------------------------------------------

function ProvidersSection({ config }: { config: Record<string, unknown> }) {
  const client = useGatewayStore((s) => s.client);

  const providers = useMemo(() => {
    const models = config.models as Record<string, unknown> | undefined;
    const raw = models?.providers as Record<string, ProviderData> | undefined;
    return raw ?? {};
  }, [config]);

  const ids = Object.keys(providers);

  const handleSave = useCallback(async (id: string, changes: Partial<ProviderData>) => {
    if (!client) throw new Error("Not connected");
    await client.call("config.patch", {
      patch: { models: { providers: { [id]: changes } } },
    });
  }, [client]);

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
          <ProviderRow key={id} id={id} provider={providers[id]} onSave={handleSave} />
        ))}
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Section 2: Agent Models
// ---------------------------------------------------------------------------

interface AgentModelRowProps {
  agent: Agent;
  models: Model[];
  onSave: (agentId: string, modelId: string) => Promise<void>;
}

function AgentModelRow({ agent, models, onSave }: AgentModelRowProps) {
  const currentModel = agent.model?.primary ?? "";
  const [selected, setSelected] = useState(currentModel);
  const [saveStatus, setSaveStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const dirty = selected !== currentModel;

  const handleSave = useCallback(async () => {
    if (!dirty) return;
    setSaveStatus("saving");
    try {
      await onSave(agent.id, selected);
      setSaveStatus("saved");
      setTimeout(() => setSaveStatus("idle"), 2000);
    } catch {
      setSaveStatus("error");
      setTimeout(() => setSaveStatus("idle"), 3000);
    }
  }, [dirty, agent.id, selected, onSave]);

  return (
    <div className="flex items-center gap-4 rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3">
      <div className="min-w-[140px]">
        <span className="text-sm font-medium text-zinc-100">{agent.name ?? agent.id}</span>
        {agent.default && (
          <span className="ml-2 text-[10px] uppercase tracking-wider text-emerald-500 font-semibold">default</span>
        )}
      </div>

      <select
        value={selected}
        onChange={(e) => setSelected(e.target.value)}
        className="flex-1 rounded border border-zinc-700 bg-zinc-800 px-3 py-1.5 text-sm text-zinc-200
          focus:border-zinc-500 focus:outline-none focus:ring-1 focus:ring-zinc-500"
      >
        {/* Keep the current value as an option even if not in the models list */}
        {currentModel && !models.some((m) => m.id === currentModel) && (
          <option value={currentModel}>{currentModel}</option>
        )}
        {models.map((m) => (
          <option key={m.id} value={m.id}>
            {m.name} ({m.provider}){m.reasoning ? " · reasoning" : ""}
          </option>
        ))}
      </select>

      <div className="flex items-center gap-2 min-w-[100px] justify-end">
        <SaveFeedback status={saveStatus} />
        <button
          disabled={!dirty || saveStatus === "saving"}
          onClick={handleSave}
          className="rounded px-3 py-1 text-xs font-medium transition-colors
            bg-emerald-700 hover:bg-emerald-600 text-white
            disabled:bg-zinc-700 disabled:text-zinc-500 disabled:cursor-not-allowed"
        >
          Save
        </button>
      </div>
    </div>
  );
}

function AgentModelsSection() {
  const { data: agentData, isLoading: agentsLoading } = useAgents();
  const { data: modelsData, isLoading: modelsLoading } = useModels();
  const client = useGatewayStore((s) => s.client);

  const agents = agentData?.agents ?? [];
  const models = modelsData?.models ?? [];

  const handleSave = useCallback(async (agentId: string, modelId: string) => {
    if (!client) throw new Error("Not connected");
    await client.call("config.patch", {
      patch: { agents: { [agentId]: { model: { primary: modelId } } } },
    });
  }, [client]);

  if (agentsLoading || modelsLoading) return <Spinner />;

  return (
    <section className="mb-8">
      <SectionHeading>Agent Models</SectionHeading>
      {agents.length === 0 ? (
        <p className="text-sm text-zinc-500">No agents configured.</p>
      ) : (
        <div className="space-y-2">
          {agents.map((agent) => (
            <AgentModelRow
              key={agent.id}
              agent={agent}
              models={models}
              onSave={handleSave}
            />
          ))}
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
      <span className="text-sm text-zinc-200 font-mono">{value ?? <span className="text-zinc-600">—</span>}</span>
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
        <InfoRow label="Port" value={String(gateway?.port ?? gateway?.wsPort ?? "—")} />
        <InfoRow label="Host" value={String(gateway?.host ?? "0.0.0.0")} />

        <h3 className="text-xs uppercase tracking-wider text-zinc-500 font-semibold mt-4 mb-2">Logging</h3>
        <InfoRow label="Level" value={String(logging?.level ?? "info")} />
        <InfoRow label="File" value={String(logging?.file ?? "—")} />

        <h3 className="text-xs uppercase tracking-wider text-zinc-500 font-semibold mt-4 mb-2">Sandbox</h3>
        {sandbox ? (
          <>
            <InfoRow label="Scope" value={String((sandbox as Record<string, unknown>).scope ?? "—")} />
            <InfoRow label="Image" value={String((sandbox.docker as Record<string, unknown> | undefined)?.image ?? "—")} />
            <InfoRow label="Network" value={String((sandbox.docker as Record<string, unknown> | undefined)?.network ?? "—")} />
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

  return (
    <div className="p-6 max-w-4xl">
      <h1 className="text-2xl font-semibold text-zinc-100 mb-1">Settings</h1>
      <p className="text-sm text-zinc-500 mb-6">Configuration management</p>

      {isLoading && <Spinner />}
      {error && <ErrorBox message={error instanceof Error ? error.message : "Failed to load config"} />}

      {data?.config && (
        <>
          <ProvidersSection config={data.config} />
          <AgentModelsSection />
          <GeneralInfoSection config={data.config} />
        </>
      )}
    </div>
  );
}
