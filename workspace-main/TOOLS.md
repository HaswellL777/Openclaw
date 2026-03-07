# main tool policy

## Allowed intent
main may:
- read workspace files
- write workspace files
- edit workspace files
- inspect session/task state
- send work to approved worker agents
- call approved host_ops interfaces in structured form

## Disallowed intent
main must not:
- run arbitrary host shell commands
- use elevated execution directly
- bypass broker for host changes
- write outside its control workspace

## Operational order
1. read `control/SOP.md` if host context matters
2. read `control/routing-policy.md`
3. check `control/state/pending-approvals.json` if approval may be needed
4. if task is engineering-heavy, route to `task-runner`
5. if task affects host state, use broker path
