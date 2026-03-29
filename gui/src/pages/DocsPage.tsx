import { useState } from "react";
import { PageHeader, Card, CardHeader, CardBody, SectionLabel } from "@/components/shared";

// ---------------------------------------------------------------------------
// Help sections data
// ---------------------------------------------------------------------------

interface HelpSection {
  title: string;
  items: { label: string; content: string }[];
}

const SECTIONS: HelpSection[] = [
  {
    title: "Gateway 管理",
    items: [
      { label: "重启 Gateway", content: "sudo systemctl restart openclaw-gateway.service" },
      { label: "查看 Gateway 状态", content: "sudo systemctl status openclaw-gateway.service" },
      { label: "实时查看日志（journald）", content: "sudo journalctl -u openclaw-gateway.service -f" },
      { label: "查看日志文件", content: "tail -f /var/log/openclaw/openclaw.log" },
      { label: "检查 Gateway 端口", content: "ss -tlnp | grep 17777" },
    ],
  },
  {
    title: "Docker / 沙箱",
    items: [
      { label: "查看运行中容器", content: "docker ps --filter name=openclaw" },
      { label: "查看共享沙箱容器详情", content: "docker inspect openclaw-sbx-shared" },
      { label: "强制移除容器（镜像更换后必须执行）", content: "docker rm -f openclaw-sbx-shared" },
      { label: "查看 OpenClaw 镜像", content: "docker images | grep openclaw" },
      { label: "查看容器日志", content: "docker logs openclaw-sbx-shared --tail 50" },
      { label: "查看 Docker 网络", content: "docker network inspect openclaw-task-net" },
    ],
  },
  {
    title: "配置文件",
    items: [
      { label: "主配置文件路径", content: "/etc/openclaw/openclaw.json" },
      { label: "环境变量文件（密钥）", content: "/etc/openclaw/openclaw.env" },
      { label: "查看当前配置", content: "sudo cat /etc/openclaw/openclaw.json | python3 -m json.tool" },
      { label: "验证配置（仅检查）", content: "sudo -u openclaw openclaw doctor --check" },
    ],
  },
  {
    title: "目录结构",
    items: [
      { label: "程序代码（root 所有，只读）", content: "/opt/openclaw" },
      { label: "配置（root:openclaw）", content: "/etc/openclaw/" },
      { label: "运行时数据（btrfs 独立子卷）", content: "/var/lib/openclaw/" },
      { label: "状态目录", content: "/var/lib/openclaw/.openclaw/" },
      { label: "Session 存储", content: "/var/lib/openclaw/.openclaw/sessions/" },
      { label: "Subagent 运行注册表", content: "/var/lib/openclaw/.openclaw/subagents/runs.json" },
      { label: "插件目录", content: "/var/lib/openclaw/.openclaw/extensions/" },
      { label: "Agent 工作区", content: "/var/lib/openclaw/agents/<agentId>/" },
      { label: "日志", content: "/var/log/openclaw/" },
      { label: "快照", content: "/.snapshots/" },
    ],
  },
  {
    title: "快照与备份",
    items: [
      { label: "创建根快照", content: "sudo btrfs subvolume snapshot / /.snapshots/root-pre-<label>-$(date +%Y%m%d-%H%M)" },
      { label: "列出快照", content: "ls -la /.snapshots/" },
      { label: "注意：/var/lib/openclaw 是独立子卷", content: "根快照不包含 OpenClaw 运行时数据。需要单独备份 /var/lib/openclaw。" },
      { label: "挂载 Vault（离线 noauto）", content: "sudo mount /mnt/vault" },
    ],
  },
  {
    title: "Session 管理",
    items: [
      { label: "查看 Session 列表", content: "通过本 GUI 的 Sessions 页面查看，或使用 Gateway API：sessions.list" },
      { label: "Session Key 格式", content: "agent:<agentId>:<rest> — 子代理深度 = key 中 ':subagent:' 的数量" },
      { label: "查看 Session 对话记录文件", content: "/var/lib/openclaw/agents/<agentId>/sessions/<sessionId>.jsonl" },
      { label: "活跃 = updatedAt 在最近 N 分钟内", content: "普通 Session 没有 status 字段。使用 sessions.list({activeMinutes: N}) 按时间窗口过滤。" },
      { label: "维护模式（当前）", content: "mode: 'warn'（默认）— 不自动删除。pruneAfterMs = 30 天，maxEntries = 500。" },
    ],
  },
  {
    title: "Agent 工作区",
    items: [
      { label: "发布 main 工作区", content: "bash scripts/publish-workspace-main.sh" },
      { label: "手动 rsync 其他 agent", content: "rsync -av workspace-<agent>-template/ /var/lib/openclaw/agents/<agentId>/workspace/" },
      { label: "警告：chown -R 会在 knowledge/ 上失败", content: "knowledge/ 是只读绑定挂载，不能递归 chown。需要逐个路径指定。" },
      { label: "容器 UID 必须匹配", content: "runner 必须使用 --uid 997 --gid 984（匹配 openclaw 用户）" },
    ],
  },
  {
    title: "故障排查",
    items: [
      { label: "Gateway 启动崩溃循环", content: "检查配置 schema：.strict() 拒绝未知字段。从 openclaw.json 移除所有不认识的 key。" },
      { label: "插件导致崩溃", content: "检查 /var/lib/openclaw/.openclaw/extensions/ — 每个子目录必须有 openclaw.plugin.json。" },
      { label: "配置修改不生效", content: "配置必须在 /etc/openclaw/openclaw.json，不是 /var/lib/openclaw/.openclaw/openclaw.json。" },
      { label: "更换镜像后容器不更新", content: "scope: 'shared' 会复用旧容器。执行：docker rm -f openclaw-sbx-shared" },
      { label: "queueOwnerTtlSeconds 太低", content: "默认 0.1 秒会导致任务超时。在配置中 override 到 300 以上。" },
      { label: "GUI WebSocket 连接失败", content: "Vite proxy 必须重写 Origin header 到 localhost:17777。检查 gui/vite.config.ts。" },
    ],
  },
  {
    title: "危险操作（禁止以 nick 用户执行）",
    items: [
      { label: "openclaw onboard", content: "会创建 ~/.openclaw/ 用户级配置，产生第二个 gateway 进程。禁止执行。" },
      { label: "openclaw doctor --repair", content: "会自动创建用户级状态目录进行修复。禁止执行。" },
      { label: "openclaw gateway（以 nick 执行）", content: "会产生 nick 用户的 gateway 进程，占用不同端口。禁止执行。" },
      { label: "openclaw config set", content: "会写入 ~/.openclaw/openclaw.json（用户级配置文件）。禁止执行。" },
    ],
  },
];

// ---------------------------------------------------------------------------
// Components
// ---------------------------------------------------------------------------

function CommandBlock({ content }: { content: string }) {
  const isMultiLine = content.includes("\n");
  const isCommand = !content.includes(" ") || content.startsWith("/") || content.startsWith("sudo ") ||
    content.startsWith("docker ") || content.startsWith("bash ") || content.startsWith("ls ") ||
    content.startsWith("tail ") || content.startsWith("ss ") || content.startsWith("rsync ") ||
    content.startsWith("cat ") || content.startsWith("grep ");

  if (!isCommand && !isMultiLine) {
    return <span className="text-zinc-300 text-xs leading-relaxed">{content}</span>;
  }

  return (
    <code className="block bg-zinc-950 border border-zinc-800 rounded px-2.5 py-1.5 text-xs font-mono text-amber-300 whitespace-pre-wrap select-all">
      {content}
    </code>
  );
}

function HelpSectionCard({ section }: { section: HelpSection }) {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <Card>
      <CardHeader title={section.title}>
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="text-[10px] text-zinc-500 hover:text-zinc-300 transition-colors"
        >
          {collapsed ? "Expand" : "Collapse"}
        </button>
      </CardHeader>
      {!collapsed && (
        <CardBody>
          <div className="space-y-3">
            {section.items.map((item, i) => (
              <div key={i}>
                <div className="text-[11px] text-zinc-400 font-medium mb-1">{item.label}</div>
                <CommandBlock content={item.content} />
              </div>
            ))}
          </div>
        </CardBody>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function DocsPage() {
  return (
    <div className="p-6 h-full overflow-y-auto">
      <PageHeader
        title="帮助与参考"
        subtitle="常用操作、目录结构与故障排查"
      />
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {SECTIONS.map(s => (
          <HelpSectionCard key={s.title} section={s} />
        ))}
      </div>
    </div>
  );
}
