#!/usr/bin/env node
/**
 * Creates the workspace-health-check cron job via Gateway WebSocket RPC.
 * Usage: OPENCLAW_TOKEN=<token> node scripts/add-health-check-cron.js
 *
 * Alternatively reads token from gui/.env (VITE_GATEWAY_TOKEN=...).
 */

const WebSocket = require("/opt/openclaw/node_modules/ws");
const fs = require("fs");
const path = require("path");

const GW_URL = "ws://127.0.0.1:17777";

// Read token from env or gui/.env
function getToken() {
  if (process.env.OPENCLAW_TOKEN) return process.env.OPENCLAW_TOKEN;
  try {
    const envFile = fs.readFileSync(
      path.join(__dirname, "..", "gui", ".env"),
      "utf-8"
    );
    const match = envFile.match(/VITE_GATEWAY_TOKEN=(.+)/);
    if (match) return match[1].trim();
  } catch {}
  console.error("No token found. Set OPENCLAW_TOKEN or ensure gui/.env exists.");
  process.exit(1);
}

const token = getToken();
let nextId = 1;

function send(ws, method, params) {
  const id = String(nextId++);
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timeout: ${method}`)), 15000);

    function onMsg(data) {
      let msg;
      try { msg = JSON.parse(data); } catch { return; }
      if (msg.type === "res" && String(msg.id) === id) {
        ws.removeListener("message", onMsg);
        clearTimeout(timer);
        if (msg.ok === false || msg.error) {
          reject(new Error(JSON.stringify(msg.error)));
        } else {
          resolve(msg.payload ?? msg.result ?? {});
        }
      }
    }
    ws.on("message", onMsg);
    ws.send(JSON.stringify({ type: "req", method, id, params: params ?? {} }));
  });
}

async function main() {
  const ws = new WebSocket(GW_URL);

  await new Promise((resolve, reject) => {
    ws.on("open", resolve);
    ws.on("error", reject);
  });

  // Wait for connect.challenge
  await new Promise((resolve) => {
    ws.on("message", function handler(data) {
      const msg = JSON.parse(data);
      if (msg.type === "event" && msg.event === "connect.challenge") {
        ws.removeListener("message", handler);
        resolve();
      }
    });
  });

  // Send connect handshake
  const connectId = String(nextId++);
  ws.send(JSON.stringify({
    type: "req",
    method: "connect",
    id: connectId,
    params: {
      client: { id: "gateway-client", displayName: "Cron Setup Script", mode: "backend", version: "0.1.0", platform: "linux" },
      minProtocol: 3,
      maxProtocol: 3,
      role: "operator",
      scopes: ["operator.read", "operator.write", "operator.admin"],
      auth: { token },
    },
  }));

  // Wait for handshake response
  await new Promise((resolve, reject) => {
    ws.on("message", function handler(data) {
      const msg = JSON.parse(data);
      if (msg.type === "res" && String(msg.id) === connectId) {
        ws.removeListener("message", handler);
        if (msg.ok) resolve(msg.payload);
        else reject(new Error("Handshake failed: " + JSON.stringify(msg.error)));
      }
    });
  });

  console.log("Connected to gateway.");

  // Check if job already exists
  const cronList = await send(ws, "cron.list", {});
  const jobs = cronList.jobs ?? [];
  const existing = jobs.find((j) => j.name === "workspace-health-check");
  if (existing) {
    console.log(`Job "workspace-health-check" already exists (id: ${existing.id}). Skipping creation.`);
    ws.close();
    process.exit(0);
  }

  // Create the cron job
  const healthMsg = `静默健康检查 — 仅在发现问题时报告，全部正常则回复 HEARTBEAT_OK。
检查项：
1. 读取 workspace skills/ 目录，确认每个 SKILL.md 都以 --- 开头
2. 读取 control/SOP.md 前 5 行，确认不是占位符
3. 运行 du -sh /var/log/openclaw/openclaw.log，确认大小未超 400MB
4. 运行 df -h / 和 df -h /var/lib/openclaw，确认剩余大于 10%
5. 运行 docker ps --filter name=openclaw-sbx-shared，确认容器运行
规则：全 PASS → HEARTBEAT_OK。任何 FAIL → 报告 + 修复建议。`;

  const result = await send(ws, "cron.add", {
    name: "workspace-health-check",
    schedule: { cron: "3 9 * * *" },
    wakeMode: "now",
    sessionTarget: "main",
    payload: { agentTurn: { message: healthMsg } },
  });

  console.log("Cron job created:", JSON.stringify(result, null, 2));

  ws.close();
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
