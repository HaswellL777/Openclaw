import { useState, useCallback, useMemo } from "react";
import {
  useCronJobs,
  useCronRuns,
  useGatewayStore,
} from "@/api/hooks";
import type { CronJob, CronRun } from "@/api/types";
import {
  PageHeader,
  Card,
  CardHeader,
  CardBody,
  StatusDot,
  Spinner,
  EmptyState,
  Badge,
  ErrorBox,
} from "@/components/shared";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function fmtDate(ms?: number): string {
  if (!ms) return "--";
  return new Date(ms).toLocaleString();
}

function fmtDuration(ms?: number): string {
  if (!ms) return "--";
  if (ms < 1_000) return `${ms}ms`;
  if (ms < 60_000) return `${(ms / 1_000).toFixed(1)}s`;
  return `${(ms / 60_000).toFixed(1)}m`;
}

function fmtSchedule(schedule: any): string {
  if (typeof schedule === "string") return schedule;
  if (schedule?.cron) return schedule.cron;
  if (schedule?.interval) return `every ${schedule.interval}`;
  return JSON.stringify(schedule);
}

const statusColors: Record<string, string> = {
  success: "text-emerald-400",
  running: "text-amber-400",
  failed: "text-red-400",
  error: "text-red-400",
  skipped: "text-zinc-500",
};

// ---------------------------------------------------------------------------
// Add / Edit form
// ---------------------------------------------------------------------------

interface JobFormData {
  name: string;
  schedule: string;
  agent: string;
  message: string;
  wakeMode: string;
}

const emptyForm: JobFormData = {
  name: "",
  schedule: "",
  agent: "",
  message: "",
  wakeMode: "spawn",
};

function JobForm({
  initial,
  onSubmit,
  onCancel,
  submitting,
}: {
  initial: JobFormData;
  onSubmit: (data: JobFormData) => void;
  onCancel: () => void;
  submitting: boolean;
}) {
  const [form, setForm] = useState<JobFormData>(initial);
  const set = (key: keyof JobFormData, val: string) =>
    setForm((f) => ({ ...f, [key]: val }));

  return (
    <Card>
      <CardBody className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs text-zinc-400 mb-1">Name</label>
            <input
              type="text"
              value={form.name}
              onChange={(e) => set("name", e.target.value)}
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
          </div>
          <div>
            <label className="block text-xs text-zinc-400 mb-1">
              Schedule (cron)
            </label>
            <input
              type="text"
              value={form.schedule}
              onChange={(e) => set("schedule", e.target.value)}
              placeholder="*/5 * * * *"
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-sm text-zinc-200 placeholder:text-zinc-600 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
          </div>
          <div>
            <label className="block text-xs text-zinc-400 mb-1">Agent</label>
            <input
              type="text"
              value={form.agent}
              onChange={(e) => set("agent", e.target.value)}
              placeholder="task-runner"
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-sm text-zinc-200 placeholder:text-zinc-600 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
          </div>
          <div>
            <label className="block text-xs text-zinc-400 mb-1">
              Wake Mode
            </label>
            <select
              value={form.wakeMode}
              onChange={(e) => set("wakeMode", e.target.value)}
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-sm text-zinc-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              <option value="spawn">spawn</option>
              <option value="resume">resume</option>
              <option value="send">send</option>
            </select>
          </div>
        </div>
        <div>
          <label className="block text-xs text-zinc-400 mb-1">Message</label>
          <textarea
            value={form.message}
            onChange={(e) => set("message", e.target.value)}
            rows={2}
            placeholder="Message to send when triggered"
            className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-2.5 py-1.5 text-sm text-zinc-200 placeholder:text-zinc-600 resize-none focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
        </div>
        <div className="flex justify-end gap-2">
          <button
            onClick={onCancel}
            className="px-3 py-1.5 text-xs bg-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-600 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={() => onSubmit(form)}
            disabled={!form.name || !form.schedule || submitting}
            className="px-3 py-1.5 text-xs bg-indigo-600 text-zinc-100 rounded-lg hover:bg-indigo-500 transition-colors disabled:opacity-40 disabled:cursor-not-allowed font-medium"
          >
            {submitting ? "Saving..." : "Save"}
          </button>
        </div>
      </CardBody>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Job row
// ---------------------------------------------------------------------------

function JobRow({
  job,
  selected,
  onSelect,
  onToggle,
  onRunNow,
  onEdit,
  onDelete,
}: {
  job: CronJob;
  selected: boolean;
  onSelect: () => void;
  onToggle: () => void;
  onRunNow: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const enabled = job.state?.enabled ?? false;

  return (
    <tr
      onClick={onSelect}
      className={`border-b border-zinc-800/60 text-sm cursor-pointer transition-colors ${
        selected ? "bg-zinc-800/50" : "hover:bg-zinc-800/30"
      }`}
    >
      <td className="px-3 py-2.5">
        <div className="font-medium text-zinc-200">{job.name}</div>
        <div className="text-xs text-zinc-600 font-mono">{job.id}</div>
      </td>
      <td className="px-3 py-2.5 font-mono text-xs text-zinc-400">
        {fmtSchedule(job.schedule)}
      </td>
      <td className="px-3 py-2.5">
        <button
          onClick={(e) => {
            e.stopPropagation();
            onToggle();
          }}
          className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${
            enabled ? "bg-emerald-600" : "bg-zinc-700"
          }`}
        >
          <span
            className={`inline-block h-3.5 w-3.5 rounded-full bg-white transition-transform ${
              enabled ? "translate-x-4" : "translate-x-1"
            }`}
          />
        </button>
      </td>
      <td className="px-3 py-2.5 text-xs text-zinc-400 tabular-nums">
        {fmtDate(job.state?.lastRunAtMs)}
      </td>
      <td className="px-3 py-2.5 text-xs text-zinc-400 tabular-nums">
        {fmtDate(job.state?.nextRunAtMs)}
      </td>
      <td className="px-3 py-2.5">
        <div className="flex gap-1.5" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={onRunNow}
            className="px-2 py-1 text-xs bg-indigo-600/20 text-indigo-300 rounded-lg hover:bg-indigo-600/30 transition-colors"
          >
            Run
          </button>
          <button
            onClick={onEdit}
            className="px-2 py-1 text-xs bg-zinc-700 text-zinc-300 rounded-lg hover:bg-zinc-600 transition-colors"
          >
            Edit
          </button>
          <button
            onClick={onDelete}
            className="px-2 py-1 text-xs bg-red-600/20 text-red-400 rounded-lg hover:bg-red-600/30 transition-colors"
          >
            Del
          </button>
        </div>
      </td>
    </tr>
  );
}

// ---------------------------------------------------------------------------
// Run history table
// ---------------------------------------------------------------------------

function RunHistory({ jobId }: { jobId: string }) {
  const { data, isLoading, error } = useCronRuns(jobId);
  const runs = (data as any)?.entries ?? (data as any)?.runs ?? [];

  if (isLoading) return <Spinner text="Loading run history..." />;
  if (error) return <ErrorBox message="Failed to load runs" />;

  return (
    <Card>
      <CardHeader title="Run History" count={runs.length} />
      {runs.length === 0 ? (
        <CardBody>
          <EmptyState message="No runs recorded" />
        </CardBody>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="text-xs text-zinc-500 uppercase tracking-wider border-b border-zinc-800">
                <th className="px-3 py-2 text-left">Run ID</th>
                <th className="px-3 py-2 text-left">Status</th>
                <th className="px-3 py-2 text-left">Started</th>
                <th className="px-3 py-2 text-left">Duration</th>
                <th className="px-3 py-2 text-left">Tokens</th>
                <th className="px-3 py-2 text-left">Error</th>
              </tr>
            </thead>
            <tbody>
              {runs.map((run: CronRun) => (
                <tr
                  key={run.id}
                  className="border-b border-zinc-800/50 text-sm"
                >
                  <td className="px-3 py-2 font-mono text-xs text-zinc-400">
                    {run.id.slice(0, 12)}
                  </td>
                  <td className="px-3 py-2">
                    <span
                      className={`text-xs font-medium ${
                        statusColors[run.status] ?? "text-zinc-400"
                      }`}
                    >
                      {run.status}
                    </span>
                  </td>
                  <td className="px-3 py-2 text-xs text-zinc-400 tabular-nums">
                    {fmtDate(run.startedAtMs)}
                  </td>
                  <td className="px-3 py-2 text-xs text-zinc-400 tabular-nums">
                    {fmtDuration(run.durationMs)}
                  </td>
                  <td className="px-3 py-2 text-xs text-zinc-400 tabular-nums">
                    {run.tokens?.toLocaleString() ?? "--"}
                  </td>
                  <td className="px-3 py-2 text-xs text-red-400 max-w-[200px] truncate">
                    {run.error ?? "--"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function CronPage() {
  const client = useGatewayStore((s) => s.client);
  const { data, isLoading, error, refetch } = useCronJobs();

  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [editingJob, setEditingJob] = useState<CronJob | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const jobs = data?.jobs ?? [];

  // RPC helper
  const rpc = useCallback(
    async (method: string, params?: any) => {
      if (!client) throw new Error("Not connected");
      return client.call(method, params);
    },
    [client],
  );

  // Toggle enabled
  const handleToggle = useCallback(
    async (job: CronJob) => {
      setActionError(null);
      try {
        const newEnabled = !(job.state?.enabled ?? false);
        await rpc("cron.update", { id: job.id, enabled: newEnabled });
        refetch();
      } catch (err: any) {
        setActionError(err?.message ?? "Toggle failed");
      }
    },
    [rpc, refetch],
  );

  // Run now
  const handleRunNow = useCallback(
    async (jobId: string) => {
      setActionError(null);
      try {
        await rpc("cron.trigger", { id: jobId });
        refetch();
      } catch (err: any) {
        setActionError(err?.message ?? "Trigger failed");
      }
    },
    [rpc, refetch],
  );

  // Delete
  const handleDelete = useCallback(
    async (jobId: string) => {
      setActionError(null);
      try {
        await rpc("cron.delete", { id: jobId });
        if (selectedJobId === jobId) setSelectedJobId(null);
        refetch();
      } catch (err: any) {
        setActionError(err?.message ?? "Delete failed");
      }
    },
    [rpc, refetch, selectedJobId],
  );

  // Submit form (create or update)
  const handleSubmit = useCallback(
    async (formData: JobFormData) => {
      setSubmitting(true);
      setActionError(null);
      try {
        const params: any = {
          name: formData.name,
          schedule: formData.schedule,
          wakeMode: formData.wakeMode || undefined,
          sessionTarget: {
            agent: formData.agent || undefined,
            message: formData.message || undefined,
          },
        };

        if (editingJob) {
          await rpc("cron.update", { id: editingJob.id, ...params });
        } else {
          await rpc("cron.create", params);
        }
        setShowForm(false);
        setEditingJob(null);
        refetch();
      } catch (err: any) {
        setActionError(err?.message ?? "Save failed");
      } finally {
        setSubmitting(false);
      }
    },
    [rpc, refetch, editingJob],
  );

  // Edit button -> populate form
  const handleEdit = (job: CronJob) => {
    setEditingJob(job);
    setShowForm(true);
  };

  const editFormData: JobFormData = useMemo(() => {
    if (!editingJob) return emptyForm;
    return {
      name: editingJob.name,
      schedule: fmtSchedule(editingJob.schedule),
      agent: editingJob.sessionTarget?.agent ?? "",
      message: editingJob.sessionTarget?.message ?? "",
      wakeMode: editingJob.wakeMode ?? "spawn",
    };
  }, [editingJob]);

  return (
    <div className="p-6 space-y-4">
      <PageHeader title="Cron Jobs" subtitle="Scheduled task automation">
        <button
          onClick={() => {
            setEditingJob(null);
            setShowForm((v) => !v);
          }}
          className="px-3 py-1.5 text-sm bg-indigo-600 text-zinc-100 rounded-lg hover:bg-indigo-500 transition-colors font-medium"
        >
          {showForm && !editingJob ? "Close" : "Add Job"}
        </button>
      </PageHeader>

      {/* Error */}
      {actionError && <ErrorBox message={actionError} />}

      {/* Form */}
      {showForm && (
        <JobForm
          initial={editingJob ? editFormData : emptyForm}
          onSubmit={handleSubmit}
          onCancel={() => {
            setShowForm(false);
            setEditingJob(null);
          }}
          submitting={submitting}
        />
      )}

      {/* Job table */}
      <Card>
        {isLoading ? (
          <CardBody>
            <Spinner text="Loading cron jobs..." />
          </CardBody>
        ) : error ? (
          <CardBody>
            <ErrorBox message="Failed to load cron jobs" />
          </CardBody>
        ) : jobs.length === 0 ? (
          <CardBody>
            <EmptyState message="No cron jobs configured" />
          </CardBody>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-xs text-zinc-500 uppercase tracking-wider border-b border-zinc-800">
                  <th className="px-3 py-2.5 text-left">Job</th>
                  <th className="px-3 py-2.5 text-left">Schedule</th>
                  <th className="px-3 py-2.5 text-left">Enabled</th>
                  <th className="px-3 py-2.5 text-left">Last Run</th>
                  <th className="px-3 py-2.5 text-left">Next Run</th>
                  <th className="px-3 py-2.5 text-left">Actions</th>
                </tr>
              </thead>
              <tbody>
                {jobs.map((job) => (
                  <JobRow
                    key={job.id}
                    job={job}
                    selected={job.id === selectedJobId}
                    onSelect={() =>
                      setSelectedJobId((prev) =>
                        prev === job.id ? null : job.id,
                      )
                    }
                    onToggle={() => handleToggle(job)}
                    onRunNow={() => handleRunNow(job.id)}
                    onEdit={() => handleEdit(job)}
                    onDelete={() => handleDelete(job.id)}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {/* Run history */}
      {selectedJobId && <RunHistory jobId={selectedJobId} />}
    </div>
  );
}
