import { defineConfig, createLogger } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// Suppress benign WebSocket proxy noise. In dev, React StrictMode mounts the app
// twice, so the dashboard opens a /ws connection, immediately closes it, then
// reopens it. The backend bridge writes its initial `connected` frame into the
// socket the client just dropped, which surfaces as a harmless `write EPIPE`
// (or ECONNRESET) from Vite's ws proxy. Filter only that specific case so real
// proxy failures (e.g. ECONNREFUSED when the backend is down) still log.
const logger = createLogger()
const baseError = logger.error.bind(logger)
logger.error = (msg, options) => {
  const code = (options?.error as NodeJS.ErrnoException | undefined)?.code
  if (typeof msg === 'string' && msg.includes('ws proxy') && (code === 'EPIPE' || code === 'ECONNRESET')) {
    return
  }
  baseError(msg, options)
}

// https://vite.dev/config/
export default defineConfig({
  customLogger: logger,
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      '/api': 'http://127.0.0.1:4174',
      '/ws': {
        target: 'ws://127.0.0.1:4174',
        ws: true,
        rewriteWsOrigin: true,
      },
    },
  },
})
