#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_HOST="${SYSUPDATE_WEB_APP_HOST:-127.0.0.1}"
APP_PORT="${SYSUPDATE_WEB_APP_PORT:-5173}"
APP_URL="${SYSUPDATE_WEB_APP_URL:-http://${APP_HOST}:${APP_PORT}}"
BACKEND_PID=""
DEV_PID=""

cleanup() {
    if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        kill "$BACKEND_PID"
        wait "$BACKEND_PID" 2>/dev/null || true
    fi

    if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
        kill "$DEV_PID"
        wait "$DEV_PID" 2>/dev/null || true
    fi
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

cd "$SCRIPT_DIR"

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
