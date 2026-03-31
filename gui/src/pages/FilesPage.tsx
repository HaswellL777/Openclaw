import { useState, useMemo, useCallback } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useAgents, useGatewayStore } from "@/api/hooks";
import { agentColor } from "@/api/agent-colors";
import { PrismLight as SyntaxHighlighter } from "react-syntax-highlighter";
import oneDark from "react-syntax-highlighter/dist/esm/styles/prism/one-dark";
import {
  PageHeader, Card, CardHeader, CardBody,
  Spinner, EmptyState, Badge,
} from "@/components/shared";

// Language mapping by extension
const EXT_LANG: Record<string, string> = {
  json: "json", json5: "json", jsonc: "json",
  ts: "typescript", tsx: "tsx", js: "javascript", jsx: "jsx",
  py: "python", sh: "bash", bash: "bash",
  md: "markdown", yaml: "yaml", yml: "yaml",
  css: "css", html: "markup", xml: "markup",
};

function langFromName(name: string): string {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  return EXT_LANG[ext] ?? "text";
}

function formatSize(bytes?: number): string {
  if (bytes == null) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export default function FilesPage() {
  const { data: agentData } = useAgents();
  const client = useGatewayStore(s => s.client);
  const connected = useGatewayStore(s => s.connectionState === "connected");
  const queryClient = useQueryClient();

  const agents = agentData?.agents ?? [];
  const [selectedAgent, setSelectedAgent] = useState<string>("");
  const [selectedFile, setSelectedFile] = useState<string>("");
  const [editing, setEditing] = useState(false);
  const [editContent, setEditContent] = useState("");
  const [saving, setSaving] = useState(false);

  // Auto-select first agent
  if (!selectedAgent && agents.length > 0) setSelectedAgent(agents[0].id);

  const { data: filesData, isLoading: filesLoading } = useQuery<any>({
    queryKey: ["agents.files.list", selectedAgent],
    queryFn: () => client!.call("agents.files.list", { agentId: selectedAgent }),
    enabled: connected && !!client && !!selectedAgent,
    staleTime: 15_000,
  });

  const files = (filesData?.files ?? []) as any[];

  const { data: fileData, isLoading: fileLoading } = useQuery<any>({
    queryKey: ["agents.files.get", selectedAgent, selectedFile],
    queryFn: () => client!.call("agents.files.get", { agentId: selectedAgent, name: selectedFile }),
    enabled: connected && !!client && !!selectedAgent && !!selectedFile,
    staleTime: 10_000,
  });

  const fileContent = fileData?.file?.content ?? "";
  const fileMeta = fileData?.file;

  const handleSave = useCallback(async () => {
    if (!client || !selectedAgent || !selectedFile) return;
    setSaving(true);
    try {
      await client.call("agents.files.set", { agentId: selectedAgent, name: selectedFile, content: editContent });
      setEditing(false);
      queryClient.invalidateQueries({ queryKey: ["agents.files.get", selectedAgent, selectedFile] });
      queryClient.invalidateQueries({ queryKey: ["agents.files.list", selectedAgent] });
    } catch (err: any) {
      alert("Save failed: " + (err?.message ?? "unknown error"));
    } finally {
      setSaving(false);
    }
  }, [client, selectedAgent, selectedFile, editContent, queryClient]);

  return (
    <div className="flex h-full">
      {/* Left sidebar: agent selector + file list */}
      <div className="w-[260px] shrink-0 border-r border-zinc-800 bg-zinc-900 flex flex-col">
        <div className="px-3 py-3 border-b border-zinc-800">
          <div className="text-sm font-bold text-zinc-100 mb-2">Workspace Files</div>
          <select
            value={selectedAgent}
            onChange={e => { setSelectedAgent(e.target.value); setSelectedFile(""); setEditing(false); }}
            className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-2 py-1.5 text-sm text-zinc-200"
          >
            {agents.map(a => {
              const c = agentColor(a.id);
              return <option key={a.id} value={a.id}>{a.id}</option>;
            })}
          </select>
          {filesData?.workspace && (
            <div className="text-[9px] text-zinc-600 font-mono mt-1 truncate">{filesData.workspace}</div>
          )}
        </div>
        <div className="flex-1 overflow-y-auto">
          {filesLoading ? <Spinner text="Loading files..." /> :
           files.length === 0 ? <div className="p-3"><EmptyState message="No files" /></div> :
           files.map((f: any) => (
            <button
              key={f.name}
              onClick={() => { setSelectedFile(f.name); setEditing(false); }}
              className={`w-full text-left px-3 py-2 flex items-center gap-2 text-[11px] border-b border-zinc-800/30 transition-colors ${
                selectedFile === f.name ? "bg-zinc-800" : "hover:bg-zinc-800/40"
              }`}
            >
              <span className={`truncate flex-1 ${selectedFile === f.name ? "text-zinc-100 font-medium" : "text-zinc-400"}`}>
                {f.name}
              </span>
              {f.size != null && <span className="text-[9px] text-zinc-600 tabular-nums shrink-0">{formatSize(f.size)}</span>}
            </button>
          ))}
        </div>
      </div>

      {/* Right panel: file viewer/editor */}
      <div className="flex-1 flex flex-col bg-zinc-950">
        {!selectedFile ? (
          <div className="flex-1 flex items-center justify-center">
            <EmptyState message="Select a file to view" />
          </div>
        ) : (
          <>
            {/* File header */}
            <div className="px-4 py-2.5 border-b border-zinc-800 bg-zinc-900 flex items-center gap-3">
              <span className="text-sm font-bold text-zinc-100">{selectedFile}</span>
              <Badge variant="muted">{langFromName(selectedFile)}</Badge>
              {fileMeta?.size != null && <span className="text-[10px] text-zinc-500">{formatSize(fileMeta.size)}</span>}
              {fileMeta?.updatedAtMs && (
                <span className="text-[10px] text-zinc-600 tabular-nums">
                  {new Date(fileMeta.updatedAtMs).toLocaleString("zh-CN")}
                </span>
              )}
              <div className="ml-auto flex items-center gap-2">
                {editing ? (
                  <>
                    <button onClick={handleSave} disabled={saving}
                      className="px-2.5 py-1 text-[10px] bg-emerald-600/20 text-emerald-400 rounded hover:bg-emerald-600/30 font-medium">
                      {saving ? "Saving..." : "Save"}
                    </button>
                    <button onClick={() => setEditing(false)}
                      className="px-2.5 py-1 text-[10px] bg-zinc-700 text-zinc-400 rounded hover:bg-zinc-600">
                      Cancel
                    </button>
                  </>
                ) : (
                  <button onClick={() => { setEditing(true); setEditContent(fileContent); }}
                    className="px-2.5 py-1 text-[10px] bg-indigo-600/20 text-indigo-400 rounded hover:bg-indigo-600/30">
                    Edit
                  </button>
                )}
              </div>
            </div>

            {/* File content */}
            <div className="flex-1 overflow-auto">
              {fileLoading ? <Spinner text="Loading file..." /> : editing ? (
                <textarea
                  value={editContent}
                  onChange={e => setEditContent(e.target.value)}
                  className="w-full h-full bg-zinc-950 text-zinc-300 font-mono text-xs p-4 resize-none focus:outline-none"
                  spellCheck={false}
                />
              ) : (
                <SyntaxHighlighter
                  language={langFromName(selectedFile)}
                  style={oneDark}
                  showLineNumbers
                  customStyle={{ margin: 0, padding: "16px", background: "transparent", fontSize: "12px", lineHeight: "1.6", minHeight: "100%" }}
                  codeTagProps={{ style: { fontFamily: "'IBM Plex Mono', monospace" } }}
                >
                  {fileContent || "(empty file)"}
                </SyntaxHighlighter>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
