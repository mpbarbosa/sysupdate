#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_HOST="${SYSUPDATE_WEB_APP_HOST:-127.0.0.1}"
APP_PORT="${SYSUPDATE_WEB_APP_PORT:-5173}"
APP_URL="${SYSUPDATE_WEB_APP_URL:-http://${APP_HOST}:${APP_PORT}}"
INTERACTIVE_MODE=false
BACKEND_PID=""
DEV_PID=""
SUDO_KEEPALIVE_PID=""

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Build the sysupdate web dashboard, start the Node.js backend bridge and the
Vite dev server, wait for the app to become ready, then open it in a browser.
Runs in the foreground until the dev server exits or you press Ctrl+C, which
shuts down both child processes.

Options:
    -i, --interactive   Authenticate sudo up front and keep the credentials
                        alive for the whole session, so package updates
                        triggered from the dashboard (which the backend runs
                        without a TTY) can install without failing on sudo.
    -h, --help          Show this help message and exit

Environment variables:
    SYSUPDATE_WEB_APP_HOST   Host for the Vite dev server (default: 127.0.0.1)
    SYSUPDATE_WEB_APP_PORT   Port for the Vite dev server (default: 5173)
    SYSUPDATE_WEB_APP_URL    Full URL to wait on and open
                             (default: http://\${APP_HOST}:\${APP_PORT})

Notes:
    • Must NOT be run as root — a root build writes root-owned files into
      dist/ that later non-root builds cannot remove.
    • Backend bridge configuration (SYSUPDATE_WEB_HOST/PORT, SYSUPDATE_LOG_FILE,
      etc.) is read by the backend itself; see web/CLAUDE.md.

Examples:
    ./$SCRIPT_NAME                                  # Build and launch with defaults
    ./$SCRIPT_NAME -i                               # Pre-authenticate sudo for dashboard updates
    SYSUPDATE_WEB_APP_PORT=3000 ./$SCRIPT_NAME      # Serve the dev server on port 3000
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            INTERACTIVE_MODE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

cleanup() {
    if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        kill "$BACKEND_PID"
        wait "$BACKEND_PID" 2>/dev/null || true
    fi

    if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
        kill "$DEV_PID"
        wait "$DEV_PID" 2>/dev/null || true
    fi

    if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

# Authenticate sudo once (prompting on the controlling terminal) and refresh the
# cached credentials in the background so they never expire while the app runs.
# This lets the backend's non-interactive child CLI run sudo commands without a
# TTY. The keep-alive subshell exits on its own if this script dies.
start_sudo_keepalive() {
    echo "Interactive mode: authenticating sudo so dashboard-triggered updates can install packages..."
    if ! sudo -v; then
        echo "sudo authentication failed; updates requiring root will not be able to install." >&2
        exit 1
    fi

    ( while kill -0 "$$" 2>/dev/null; do
          sudo -n true 2>/dev/null || exit
          sleep 50
      done ) &
    SUDO_KEEPALIVE_PID=$!
}

wait_for_url() {
    local url="$1"
    local attempts=30

    while [ "$attempts" -gt 0 ]; do
        if curl --silent --fail --max-time 2 "$url" >/dev/null 2>&1; then
            return 0
        fi

        attempts=$((attempts - 1))
        sleep 1
    done

    return 1
}

open_browser() {
    local url="$1"

    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 &
    elif command -v gio >/dev/null 2>&1; then
        gio open "$url" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then
        open "$url" >/dev/null 2>&1 &
    else
        echo "Open the app manually at: $url"
    fi
}

ensure_process_running() {
    local pid="$1"
    local service_name="$2"

    sleep 1

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "$service_name exited before startup completed."
        wait "$pid"
    fi
}

trap cleanup EXIT INT TERM

# Refuse to run as root. A root build writes root-owned artifacts into dist/,
# which a later non-root build cannot clear — Vite then fails with EACCES while
# emptying the output dir. Run as your normal user instead.
if [ "$(id -u)" -eq 0 ]; then
    echo "Refusing to run as root: it would create root-owned files in dist/ that later non-root builds cannot remove." >&2
    echo "Re-run as your normal user (no sudo): ./web/run_app.sh" >&2
    exit 1
fi

cd "$SCRIPT_DIR"

# Clear any previous build output up front so we can surface a clear, actionable
# message if it is unwritable (e.g. root-owned from an earlier sudo run) instead
# of leaving Vite to fail later with a cryptic EACCES stack trace.
if [ -d dist ] && ! rm -rf dist 2>/dev/null; then
    echo "Cannot remove existing build output at $SCRIPT_DIR/dist" >&2
    echo "It is likely root-owned from a previous sudo run. Remove it with:" >&2
    echo "    sudo rm -rf \"$SCRIPT_DIR/dist\"" >&2
    exit 1
fi

if [ "$INTERACTIVE_MODE" = true ]; then
    start_sudo_keepalive
fi

echo "Building web app..."
npm run build

echo "Starting backend..."
npm run backend &
BACKEND_PID=$!
ensure_process_running "$BACKEND_PID" "Backend service"

echo "Starting Vite dev server..."
npm run dev -- --host "$APP_HOST" --port "$APP_PORT" --strictPort &
DEV_PID=$!
ensure_process_running "$DEV_PID" "Vite dev server"

echo "Waiting for web app at $APP_URL..."
if wait_for_url "$APP_URL"; then
    echo "Opening browser at $APP_URL..."
    open_browser "$APP_URL"
else
    echo "Web app did not become ready in time. Open it manually at: $APP_URL"
fi

wait "$DEV_PID"
