import path from "path"
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

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
      // WebSocket proxy: browser connects to ws://HOST:3000/ws
      // Vite forwards to ws://127.0.0.1:17777 (Gateway loopback)
      '/ws': {
        target: 'http://127.0.0.1:17777',
        ws: true,
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/ws/, ''),
      },
    },
  },
})
