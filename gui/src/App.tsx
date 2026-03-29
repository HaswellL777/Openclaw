import { useEffect } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  NavLink,
  Navigate,
} from "react-router-dom";
import { useGatewayStore, useConnectionState } from "@/api/hooks";
import { StatusDot } from "@/components/shared";

import OverviewPage from "@/pages/OverviewPage";
import ChatPage from "@/pages/ChatPage";
import SessionsPage from "@/pages/SessionsPage";
import MonitorPage from "@/pages/MonitorPage";
import LogsPage from "@/pages/LogsPage";
import CronPage from "@/pages/CronPage";
import SkillsPage from "@/pages/SkillsPage";
import FilesPage from "@/pages/FilesPage";
import DockerPage from "@/pages/DockerPage";
import BrokerPage from "@/pages/BrokerPage";
import SettingsPage from "@/pages/SettingsPage";
import TaskFlowPage from "@/pages/TaskFlowPage";
import DocsPage from "@/pages/DocsPage";
import HeartbeatPage from "@/pages/HeartbeatPage";
import McpPage from "@/pages/McpPage";

const NAV_GROUPS = [
  {
    label: "Core",
    items: [
      { to: "/overview", label: "Overview", icon: "grid" },
      { to: "/chat", label: "Chat", icon: "chat" },
      { to: "/sessions", label: "Sessions", icon: "sessions" },
      { to: "/tasks", label: "Task Flow", icon: "broker" },
    ],
  },
  {
    label: "Operations",
    items: [
      { to: "/monitor", label: "Inspector", icon: "monitor" },
      { to: "/logs", label: "Logs", icon: "logs" },
      { to: "/cron", label: "Cron", icon: "cron" },
      { to: "/heartbeat", label: "Heartbeat", icon: "cron" },
    ],
  },
  {
    label: "System",
    items: [
      { to: "/skills", label: "Skills", icon: "skills" },
      { to: "/mcp", label: "MCP", icon: "skills" },
      { to: "/files", label: "Files", icon: "files" },
      { to: "/docker", label: "Docker", icon: "docker" },
      { to: "/broker", label: "Broker", icon: "broker" },
      { to: "/settings", label: "Settings", icon: "settings" },
      { to: "/docs", label: "Help", icon: "files" },
    ],
  },
] as const;

// Simple monochrome SVG icons for the sidebar
function NavIcon({ icon }: { icon: string }) {
  const cls = "w-4 h-4 shrink-0";
  switch (icon) {
    case "grid":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path d="M5 3a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2V5a2 2 0 00-2-2H5zM5 11a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2v-2a2 2 0 00-2-2H5zM11 5a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V5zM11 13a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
        </svg>
      );
    case "chat":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M18 10c0 3.866-3.582 7-8 7a8.841 8.841 0 01-4.083-.98L2 17l1.338-3.123C2.493 12.767 2 11.434 2 10c0-3.866 3.582-7 8-7s8 3.134 8 7zM7 9H5v2h2V9zm8 0h-2v2h2V9zm-4 0H9v2h2V9z" clipRule="evenodd" />
        </svg>
      );
    case "sessions":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path d="M2 4a1 1 0 011-1h2a1 1 0 011 1v12a1 1 0 01-1 1H3a1 1 0 01-1-1V4zM8 4a1 1 0 011-1h2a1 1 0 011 1v12a1 1 0 01-1 1H9a1 1 0 01-1-1V4zM15 3a1 1 0 00-1 1v12a1 1 0 001 1h2a1 1 0 001-1V4a1 1 0 00-1-1h-2z" />
        </svg>
      );
    case "monitor":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M3 4a1 1 0 011-1h12a1 1 0 011 1v2a1 1 0 01-1 1H4a1 1 0 01-1-1V4zm0 5a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H4a1 1 0 01-1-1V9zm11-1a1 1 0 00-1 1v6a1 1 0 001 1h2a1 1 0 001-1V9a1 1 0 00-1-1h-2z" clipRule="evenodd" />
        </svg>
      );
    case "logs":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4zm2 6a1 1 0 011-1h6a1 1 0 110 2H7a1 1 0 01-1-1zm1 3a1 1 0 100 2h6a1 1 0 100-2H7z" clipRule="evenodd" />
        </svg>
      );
    case "cron":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clipRule="evenodd" />
        </svg>
      );
    case "skills":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path d="M11 17a1 1 0 001.447.894l4-2A1 1 0 0017 15V9.236a1 1 0 00-1.447-.894l-4 2a1 1 0 00-.553.894V17zM15.211 6.276a1 1 0 000-1.788l-4.764-2.382a1 1 0 00-.894 0L4.789 4.488a1 1 0 000 1.788l4.764 2.382a1 1 0 00.894 0l4.764-2.382zM4.447 8.342A1 1 0 003 9.236V15a1 1 0 00.553.894l4 2A1 1 0 009 17v-5.764a1 1 0 00-.553-.894l-4-2z" />
        </svg>
      );
    case "files":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M2 6a2 2 0 012-2h5l2 2h5a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V6z" clipRule="evenodd" />
        </svg>
      );
    case "docker":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M3 5a2 2 0 012-2h10a2 2 0 012 2v8a2 2 0 01-2 2h-2.22l.123.489.804.804A1 1 0 0113 18H7a1 1 0 01-.707-1.707l.804-.804L7.22 15H5a2 2 0 01-2-2V5zm5.771 7H5V5h10v7H8.771z" clipRule="evenodd" />
        </svg>
      );
    case "broker":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path d="M5 2a1 1 0 011 1v1h1a1 1 0 010 2H6v1a1 1 0 01-2 0V6H3a1 1 0 010-2h1V3a1 1 0 011-1zm0 10a1 1 0 011 1v1h1a1 1 0 110 2H6v1a1 1 0 11-2 0v-1H3a1 1 0 110-2h1v-1a1 1 0 011-1zM12 2a1 1 0 01.967.744L14.146 7.2 17.5 9.134a1 1 0 010 1.732l-3.354 1.935-1.18 4.455a1 1 0 01-1.933 0L9.854 12.8 6.5 10.866a1 1 0 010-1.732l3.354-1.935 1.18-4.455A1 1 0 0112 2z" />
        </svg>
      );
    case "settings":
      return (
        <svg className={cls} viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
        </svg>
      );
    default:
      return <div className={cls} />;
  }
}

function ConnectionIndicator() {
  const state = useConnectionState();
  const variant =
    state === "connected"
      ? "connected"
      : state === "connecting"
        ? "connecting"
        : "disconnected";
  const label =
    state === "connected"
      ? "Connected"
      : state === "connecting"
        ? "Connecting..."
        : "Disconnected";

  return (
    <div className="flex items-center gap-2 px-4 py-3 text-xs text-zinc-400">
      <StatusDot status={variant} size="xs" />
      {label}
    </div>
  );
}

function Sidebar() {
  return (
    <aside className="fixed top-0 left-0 bottom-0 w-[220px] bg-zinc-900 border-r border-zinc-800 flex flex-col">
      {/* Logo / Title */}
      <div className="px-4 py-4 border-b border-zinc-800">
        <div className="flex items-center gap-2.5">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center shadow-md shadow-indigo-500/20">
            <svg
              className="w-4 h-4 text-white"
              viewBox="0 0 20 20"
              fill="currentColor"
            >
              <path d="M5 2a1 1 0 011 1v1h1a1 1 0 010 2H6v1a1 1 0 01-2 0V6H3a1 1 0 010-2h1V3a1 1 0 011-1zm0 10a1 1 0 011 1v1h1a1 1 0 110 2H6v1a1 1 0 11-2 0v-1H3a1 1 0 110-2h1v-1a1 1 0 011-1zM12 2a1 1 0 01.967.744L14.146 7.2 17.5 9.134a1 1 0 010 1.732l-3.354 1.935-1.18 4.455a1 1 0 01-1.933 0L9.854 12.8 6.5 10.866a1 1 0 010-1.732l3.354-1.935 1.18-4.455A1 1 0 0112 2z" />
            </svg>
          </div>
          <div>
            <div className="text-base font-bold text-zinc-100 tracking-tight leading-none">
              OpenClaw
            </div>
            <div className="text-[10px] text-zinc-500 leading-none mt-0.5">
              Control Panel
            </div>
          </div>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto py-1">
        {NAV_GROUPS.map((group, gi) => (
          <div key={group.label}>
            {gi > 0 && <div className="mx-4 my-1.5 border-t border-zinc-800/60" />}
            <div className="px-4 pt-3 pb-1.5">
              <span className="text-[10px] font-semibold uppercase tracking-wider text-zinc-600">
                {group.label}
              </span>
            </div>
            {group.items.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  `flex items-center gap-2.5 mx-2 px-2.5 py-1.5 rounded-lg text-sm transition-all duration-150 ${
                    isActive
                      ? "bg-indigo-500/10 text-indigo-300 font-medium shadow-sm shadow-indigo-500/5"
                      : "text-zinc-400 hover:bg-zinc-800/50 hover:text-zinc-200 hover:translate-x-0.5"
                  }`
                }
              >
                <NavIcon icon={item.icon} />
                {item.label}
              </NavLink>
            ))}
          </div>
        ))}
      </nav>

      {/* Connection status */}
      <div className="border-t border-zinc-800">
        <ConnectionIndicator />
      </div>
    </aside>
  );
}

export default function App() {
  const init = useGatewayStore((s) => s.init);

  useEffect(() => {
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl =
      import.meta.env.VITE_WS_URL ??
      `${proto}//${window.location.host}/ws`;
    const token = import.meta.env.VITE_GATEWAY_TOKEN ?? undefined;
    init(wsUrl, token);
  }, [init]);

  return (
    <BrowserRouter>
      <div className="flex min-h-screen bg-zinc-950">
        <Sidebar />
        <main className="ml-[220px] flex-1 min-h-screen">
          <Routes>
            <Route path="/" element={<Navigate to="/overview" replace />} />
            <Route path="/overview" element={<OverviewPage />} />
            <Route path="/chat" element={<ChatPage />} />
            <Route path="/sessions" element={<SessionsPage />} />
            <Route path="/monitor" element={<MonitorPage />} />
            <Route path="/logs" element={<LogsPage />} />
            <Route path="/cron" element={<CronPage />} />
            <Route path="/skills" element={<SkillsPage />} />
            <Route path="/files" element={<FilesPage />} />
            <Route path="/docker" element={<DockerPage />} />
            <Route path="/broker" element={<BrokerPage />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="/tasks" element={<TaskFlowPage />} />
            <Route path="/docs" element={<DocsPage />} />
            <Route path="/heartbeat" element={<HeartbeatPage />} />
            <Route path="/mcp" element={<McpPage />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}
