import path from "path"
import fs from "fs"
import http from "http"
import crypto from "crypto"
import { execFile } from "child_process"
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

/**
 * Vite plugin: token-based authentication middleware.
 *
 * When GUI_AUTH_TOKEN env var is set, ALL requests must include it as:
 *   - Cookie: token=<value>  (set after login)
 *   - Query: ?token=<value>  (for initial login URL)
 *
 * The /login page is always accessible and handles token submission.
 * If GUI_AUTH_TOKEN is not set, auth is disabled (open access).
 */
function authPlugin(): Plugin {
  const TOKEN = process.env.GUI_AUTH_TOKEN ?? '';
  const COOKIE_NAME = 'openclaw_gui_token';
  const COOKIE_MAX_AGE = 86400 * 30; // 30 days

  // Login page HTML
  const loginPage = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OpenClaw — Login</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      min-height: 100vh; display: flex; align-items: center; justify-content: center;
      background: #09090b; color: #e4e4e7; font-family: 'IBM Plex Sans', system-ui, sans-serif;
    }
    .card {
      width: 360px; padding: 2.5rem; background: #18181b; border: 1px solid #27272a;
      border-radius: 1rem;
    }
    .card h1 { font-size: 1.25rem; font-weight: 600; margin-bottom: 0.25rem; }
    .card p { font-size: 0.8rem; color: #71717a; margin-bottom: 1.5rem; }
    .card input {
      width: 100%; padding: 0.625rem 0.75rem; background: #09090b; border: 1px solid #3f3f46;
      border-radius: 0.5rem; color: #e4e4e7; font-size: 0.875rem; outline: none;
      font-family: 'IBM Plex Mono', monospace;
    }
    .card input:focus { border-color: #6366f1; }
    .card button {
      width: 100%; margin-top: 1rem; padding: 0.625rem; background: #4f46e5; color: white;
      border: none; border-radius: 0.5rem; font-size: 0.875rem; font-weight: 500;
      cursor: pointer; transition: background 0.15s;
    }
    .card button:hover { background: #4338ca; }
    .error { color: #f87171; font-size: 0.75rem; margin-top: 0.75rem; display: none; }
  </style>
</head>
<body>
  <div class="card">
    <h1>OpenClaw Control Panel</h1>
    <p>Enter access token to continue</p>
    <form id="f">
      <input type="password" id="t" placeholder="Access token" autofocus autocomplete="off" />
      <button type="submit">Login</button>
      <div class="error" id="e">Invalid token. Try again.</div>
    </form>
  </div>
  <script>
    const f=document.getElementById('f'), t=document.getElementById('t'), e=document.getElementById('e');
    f.onsubmit=async(ev)=>{
      ev.preventDefault();
      const r=await fetch('/__auth/verify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:t.value})});
      if(r.ok){window.location.href=new URLSearchParams(window.location.search).get('next')||'/';}
      else{e.style.display='block';t.select();}
    };
  </script>
</body>
</html>`;

  return {
    name: 'openclaw-auth',
    configureServer(server) {
      if (!TOKEN) {
        console.log('[auth] GUI_AUTH_TOKEN not set — auth disabled (open access)');
        return;
      }
      console.log('[auth] Token authentication enabled');

      // Must run before other middleware — use unshift-style early hook
      server.middlewares.use((req: any, res: any, next: any) => {
        const url = new URL(req.url ?? '/', `http://${req.headers.host}`);

        // Auth verification endpoint
        if (url.pathname === '/__auth/verify' && req.method === 'POST') {
          let body = '';
          req.on('data', (c: Buffer) => { body += c.toString(); });
          req.on('end', () => {
            try {
              const { token } = JSON.parse(body);
              if (token && crypto.timingSafeEqual(
                Buffer.from(token),
                Buffer.from(TOKEN)
              )) {
                res.setHeader('Set-Cookie',
                  `${COOKIE_NAME}=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${COOKIE_MAX_AGE}`
                );
                res.statusCode = 200;
                res.end('ok');
              } else {
                res.statusCode = 401;
                res.end('invalid');
              }
            } catch {
              res.statusCode = 400;
              res.end('bad request');
            }
          });
          return;
        }

        // Login page — always accessible
        if (url.pathname === '/login') {
          res.setHeader('Content-Type', 'text/html');
          res.end(loginPage);
          return;
        }

        // Check auth: cookie or query param
        const cookies = parseCookies(req.headers.cookie ?? '');
        const cookieToken = cookies[COOKIE_NAME];
        const queryToken = url.searchParams.get('token');

        // Query param login: set cookie and redirect
        if (queryToken) {
          try {
            if (crypto.timingSafeEqual(
              Buffer.from(queryToken),
              Buffer.from(TOKEN)
            )) {
              res.setHeader('Set-Cookie',
                `${COOKIE_NAME}=${queryToken}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${COOKIE_MAX_AGE}`
              );
              // Redirect to clean URL (strip token from query)
              url.searchParams.delete('token');
              res.writeHead(302, { Location: url.pathname + url.search });
              res.end();
              return;
            }
          } catch {
            // length mismatch — fall through to redirect
          }
        }

        // Cookie auth
        if (cookieToken) {
          try {
            if (crypto.timingSafeEqual(
              Buffer.from(cookieToken),
              Buffer.from(TOKEN)
            )) {
              return next();
            }
          } catch {
            // length mismatch — fall through
          }
        }

        // Not authenticated — redirect to login
        const next_url = url.pathname !== '/' ? `?next=${encodeURIComponent(url.pathname + url.search)}` : '';
        res.writeHead(302, { Location: `/login${next_url}` });
        res.end();
      });
    },
  };
}

function parseCookies(header: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const pair of header.split(';')) {
    const [key, ...vals] = pair.trim().split('=');
    if (key) result[key.trim()] = vals.join('=').trim();
  }
  return result;
}

/**
 * Vite plugin: Docker container management API.
 * Exposes /api/docker/* endpoints that call the docker CLI.
 * Requires the Vite process user (nick) to be in the docker group.
 */
function dockerApiPlugin(): Plugin {
  function dockerExec(args: string[]): Promise<string> {
    return new Promise((resolve, reject) => {
      execFile('docker', args, { timeout: 10_000 }, (err, stdout, stderr) => {
        if (err) reject(new Error(stderr || err.message));
        else resolve(stdout);
      });
    });
  }

  /** Like dockerExec but merges stdout+stderr (for logs) */
  function dockerExecAll(args: string[]): Promise<string> {
    return new Promise((resolve, reject) => {
      execFile('docker', args, { timeout: 10_000 }, (err, stdout, stderr) => {
        if (err && !stdout && !stderr) reject(new Error(err.message));
        else resolve((stdout ?? '') + (stderr ?? ''));
      });
    });
  }

  function jsonResponse(res: http.ServerResponse, data: unknown, status = 200) {
    res.statusCode = status;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(data));
  }

  function readBody(req: http.IncomingMessage): Promise<string> {
    return new Promise((resolve) => {
      let body = '';
      req.on('data', (c: Buffer) => { body += c.toString(); });
      req.on('end', () => resolve(body));
    });
  }

  return {
    name: 'openclaw-docker-api',
    configureServer(server) {
      // GET /api/docker/containers — list containers (with working dir from inspect)
      server.middlewares.use('/api/docker/containers', async (_req, res) => {
        try {
          const out = await dockerExec([
            'ps', '-a', '--format', '{{json .}}'
          ]);
          const raw = out.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
          // Batch-inspect running containers to get working dir
          const containers = await Promise.all(raw.map(async (c: any) => {
            let workDir = '/';
            if (c.State === 'running') {
              try {
                const insp = await dockerExec([
                  'inspect', '--format', '{{.Config.WorkingDir}}', c.ID
                ]);
                workDir = insp.trim() || '/';
              } catch { /* ignore */ }
            }
            return {
              id: c.ID,
              name: c.Names,
              image: c.Image,
              status: c.Status,
              state: c.State,
              ports: c.Ports,
              created: c.CreatedAt,
              workDir,
            };
          }));
          jsonResponse(res, { containers });
        } catch (err: any) {
          jsonResponse(res, { error: err.message, hint: 'Is nick in the docker group? Run: sudo usermod -aG docker nick && restart GUI service' }, 500);
        }
      });

      // GET /api/docker/images — list images
      server.middlewares.use('/api/docker/images', async (_req, res) => {
        try {
          const out = await dockerExec([
            'images', '--format', '{{json .}}'
          ]);
          const images = out.trim().split('\n').filter(Boolean).map((line) => {
            const img = JSON.parse(line);
            return {
              id: img.ID,
              repository: img.Repository,
              tag: img.Tag,
              size: img.Size,
              created: img.CreatedAt ?? img.CreatedSince,
            };
          });
          jsonResponse(res, { images });
        } catch (err: any) {
          jsonResponse(res, { error: err.message }, 500);
        }
      });

      // GET /api/docker/networks — list networks
      server.middlewares.use('/api/docker/networks', async (_req, res) => {
        try {
          const out = await dockerExec([
            'network', 'ls', '--format', '{{json .}}'
          ]);
          const networks = out.trim().split('\n').filter(Boolean).map((line) => {
            const n = JSON.parse(line);
            return { id: n.ID, name: n.Name, driver: n.Driver, scope: n.Scope };
          });
          jsonResponse(res, { networks });
        } catch (err: any) {
          jsonResponse(res, { error: err.message }, 500);
        }
      });

      // POST /api/docker/action — container actions (stop/start/restart)
      server.middlewares.use('/api/docker/action', async (req: any, res) => {
        if (req.method !== 'POST') {
          jsonResponse(res, { error: 'POST required' }, 405);
          return;
        }
        try {
          const body = JSON.parse(await readBody(req));
          const { action, containerId } = body;
          if (!containerId || !['stop', 'start', 'restart'].includes(action)) {
            jsonResponse(res, { error: 'Invalid action or containerId' }, 400);
            return;
          }
          await dockerExec([action, containerId]);
          jsonResponse(res, { ok: true, action, containerId });
        } catch (err: any) {
          jsonResponse(res, { error: err.message }, 500);
        }
      });

      // GET /api/docker/logs?id=xxx&tail=100 — container logs (stdout+stderr)
      server.middlewares.use('/api/docker/logs', async (req: any, res) => {
        try {
          const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
          const id = url.searchParams.get('id');
          const tail = url.searchParams.get('tail') ?? '100';
          if (!id) {
            jsonResponse(res, { error: 'id parameter required' }, 400);
            return;
          }
          const out = await dockerExecAll(['logs', '--tail', tail, '--timestamps', id]);
          jsonResponse(res, { logs: out });
        } catch (err: any) {
          jsonResponse(res, { error: err.message }, 500);
        }
      });

      // GET /api/docker/inspect?id=xxx — detailed container info
      server.middlewares.use('/api/docker/inspect', async (req: any, res) => {
        try {
          const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
          const id = url.searchParams.get('id');
          if (!id) {
            jsonResponse(res, { error: 'id parameter required' }, 400);
            return;
          }
          const out = await dockerExec(['inspect', id]);
          const info = JSON.parse(out)[0];
          const mounts = (info.Mounts ?? []).map((m: any) => ({
            source: m.Source,
            destination: m.Destination,
            mode: m.Mode,
            rw: m.RW,
            type: m.Type,
          }));
          const networkNames = Object.keys(info.NetworkSettings?.Networks ?? {});
          jsonResponse(res, {
            id: info.Id?.slice(0, 12),
            name: info.Name?.replace(/^\//, ''),
            image: info.Config?.Image,
            workDir: info.Config?.WorkingDir || '/',
            user: info.Config?.User || 'root',
            cmd: info.Config?.Cmd,
            entrypoint: info.Config?.Entrypoint,
            env: (info.Config?.Env ?? []).filter((e: string) => !e.startsWith('PATH=')),
            created: info.Created,
            startedAt: info.State?.StartedAt,
            state: info.State?.Status,
            pid: info.State?.Pid,
            restartCount: info.RestartCount,
            mounts,
            networks: networkNames,
            readonlyRoot: info.HostConfig?.ReadonlyRootfs ?? false,
            memory: info.HostConfig?.Memory,
            cpus: info.HostConfig?.NanoCpus ? info.HostConfig.NanoCpus / 1e9 : 0,
          });
        } catch (err: any) {
          jsonResponse(res, { error: err.message }, 500);
        }
      });

      // GET /api/docker/files?id=xxx&path=/some/dir — list files in container
      server.middlewares.use('/api/docker/files', async (req: any, res) => {
        try {
          const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
          const id = url.searchParams.get('id');
          const dirPath = url.searchParams.get('path') ?? '/';
          if (!id) {
            jsonResponse(res, { error: 'id parameter required' }, 400);
            return;
          }
          // ls -la with type indicators; parse into structured entries
          const out = await dockerExec([
            'exec', '-u', '0', id, 'ls', '-la', '--time-style=long-iso', dirPath
          ]);
          const lines = out.trim().split('\n').slice(1); // skip "total N" line
          const entries = lines.map((line) => {
            const parts = line.split(/\s+/);
            if (parts.length < 8) return null;
            const perms = parts[0];
            const size = parts[4];
            const date = parts[5];
            const time = parts[6];
            const name = parts.slice(7).join(' ');
            if (name === '.' || name === '..') return null;
            const isDir = perms.startsWith('d');
            const isLink = perms.startsWith('l');
            return { name: name.split(' -> ')[0], perms, size, date: `${date} ${time}`, isDir, isLink };
          }).filter(Boolean);
          jsonResponse(res, { path: dirPath, entries });
        } catch (err: any) {
          jsonResponse(res, { error: err.message }, 500);
        }
      });

      // GET /api/docker/cat?id=xxx&path=/some/file — read file from container
      server.middlewares.use('/api/docker/cat', async (req: any, res) => {
        try {
          const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
          const id = url.searchParams.get('id');
          const filePath = url.searchParams.get('path');
          if (!id || !filePath) {
            jsonResponse(res, { error: 'id and path parameters required' }, 400);
            return;
          }
          // Check file size first (don't read huge files)
          const sizeOut = await dockerExec(['exec', '-u', '0', id, 'stat', '-c', '%s', filePath]);
          const fileSize = parseInt(sizeOut.trim(), 10);
          if (fileSize > 1_000_000) {
            jsonResponse(res, { error: `File too large (${fileSize} bytes). Max 1MB.`, size: fileSize }, 413);
            return;
          }
          const content = await dockerExec(['exec', '-u', '0', id, 'cat', filePath]);
          jsonResponse(res, { path: filePath, size: fileSize, content });
        } catch (err: any) {
          jsonResponse(res, { error: err.message }, 500);
        }
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), tailwindcss(), authPlugin(), runsApiPlugin(), dockerApiPlugin()],
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
