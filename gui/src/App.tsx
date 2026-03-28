import { useEffect } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  NavLink,
  Navigate,
} from "react-router-dom";
import { useGatewayStore, useConnectionState } from "@/api/hooks";

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

const NAV_ITEMS = [
  { to: "/overview", label: "Overview", icon: "📊" },
  { to: "/chat", label: "Chat", icon: "💬" },
  { to: "/sessions", label: "Sessions", icon: "🔗" },
  { to: "/monitor", label: "Monitor", icon: "🩺" },
  { to: "/logs", label: "Logs", icon: "📜" },
  { to: "/cron", label: "Cron", icon: "⏰" },
  { to: "/skills", label: "Skills", icon: "🧩" },
  { to: "/files", label: "Files", icon: "📁" },
  { to: "/docker", label: "Docker", icon: "🐳" },
  { to: "/broker", label: "Broker", icon: "🔀" },
  { to: "/settings", label: "Settings", icon: "⚙️" },
] as const;

function ConnectionDot() {
  const state = useConnectionState();
  const color =
    state === "connected"
      ? "bg-emerald-500"
      : state === "connecting"
        ? "bg-amber-500 animate-pulse"
        : "bg-red-500";
  const label =
    state === "connected"
      ? "Connected"
      : state === "connecting"
        ? "Connecting…"
        : "Disconnected";

  return (
    <div className="flex items-center gap-2 px-4 py-2 text-xs text-zinc-400">
      <span className={`inline-block h-2 w-2 rounded-full ${color}`} />
      {label}
    </div>
  );
}

function Sidebar() {
  return (
    <aside className="fixed top-0 left-0 bottom-0 w-[220px] bg-zinc-900 border-r border-zinc-800 flex flex-col">
      <div className="px-4 py-4 text-lg font-bold text-zinc-100 tracking-tight border-b border-zinc-800">
        OpenClaw
      </div>
      <nav className="flex-1 overflow-y-auto py-2">
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            className={({ isActive }) =>
              `flex items-center gap-3 px-4 py-2 text-sm transition-colors ${
                isActive
                  ? "bg-zinc-800 text-zinc-100"
                  : "text-zinc-400 hover:bg-zinc-800/50 hover:text-zinc-200"
              }`
            }
          >
            <span className="text-base leading-none">{item.icon}</span>
            {item.label}
          </NavLink>
        ))}
      </nav>
      <div className="border-t border-zinc-800">
        <ConnectionDot />
      </div>
    </aside>
  );
}

export default function App() {
  const init = useGatewayStore((s) => s.init);

  useEffect(() => {
    const wsUrl =
      import.meta.env.VITE_WS_URL ??
      `ws://${window.location.hostname}:17777`;
    init(wsUrl);
  }, [init]);

  return (
    <BrowserRouter>
      <div className="flex min-h-screen">
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
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}
