# host-ops broker skeleton

This directory contains the future host-ops broker framework.

Phase 0 status:
- skeleton only
- no live socket
- no deployment
- no wrapper execution from this repo

Design constraints:
- structured requests only
- no free-form shell
- only root-owned wrappers in later phases
- request-id / task-id must be preserved end-to-end
