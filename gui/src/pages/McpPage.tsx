import { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { useConfig, useAgents, useGatewayStore } from "@/api/hooks";
import { agentColor } from "@/api/agent-colors";
import { PrismLight as SyntaxHighlighter } from "react-syntax-highlighter";
import oneDark from "react-syntax-highlighter/dist/esm/styles/prism/one-dark";
import jsonLang from "react-syntax-highlighter/dist/esm/languages/prism/json";
import {
  PageHeader, Card, CardHeader, CardBody,
  Spinner, EmptyState, Badge, SectionLabel,
} from "@/components/shared";

SyntaxHighlighter.registerLanguage("json", jsonLang);

// Sensitive env var keys to redact
const SENSITIVE_KEYS = /key|secret|token|password|api_key/i;

export default function McpPage() {
  const { data: config, isLoading: configLoading } = useConfig();
  const { data: agentData } = useAgents();
  const client = useGatewayStore(s => s.client);
  const connected = useGatewayStore(s => s.connectionState === "connected");

  const [selectedAgent, setSelectedAgent] = useState<string>("");
  const [showRaw, setShowRaw] = useState(false);
  const agents = agentData?.agents ?? [];

  // Extract MCP servers from config
  const mcpServers = useMemo(() => {
    if (!config) return {};
    // Check multiple possible locations — config.get returns different views
    const c = config as any;
    return c.resolved?.mcp?.servers
      ?? c.parsed?.mcp?.servers
      ?? c.config?.mcp?.servers
      ?? {};
  }, [config]);

  const serverEntries = Object.entries(mcpServers) as [string, any][];

  // MCP raw config for syntax highlight
  const mcpRaw = useMemo(() => {
    if (!config) return "";
    const c = config as any;
    const mcp = c.resolved?.mcp ?? c.parsed?.mcp ?? c.config?.mcp;
    return mcp ? JSON.stringify(mcp, null, 2) : "";
  }, [config]);

  // Tools catalog for selected agent
  if (!selectedAgent && agents.length > 0) setSelectedAgent(agents[0].id);
  const { data: toolsData } = useQuery<any>({
    queryKey: ["tools.catalog", selectedAgent],
    queryFn: () => client!.call("tools.catalog", { agentId: selectedAgent }),
    enabled: connected && !!client && !!selectedAgent,
    staleTime: 60_000,
  });

  const toolGroups = (toolsData?.groups ?? []) as any[];

  return (
    <div className="p-6 h-full overflow-y-auto">
      <PageHeader title="MCP Servers" subtitle="Model Context Protocol server configuration and tools" />

      {/* Info banner */}
      <div className="rounded-xl border border-blue-800/30 bg-blue-950/20 px-4 py-3 text-sm text-blue-300 mb-6 flex items-start gap-2.5">
        <svg className="w-4 h-4 shrink-0 mt-0.5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
        </svg>
        <div>
          <div className="font-semibold mb-0.5">Read-only view</div>
          <div className="text-blue-300/70 text-xs">MCP server configuration is managed via the config file. Gateway does not have write access (EROFS).</div>
        </div>
      </div>

      {/* MCP Servers */}
      <SectionLabel>Configured Servers</SectionLabel>
      {configLoading ? <Spinner text="Loading..." /> :
       serverEntries.length === 0 ? (
        <Card className="mb-6"><CardBody><EmptyState message="No MCP servers configured" /></CardBody></Card>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
          {serverEntries.map(([name, server]) => (
            <Card key={name}>
              <CardHeader title={name}>
                <Badge variant={server.enabled !== false ? "emerald" : "muted"}>
                  {server.enabled !== false ? "enabled" : "disabled"}
                </Badge>
              </CardHeader>
              <CardBody>
                <div className="space-y-2 text-xs">
                  {server.command && (
                    <div>
                      <span className="text-zinc-500">Command: </span>
                      <code className="text-amber-300 bg-zinc-800 px-1.5 py-0.5 rounded font-mono">{server.command}</code>
                    </div>
                  )}
                  {server.url && (
                    <div>
                      <span className="text-zinc-500">URL: </span>
                      <span className="text-zinc-300 font-mono">{server.url}</span>
                    </div>
                  )}
                  {server.args?.length > 0 && (
                    <div>
                      <span className="text-zinc-500">Args: </span>
                      <div className="flex flex-wrap gap-1 mt-0.5">
                        {server.args.map((arg: string, i: number) => (
                          <span key={i} className="px-1.5 py-0.5 bg-zinc-800 text-zinc-400 rounded text-[10px] font-mono">{arg}</span>
                        ))}
                      </div>
                    </div>
                  )}
                  {server.env && Object.keys(server.env).length > 0 && (
                    <div>
                      <span className="text-zinc-500">Environment: </span>
                      <div className="mt-0.5 space-y-0.5">
                        {Object.entries(server.env).map(([k, v]) => (
                          <div key={k} className="flex items-center gap-1.5 text-[10px] font-mono">
                            <span className="text-zinc-400">{k}=</span>
                            <span className="text-zinc-600">
                              {SENSITIVE_KEYS.test(k) ? "***" : String(v).slice(0, 50)}
                            </span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </CardBody>
            </Card>
          ))}
        </div>
      )}

      {/* Tools from catalog */}
      <SectionLabel>Tools Catalog</SectionLabel>
      <Card className="mb-6">
        <CardHeader title="Agent Tools">
          <select value={selectedAgent} onChange={e => setSelectedAgent(e.target.value)}
            className="bg-zinc-800 border border-zinc-700/50 rounded px-2 py-1 text-[11px] text-zinc-300">
            {agents.map(a => <option key={a.id} value={a.id}>{a.id}</option>)}
          </select>
        </CardHeader>
        <CardBody>
          {toolGroups.length === 0 ? <EmptyState message="No tools found" /> : (
            <div className="space-y-3">
              {toolGroups.map((g: any) => (
                <div key={g.label}>
                  <div className="text-[10px] text-zinc-500 font-semibold mb-1">{g.label}</div>
                  <div className="flex flex-wrap gap-1">
                    {(g.tools ?? []).map((t: any) => (
                      <Badge key={t.id} variant="muted">{t.label ?? t.id}</Badge>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardBody>
      </Card>

      {/* Raw config */}
      {mcpRaw && (
        <Card>
          <CardHeader title="Raw MCP Configuration">
            <button onClick={() => setShowRaw(!showRaw)} className="text-[10px] text-zinc-500 hover:text-zinc-300">
              {showRaw ? "Collapse" : "Expand"}
            </button>
          </CardHeader>
          {showRaw && (
            <CardBody className="p-0">
              <SyntaxHighlighter language="json" style={oneDark}
                customStyle={{ margin: 0, padding: "12px", background: "transparent", fontSize: "11px", lineHeight: "1.5" }}
                codeTagProps={{ style: { fontFamily: "'IBM Plex Mono', monospace" } }}
              >{mcpRaw}</SyntaxHighlighter>
            </CardBody>
          )}
        </Card>
      )}
    </div>
  );
}
