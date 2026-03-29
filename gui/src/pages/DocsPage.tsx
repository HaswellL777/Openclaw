import { useState } from "react";
import { PageHeader, Card, CardHeader, CardBody, SectionLabel } from "@/components/shared";

// ---------------------------------------------------------------------------
// Help sections data
// ---------------------------------------------------------------------------

interface HelpSection {
  title: string;
  items: { label: string; content: string }[];
}

const SECTIONS: HelpSection[] = [
  {
    title: "Gateway Management",
    items: [
      { label: "Restart gateway", content: "sudo systemctl restart openclaw-gateway.service" },
      { label: "Check gateway status", content: "sudo systemctl status openclaw-gateway.service" },
      { label: "View gateway logs (live)", content: "sudo journalctl -u openclaw-gateway.service -f" },
      { label: "View gateway log file", content: "tail -f /var/log/openclaw/openclaw.log" },
      { label: "Check gateway port", content: "ss -tlnp | grep 17777" },
    ],
  },
  {
    title: "Docker / Sandbox",
    items: [
      { label: "List running containers", content: "docker ps --filter name=openclaw" },
      { label: "View shared sandbox container", content: "docker inspect openclaw-sbx-shared" },
      { label: "Force remove shared container (after image change)", content: "docker rm -f openclaw-sbx-shared" },
      { label: "List OpenClaw images", content: "docker images | grep openclaw" },
      { label: "View container logs", content: "docker logs openclaw-sbx-shared --tail 50" },
      { label: "View Docker network", content: "docker network inspect openclaw-task-net" },
    ],
  },
  {
    title: "Configuration",
    items: [
      { label: "Config file path", content: "/etc/openclaw/openclaw.json" },
      { label: "Environment file (secrets)", content: "/etc/openclaw/openclaw.env" },
      { label: "View current config", content: "sudo cat /etc/openclaw/openclaw.json | python3 -m json.tool" },
      { label: "Validate config (dry run)", content: "sudo -u openclaw openclaw doctor --check" },
    ],
  },
  {
    title: "Directory Structure",
    items: [
      { label: "Code (root-owned, read-only)", content: "/opt/openclaw" },
      { label: "Config (root:openclaw)", content: "/etc/openclaw/" },
      { label: "Runtime data (btrfs subvolume)", content: "/var/lib/openclaw/" },
      { label: "State directory", content: "/var/lib/openclaw/.openclaw/" },
      { label: "Session store", content: "/var/lib/openclaw/.openclaw/sessions/" },
      { label: "Subagent runs registry", content: "/var/lib/openclaw/.openclaw/subagents/runs.json" },
      { label: "Extensions (plugins)", content: "/var/lib/openclaw/.openclaw/extensions/" },
      { label: "Agent workspaces", content: "/var/lib/openclaw/agents/<agentId>/" },
      { label: "Logs", content: "/var/log/openclaw/" },
      { label: "Snapshots", content: "/.snapshots/" },
    ],
  },
  {
    title: "Snapshot & Backup",
    items: [
      { label: "Create root snapshot", content: "sudo btrfs subvolume snapshot / /.snapshots/root-pre-<label>-$(date +%Y%m%d-%H%M)" },
      { label: "List snapshots", content: "ls -la /.snapshots/" },
      { label: "Note: /var/lib/openclaw is separate subvolume", content: "Root snapshots do NOT include OpenClaw runtime data. Backup /var/lib/openclaw separately." },
      { label: "Vault mount (offline, noauto)", content: "sudo mount /mnt/vault" },
    ],
  },
  {
    title: "Session Management",
    items: [
      { label: "List sessions (via GUI)", content: "Open Sessions page in this GUI, or use gateway API: sessions.list" },
      { label: "Session key format", content: "agent:<agentId>:<rest> — subagent depth = count of ':subagent:' in key" },
      { label: "View session transcript on disk", content: "/var/lib/openclaw/agents/<agentId>/sessions/<sessionId>.jsonl" },
      { label: "Session 'active' = updatedAt within N minutes", content: "No status field for regular sessions. Use sessions.list({activeMinutes: N}) to filter." },
      { label: "Maintenance mode (current)", content: "mode: 'warn' (default) — does not auto-delete. pruneAfterMs = 30 days, maxEntries = 500." },
    ],
  },
  {
    title: "Agent Workspaces",
    items: [
      { label: "Publish main workspace", content: "bash scripts/publish-workspace-main.sh" },
      { label: "Manual rsync for task-runner/RC/auditor", content: "rsync -av workspace-<agent>-template/ /var/lib/openclaw/agents/<agentId>/workspace/" },
      { label: "WARNING: chown -R fails on knowledge/", content: "knowledge/ is a read-only bind mount. Chown specific paths only, not -R." },
      { label: "Container UID must match", content: "runner must be --uid 997 --gid 984 (matches openclaw user)" },
    ],
  },
  {
    title: "Troubleshooting",
    items: [
      { label: "Gateway crash loop", content: "Check config schema: .strict() rejects unknown fields. Remove any unrecognized keys from openclaw.json." },
      { label: "Plugin crash loop", content: "Check /var/lib/openclaw/.openclaw/extensions/ — every subdirectory must have openclaw.plugin.json." },
      { label: "Config changes not taking effect", content: "Config must be in /etc/openclaw/openclaw.json, NOT /var/lib/openclaw/.openclaw/openclaw.json." },
      { label: "Container not updating after image change", content: "scope: 'shared' reuses the existing container. Run: docker rm -f openclaw-sbx-shared" },
      { label: "queueOwnerTtlSeconds too low", content: "Default 0.1s causes task timeouts. Override to 300+ in config." },
      { label: "GUI WebSocket connection fails", content: "Vite proxy must rewrite Origin header to localhost:17777. Check gui/vite.config.ts." },
    ],
  },
  {
    title: "Dangerous Operations (DO NOT run as nick)",
    items: [
      { label: "openclaw onboard", content: "Creates ~/.openclaw/ user-level config, spawns second gateway. DO NOT RUN." },
      { label: "openclaw doctor --repair", content: "Auto-repairs by creating user-level state. DO NOT RUN." },
      { label: "openclaw gateway (as nick)", content: "Spawns nick-owned gateway on different port. DO NOT RUN." },
      { label: "openclaw config set", content: "Writes to ~/.openclaw/openclaw.json (user-level). DO NOT RUN." },
    ],
  },
];

// ---------------------------------------------------------------------------
// Components
// ---------------------------------------------------------------------------

function CommandBlock({ content }: { content: string }) {
  const isMultiLine = content.includes("\n");
  const isCommand = !content.includes(" ") || content.startsWith("/") || content.startsWith("sudo ") ||
    content.startsWith("docker ") || content.startsWith("bash ") || content.startsWith("ls ") ||
    content.startsWith("tail ") || content.startsWith("ss ") || content.startsWith("rsync ") ||
    content.startsWith("cat ") || content.startsWith("grep ");

  if (!isCommand && !isMultiLine) {
    return <span className="text-zinc-300 text-xs leading-relaxed">{content}</span>;
  }

  return (
    <code className="block bg-zinc-950 border border-zinc-800 rounded px-2.5 py-1.5 text-xs font-mono text-amber-300 whitespace-pre-wrap select-all">
      {content}
    </code>
  );
}

function HelpSectionCard({ section }: { section: HelpSection }) {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <Card>
      <CardHeader title={section.title}>
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="text-[10px] text-zinc-500 hover:text-zinc-300 transition-colors"
        >
          {collapsed ? "Expand" : "Collapse"}
        </button>
      </CardHeader>
      {!collapsed && (
        <CardBody>
          <div className="space-y-3">
            {section.items.map((item, i) => (
              <div key={i}>
                <div className="text-[11px] text-zinc-400 font-medium mb-1">{item.label}</div>
                <CommandBlock content={item.content} />
              </div>
            ))}
          </div>
        </CardBody>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function DocsPage() {
  return (
    <div className="p-6 h-full overflow-y-auto">
      <PageHeader
        title="Help & Reference"
        subtitle="Common operations, directory structure, and troubleshooting"
      />
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {SECTIONS.map(s => (
          <HelpSectionCard key={s.title} section={s} />
        ))}
      </div>
    </div>
  );
}
