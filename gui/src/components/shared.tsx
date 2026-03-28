import type { ReactNode } from "react";

// ---------------------------------------------------------------------------
// PageHeader — consistent page title with bottom border
// ---------------------------------------------------------------------------

export function PageHeader({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children?: ReactNode;
}) {
  return (
    <div className="flex items-center justify-between border-b border-zinc-800 pb-4 mb-6">
      <div>
        <h1 className="text-2xl font-bold text-zinc-100 tracking-tight">
          {title}
        </h1>
        {subtitle && (
          <p className="text-sm text-zinc-500 mt-0.5">{subtitle}</p>
        )}
      </div>
      {children && <div className="flex items-center gap-3">{children}</div>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Card — consistent panel with rounded-xl, shadow, zinc-900 bg
// ---------------------------------------------------------------------------

export function Card({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`rounded-xl border border-zinc-800 bg-zinc-900 shadow-sm shadow-black/20 ${className}`}
    >
      {children}
    </div>
  );
}

export function CardHeader({
  title,
  count,
  children,
}: {
  title: string;
  count?: number | string;
  children?: ReactNode;
}) {
  return (
    <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800">
      <div className="flex items-center gap-2">
        <h3 className="text-sm font-semibold text-zinc-200">{title}</h3>
        {count != null && (
          <span className="text-xs text-zinc-500 tabular-nums">({count})</span>
        )}
      </div>
      {children}
    </div>
  );
}

export function CardBody({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={`p-4 ${className}`}>{children}</div>;
}

// ---------------------------------------------------------------------------
// StatusDot — consistent status indicators across all pages
//   active/connected/running = pulsing green
//   idle/default = solid gray
//   error/failed = red
//   warning/loading = amber pulse
// ---------------------------------------------------------------------------

export type StatusVariant =
  | "active"
  | "idle"
  | "error"
  | "warning"
  | "connected"
  | "connecting"
  | "disconnected"
  | "running"
  | "stopped"
  | "healthy"
  | "unhealthy";

const dotClasses: Record<StatusVariant, string> = {
  active: "bg-emerald-500 animate-pulse",
  connected: "bg-emerald-500 animate-pulse",
  running: "bg-emerald-500 animate-pulse",
  healthy: "bg-emerald-500 animate-pulse",
  idle: "bg-zinc-500",
  warning: "bg-amber-500 animate-pulse",
  connecting: "bg-amber-500 animate-pulse",
  error: "bg-red-500",
  disconnected: "bg-red-500",
  stopped: "bg-red-500",
  unhealthy: "bg-red-500",
};

export function StatusDot({
  status,
  size = "sm",
}: {
  status: StatusVariant;
  size?: "xs" | "sm" | "md";
}) {
  const sizeClass =
    size === "xs"
      ? "h-1.5 w-1.5"
      : size === "md"
        ? "h-3 w-3"
        : "h-2 w-2";
  return (
    <span
      className={`inline-block rounded-full shrink-0 ${sizeClass} ${dotClasses[status] ?? "bg-zinc-600"}`}
    />
  );
}

// ---------------------------------------------------------------------------
// Spinner — consistent loading spinner
// ---------------------------------------------------------------------------

export function Spinner({ text = "Loading..." }: { text?: string }) {
  return (
    <div className="flex items-center justify-center gap-2.5 text-zinc-500 text-sm py-8">
      <svg
        className="animate-spin h-4 w-4"
        viewBox="0 0 24 24"
        fill="none"
      >
        <circle
          className="opacity-25"
          cx="12"
          cy="12"
          r="10"
          stroke="currentColor"
          strokeWidth="4"
        />
        <path
          className="opacity-75"
          fill="currentColor"
          d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"
        />
      </svg>
      {text}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Skeleton — loading placeholder bars
// ---------------------------------------------------------------------------

export function Skeleton({
  lines = 3,
  className = "",
}: {
  lines?: number;
  className?: string;
}) {
  return (
    <div className={`space-y-3 ${className}`}>
      {Array.from({ length: lines }).map((_, i) => (
        <div
          key={i}
          className="h-4 rounded bg-zinc-800 animate-pulse"
          style={{ width: `${70 + Math.random() * 30}%` }}
        />
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// EmptyState — friendly empty state with icon
// ---------------------------------------------------------------------------

export function EmptyState({
  icon,
  message,
  children,
}: {
  icon?: string;
  message: string;
  children?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      {icon && (
        <div className="text-3xl text-zinc-700 mb-3 select-none">{icon}</div>
      )}
      <p className="text-sm text-zinc-500">{message}</p>
      {children && <div className="mt-3">{children}</div>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// ErrorBox
// ---------------------------------------------------------------------------

export function ErrorBox({ message }: { message: string }) {
  return (
    <div className="rounded-xl border border-red-900/50 bg-red-950/30 px-4 py-3 text-sm text-red-300 flex items-center gap-2">
      <svg
        className="h-4 w-4 shrink-0 text-red-400"
        viewBox="0 0 20 20"
        fill="currentColor"
      >
        <path
          fillRule="evenodd"
          d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z"
          clipRule="evenodd"
        />
      </svg>
      {message}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Badge — small colored label
// ---------------------------------------------------------------------------

export type BadgeVariant =
  | "default"
  | "muted"
  | "indigo"
  | "amber"
  | "emerald"
  | "red"
  | "blue"
  | "purple"
  | "cyan";

const badgeClasses: Record<BadgeVariant, string> = {
  default: "bg-zinc-700 text-zinc-200",
  muted: "bg-zinc-800 text-zinc-400",
  indigo: "bg-indigo-500/20 text-indigo-300",
  amber: "bg-amber-500/20 text-amber-300",
  emerald: "bg-emerald-500/20 text-emerald-300",
  red: "bg-red-500/20 text-red-300",
  blue: "bg-blue-500/20 text-blue-300",
  purple: "bg-purple-500/20 text-purple-300",
  cyan: "bg-cyan-500/20 text-cyan-300",
};

export function Badge({
  children,
  variant = "default",
  className = "",
}: {
  children: ReactNode;
  variant?: BadgeVariant;
  className?: string;
}) {
  return (
    <span
      className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ${badgeClasses[variant]} ${className}`}
    >
      {children}
    </span>
  );
}

// ---------------------------------------------------------------------------
// SectionLabel — uppercase tracking-wider section label
// ---------------------------------------------------------------------------

export function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold mb-2">
      {children}
    </div>
  );
}
