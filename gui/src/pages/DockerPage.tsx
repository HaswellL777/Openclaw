import { useState, useCallback } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  PageHeader,
  Card,
  CardHeader,
  CardBody,
  StatusDot,
  Spinner,
  ErrorBox,
  Badge,
  EmptyState,
  SectionLabel,
} from "@/components/shared";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Container {
  id: string;
  name: string;
  image: string;
  status: string;
  state: string;
  ports: string;
  created: string;
  workDir: string;
}

interface DockerImage {
  id: string;
  repository: string;
  tag: string;
  size: string;
  created: string;
}

interface DockerNetwork {
  id: string;
  name: string;
  driver: string;
  scope: string;
}

interface FileEntry {
  name: string;
  perms: string;
  size: string;
  date: string;
  isDir: boolean;
  isLink: boolean;
}

interface ContainerInspect {
  id: string;
  name: string;
  image: string;
  workDir: string;
  user: string;
  cmd: string[];
  entrypoint: string[];
  env: string[];
  created: string;
  startedAt: string;
  state: string;
  pid: number;
  restartCount: number;
  mounts: Array<{ source: string; destination: string; mode: string; rw: boolean; type: string }>;
  networks: string[];
  readonlyRoot: boolean;
  memory: number;
  cpus: number;
}

// ---------------------------------------------------------------------------
// Data hooks
// ---------------------------------------------------------------------------

function useContainers() {
  return useQuery<{ containers: Container[]; error?: string }>({
    queryKey: ["docker", "containers"],
    queryFn: () => fetch("/api/docker/containers").then((r) => r.json()),
    staleTime: 5_000,
    refetchInterval: 10_000,
  });
}

function useImages() {
  return useQuery<{ images: DockerImage[] }>({
    queryKey: ["docker", "images"],
    queryFn: () => fetch("/api/docker/images").then((r) => r.json()),
    staleTime: 60_000,
  });
}

function useNetworks() {
  return useQuery<{ networks: DockerNetwork[] }>({
    queryKey: ["docker", "networks"],
    queryFn: () => fetch("/api/docker/networks").then((r) => r.json()),
    staleTime: 60_000,
  });
}

// ---------------------------------------------------------------------------
// Container row
// ---------------------------------------------------------------------------

function ContainerRow({
  container,
  onAction,
  onInspect,
  onBrowseFiles,
  acting,
}: {
  container: Container;
  onAction: (action: string, id: string) => void;
  onInspect: (id: string, name: string) => void;
  onBrowseFiles: (id: string, name: string, workDir: string) => void;
  acting: string | null;
}) {
  const isRunning = container.state === "running";

  return (
    <div className="flex items-center gap-3 rounded-lg border border-zinc-800 bg-zinc-950/50 px-4 py-3">
      <StatusDot status={isRunning ? "running" : "stopped"} size="sm" />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-zinc-100 truncate">{container.name}</span>
          <Badge variant={isRunning ? "emerald" : "muted"}>{container.state}</Badge>
        </div>
        <div className="text-xs text-zinc-500 mt-0.5 flex items-center gap-3">
          <span className="font-mono">{container.image}</span>
          <span className="text-zinc-600">{container.status}</span>
        </div>
      </div>
      <div className="flex gap-1.5 shrink-0">
        {isRunning && (
          <button
            onClick={() => onBrowseFiles(container.id, container.name, container.workDir)}
            className="px-2 py-1 text-xs bg-indigo-600/20 text-indigo-400 rounded-lg hover:bg-indigo-600/30 transition-colors"
          >
            Files
          </button>
        )}
        <button
          onClick={() => onInspect(container.id, container.name)}
          className="px-2 py-1 text-xs bg-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-600 transition-colors"
        >
          Inspect
        </button>
        {isRunning ? (
          <>
            <button
              onClick={() => onAction("restart", container.id)}
              disabled={acting === container.id}
              className="px-2 py-1 text-xs bg-amber-600/20 text-amber-400 rounded-lg hover:bg-amber-600/30 transition-colors disabled:opacity-50"
            >
              Restart
            </button>
            <button
              onClick={() => onAction("stop", container.id)}
              disabled={acting === container.id}
              className="px-2 py-1 text-xs bg-red-600/20 text-red-400 rounded-lg hover:bg-red-600/30 transition-colors disabled:opacity-50"
            >
              Stop
            </button>
          </>
        ) : (
          <button
            onClick={() => onAction("start", container.id)}
            disabled={acting === container.id}
            className="px-2 py-1 text-xs bg-emerald-600/20 text-emerald-400 rounded-lg hover:bg-emerald-600/30 transition-colors disabled:opacity-50"
          >
            Start
          </button>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Inspect modal
// ---------------------------------------------------------------------------

function InspectModal({ containerId, containerName, onClose }: {
  containerId: string;
  containerName: string;
  onClose: () => void;
}) {
  const { data, isLoading, error } = useQuery<ContainerInspect & { error?: string }>({
    queryKey: ["docker", "inspect", containerId],
    queryFn: () => fetch(`/api/docker/inspect?id=${containerId}`).then((r) => r.json()),
    staleTime: 10_000,
  });

  function InfoRow({ label, value }: { label: string; value: React.ReactNode }) {
    return (
      <div className="flex items-baseline justify-between py-1.5 border-b border-zinc-800/50 last:border-b-0">
        <span className="text-xs text-zinc-500">{label}</span>
        <span className="text-xs text-zinc-200 font-mono text-right max-w-[60%] truncate">{value ?? "--"}</span>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm" onClick={onClose}>
      <div className="w-[600px] max-h-[80vh] flex flex-col rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800 shrink-0">
          <span className="text-sm font-semibold text-zinc-100">{containerName}</span>
          <button onClick={onClose} className="px-2.5 py-1 text-xs bg-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-600 transition-colors">Close</button>
        </div>
        <div className="flex-1 overflow-y-auto p-4 space-y-4 min-h-0">
          {isLoading && <Spinner />}
          {(error || data?.error) && <ErrorBox message={data?.error ?? "Failed to inspect"} />}
          {data && !data.error && (
            <>
              <div>
                <SectionLabel>Container</SectionLabel>
                <div className="rounded-lg border border-zinc-800 bg-zinc-950/50 p-3">
                  <InfoRow label="ID" value={data.id} />
                  <InfoRow label="Image" value={data.image} />
                  <InfoRow label="State" value={data.state} />
                  <InfoRow label="PID" value={data.pid} />
                  <InfoRow label="Working Dir" value={data.workDir} />
                  <InfoRow label="User" value={data.user || "root"} />
                  <InfoRow label="Command" value={(data.cmd ?? []).join(" ")} />
                  <InfoRow label="Read-only Root" value={data.readonlyRoot ? "Yes" : "No"} />
                  <InfoRow label="Started" value={data.startedAt ? new Date(data.startedAt).toLocaleString() : "--"} />
                  <InfoRow label="Restarts" value={String(data.restartCount)} />
                  {data.cpus > 0 && <InfoRow label="CPU Limit" value={`${data.cpus} cores`} />}
                  {data.memory > 0 && <InfoRow label="Memory Limit" value={`${Math.round(data.memory / 1024 / 1024)}MB`} />}
                </div>
              </div>

              {data.mounts.length > 0 && (
                <div>
                  <SectionLabel>Mounts ({data.mounts.length})</SectionLabel>
                  <div className="space-y-1.5">
                    {data.mounts.map((m, i) => (
                      <div key={i} className="rounded-lg border border-zinc-800 bg-zinc-950/50 px-3 py-2">
                        <div className="flex items-center gap-2 text-xs font-mono">
                          <span className="text-zinc-400 truncate">{m.source}</span>
                          <span className="text-zinc-600 shrink-0">&rarr;</span>
                          <span className="text-zinc-200 truncate">{m.destination}</span>
                        </div>
                        <div className="flex gap-2 mt-1">
                          <Badge variant="muted">{m.type}</Badge>
                          <Badge variant={m.rw ? "emerald" : "amber"}>{m.rw ? "rw" : "ro"}</Badge>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {data.networks.length > 0 && (
                <div>
                  <SectionLabel>Networks</SectionLabel>
                  <div className="flex gap-2">
                    {data.networks.map((n) => <Badge key={n} variant="cyan">{n}</Badge>)}
                  </div>
                </div>
              )}

              {data.env.length > 0 && (
                <div>
                  <SectionLabel>Environment</SectionLabel>
                  <div className="rounded-lg border border-zinc-800 bg-zinc-950/50 p-3 space-y-0.5">
                    {data.env.map((e, i) => {
                      const [k, ...v] = e.split("=");
                      return (
                        <div key={i} className="text-xs font-mono">
                          <span className="text-zinc-500">{k}</span>
                          <span className="text-zinc-700">=</span>
                          <span className="text-zinc-300">{v.join("=")}</span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// File browser modal — with quick-nav shortcuts
// ---------------------------------------------------------------------------

/** Well-known directories in OpenClaw sandbox containers */
const QUICK_NAV = [
  { label: "Workspace", path: "/workspace" },
  { label: "Skills", path: "/workspace/skills" },
  { label: "Control", path: "/workspace/control" },
  { label: "Tasks", path: "/workspace/tasks" },
  { label: "Knowledge", path: "/workspace/knowledge" },
  { label: "Outputs", path: "/workspace/outputs" },
  { label: "Root /", path: "/" },
];

function FileBrowser({
  containerId,
  containerName,
  initialPath,
  onClose,
}: {
  containerId: string;
  containerName: string;
  initialPath: string;
  onClose: () => void;
}) {
  const [currentPath, setCurrentPath] = useState(initialPath || "/workspace");
  const [viewingFile, setViewingFile] = useState<string | null>(null);
  const [pathError, setPathError] = useState<string | null>(null);

  const { data: dirData, isLoading: dirLoading, error: dirError } = useQuery<{
    path: string;
    entries: FileEntry[];
    error?: string;
  }>({
    queryKey: ["docker", "files", containerId, currentPath],
    queryFn: () =>
      fetch(`/api/docker/files?id=${containerId}&path=${encodeURIComponent(currentPath)}`).then((r) => r.json()),
    staleTime: 5_000,
  });

  // Clear pathError when directory loads successfully
  const dirHasError = !!(dirError || dirData?.error);
  if (!dirLoading && !dirHasError && pathError) setPathError(null);

  const { data: fileData, isLoading: fileLoading } = useQuery<{
    path: string;
    content: string;
    size: number;
    error?: string;
  }>({
    queryKey: ["docker", "cat", containerId, viewingFile],
    queryFn: () =>
      fetch(`/api/docker/cat?id=${containerId}&path=${encodeURIComponent(viewingFile!)}`).then((r) => r.json()),
    enabled: !!viewingFile,
    staleTime: 10_000,
  });

  const navigateTo = (entry: FileEntry) => {
    if (entry.isDir) {
      const sep = currentPath === "/" ? "" : "/";
      setCurrentPath(`${currentPath}${sep}${entry.name}`);
      setViewingFile(null);
    } else {
      const sep = currentPath === "/" ? "" : "/";
      setViewingFile(`${currentPath}${sep}${entry.name}`);
    }
  };

  const goUp = () => {
    if (currentPath === "/") return;
    const parts = currentPath.split("/").filter(Boolean);
    parts.pop();
    setCurrentPath("/" + parts.join("/") || "/");
    setViewingFile(null);
  };

  const jumpTo = (path: string) => {
    setPathError(null);
    setCurrentPath(path);
    setViewingFile(null);
  };

  const breadcrumbs = currentPath.split("/").filter(Boolean);
  const entries = dirData?.entries ?? [];
  // Sort: dirs first, then files, alphabetical within each
  const sorted = [...entries].sort((a, b) => {
    if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
    return a.name.localeCompare(b.name);
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div className="w-[90vw] max-w-6xl h-[85vh] flex flex-col rounded-xl border border-zinc-700 bg-zinc-900 shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-2.5 border-b border-zinc-800 shrink-0">
          <div className="flex items-center gap-2 min-w-0 flex-1">
            <span className="text-sm font-semibold text-zinc-100 shrink-0">{containerName}</span>
            <span className="text-zinc-700 shrink-0">|</span>
            {/* Breadcrumb */}
            <div className="flex items-center gap-0.5 text-xs overflow-hidden">
              <button onClick={() => jumpTo("/")} className="text-indigo-400 hover:text-indigo-300 shrink-0">/</button>
              {breadcrumbs.map((part, i) => (
                <span key={i} className="flex items-center gap-0.5 shrink-0">
                  <span className="text-zinc-700">/</span>
                  <button
                    onClick={() => jumpTo("/" + breadcrumbs.slice(0, i + 1).join("/"))}
                    className="text-indigo-400 hover:text-indigo-300"
                  >{part}</button>
                </span>
              ))}
            </div>
          </div>
          <button onClick={onClose} className="px-2.5 py-1 text-xs bg-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-600 transition-colors shrink-0 ml-2">
            Close
          </button>
        </div>

        {/* Quick nav */}
        <div className="flex items-center gap-1.5 px-4 py-2 border-b border-zinc-800/50 bg-zinc-900/50 overflow-x-auto shrink-0">
          {QUICK_NAV.map((nav) => (
            <button
              key={nav.path}
              onClick={() => jumpTo(nav.path)}
              className={`px-2 py-0.5 text-[11px] rounded-md transition-colors shrink-0 ${
                currentPath === nav.path || currentPath.startsWith(nav.path + "/")
                  ? "bg-indigo-600/30 text-indigo-300"
                  : "bg-zinc-800 text-zinc-400 hover:bg-zinc-700 hover:text-zinc-300"
              }`}
            >{nav.label}</button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 flex min-h-0">
          {/* File list */}
          <div className={`${viewingFile ? "w-[340px] shrink-0 border-r border-zinc-800" : "flex-1"} flex flex-col min-h-0`}>
            <div className="flex-1 overflow-y-auto">
              {currentPath !== "/" && (
                <button
                  onClick={goUp}
                  className="w-full flex items-center gap-2.5 px-4 py-2 text-xs text-indigo-400 hover:bg-zinc-800/50 border-b border-zinc-800/30"
                >
                  <span className="text-sm leading-none">↑</span>
                  <span>..</span>
                </button>
              )}
              {dirLoading && <Spinner text="Loading..." />}
              {(dirError || dirData?.error) && (
                <div className="p-4 space-y-2">
                  <div className="flex items-center gap-2 text-xs text-amber-400">
                    <span>⚠</span>
                    <span>{dirData?.error ?? "Failed to list directory"}</span>
                  </div>
                  {currentPath !== "/" && (
                    <button
                      onClick={goUp}
                      className="px-2.5 py-1 text-xs bg-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-600 transition-colors"
                    >
                      Go to parent directory
                    </button>
                  )}
                </div>
              )}
              {sorted.map((entry) => (
                <button
                  key={entry.name}
                  onClick={() => navigateTo(entry)}
                  className={`w-full flex items-center gap-3 px-4 py-1.5 text-left hover:bg-zinc-800/50 border-b border-zinc-800/20 ${
                    viewingFile?.endsWith("/" + entry.name) ? "bg-zinc-800/70" : ""
                  }`}
                >
                  <span className="w-4 text-center text-sm leading-none shrink-0">
                    {entry.isDir ? "📁" : entry.isLink ? "🔗" : "📄"}
                  </span>
                  <span className={`text-sm truncate flex-1 ${entry.isDir ? "text-indigo-400 font-medium" : "text-zinc-300"}`}>
                    {entry.name}
                  </span>
                  {!entry.isDir && (
                    <span className="text-[10px] text-zinc-600 font-mono tabular-nums shrink-0">{entry.size}</span>
                  )}
                </button>
              ))}
              {!dirLoading && !dirData?.error && sorted.length === 0 && (
                <div className="p-4 text-xs text-zinc-600 text-center">(empty directory)</div>
              )}
            </div>
          </div>

          {/* File content viewer */}
          {viewingFile && (
            <div className="flex-1 flex flex-col min-w-0">
              <div className="flex items-center justify-between px-4 py-2 border-b border-zinc-800 bg-zinc-950/50 shrink-0">
                <span className="text-xs text-zinc-400 font-mono truncate">{viewingFile.split("/").pop()}</span>
                <div className="flex items-center gap-2 shrink-0 ml-2">
                  {fileData?.size != null && !fileData.error && (
                    <span className="text-[10px] text-zinc-600 tabular-nums">{fileData.size.toLocaleString()} bytes</span>
                  )}
                  <button
                    onClick={() => setViewingFile(null)}
                    className="px-1.5 py-0.5 text-[10px] bg-zinc-800 text-zinc-400 rounded hover:bg-zinc-700 transition-colors"
                  >✕</button>
                </div>
              </div>
              <div className="flex-1 overflow-auto p-4 min-h-0">
                {fileLoading && <Spinner text="Reading..." />}
                {fileData?.error && <ErrorBox message={fileData.error} />}
                {fileData?.content != null && !fileData.error && (
                  <pre className="text-xs text-zinc-300 font-mono whitespace-pre-wrap break-all leading-relaxed">
                    {fileData.content || "(empty file)"}
                  </pre>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function DockerPage() {
  const qc = useQueryClient();
  const { data: containerData, isLoading: containersLoading } = useContainers();
  const { data: imageData, isLoading: imagesLoading } = useImages();
  const { data: networkData } = useNetworks();

  const [acting, setActing] = useState<string | null>(null);
  const [inspectTarget, setInspectTarget] = useState<{ id: string; name: string } | null>(null);
  const [fileTarget, setFileTarget] = useState<{ id: string; name: string; workDir: string } | null>(null);

  const handleAction = useCallback(
    async (action: string, containerId: string) => {
      setActing(containerId);
      try {
        const res = await fetch("/api/docker/action", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action, containerId }),
        });
        if (!res.ok) {
          const data = await res.json();
          alert(`Action failed: ${data.error}`);
        }
        qc.invalidateQueries({ queryKey: ["docker", "containers"] });
      } finally {
        setActing(null);
      }
    },
    [qc]
  );

  const containers = containerData?.containers ?? [];
  const hasError = containerData?.error;
  const images = imageData?.images ?? [];
  const networks = networkData?.networks ?? [];
  const runningCount = containers.filter((c) => c.state === "running").length;

  return (
    <div className="p-6 max-w-5xl">
      <PageHeader title="Docker" subtitle="Container sandbox management">
        {containers.length > 0 && (
          <div className="flex items-center gap-2">
            <StatusDot status={runningCount > 0 ? "running" : "idle"} size="sm" />
            <span className="text-xs text-zinc-400">{runningCount}/{containers.length} running</span>
          </div>
        )}
      </PageHeader>

      {/* Containers */}
      <Card>
        <CardHeader title="Containers" count={containers.length}>
          <button
            onClick={() => qc.invalidateQueries({ queryKey: ["docker"] })}
            className="px-2 py-1 text-xs bg-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-600 transition-colors"
          >Refresh</button>
        </CardHeader>
        <CardBody className="space-y-2">
          {containersLoading && <Spinner />}
          {hasError && <ErrorBox message={String(hasError)} />}
          {!containersLoading && !hasError && containers.length === 0 && (
            <EmptyState message="No containers found" />
          )}
          {containers.map((c) => (
            <ContainerRow
              key={c.id}
              container={c}
              onAction={handleAction}
              onInspect={(id, name) => setInspectTarget({ id, name })}
              onBrowseFiles={(id, name, workDir) => setFileTarget({ id, name, workDir })}
              acting={acting}
            />
          ))}
        </CardBody>
      </Card>

      {/* Images */}
      <Card className="mt-4">
        <CardHeader title="Images" count={images.length} />
        <CardBody>
          {imagesLoading && <Spinner />}
          {images.length === 0 && !imagesLoading && <EmptyState message="No images found" />}
          {images.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b border-zinc-800 text-zinc-500">
                    <th className="text-left py-2 pr-4 font-medium">Repository</th>
                    <th className="text-left py-2 pr-4 font-medium">Tag</th>
                    <th className="text-left py-2 pr-4 font-medium">Size</th>
                    <th className="text-left py-2 font-medium">ID</th>
                  </tr>
                </thead>
                <tbody>
                  {images.map((img, idx) => (
                    <tr key={`${img.repository}-${img.tag}-${idx}`} className="border-b border-zinc-800/50">
                      <td className="py-2 pr-4 text-zinc-200 font-mono">{img.repository}</td>
                      <td className="py-2 pr-4">
                        <Badge variant={img.tag === "<none>" ? "muted" : "indigo"}>{img.tag}</Badge>
                      </td>
                      <td className="py-2 pr-4 text-zinc-400 tabular-nums">{img.size}</td>
                      <td className="py-2 text-zinc-600 font-mono">{img.id.replace("sha256:", "").slice(0, 12)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardBody>
      </Card>

      {/* Networks */}
      <Card className="mt-4">
        <CardHeader title="Networks" count={networks.length} />
        <CardBody className="space-y-2">
          {networks.length === 0 && <EmptyState message="No networks found" />}
          {networks.map((n) => (
            <div key={n.id} className="flex items-center gap-3 rounded-lg border border-zinc-800 bg-zinc-950/50 px-4 py-2.5">
              <span className="text-sm text-zinc-200 font-medium flex-1">{n.name}</span>
              <Badge variant="muted">{n.driver}</Badge>
              <Badge variant="cyan">{n.scope}</Badge>
              <span className="text-xs text-zinc-600 font-mono">{n.id.slice(0, 12)}</span>
            </div>
          ))}
        </CardBody>
      </Card>

      {/* Modals */}
      {inspectTarget && (
        <InspectModal containerId={inspectTarget.id} containerName={inspectTarget.name} onClose={() => setInspectTarget(null)} />
      )}
      {fileTarget && (
        <FileBrowser containerId={fileTarget.id} containerName={fileTarget.name} initialPath={fileTarget.workDir} onClose={() => setFileTarget(null)} />
      )}
    </div>
  );
}
