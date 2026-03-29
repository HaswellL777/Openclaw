import path from "path"
import fs from "fs"
import http from "http"
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import type { ProxyOptions, Plugin } from 'vite'

/** Vite plugin: serve /api/runs from OpenClaw's runs.json */
function runsApiPlugin(): Plugin {
  const RUNS_PATH = '/var/lib/openclaw/.openclaw/subagents/runs.json';

  return {
    name: 'openclaw-runs-api',
    configureServer(server) {
      server.middlewares.use('/api/runs', (_req, res) => {
        try {
          const raw = fs.readFileSync(RUNS_PATH, 'utf-8');
          const data = JSON.parse(raw);
          const runs = data.runs ?? {};

          // Transform to array with only needed fields
          const result = Object.values(runs).map((r: any) => ({
            runId: r.runId ?? '',
            childSessionKey: r.childSessionKey ?? '',
            requesterSessionKey: r.requesterSessionKey ?? '',
            task: (r.task ?? '').slice(0, 200),
            label: r.label ?? '',
            createdAt: r.createdAt ?? 0,
            startedAt: r.startedAt ?? 0,
            endedAt: r.endedAt ?? 0,
            status: r.outcome?.status ?? 'unknown',
            cleanup: r.cleanup ?? '',
            spawnMode: r.spawnMode ?? 'run',
          }));

          res.setHeader('Content-Type', 'application/json');
          res.end(JSON.stringify(result));
        } catch (err: any) {
          if (err.code === 'EACCES' || err.code === 'ENOENT') {
            // Fallback: try gui/public/runs-export.json
            const fallback = path.resolve(__dirname, 'public/runs-export.json');
            if (fs.existsSync(fallback)) {
              res.setHeader('Content-Type', 'application/json');
              res.end(fs.readFileSync(fallback, 'utf-8'));
            } else {
              res.statusCode = 503;
              res.end(JSON.stringify({
                error: 'Cannot read runs.json. Run: bash scripts/setup-runs-access.sh',
              }));
            }
          } else {
            res.statusCode = 500;
            res.end(JSON.stringify({ error: String(err.message) }));
          }
        }
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), tailwindcss(), runsApiPlugin()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    host: '::',
    port: 3000,
    proxy: {
      '/ws': {
        target: 'http://127.0.0.1:17777',
        ws: true,
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/ws/, ''),
        configure: (proxy: any) => {
          proxy.on('proxyReqWs', (proxyReq: http.ClientRequest) => {
            proxyReq.setHeader('origin', 'http://localhost:17777');
            proxyReq.setHeader('host', 'localhost:17777');
          });
        },
      } satisfies ProxyOptions,
    },
  },
})
