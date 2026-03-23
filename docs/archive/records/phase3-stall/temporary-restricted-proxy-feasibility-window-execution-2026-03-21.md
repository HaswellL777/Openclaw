# Temporary Restricted Proxy Feasibility Window Execution Evidence Record

> 日期：2026-03-21
> 文档类型：**execution evidence record**
> evidence bundle：`artifacts/phase3/temporary-restricted-proxy-feasibility-window-exp-docker-access-feasibility-20260321-131819/`
> 结果：**HARD_STOP**
> 唯一 hard-stop reason：**hello-world image missing**
> 文档性质：**这是执行证据记录，不是 Phase 3 implementation record，不是 docker-prerequisite establishment completion record**

---

## 1. 记录边界

本记录只收口 `temporary-restricted-proxy-feasibility-window` 在 `2026-03-21` 的执行证据。

本记录**不**表示：

- Phase 3 已开始实施
- `docker-prerequisite-establishment-for-phase3` 已完成
- temporary restricted proxy execution 已实际启动
- proxy/helper/candidate 已被冻结为长期终态

以下结论仅基于 bundle 内可直接引用的文件，不补写 bundle 之外的运行态事实。

## 2. 直接证据锚点

### 2.1 validate-only / helper 准备物

- `freeze-card.env`
- `57-current-candidate-plugins.json`
- `58-validate-only-candidate.sha256.txt`
- `59-validate-only-candidate-plugins.json`
- `60-validate-only-config-file.txt`
- `61-validate-only-config-validate.txt`
- `70-helper-ls.txt`
- `71-helper-compile.txt`
- `72-helper.sha256.txt`

### 2.2 pre-proxy 观测

- `73-docker-service-active-pre-proxy.txt`
- `74-docker-socket-active-pre-proxy.txt`
- `75-docker-sock-pre-proxy.txt`
- `76-docker-group-pre-proxy.txt`
- `77-openclaw-id-pre-proxy.txt`
- `78-python3-path.txt`
- `79-systemd-run-path.txt`
- `80-hello-world-image-check.txt`
- `81-openclaw-direct-docker-info.txt`
- `90-docker-image-ls-pre-proxy.txt`
- `95-sudo-docker-image-inspect-hello-world.json`
- `96-sudo-docker-image-ls-pre-proxy.txt`

### 2.3 hard-stop / 未启动 / post-stop 状态

- `89-hard-stop-reason.txt`
- `91-proxy-socket-presence.txt`
- `92-proxy-unit-active-if-any.txt`
- `93-proxy-journal-if-any.txt`
- `94-audit-jsonl-presence.txt`
- `97-window-result-summary.txt`
- `98-gateway-active-post-stop.txt`
- `99-broker-active-post-stop.txt`

## 3. 证据支撑的事实

### 3.1 validate-only 候选与 helper 文件存在

- bundle 中存在冻结卡，固定了本次实验包的 `EXP_RUN_ID`、候选 endpoint、isolated dir 与预期 evidence sink，见 `freeze-card.env`。
- helper 文件 `docker_restricted_proxy.py` 已存在于隔离目录，并留下 ls、compile 与 sha256 证据，见 `70-helper-ls.txt`、`71-helper-compile.txt`、`72-helper.sha256.txt`。
- validate-only 候选文件已生成并通过 config validate，见 `58-validate-only-candidate.sha256.txt`、`60-validate-only-config-file.txt`、`61-validate-only-config-validate.txt`。

### 3.2 pre-proxy Docker / access 观测已记录

- `docker.service` 在 pre-proxy 时为 `active`，见 `73-docker-service-active-pre-proxy.txt`。
- `docker.socket` 在 pre-proxy 时为 `active`，见 `74-docker-socket-active-pre-proxy.txt`。
- `/var/run/docker.sock` 存在，权限为 `root:docker` / `srw-rw----`，见 `75-docker-sock-pre-proxy.txt`。
- `docker` 组存在，见 `76-docker-group-pre-proxy.txt`。
- `openclaw` 用户存在，见 `77-openclaw-id-pre-proxy.txt`。
- `python3` 与 `systemd-run` 路径已记录，见 `78-python3-path.txt`、`79-systemd-run-path.txt`。
- `openclaw` 直接访问 Docker daemon 仍报 `permission denied`，见 `81-openclaw-direct-docker-info.txt`。

### 3.3 唯一 hard-stop reason 是 hello-world image missing

- `80-hello-world-image-check.txt` 记录 `hello_world_present_exit=1`。
- `95-sudo-docker-image-inspect-hello-world.json` 记录为 `[]`。
- `96-sudo-docker-image-ls-pre-proxy.txt` 只有表头，没有 `hello-world` 条目。
- `89-hard-stop-reason.txt` 明确写为：`HARD_STOP=hello-world image missing; do not start temporary restricted proxy window`。
- `97-window-result-summary.txt` 明确写为：
  - `WINDOW_RESULT=HARD_STOP`
  - `HARD_STOP_REASON=hello-world image missing`

基于以上锚点，本次记录只接受一个 hard-stop reason：

- **hello-world image missing**

## 4. 明确未发生的事项

### 4.1 proxy not started

以下证据直接支撑 proxy 未启动：

- `97-window-result-summary.txt`：`PROXY_NOT_STARTED=yes`
- `91-proxy-socket-presence.txt`：`proxy_socket_present=no`
- `92-proxy-unit-active-if-any.txt`：`inactive`
- `93-proxy-journal-if-any.txt`：`-- No entries --`

因此，本次窗口只能写为：

- **proxy not started**

### 4.2 audit jsonl not created

以下证据直接支撑 audit jsonl 未创建：

- `94-audit-jsonl-presence.txt`：`audit_jsonl_exists=no`
- `97-window-result-summary.txt`：`AUDIT_JSONL_PRESENT=no`

因此，本次窗口只能写为：

- **audit jsonl not created**

## 5. 窗口收口时的服务状态

以下文件直接支撑窗口收口时 gateway / broker 仍保持 active：

- `98-gateway-active-post-stop.txt`：`active`
- `99-broker-active-post-stop.txt`：`active`

因此，本次记录明确写为：

- **gateway remained active**
- **broker remained active**

## 6. 结论

本次 `temporary-restricted-proxy-feasibility-window` 的 execution evidence 只能收口为：

- **HARD_STOP**
- **唯一 hard-stop reason = hello-world image missing**
- **proxy not started**
- **audit jsonl not created**
- **gateway remained active**
- **broker remained active**

这份记录是执行证据收口，不是 Phase 3 implementation record，也不是 docker-prerequisite establishment completion record。
