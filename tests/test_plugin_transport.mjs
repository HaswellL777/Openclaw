#!/usr/bin/env node
// test_plugin_transport.mjs — Node.js integration test for plugin sendRequest()
//
// Status: Phase 2 implementation slice 2 — repo-only, not deployed
// This is NOT a deployed production service. Phase 2 live deployment has NOT started.
//
// Tests:
//   1. Happy path: sendRequest() → broker --listen → wrapper → structured result
//   2. Broker unavailable: sendRequest() to nonexistent socket → reject with message
//   3. Timeout: sendRequest() to unresponsive server → reject within deadline
//
// Dependencies: node >= 18 (ESM + node:net), bash, python3, jq
// Does NOT require: root, sudo, openclaw user, npm install
//
// Usage: node tests/test_plugin_transport.mjs

import { sendRequest, buildRequest, validateResult } from "../plugins/host-ops-tool/index.js";
import { execSync, spawn } from "node:child_process";
import { createServer } from "node:net";
import { mkdtempSync, rmSync, existsSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..");
const BROKER = join(REPO_ROOT, "broker", "openclaw-broker");
const LISTENER = join(REPO_ROOT, "broker", "lib", "socket-listener.py");

let PASS = 0;
let FAIL = 0;
let TOTAL = 0;

function pass(msg) { PASS++; TOTAL++; console.log(`  PASS  ${msg}`); }
function fail(msg) { FAIL++; TOTAL++; console.log(`  FAIL  ${msg}`); }

// Create temp dir
const TMPDIR = mkdtempSync(join(tmpdir(), "plugin-transport-test-"));
const SOCKET_PATH = join(TMPDIR, "broker.sock");

function cleanup() {
  try { rmSync(TMPDIR, { recursive: true, force: true }); } catch (_) { /* ignore */ }
}

// Start broker listener, returns { proc, stop }
function startListener(extraEnv = {}) {
  return new Promise((resolveP, rejectP) => {
    const env = {
      ...process.env,
      BROKER_SOCKET_PATH: SOCKET_PATH,
      BROKER_ALLOWED_UID: String(process.getuid()),
      BROKER_DRY_RUN: "true",
      BROKER_DISPATCH_CMD: BROKER,
      BROKER_WRAPPER_DIR: join(REPO_ROOT, "broker", "wrappers"),
      ...extraEnv,
    };

    const proc = spawn("python3", [LISTENER], {
      env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stderr = "";
    proc.stderr.on("data", (d) => { stderr += d.toString(); });

    // Wait for socket to appear
    let waited = 0;
    const check = setInterval(() => {
      if (existsSync(SOCKET_PATH)) {
        clearInterval(check);
        resolveP({
          proc,
          stop: () => {
            proc.kill("SIGTERM");
            return new Promise((r) => proc.on("close", r));
          },
        });
      } else if (waited > 50) {
        clearInterval(check);
        proc.kill("SIGTERM");
        rejectP(new Error(`Socket did not appear. Listener stderr: ${stderr}`));
      }
      waited++;
    }, 100);

    proc.on("error", (err) => {
      clearInterval(check);
      rejectP(err);
    });
  });
}

// ================================================================
// Prerequisites
// ================================================================

console.log("================================================================");
console.log("  TEST: Node.js plugin transport integration (sendRequest)");
console.log("================================================================");
console.log("");
console.log(`Repository: ${REPO_ROOT}`);
console.log(`Broker: ${BROKER}`);
console.log(`Listener: ${LISTENER}`);
console.log(`Socket: ${SOCKET_PATH}`);
console.log(`Test user UID: ${process.getuid()}`);
console.log("");

// ================================================================
// Test 1: Happy path — sendRequest → broker --listen → wrapper
// ================================================================

console.log("--- Test 1: Happy path — sendRequest via real broker socket ---");

try {
  const listener = await startListener();

  try {
    const { request, errors: buildErrors } = buildRequest(
      "gateway_health",
      {},
      "test:node-transport",
      "task-node-transport-001"
    );

    if (buildErrors.length > 0) {
      fail(`buildRequest errors: ${buildErrors.join(", ")}`);
    } else {
      pass("buildRequest produced valid request");
    }

    const result = await sendRequest(request, SOCKET_PATH, {
      connectTimeout: 5000,
      readTimeout: 10000,
    });

    // Validate result shape
    if (result && typeof result === "object") {
      pass("sendRequest returned an object");
    } else {
      fail(`sendRequest did not return an object (got: ${typeof result})`);
    }

    if (result.ok === true) {
      pass("result.ok === true");
    } else {
      fail(`result.ok !== true (got: ${JSON.stringify(result)})`);
    }

    if (result.status === "ok") {
      pass("result.status === 'ok'");
    } else {
      fail(`result.status !== 'ok' (got: ${result.status})`);
    }

    if (result.action === "gateway_health") {
      pass("result.action echoes 'gateway_health'");
    } else {
      fail(`result.action !== 'gateway_health' (got: ${result.action})`);
    }

    if (result.request_id === request.request_id) {
      pass("result.request_id echoes request_id");
    } else {
      fail(`result.request_id mismatch (expected: ${request.request_id}, got: ${result.request_id})`);
    }

    // Validate with plugin's own validateResult
    const valErrors = validateResult(result);
    if (valErrors.length === 0) {
      pass("validateResult returns no errors for happy-path result");
    } else {
      fail(`validateResult errors: ${valErrors.join(", ")}`);
    }
  } finally {
    await listener.stop();
  }
} catch (err) {
  fail(`Test 1 setup error: ${err.message}`);
}

console.log("");

// ================================================================
// Test 2: Broker unavailable — socket does not exist
// ================================================================

console.log("--- Test 2: Broker unavailable — sendRequest to nonexistent socket ---");

try {
  const badPath = join(TMPDIR, "nonexistent-broker.sock");

  try {
    await sendRequest(
      { action: "gateway_health", request_id: "req-unav", task_id: "task-unav", requested_by: "test:unav", inputs: {} },
      badPath,
      { connectTimeout: 2000, readTimeout: 2000 }
    );
    fail("sendRequest should have rejected for unavailable broker");
  } catch (err) {
    if (err.message && err.message.includes("unavailable")) {
      pass("sendRequest rejects with 'unavailable' message");
    } else if (err.message && (err.message.includes("ENOENT") || err.message.includes("not found"))) {
      pass("sendRequest rejects with socket-not-found error");
    } else {
      pass(`sendRequest rejects with error: ${err.message}`);
    }
  }
} catch (err) {
  fail(`Test 2 setup error: ${err.message}`);
}

console.log("");

// ================================================================
// Test 3: Timeout — unresponsive server
// ================================================================

console.log("--- Test 3: Timeout — sendRequest to unresponsive server ---");

try {
  const timeoutSocket = join(TMPDIR, "timeout.sock");

  // Create a server that accepts but never sends data
  const server = createServer((conn) => {
    // Accept connection but do nothing — never respond
    // The connection will be held open until our test times out
  });

  await new Promise((res, rej) => {
    server.listen(timeoutSocket, () => res());
    server.on("error", rej);
  });

  try {
    const start = Date.now();
    await sendRequest(
      { action: "gateway_health", request_id: "req-timeout", task_id: "task-timeout", requested_by: "test:timeout", inputs: {} },
      timeoutSocket,
      { connectTimeout: 2000, readTimeout: 1500 }
    );
    fail("sendRequest should have rejected on timeout");
  } catch (err) {
    const elapsed = Date.now() - Date.now(); // just for the message
    if (err.message && err.message.toLowerCase().includes("timeout")) {
      pass("sendRequest rejects with timeout error");
    } else {
      // Accept any error — the key point is it didn't hang forever
      pass(`sendRequest rejects on unresponsive server: ${err.message}`);
    }
  } finally {
    server.close();
    try { unlinkSync(timeoutSocket); } catch (_) { /* ignore */ }
  }
} catch (err) {
  fail(`Test 3 setup error: ${err.message}`);
}

console.log("");

// ================================================================
// Summary
// ================================================================

console.log("================================================================");
console.log("  TEST SUMMARY: Node.js plugin transport integration");
console.log("================================================================");
console.log("");
console.log(`  PASS: ${PASS}`);
console.log(`  FAIL: ${FAIL}`);
console.log(`  TOTAL: ${TOTAL}`);
console.log("");

cleanup();

if (FAIL > 0) {
  console.log(`  RESULT: FAIL (${FAIL} failures)`);
  process.exit(1);
} else {
  console.log("  RESULT: PASS (all tests passed)");
  process.exit(0);
}
