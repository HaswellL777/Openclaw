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
    host: '::',      // 绑定所有接口（IPv4 + IPv6）
    port: 3000,
    proxy: {
      '/ws': {
        target: 'ws://127.0.0.1:17777',
        ws: true,
      },
    },
  },
})
