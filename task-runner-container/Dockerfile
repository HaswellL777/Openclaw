FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WORKSPACE_ROOT=/workspace
ENV TASK_REPO_PATH=/workspace/repo
ENV TASK_INPUTS_PATH=/workspace/inputs
ENV TASK_OUTPUTS_PATH=/workspace/outputs
ENV ARTIFACT_EXPORT_PATH=/workspace/outputs/export
ENV HOME=/home/runner

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        git \
        jq \
        python3 \
        ripgrep \
    && rm -rf /var/lib/apt/lists/*

# OpenClaw gateway runs docker exec as the openclaw user (UID 997, GID 984).
# The container user must match so file ownership is correct and /home/runner
# is accessible when operator does `docker exec -it <container> bash`.
RUN groupadd --gid 984 runner \
    && useradd --uid 997 --gid 984 --create-home --home-dir /home/runner --shell /bin/bash runner \
    && mkdir -p /workspace/repo /workspace/inputs /workspace/outputs/export \
    && chmod -R 1777 /workspace \
    && chown -R runner:runner /home/runner

COPY entrypoint.sh /usr/local/bin/task-runner-entrypoint
COPY bootstrap/prepare-workspace.sh /usr/local/bin/prepare-workspace
COPY bootstrap/bootstrap-codex.sh /usr/local/bin/bootstrap-codex
COPY bootstrap/bootstrap-claudecode.sh /usr/local/bin/bootstrap-claudecode

RUN chmod 0755 \
    /usr/local/bin/task-runner-entrypoint \
    /usr/local/bin/prepare-workspace \
    /usr/local/bin/bootstrap-codex \
    /usr/local/bin/bootstrap-claudecode

USER runner
WORKDIR /workspace/repo

# OpenClaw sandbox.docker manages container lifecycle via docker exec.
# The container must stay running; OpenClaw will exec tool commands into it.
# Use CMD (not ENTRYPOINT) so OpenClaw can override the command if needed.
# OpenClaw typically sets CMD to "sleep infinity" itself.
ENTRYPOINT []
CMD ["sleep", "infinity"]
