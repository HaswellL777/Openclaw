# host-ops-tool plugin skeleton

This is a development-only plugin skeleton for Phase 2 dev-repo prep.

Important:
- Do not copy this directory into the runtime extensions path
- Do not deploy to `/var/lib/openclaw/.openclaw/extensions/` until Phase 2 live deployment
- Real manifest fields must be filled only after verifying the official plugin schema
- This skeleton does NOT connect to a live broker

Planned role:
- Receive structured host_ops requests from main agent
- Forward validated requests to the broker via Unix socket
- Never expose arbitrary shell execution

Current contents:
- `index.js` — Plugin skeleton with request builder and validator functions
- `package.json` — Package metadata (private, not publishable)
- `manifest-notes.md` — Notes on deferred manifest work
- `lib/build-request.sh` — Shell-based request fixture generator for testing
- `lib/validate-request.sh` — Shell-based request validator for testing
