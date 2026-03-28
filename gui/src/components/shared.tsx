export function Spinner({ text = "Loading…" }: { text?: string }) {
  return (
    <div className="flex items-center gap-2 text-zinc-500 text-sm py-4">
      <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z" />
      </svg>
      {text}
    </div>
  );
}

export function ErrorBox({ message }: { message: string }) {
  return (
    <div className="rounded bg-red-950/40 border border-red-900 px-3 py-2 text-red-400 text-sm">
      {message}
    </div>
  );
}

export function StatusDot({ ok, pulse }: { ok: boolean; pulse?: boolean }) {
  return (
    <span
      className={`inline-block h-2.5 w-2.5 rounded-full ${
        ok ? "bg-emerald-500" : "bg-red-500"
      } ${pulse ? "animate-pulse" : ""}`}
    />
  );
}
