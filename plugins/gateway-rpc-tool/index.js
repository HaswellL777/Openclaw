// gateway-rpc-tool plugin
// Exposes selected gateway RPC methods as agent-callable tools.
// Uses openclaw CLI commands internally for reliable gateway communication.
//
// Supported method groups:
//   - cron: list, add, remove, run, status
//   - sessions: list, abort, reset
//   - health: gateway health check
//   - config: read-only config queries
//   - usage: token usage queries
//
// Security:
//   - Tool is optional (requires tools.allow)
//   - Only configured agents can use it (default: main only)
//   - Destructive operations (sessions.delete, config.set) are excluded
//   - All calls logged via plugin logger

const METHODS = {
  // --- Cron ---
  "cron.list": {
    description: "List all cron jobs",
    cmd: ["openclaw", "cron", "list", "--json"],
    params: [],
  },
  "cron.add": {
    description: "Add a new cron job",
    cmd: ["openclaw", "cron", "add", "--json"],
    params: [
      { name: "name", flag: "--name", required: true },
      { name: "cron", flag: "--cron", required: false },
      { name: "every", flag: "--every", required: false },
      { name: "session", flag: "--session", required: false, default: "isolated" },
      { name: "agent", flag: "--agent", required: false },
      { name: "message", flag: "--message", required: false },
      { name: "systemEvent", flag: "--system-event", required: false },
      { name: "wake", flag: "--wake", required: false, default: "now" },
      { name: "description", flag: "--description", required: false },
      { name: "disabled", flag: "--disabled", required: false, type: "boolean" },
    ],
  },
  "cron.remove": {
    description: "Remove a cron job by ID",
    cmd: ["openclaw", "cron", "rm", "--json"],
    params: [
      { name: "id", positional: true, required: true },
    ],
  },
  "cron.run": {
    description: "Run a cron job immediately (debug)",
    cmd: ["openclaw", "cron", "run", "--json"],
    params: [
      { name: "id", positional: true, required: true },
    ],
  },
  "cron.enable": {
    description: "Enable a cron job",
    cmd: ["openclaw", "cron", "enable", "--json"],
    params: [
      { name: "id", positional: true, required: true },
    ],
  },
  "cron.disable": {
    description: "Disable a cron job",
    cmd: ["openclaw", "cron", "disable", "--json"],
    params: [
      { name: "id", positional: true, required: true },
    ],
  },
  "cron.status": {
    description: "Show cron scheduler status",
    cmd: ["openclaw", "cron", "status", "--json"],
    params: [],
  },

  // --- Health ---
  "health": {
    description: "Get gateway health status",
    cmd: ["openclaw", "status", "--json"],
    params: [],
  },

  // --- Sessions ---
  "sessions.list": {
    description: "List sessions (optional agent filter)",
    cmd: ["openclaw", "sessions", "list", "--json"],
    params: [
      { name: "agent", flag: "--agent", required: false },
      { name: "limit", flag: "--limit", required: false },
    ],
  },
  "sessions.abort": {
    description: "Abort a running session",
    cmd: ["openclaw", "sessions", "abort"],
    params: [
      { name: "key", positional: true, required: true },
    ],
  },

  // --- Config (read-only) ---
  "config.get": {
    description: "Read a config value by path (read-only)",
    cmd: ["openclaw", "config", "get", "--json"],
    params: [
      { name: "path", positional: true, required: true },
    ],
  },

  // --- Usage ---
  "usage.status": {
    description: "Show token usage summary",
    cmd: ["openclaw", "usage", "--json"],
    params: [],
  },

  // --- Skills ---
  "skills.status": {
    description: "Show skills status",
    cmd: ["openclaw", "skills", "status", "--json"],
    params: [],
  },

  // --- Agents ---
  "agents.list": {
    description: "List configured agents",
    cmd: ["openclaw", "agents", "list", "--json"],
    params: [],
  },
};

const METHOD_NAMES = Object.keys(METHODS);

/**
 * Build CLI arguments from method definition and user params.
 */
function buildArgs(methodDef, userParams) {
  const args = [...methodDef.cmd];
  const errors = [];

  for (const p of methodDef.params) {
    const value = userParams[p.name] ?? p.default;

    if (p.required && (value === undefined || value === null || value === "")) {
      errors.push(`Missing required parameter: ${p.name}`);
      continue;
    }

    if (value === undefined || value === null) continue;

    if (p.positional) {
      args.push(String(value));
    } else if (p.type === "boolean") {
      if (value === true || value === "true") {
        args.push(p.flag);
      }
    } else {
      args.push(p.flag, String(value));
    }
  }

  return { args, errors };
}

/**
 * Create the gateway_rpc agent tool.
 */
function createGatewayRpcTool(api) {
  const allowedAgents = new Set(
    (api.pluginConfig?.allowedAgents ?? ["main"]).map(String)
  );
  const logger = api.logger;
  const runCmd = api.runtime?.system?.runCommandWithTimeout;

  return (ctx) => {
    // Gate by agent
    if (ctx.agentId && !allowedAgents.has(ctx.agentId)) {
      return null;
    }

    return {
      name: "gateway_rpc",
      label: "Gateway RPC",
      description:
        "Call gateway management RPC methods. " +
        "Supported methods: " + METHOD_NAMES.join(", ") + ". " +
        "Use this tool to manage cron jobs, query sessions, check health, " +
        "read config, and view usage statistics.",
      ownerOnly: true,

      parameters: {
        type: "object",
        required: ["method"],
        additionalProperties: false,
        properties: {
          method: {
            type: "string",
            enum: METHOD_NAMES,
            description: "RPC method to call",
          },
          params: {
            type: "object",
            description:
              "Method-specific parameters. Varies per method. " +
              "cron.add: {name, cron, session, agent, message, wake} | " +
              "cron.remove/run/enable/disable: {id} | " +
              "sessions.list: {agent, limit} | " +
              "sessions.abort: {key} | " +
              "config.get: {path}",
          },
        },
      },

      async execute(toolCallId, params) {
        const method = params?.method;
        const userParams = params?.params ?? {};

        // Validate method
        if (!method || !METHODS[method]) {
          return {
            content: [{
              type: "text",
              text: JSON.stringify({
                ok: false,
                error: `Unknown method: ${method}. Available: ${METHOD_NAMES.join(", ")}`,
              }),
            }],
          };
        }

        const methodDef = METHODS[method];
        const { args, errors } = buildArgs(methodDef, userParams);

        if (errors.length > 0) {
          return {
            content: [{
              type: "text",
              text: JSON.stringify({
                ok: false,
                error: `Parameter errors: ${errors.join("; ")}`,
              }),
            }],
          };
        }

        logger.info(`gateway_rpc: ${method}`, { method, params: userParams, agentId: ctx.agentId });

        try {
          let result;

          if (runCmd) {
            // Use plugin runtime's runCommandWithTimeout (preferred — in-process)
            // Signature: runCommandWithTimeout(argv: string[], optionsOrTimeout)
            // Returns: { stdout, stderr, code, signal, killed, termination }
            result = await runCmd(args, { timeoutMs: 30_000, cwd: "/tmp" });
            result.exitCode = result.code ?? 0;
          } else {
            // Fallback: use child_process
            const { execFile } = await import("node:child_process");
            const { promisify } = await import("node:util");
            const execFileAsync = promisify(execFile);

            const { stdout, stderr } = await execFileAsync(args[0], args.slice(1), {
              timeout: 30_000,
              maxBuffer: 1024 * 1024,
              cwd: "/tmp",
            });

            result = { stdout, stderr, exitCode: 0 };
          }

          // Parse output
          const output = (result.stdout ?? "").toString().trim();
          const stderr = (result.stderr ?? "").toString().trim();

          // Try to parse as JSON for cleaner output
          let parsed;
          try {
            parsed = JSON.parse(output);
          } catch {
            parsed = null;
          }

          const response = {
            ok: (result.exitCode ?? 0) === 0,
            method,
            result: parsed ?? output,
            ...(stderr && { stderr }),
          };

          return {
            content: [{
              type: "text",
              text: JSON.stringify(response, null, 2),
            }],
          };
        } catch (err) {
          logger.error(`gateway_rpc failed: ${method}`, { error: err.message });

          return {
            content: [{
              type: "text",
              text: JSON.stringify({
                ok: false,
                method,
                error: err.message,
              }),
            }],
          };
        }
      },
    };
  };
}

/**
 * Plugin registration entry point.
 */
export default function register(api) {
  api.registerTool(createGatewayRpcTool(api), { optional: true });

  api.logger.info("gateway-rpc-tool: registered gateway_rpc tool", {
    methods: METHOD_NAMES,
    allowedAgents: Array.from(api.pluginConfig?.allowedAgents ?? ["main"]),
  });
}
