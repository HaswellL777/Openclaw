import path from "path"
import http from "http"
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import type { ProxyOptions } from 'vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
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
          // Rewrite Origin header on WebSocket upgrade so Gateway
          // sees a localhost origin and passes the origin check.
          proxy.on('proxyReqWs', (proxyReq: http.ClientRequest) => {
            proxyReq.setHeader('origin', 'http://localhost:17777');
            proxyReq.setHeader('host', 'localhost:17777');
          });
        },
      } satisfies ProxyOptions,
    },
  },
})
