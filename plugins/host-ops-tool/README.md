# host-ops-tool plugin skeleton

This is a development-only plugin skeleton.

Important:
- do not copy this directory into the runtime extensions path
- do not deploy to /var/lib/openclaw/.openclaw/extensions during Phase 0
- real manifest fields must be filled only after verifying the official plugin schema

Planned role:
- receive structured host_ops requests from main
- forward validated requests to the broker
- never expose arbitrary shell execution
