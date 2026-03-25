#!/usr/bin/env bash
# tests/test-phase4-readiness.sh
# Comprehensive validation for Phase 4 deployment
#
# Run AFTER all operator actions are complete.
# This script generates commands for the operator to run and check.
# It does NOT execute live commands itself.

set -euo pipefail

PASS=0
FAIL=0
SKIP=0

check() {
    local desc="$1"
    local cmd="$2"
    echo "──────────────────────────────────────────"
    echo "CHECK: $desc"
    echo "  CMD: $cmd"
    echo ""
}

section() {
    echo ""
    echo "══════════════════════════════════════════"
    echo "SECTION: $1"
    echo "══════════════════════════════════════════"
}

# ─── Section 1: Pre-flight ───
section "Pre-flight checks"

check "Node.js version >= 22.16" \
    "node --version  # expect >= v22.16.0"

check "OpenClaw version" \
    "sudo -u openclaw openclaw --version  # expect 2026.3.23-2 if upgraded, or 2026.3.13"

check "Gateway running" \
    "sudo systemctl status openclaw-gateway  # expect active (running)"

check "Feishu channel responsive" \
    "# Send a test message via Feishu, verify agent responds"

# ─── Section 2: vLLM shutdown ───
section "vLLM shutdown verification"

check "vLLM not running" \
    "ps aux | grep -v grep | grep vllm  # expect no output"

check "GPU memory freed" \
    "nvidia-smi  # expect Processes: none, Memory Used: ~0MB"

check "vLLM service disabled" \
    "systemctl status vllm 2>&1 | grep -E 'inactive|not-found'  # expect inactive or not found"

# ─── Section 3: Hook cleanup ───
section "Hook & plugin cleanup verification"

check "No tool-audit-plugin in plugins.allow" \
    "grep -c 'tool-audit-plugin' /etc/openclaw/openclaw.json  # expect 0"

check "No hooks block" \
    "grep -c 'tool-audit-probe' /etc/openclaw/openclaw.json  # expect 0"

check "Gateway healthy after cleanup" \
    "sudo journalctl -u openclaw-gateway -n 20 --no-pager | grep -i error  # expect no errors"

# ─── Section 4: Docker image rebuild ───
section "Docker image verification"

check "Full image exists" \
    "sudo docker images openclaw-task-claude --format '{{.Tag}}'  # expect 2026-03-v3-full"

check "Scrapling in full image" \
    "sudo docker run --rm openclaw-task-claude:2026-03-v3-full python3 -c 'import scrapling; print(scrapling.__version__)'  # expect version number"

check "GPU image exists (if built)" \
    "sudo docker images openclaw-task-claude --format '{{.Tag}}' | grep gpu  # expect 2026-03-v3-gpu"

check "PyTorch CUDA in GPU image" \
    "sudo docker run --rm --gpus all openclaw-task-claude:2026-03-v3-gpu python3 -c 'import torch; print(torch.cuda.is_available())'  # expect True"

check "uv in GPU image" \
    "sudo docker run --rm openclaw-task-claude:2026-03-v3-gpu uv --version  # expect version number"

check "Container UID correct" \
    "sudo docker run --rm openclaw-task-claude:2026-03-v3-full id  # expect uid=997(runner) gid=984(runner)"

# ─── Section 5: Long-running tasks config ───
section "Long-running tasks configuration"

check "scope is shared" \
    "grep -A5 'task-runner' /etc/openclaw/openclaw.json | grep scope  # expect shared"

check "runTimeoutSeconds increased" \
    "grep runTimeoutSeconds /etc/openclaw/openclaw.json  # expect 14400"

check "archiveAfterMinutes increased" \
    "grep archiveAfterMinutes /etc/openclaw/openclaw.json  # expect 1440"

check "prune idleHours increased" \
    "grep idleHours /etc/openclaw/openclaw.json  # expect 24"

check "Shared scope: container reuse" \
    "# From Feishu, spawn two consecutive task-runner sessions
# Second should reuse the same container (check docker ps output)"

check "Shared scope: file persistence" \
    "# First session: create /workspace/outputs/test-persist.txt
# Second session: verify file exists"

# ─── Section 6: Knowledge repos ───
section "Knowledge repos (LabClaw + autoresearch)"

check "LabClaw cloned" \
    "ls /home/nick/repos/LabClaw/  # expect SKILL.md files"

check "autoresearch cloned" \
    "ls /home/nick/repos/autoresearch/  # expect train.py, prepare.py, program.md"

check "Knowledge mount active" \
    "mount | grep knowledge  # expect bind mount from /home/nick/repos"

check "Container can see knowledge" \
    "sudo docker exec <container-id> ls /workspace/knowledge/  # expect LabClaw/ autoresearch/"

check "LabClaw SKILL.md readable" \
    "sudo docker exec <container-id> cat /workspace/knowledge/LabClaw/general/statistics/SKILL.md | head -5"

# ─── Section 7: ACP spike (after upgrade + config deploy) ───
section "ACP spike test (requires upgrade to 2026.3.22+ first)"

check "ACP enabled in config" \
    "grep -A3 '\"acp\"' /etc/openclaw/openclaw.json  # expect enabled: true"

check "No stale acpx plugin entry" \
    "grep -c 'acpx' /etc/openclaw/openclaw.json  # expect 0 (2026.3.22+) or 1-2 (2026.3.13)"

check "ANTHROPIC_BASE_URL set" \
    "grep ANTHROPIC_BASE_URL /etc/openclaw/openclaw.env  # expect https://new.motchat.com"

check "ANTHROPIC_API_KEY set" \
    "grep -c ANTHROPIC_API_KEY /etc/openclaw/openclaw.env  # expect 1 (don't print value)"

check "workspace-claude-engineer exists" \
    "ls -la /var/lib/openclaw/.openclaw/workspace-claude-engineer/  # expect directory"

check "Claude Code settings for openclaw user" \
    "sudo cat /var/lib/openclaw/.claude/settings.json  # expect allowedDirectories"

check "ACP session spawn test" \
    "# From Feishu: '使用 claude-engineer 在 task-workspaces 创建 hello.txt'
# Check: sudo journalctl -u openclaw-gateway -n 50 | grep -i acp
# Check: ls /var/lib/openclaw/task-workspaces/hello.txt"

check "ACP session respects TTL" \
    "# ACP session should auto-terminate after 60 min
# Check: ps aux | grep claude  # after 60min, no claude process"

# ─── Section 8: Memory system ───
section "Memory system verification"

check "MEMORY.md in live workspace" \
    "sudo cat /var/lib/openclaw/.openclaw/workspace-main/MEMORY.md  # expect content"

check "memory/ directory exists" \
    "sudo ls /var/lib/openclaw/.openclaw/workspace-main/memory/  # expect directory"

check "Agent can write memory" \
    "# From Feishu: '记住：测试时间 2026-03-25'
# Then check: sudo ls /var/lib/openclaw/.openclaw/workspace-main/memory/
# Expect: 2026-03-25.md or MEMORY.md updated"

# ─── Section 9: Workspace publish ───
section "Workspace publish verification"

check "workspace-main-template updated" \
    "ls workspace-main-template/skills/task-delegation/SKILL.md  # expect exists"

check "Publish script runs" \
    "bash scripts/publish-workspace-main.sh --dry-run  # expect success"

check "Published workspace has new skills" \
    "sudo ls /var/lib/openclaw/.openclaw/workspace-main/skills/  # expect task-delegation/"

check "Published workspace has MEMORY.md" \
    "sudo cat /var/lib/openclaw/.openclaw/workspace-main/MEMORY.md | head -3  # expect content"

# ─── Section 10: Upgrade verification (if upgraded) ───
section "OpenClaw 2026.3.23-2 upgrade verification (if applicable)"

check "Version correct" \
    "sudo -u openclaw openclaw --version  # expect 2026.3.23-2"

check "Doctor clean" \
    "sudo -u openclaw openclaw doctor  # expect no critical issues"

check "Feishu channel still works" \
    "# Send message, verify response"

check "Broker still works" \
    "# From Feishu: '执行系统健康检查' → should call gateway_health"

check "skills command available" \
    "sudo -u openclaw openclaw skills list  # expect list of installed skills"

check "No CLAWDBOT/MOLTBOT env vars" \
    "env | grep -iE 'clawdbot|moltbot'  # expect no output"

# ─── Section 11: GPU passthrough (if GPU image built) ───
section "GPU passthrough verification"

check "nvidia-container-toolkit installed" \
    "dpkg -l | grep nvidia-container-toolkit  # expect installed"

check "Container GPU visible" \
    "sudo docker run --rm --gpus all openclaw-task-claude:2026-03-v3-gpu nvidia-smi  # expect GPU info"

check "PyTorch CUDA functional" \
    "sudo docker run --rm --gpus all openclaw-task-claude:2026-03-v3-gpu python3 -c \"
import torch
x = torch.randn(100, 100, device='cuda')
print(f'CUDA tensor created on {x.device}')
\"  # expect 'CUDA tensor created on cuda:0'"

# ─── Summary ───
echo ""
echo "══════════════════════════════════════════"
echo "TEST PLAN COMPLETE"
echo ""
echo "Total checks: ~40"
echo "Sections: 11"
echo ""
echo "Recommended execution order:"
echo "  1. Pre-flight (Section 1)"
echo "  2. vLLM shutdown (Section 2)"
echo "  3. Hook cleanup + config deploy (Section 3)"
echo "  4. OpenClaw upgrade to 2026.3.23-2 (Section 10)"
echo "  5. Docker image rebuild (Section 4)"
echo "  6. Long-running tasks config (Section 5)"
echo "  7. Knowledge repos (Section 6)"
echo "  8. Workspace publish (Section 9)"
echo "  9. Memory system (Section 8)"
echo "  10. ACP spike (Section 7)"
echo "  11. GPU passthrough (Section 11)"
echo "══════════════════════════════════════════"
