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

// Backend bridge address — same variables backend/server.js and run_app.sh read,
// so an alternative port set for one process is picked up by all three.
const backendHost = process.env.SYSUPDATE_WEB_HOST ?? '127.0.0.1'
const backendPort = process.env.SYSUPDATE_WEB_PORT ?? '4174'
const backendOrigin = `${backendHost}:${backendPort}`

// https://vite.dev/config/
export default defineConfig({
  customLogger: logger,
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      '/api': `http://${backendOrigin}`,
      '/ws': {
        target: `ws://${backendOrigin}`,
        ws: true,
        rewriteWsOrigin: true,
      },
    },
  },
})
