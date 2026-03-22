# Hello-World Image Prerequisite Remediation Micro-Window

> 日期：2026-03-22
> 文档类型：**execution evidence record**
> live baseline：OpenClaw `2026.3.13`
> 结果：**PASS**
> 文档性质：**这是 prerequisite-only remediation 微窗口的执行证据，不是 temporary restricted proxy execution record，不是 Phase 3 implementation record，不是 docker-prerequisite establishment completion record**

---

## 1. 记录边界

本记录只收口 `2026-03-22` 的受限 remediation 微窗口，其唯一目标是：

- 恢复 root/operator 对 Docker registry 的可达性；
- 补齐 `hello-world` image prerequisite；
- 为后续是否重新进入 temporary restricted proxy feasibility execution 的进入评审提供直接证据。

本记录**不**表示：

- temporary restricted proxy execution 已启动；
- proxy audit jsonl 已创建；
- proxy execution 已验证；
- `/etc/openclaw/openclaw.json` 或 `openclaw.live.json` 已修改；
- `openclaw` 用户组归属已变更；
- Phase 3 已进入 implementation 或 GO。

## 2. remediation 前直接证据

### 2.1 `hello-world` image 缺失

- `/etc/docker/daemon.json` 起初不存在。
- `sudo docker image inspect hello-world` 返回：
  - `[]`
  - `Error response from daemon: No such image: hello-world:latest`
- `sudo docker image ls hello-world` 只有表头，没有 `hello-world` 条目。

### 2.2 remediation 前服务健康

以下服务在 remediation 前均为 `active`：

- `docker.service`
- `docker.socket`
- `openclaw-gateway.service`
- `openclaw-broker.service`

## 3. remediation 变更内容

本窗口只执行了最小 Docker daemon registry reachability remediation：

- 创建 `/etc/docker/daemon.json`
- 只添加 `registry-mirrors`
- 未添加其他 Docker daemon 配置项

最终写入内容为：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
```

随后执行：

- `sudo systemctl restart docker.service`

重启后：

- `docker.service = active`
- `docker.socket = active`

## 4. prerequisite 已补齐的直接证据

registry reachability remediation 后，以下直接证据表明 `hello-world` prerequisite 已补齐：

- `timeout 180s sudo docker pull hello-world` 成功；
- 输出包含：
  - `Status: Downloaded newer image for hello-world:latest`
  - `docker.io/library/hello-world:latest`
- `sudo docker image inspect hello-world` 返回完整镜像元数据；
- `sudo docker image ls hello-world` 显示：
  - `hello-world   latest`

因此，本窗口可以直接收口为：

- **`hello-world` image prerequisite established**

## 5. remediation 后 post-check

以下服务在 remediation 后仍为 `active`：

- `docker.service`
- `docker.socket`
- `openclaw-gateway.service`
- `openclaw-broker.service`

因此，本次 remediation 未引入已观察到的 Docker / gateway / broker 健康退化。

## 6. snapshot / Vault evidence

### 6.1 变更前保护

- Pre snapshot：`root-pre-docker-mirror-remediation-2026-03-22-0940`
- Pre-window Vault sync：`root-auto-2026-03-22-0940`

### 6.2 变更后保护

- Post snapshot：`root-post-docker-mirror-remediation-2026-03-22-0944`
- Post-window Vault sync：`root-auto-2026-03-22-0944`

说明：

- root snapshot 仅覆盖根系统状态，不恢复 `/var/lib/openclaw` 运行态子卷内容；
- 本记录只把上述快照 / Vault evidence 作为本次最小 remediation 的保护锚点，不扩展为 proxy execution 或 Phase 3 rollback 叙事。

## 7. 明确未发生的事项

本窗口明确未发生以下事项：

- temporary restricted proxy **未启动**
- proxy audit jsonl **未创建**
- proxy execution **未验证**
- `/etc/openclaw/openclaw.json` **未修改**
- `openclaw.live.json` **未修改**
- `openclaw` 用户组归属 **未变更**
- Phase 3 implementation **未推进**

## 8. 结论

本次 `2026-03-22` remediation 微窗口只在 prerequisite-only 边界内完成了最小 Docker registry reachability 修复，并已形成 `hello-world` image 从“缺失”到“存在”的直接闭环证据。

本次记录只能收口为：

- **hello-world prerequisite 已补齐**
- **docker.service / docker.socket / gateway / broker 前后均保持 active**
- **temporary restricted proxy 未启动**
- **audit jsonl 未创建**
- **proxy execution 未验证**
- **Phase 3 仍为 NO-GO**

后续最多只意味着：

- 可以返回 temporary restricted proxy feasibility execution 的**进入评审**

它**不意味着**：

- temporary restricted proxy execution 已开始
- Phase 3 implementation 已开始
- Phase 3 已转为 GO
