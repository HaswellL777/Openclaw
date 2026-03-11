export function hostOpsToolSkeleton() {
  return {
    status: "phase2-prep",
    note: "Schemas and wrapper stubs in repo; broker not yet deployed",
    actions: [
      "gateway_health",
      "gateway_restart",
      "validate_openclaw_json_candidate",
      "deploy_openclaw_json_candidate",
      "snapshot_pre",
      "snapshot_post",
      "vault_sync",
      "rollback_prepare"
    ],
    schemas: {
      request: "broker/schemas/host-ops-request.schema.json",
      result: "broker/schemas/host-ops-result.schema.json",
      actions: "broker/schemas/actions/*.schema.json"
    }
  };
}
