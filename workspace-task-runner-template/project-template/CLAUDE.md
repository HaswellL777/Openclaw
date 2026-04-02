# Task Project — Claude Code 容器内执行规则

## 你是谁
你是 OpenClaw task-runner 通过 ACP 启动的 Claude Code 会话，在 Docker 容器内执行具体工程任务。

## 安全边界

### 禁止操作
- **禁止**访问容器外的宿主机文件系统
- **禁止**直接修改 `/etc/openclaw/openclaw.json` 或任何宿主机配置
- **禁止**执行 `systemctl`、`docker`、`btrfs` 等宿主机管理命令
- **禁止**直接操作 snapshot 或 Vault
- **禁止**启动网络服务或监听端口
- **禁止**安装系统级包（`apt install` 等），除非任务明确要求且在 pip 范围内

### 允许操作
- 读写 `/workspace/` 下所有文件（knowledge/ 除外，只读）
- 读写当前任务目录 `/workspace/outputs/<task-id>/`
- 使用 Python、Node.js、git、常见 CLI 工具
- 通过 pip 安装 Python 包
- 生成 `host-change-request.json` 请求宿主机变更（由 main agent 审批）

## 输出规范

所有输出写入 `/workspace/outputs/<task-id>/`：

| 文件 | 必须 | 说明 |
|------|------|------|
| `summary.json` | ✅ | 机器可读结果，遵循 `schemas/task-runner-summary.schema.json` |
| `summary.md` | ✅ | 人类可读摘要 |
| `plan.md` | 推荐 | 执行计划 |
| `diff.patch` | 如有代码改动 | unified diff |
| `test.log` | 如运行了测试 | 测试日志 |
| `lint.log` | 如运行了 lint | lint 结果 |
| `host-change-request.json` | 如需宿主机变更 | 遵循 `schemas/host-change-request.schema.json` |

## 工作流

1. 理解任务要求
2. 制定计划，写入 `plan.md`
3. 执行实现
4. 运行测试/验证
5. 写 `summary.json` + `summary.md`
6. 如需宿主机变更，写 `host-change-request.json`

## 质量标准

- 先小范围验证，再全量执行
- 失败时把日志写入 `logs/`，在 `summary.json` 中标记 `status: "failed"`
- 不要猜测——不确定的行为从源码找证据
- 保持改动最小化、可审查
