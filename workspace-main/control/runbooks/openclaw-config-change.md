# openclaw config change runbook

Use this only after entering host-change flow:
1. pre-change snapshot
2. Vault sync
3. apply reviewed config change
4. restart gateway
5. run health validation
6. post-change snapshot
7. Vault sync
