// host-ops-tool plugin
// Status: Phase 2 — broker backend deployed, plugin lifecycle active,
//         registerTool-based tool registration implemented (gateway_health + gateway_restart + validate_openclaw_json_candidate + deploy_openclaw_json_candidate + snapshot_pre + snapshot_post + rollback_prepare)
// This module provides:
//   1. register(api) export that calls api.registerTool() to register the
//      "host_ops" agent-facing tool (optional: true — requires tools.allow)
//   2. Request building, validation, and Unix socket transport for broker protocol
// Transport: Unix domain socket client (Node.js net module).
// No HTTP, no network listening.
//
// Tool registration evidence (live SDK v2026.3.2, 2026-03-15):
//   - OpenClawPluginApi.registerTool exists:
//       .../plugin-sdk/plugins/types.d.ts:233
//   - JS implementation confirmed:
//       .../plugin-sdk/registry-DmSqCQJS.js:323-337, :594
//   - resolvePluginTools injects into agent tool list:
//       .../plugin-sdk/reply-DFFRlayb.js:65825, :75859-75879
//   - Reference: bundled llm-task extension uses identical pattern:
//       .../extensions/llm-task/index.ts — api.registerTool(tool, { optional: true })
//
// Fail-closed policy:
//   - Only ENABLED_ACTIONS are permitted (currently: gateway_health, gateway_restart, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, rollback_prepare)
//   - All other actions are rejected at execute time
//   - Tool is optional: true — invisible to agent unless tools.allow includes it

import { createConnection } from "node:net";

const ACTIONS = [
  "gateway_health",
  "gateway_restart",
  "validate_openclaw_json_candidate",
  "deploy_openclaw_json_candidate",
  "snapshot_pre",
  "snapshot_post",
  "vault_sync",
  "rollback_prepare",
];

const SCHEMA_PATHS = {
  request: "broker/schemas/host-ops-request.schema.json",
  result: "broker/schemas/host-ops-result.schema.json",
  actions: "broker/schemas/actions/",
};

const STATUS_VALUES = ["ok", "error", "denied"];

// Fail-closed: only these actions are permitted in the current version.
// Expand this list deliberately as each action is validated for live use.
const ENABLED_ACTIONS = ["gateway_health", "gateway_restart", "validate_openclaw_json_candidate", "deploy_openclaw_json_candidate", "snapshot_pre", "snapshot_post", "rollback_prepare"];

/**
 * Build a schema-conformant broker request object.
 * @param {string} action - One of 8 supported actions
 * @param {object} inputs - Action-specific input object
 * @param {string} requestedBy - Identity string (e.g. "agent:main")
 * @param {string} [taskId] - OpenClaw task identifier
 * @returns {{ request: object, errors: string[] }}
 */
export function buildRequest(action, inputs, requestedBy, taskId) {
  const errors = [];

  if (!ACTIONS.includes(action)) {
    errors.push(`Unknown action: ${action}. Must be one of: ${ACTIONS.join(", ")}`);
  }
  if (!inputs || typeof inputs !== "object") {
    errors.push("inputs must be a non-null object");
  }
  if (!requestedBy || typeof requestedBy !== "string") {
    errors.push("requestedBy must be a non-empty string");
  }

  const now = new Date();
  const ts = now.toISOString().replace(/[-:T]/g, "").slice(0, 14);
  const rand = Math.random().toString(36).slice(2, 8);
  const requestId = `req-${ts}-${rand}`;
  const resolvedTaskId = taskId || `task-${ts}-${rand}`;

  const request = {
    action: action,
    request_id: requestId,
    task_id: resolvedTaskId,
    requested_by: requestedBy,
    inputs: inputs || {},
  };

  return { request, errors };
}

/**
 * Validate a request object against protocol rules (without JSON Schema library).
 * Returns list of validation errors (empty = valid).
 * @param {object} request - Request object to validate
 * @returns {string[]} errors
 */
export function validateRequest(request) {
  const errors = [];

  if (!request || typeof request !== "object") {
    return ["Request must be a non-null object"];
  }

  // Required fields
  for (const field of ["action", "request_id", "task_id", "requested_by", "inputs"]) {
    if (!(field in request)) {
      errors.push(`Missing required field: ${field}`);
    }
  }

  // Action enum
  if (request.action && !ACTIONS.includes(request.action)) {
    errors.push(`Invalid action: ${request.action}`);
  }

  // Type checks
  if (request.request_id && typeof request.request_id !== "string") {
    errors.push("request_id must be a string");
  }
  if (request.task_id && typeof request.task_id !== "string") {
    errors.push("task_id must be a string");
  }
  if (request.requested_by && typeof request.requested_by !== "string") {
    errors.push("requested_by must be a string");
  }
  if (request.inputs && typeof request.inputs !== "object") {
    errors.push("inputs must be an object");
  }
  if (request.inputs && Array.isArray(request.inputs)) {
    errors.push("inputs must be an object, not an array");
  }

  // No extra top-level fields (mirrors additionalProperties: false)
  const KNOWN_FIELDS = ["action", "request_id", "task_id", "requested_by", "inputs"];
  for (const key of Object.keys(request)) {
    if (!KNOWN_FIELDS.includes(key)) {
      errors.push(`Unknown top-level field: ${key}`);
    }
  }

  // Action-specific input validation
  if (request.action && request.inputs && errors.length === 0) {
    errors.push(...validateActionInputs(request.action, request.inputs));
  }

  return errors;
}

/**
 * Validate action-specific inputs.
 * @param {string} action
 * @param {object} inputs
 * @returns {string[]} errors
 */
function validateActionInputs(action, inputs) {
  const errors = [];

  switch (action) {
    case "gateway_health":
      // No required inputs
      break;

    case "gateway_restart":
      if (!inputs.reason || typeof inputs.reason !== "string") {
        errors.push("gateway_restart requires inputs.reason (string)");
      }
      break;

    case "validate_openclaw_json_candidate":
    case "deploy_openclaw_json_candidate":
      if (!inputs.candidate_path || typeof inputs.candidate_path !== "string") {
        errors.push(`${action} requires inputs.candidate_path (string)`);
      } else {
        if (!inputs.candidate_path.startsWith("/var/lib/openclaw/approvals/candidates/")) {
          errors.push("candidate_path must start with /var/lib/openclaw/approvals/candidates/");
        }
        if (inputs.candidate_path.includes("..")) {
          errors.push("candidate_path must not contain path traversal (..)");
        }
      }
      if (!inputs.expected_sha256 || typeof inputs.expected_sha256 !== "string") {
        errors.push(`${action} requires inputs.expected_sha256 (string)`);
      } else if (!/^[a-f0-9]{64}$/.test(inputs.expected_sha256)) {
        errors.push("expected_sha256 must be exactly 64 lowercase hex characters");
      }
      break;

    case "snapshot_pre":
    case "snapshot_post":
      if (!inputs.label || typeof inputs.label !== "string") {
        errors.push(`${action} requires inputs.label (string)`);
      } else if (inputs.label.length > 128) {
        errors.push("label exceeds 128 character limit");
      } else if (!/^[a-zA-Z0-9._-]+$/.test(inputs.label)) {
        errors.push("label must be alphanumeric with dots, hyphens, underscores only");
      }
      if (!inputs.reason || typeof inputs.reason !== "string") {
        errors.push(`${action} requires inputs.reason (string)`);
      }
      break;

    case "vault_sync":
      if (!inputs.snapshot_name || typeof inputs.snapshot_name !== "string") {
        errors.push("vault_sync requires inputs.snapshot_name (string)");
      } else if (inputs.snapshot_name.length > 128) {
        errors.push("snapshot_name exceeds 128 character limit");
      } else if (!/^[a-zA-Z0-9._-]+$/.test(inputs.snapshot_name)) {
        errors.push("snapshot_name must be alphanumeric with dots, hyphens, underscores only");
      }
      break;

    case "rollback_prepare":
      if (!inputs.target_snapshot || typeof inputs.target_snapshot !== "string") {
        errors.push("rollback_prepare requires inputs.target_snapshot (string)");
      } else if (inputs.target_snapshot.length > 128) {
        errors.push("target_snapshot exceeds 128 character limit");
      } else if (!/^[a-zA-Z0-9._-]+$/.test(inputs.target_snapshot)) {
        errors.push("target_snapshot must be alphanumeric with dots, hyphens, underscores only");
      }
      if (!inputs.reason || typeof inputs.reason !== "string") {
        errors.push("rollback_prepare requires inputs.reason (string)");
      }
      break;
  }

  return errors;
}

/**
 * Validate a result object against protocol rules.
 * @param {object} result - Result object to validate
 * @returns {string[]} errors
 */
export function validateResult(result) {
  const errors = [];

  if (!result || typeof result !== "object") {
    return ["Result must be a non-null object"];
  }

  for (const field of ["ok", "action", "request_id", "task_id", "status"]) {
    if (!(field in result)) {
      errors.push(`Missing required field: ${field}`);
    }
  }

  if (typeof result.ok !== "boolean") {
    errors.push("ok must be a boolean");
  }
  if (result.status && !STATUS_VALUES.includes(result.status)) {
    errors.push(`Invalid status: ${result.status}. Must be one of: ${STATUS_VALUES.join(", ")}`);
  }

  // ok/status consistency
  if (result.ok === true && result.status !== "ok") {
    errors.push("ok=true requires status='ok'");
  }
  if (result.ok === false && result.status === "ok") {
    errors.push("ok=false must not have status='ok'");
  }

  return errors;
}

/**
 * Export skeleton info for introspection.
 */
export function hostOpsToolSkeleton() {
  return {
    status: "phase2-registerTool-implemented",
    note: "register(api) calls api.registerTool with optional:true. Tool supports gateway_health, gateway_restart, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, and rollback_prepare. Agent-facing activation requires tools.allow to include host_ops.",
    enabledActions: ENABLED_ACTIONS,
    allActions: ACTIONS,
    schemas: SCHEMA_PATHS,
  };
}

/**
 * Create the host_ops agent tool object.
 *
 * Tool shape follows AgentTool interface from @mariozechner/pi-agent-core:
 *   { name, label, description, parameters, execute }
 * Parameters is a plain JSON Schema object (equivalent to TypeBox output).
 *
 * @returns {object} AgentTool-compatible tool object
 */
function createHostOpsTool() {
  return {
    name: "host_ops",
    label: "Host Operations",
    description:
      "Execute host operations via the host-ops broker daemon. " +
      "Sends a structured JSON request over Unix socket to the broker, " +
      "which delegates to root-owned wrapper scripts. " +
      "Currently supported actions: gateway_health, gateway_restart, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, rollback_prepare. " +
      "NOTE: gateway_restart uses --no-block dispatch and returns before the restart completes. " +
      "Always call gateway_health afterward to verify the gateway is healthy after the restart completes.",
    parameters: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ENABLED_ACTIONS,
          description:
            "Host operation action to execute. " +
            "Currently supported: gateway_health, gateway_restart, validate_openclaw_json_candidate, deploy_openclaw_json_candidate, snapshot_pre, snapshot_post, rollback_prepare. " +
            "gateway_restart dispatches restart via --no-block and requires a follow-up gateway_health call to verify the gateway is healthy.",
        },
        inputs: {
          type: "object",
          properties: {
            label: {
              type: "string",
              description:
                "Snapshot label (required for snapshot_pre, snapshot_post). " +
                "Alphanumeric with dots, hyphens, underscores only, max 128 chars.",
            },
            reason: {
              type: "string",
              description:
                "Reason for the operation (required for gateway_restart, snapshot_pre, snapshot_post, rollback_prepare).",
            },
            target_snapshot: {
              type: "string",
              description:
                "Name of target snapshot to verify (required for rollback_prepare). " +
                "Alphanumeric with dots, hyphens, underscores only, max 128 chars.",
            },
            candidate_path: {
              type: "string",
              description:
                "Absolute path to candidate JSON file (required for validate_openclaw_json_candidate, deploy_openclaw_json_candidate). " +
                "Must start with /var/lib/openclaw/approvals/candidates/.",
            },
            expected_sha256: {
              type: "string",
              description:
                "Expected SHA256 hash of candidate file, 64 lowercase hex characters (required for validate_openclaw_json_candidate, deploy_openclaw_json_candidate).",
            },
          },
          description:
            "Action-specific input object. Required for validate_openclaw_json_candidate and deploy_openclaw_json_candidate " +
            "(needs candidate_path, expected_sha256). Required for snapshot_pre and snapshot_post (needs label, reason). " +
            "Required for rollback_prepare (needs target_snapshot, reason). Required for gateway_restart (needs reason). " +
            "Not needed for gateway_health.",
        },
      },
      required: ["action"],
      additionalProperties: false,
    },

    async execute(toolCallId, params) {
      // Fail-closed: reject unknown top-level parameters (defense-in-depth
      // beyond schema additionalProperties:false which depends on runtime)
      const ALLOWED_PARAMS = ["action", "inputs"];
      if (params && typeof params === "object") {
        const extraKeys = Object.keys(params).filter(k => !ALLOWED_PARAMS.includes(k));
        if (extraKeys.length > 0) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  ok: false,
                  status: "error",
                  message: `Unknown parameter(s): ${extraKeys.join(", ")}. Only action and inputs are accepted.`,
                }),
              },
            ],
            details: { unknownParams: extraKeys },
          };
        }
      }

      const action =
        params && typeof params.action === "string" ? params.action : "";

      // Fail-closed: reject anything not in ENABLED_ACTIONS
      if (!ENABLED_ACTIONS.includes(action)) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                ok: false,
                status: "denied",
                message: `Action '${action}' is not enabled. Currently supported: ${ENABLED_ACTIONS.join(", ")}`,
              }),
            },
          ],
          details: { denied: true, action },
        };
      }

      // Read and validate inputs — fail-closed on non-object
      const rawInputs = params && params.inputs !== undefined ? params.inputs : {};
      if (rawInputs === null || typeof rawInputs !== "object" || Array.isArray(rawInputs)) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                ok: false,
                status: "error",
                message: "inputs must be a plain object",
              }),
            },
          ],
          details: { inputsError: true },
        };
      }

      // Build request using existing helper
      const { request, errors: buildErrors } = buildRequest(
        action,
        rawInputs,
        "agent:main",
      );
      if (buildErrors.length > 0) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                ok: false,
                status: "error",
                message: `Request build failed: ${buildErrors.join("; ")}`,
              }),
            },
          ],
          details: { buildErrors },
        };
      }

      // Validate request using existing helper
      const validationErrors = validateRequest(request);
      if (validationErrors.length > 0) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                ok: false,
                status: "error",
                message: `Request validation failed: ${validationErrors.join("; ")}`,
              }),
            },
          ],
          details: { validationErrors },
        };
      }

      // Send to broker via Unix socket
      let result;
      try {
        result = await sendRequest(request);
      } catch (err) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                ok: false,
                status: "error",
                message: `Broker transport error: ${err.message}`,
              }),
            },
          ],
          details: { transportError: err.message },
        };
      }

      // Validate broker result using existing helper
      const resultErrors = validateResult(result);
      if (resultErrors.length > 0) {
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                ok: false,
                status: "error",
                message: `Broker returned invalid result: ${resultErrors.join("; ")}`,
                raw: result,
              }),
            },
          ],
          details: { resultErrors, raw: result },
        };
      }

      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: result,
      };
    },
  };
}

/**
 * OpenClaw plugin lifecycle entry point.
 * Called by gateway loader when the plugin is activated.
 *
 * Registers the "host_ops" agent-facing tool via api.registerTool().
 * The tool is registered as optional: true, meaning it will NOT appear
 * in the agent's tool list unless explicitly enabled in tools.allow
 * (e.g. main.tools.allow) in /etc/openclaw/openclaw.json.
 *
 * @param {object} api - OpenClaw Plugin SDK API object (OpenClawPluginApi)
 */
export default function register(api) {
  api.registerTool(createHostOpsTool(), { optional: true });
}

// --- Transport: Unix socket client ---

const DEFAULT_SOCKET_PATH = "/run/openclaw/broker.sock";
const CONNECT_TIMEOUT_MS = 5000;
const READ_TIMEOUT_MS = 30000;

/**
 * Send a request to the broker via Unix domain socket.
 * Fail-closed: any transport error rejects with a structured error.
 *
 * @param {object} request - A validated broker request object
 * @param {string} [socketPath] - Unix socket path (default: BROKER_SOCKET_PATH env or /run/openclaw/broker.sock)
 * @param {object} [options] - Optional overrides: { connectTimeout, readTimeout }
 * @returns {Promise<object>} Parsed result object from broker
 */
export function sendRequest(request, socketPath, options) {
  const resolvedPath =
    socketPath ||
    (typeof process !== "undefined" && process.env && process.env.BROKER_SOCKET_PATH) ||
    DEFAULT_SOCKET_PATH;
  const connectTimeout = (options && options.connectTimeout) || CONNECT_TIMEOUT_MS;
  const readTimeout = (options && options.readTimeout) || READ_TIMEOUT_MS;

  return new Promise((resolve, reject) => {
    const chunks = [];
    let connectTimerId = null;
    let readTimerId = null;
    let settled = false;

    function settle(fn, value) {
      if (settled) return;
      settled = true;
      clearTimeout(connectTimerId);
      clearTimeout(readTimerId);
      fn(value);
    }

    // Connect timeout
    connectTimerId = setTimeout(() => {
      settle(reject, new Error(`Connect timeout after ${connectTimeout}ms to ${resolvedPath}`));
      try {
        conn.destroy();
      } catch (_) {
        /* ignore */
      }
    }, connectTimeout);

    let conn;
    try {
      conn = createConnection({ path: resolvedPath });
    } catch (err) {
      settle(reject, new Error(`Failed to create connection to ${resolvedPath}: ${err.message}`));
      return;
    }

    conn.on("connect", () => {
      clearTimeout(connectTimerId);

      // Start read timeout
      readTimerId = setTimeout(() => {
        settle(reject, new Error(`Read timeout after ${readTimeout}ms`));
        try {
          conn.destroy();
        } catch (_) {
          /* ignore */
        }
      }, readTimeout);

      // Send request and half-close
      const payload = JSON.stringify(request);
      conn.end(payload);
    });

    conn.on("data", (chunk) => {
      chunks.push(chunk);
    });

    conn.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf-8").trim();
      if (!raw) {
        settle(reject, new Error("Broker returned empty response"));
        return;
      }
      try {
        const result = JSON.parse(raw);
        settle(resolve, result);
      } catch (err) {
        settle(reject, new Error(`Broker returned non-JSON response: ${raw.slice(0, 200)}`));
      }
    });

    conn.on("error", (err) => {
      if (err.code === "ENOENT") {
        settle(reject, new Error(`Broker unavailable: socket not found at ${resolvedPath}`));
      } else if (err.code === "ECONNREFUSED") {
        settle(reject, new Error(`Broker unavailable: connection refused at ${resolvedPath}`));
      } else if (err.code === "EACCES") {
        settle(reject, new Error(`Broker socket permission denied: ${resolvedPath}`));
      } else {
        settle(reject, new Error(`Broker connection error: ${err.message}`));
      }
    });
  });
}

export { ACTIONS, SCHEMA_PATHS, STATUS_VALUES };
