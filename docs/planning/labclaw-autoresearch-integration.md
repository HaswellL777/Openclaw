# LabClaw + autoresearch 集成方案

> 日期：2026-03-25
> 仓库：
>   - https://github.com/wu-yc/LabClaw（240 biomedical research SKILL.md）
>   - https://github.com/karpathy/autoresearch（ML 自动实验循环）
> Close-by：2026-03-28（clone + 初步测试）

---

## 1. LabClaw (wu-yc/LabClaw)

### 性质

纯 SKILL.md 仓库（240 个 Markdown 文件），无可执行代码。使用 OpenClaw SKILL.md 格式
（YAML frontmatter + Markdown 指令）。涵盖生物医学研究：基因组学、蛋白质组学、药物发现、
文献检索、数据分析等。

### 集成方式

**方式 1（推荐，2026.3.22+ 可用）：ClawHub 安装**
```bash
sudo -u openclaw openclaw skills install labclaw
# 或指定 GitHub 源：
sudo -u openclaw openclaw skills install https://github.com/wu-yc/LabClaw
```

**方式 2（当前 2026.3.13 可用）：Clone 到 knowledge 目录**
```bash
cd /home/nick/repos
git clone https://github.com/wu-yc/LabClaw.git

# 容器内通过 /workspace/knowledge/LabClaw/ 可见（mount --bind 已配置）
# Agent 可以读取 skill 文件但不会自动发现——需要手动引用
```

**方式 3（2026.3.22+ 可用）：extraDirs 配置**
在 openclaw.json 中添加：
```json5
{
  skills: {
    load: {
      extraDirs: ["/var/lib/openclaw/.openclaw/workspace-task-runner/knowledge/LabClaw"]
    }
  }
}
```
这样 LabClaw 的 SKILL.md 文件会被 OpenClaw skill 系统自动发现。

### 容器内可用性评估

| Skill 类别 | 数量 | 容器内可用 | 原因 |
|------------|------|-----------|------|
| general/ | 54 | 大部分可用 | 统计、ML、写作——Python + numpy/pandas 足够 |
| literature/ | 33 | 大部分可用 | 搜索 API + 文本处理——需网络 |
| visualization/ | 4 | 可用 | matplotlib/plotly——已装或可 pip install |
| bio/ | 86 | 部分可用 | 需 biopython/samtools/BLAST 等重型工具 |
| pharma/ | 36 | 部分可用 | 需 rdkit/DeepChem 等 |
| med/ | 22 | 少量可用 | 需医学专业工具 |
| vision/ | 5 | 需 GPU | 需 PyTorch + GPU |

**安全**：Skill 文件是纯 Markdown，不含可执行代码。OpenClaw skill 资格检查（`requires.bins`）
会自动过滤不满足依赖的 skill。

---

## 2. autoresearch (karpathy/autoresearch)

### 性质

ML 自动实验循环。Python 项目（~630 行），由外部 coding agent 驱动。Agent 反复
编辑 `train.py`、运行实验、评估结果（val_bpb）、git commit 或 reset。
每次实验固定 5 分钟。~12 实验/小时，一夜 ~100 实验。

### 依赖

- Python >= 3.10
- `uv` 包管理器
- PyTorch 2.9.1 (CUDA 12.8)
- GPU（RTX 5060 Ti 16GB 可用，需降配）
- 外部 coding agent（Claude Code / Codex）

### 集成方式

autoresearch 是一个完整的任务项目，不是 skill 库。集成方式：

**Step 1：Clone 到 knowledge**
```bash
cd /home/nick/repos
git clone https://github.com/karpathy/autoresearch.git
```

**Step 2：创建 autoresearch skill（task-runner / claude-engineer）**

autoresearch 的运行需要：
1. 一个持久化的工作目录（shared scope 容器或 ACP workspace）
2. GPU 透传（Dockerfile.gpu 镜像）
3. 外部 coding agent 驱动循环

最佳路径是 **ACP Claude Code session**（Phase 4 后）：
- Claude Code 作为驱动 agent，直接在 autoresearch repo 中工作
- 读 `program.md`，编辑 `train.py`，运行 `uv run train.py`，评估结果
- 这正是 autoresearch 设计的使用方式

当前（Phase 4 前）的替代方案：
- main agent 通过 sessions_spawn 多步驱动 task-runner
- 每步：编辑代码 → spawn 执行 → 读取结果 → 决定下一步
- 受限于 session scope（升级配置到 shared 后改善）

**Step 3：RTX 5060 Ti 16GB 适配**

autoresearch 默认配置面向 H100 (80GB)。16GB GPU 需要降配：

```python
# 在 train.py 中调整（agent 或 operator 修改）：
# - 减小 vocab_size
# - 降低 MAX_SEQ_LEN
# - 减小模型参数量
# - 用 torch.nn.functional.scaled_dot_product_attention 替代 FlashAttention-3
```

社区 fork `jsegov/autoresearch-win-rtx` 提供了消费级 GPU 适配方案，可参考。

**Step 4：容器环境**

使用 Dockerfile.gpu 镜像 + 额外安装 `uv`：
```dockerfile
# 在 Dockerfile.gpu Layer 4 中添加：
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
```

---

## 3. Operator 操作清单

### 立即可做

```bash
# 1. Clone 两个仓库
cd /home/nick/repos
git clone https://github.com/wu-yc/LabClaw.git
git clone https://github.com/karpathy/autoresearch.git

# 2. 验证 mount --bind 可见
ls /var/lib/openclaw/.openclaw/workspace-task-runner/knowledge/
# 期望看到 LabClaw/ 和 autoresearch/

# 3. 如果 knowledge 目录为空，检查 fstab mount
mount | grep knowledge
# 如果没挂载：
sudo mount --bind /home/nick/repos /var/lib/openclaw/.openclaw/workspace-task-runner/knowledge
sudo mount -o remount,bind,ro /var/lib/openclaw/.openclaw/workspace-task-runner/knowledge
```

### 升级到 2026.3.22+ 后

```bash
# 4. 用 ClawHub 安装 LabClaw skills（如果支持）
sudo -u openclaw openclaw skills install https://github.com/wu-yc/LabClaw

# 5. 或配置 extraDirs
# 在 openclaw.json 中添加 skills.load.extraDirs
```

### Phase 4 ACP 后

```bash
# 6. 使用 ACP Claude Code session 驱动 autoresearch
# 从飞书发送：
# "启动 autoresearch 实验循环：clone /workspace/knowledge/autoresearch 到工作目录，
#  按 program.md 指令开始自动实验，目标 val_bpb 最小化"
```

---

## 4. 测试计划

### LabClaw 测试

1. **可见性**：`ls /workspace/knowledge/LabClaw/` 在容器内可见
2. **Skill 读取**：task-runner 可以读取并理解 LabClaw SKILL.md
3. **简单执行**：选一个 `general/` 类 skill（如 statistics），让 task-runner 按 skill 指令执行
4. **资格检查**（2026.3.22+ 后）：`openclaw skills check --eligible` 显示可用 LabClaw skills

### autoresearch 测试

1. **环境准备**：GPU 镜像构建成功，nvidia-smi 容器内可见
2. **依赖安装**：`uv sync` 在容器内成功
3. **数据准备**：`uv run prepare.py` 成功下载数据集
4. **单次实验**：`uv run train.py` 完成一次 5 分钟训练
5. **Agent 驱动**（Phase 4 后）：ACP session 按 program.md 完成 3 轮实验循环
