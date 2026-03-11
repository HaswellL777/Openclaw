// host-ops-tool plugin skeleton
// Status: Phase 2 dev-repo prep — not for live deployment
// This module provides request building and validation functions
// for the host-ops broker protocol. It has no live dependencies.

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
    status: "phase2-dev-repo-prep",
    note: "Schemas, wrapper stubs, and protocol spec in repo; broker not yet deployed",
    actions: ACTIONS,
    schemas: SCHEMA_PATHS,
  };
}

export { ACTIONS, SCHEMA_PATHS, STATUS_VALUES };
