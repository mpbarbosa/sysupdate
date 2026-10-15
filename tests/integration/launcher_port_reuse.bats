#!/usr/bin/env bats
#
# Integration tests: the port-reuse decisions in web/run_app.sh.
#
# The launcher adopts a server it finds on the app or backend port only when
# that server identifies itself as this project, and aborts otherwise. Both
# bugs that rule exists to prevent — a launcher that SIGTERMed its own backend,
# and one that opened the browser onto an unrelated repo's Vite app — were found
# and fixed with hand verification only, which is what this suite replaces.
#
# How the launcher is driven here:
#
#   • Fake listeners stand in for the dev server and the bridge: `python3 -m
#     http.server` over a fixture directory, on ports this suite picks for
#     itself. 5173/5174/4174 are routinely busy on a developer's machine, so
#     nothing here may assume a fixed port is free.
#   • `npm` is shadowed by a stub on PATH. "Starting a service" then costs
#     nothing and, more importantly, becomes observable: a line in a log file
#     proves whether the launcher reused a server or started a second one. The
#     browser openers are stubbed for the same reason.
#   • The launcher is copied into a sandbox before being run, because it `cd`s
#     to its own directory and clears `dist/` there — running the repo copy in
#     place would delete the real build output. The copy is taken from
#     web/run_app.sh at test time, so a regression in the real file still fails
#     these tests.
#   • The probe helpers are exercised directly by sourcing the launcher with
#     SYSUPDATE_RUN_APP_DEFINE_ONLY=1, which stops it before the trap and the
#     build. Retry timing has no other honest seam.
#
# None of this needs root (sudo cannot work in some of the environments this
# repo is developed in), so the launcher's `-i` path is out of scope.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
LAUNCHER="$REPO_ROOT/web/run_app.sh"

setup() {
    export NO_COLOR=1

    SANDBOX="$BATS_TEST_TMPDIR/sandbox"
    mkdir -p "$SANDBOX/bin"
    cp "$LAUNCHER" "$SANDBOX/run_app.sh"

    NPM_LOG="$SANDBOX/npm.log"
    BROWSER_LOG="$SANDBOX/browser.log"
    LISTENER_PIDS="$SANDBOX/listener-pids"
    : > "$NPM_LOG"
    : > "$BROWSER_LOG"
    : > "$LISTENER_PIDS"

    write_stubs

    APP_PORT="$(free_port)"
    BACKEND_PORT="$(free_port "$APP_PORT")"
}

teardown() {
    local pid
    while read -r pid; do
        [ -n "$pid" ] || continue
        kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    done < "$LISTENER_PIDS"
}

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

# A free TCP port on the loopback interface, different from any port passed in.
# Asking the kernel beats picking a number: other work on the same machine owns
# the project's default ports.
free_port() {
    local port
    while :; do
        port="$(python3 -I -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()')"
        case " $* " in
            *" $port "*) continue ;;
            *) echo "$port"; return 0 ;;
        esac
    done
}

# Stubs for everything the launcher shells out to that we do not want to
# actually happen. `npm` records every invocation and then impersonates the
# service it was asked for, so a started service is both cheap and visible.
write_stubs() {
    cat > "$SANDBOX/bin/npm" << 'EOF'
#!/usr/bin/env bash
echo "npm $*" >> "$NPM_LOG"
case "${2:-}" in
    build)
        # These tests are about port decisions, not about Vite.
        exit 0
        ;;
    backend)
        exec python3 -I -m http.server "$SYSUPDATE_WEB_PORT" --bind 127.0.0.1 \
            --directory "$STUB_BACKEND_DIR" >/dev/null 2>&1
        ;;
    dev)
        exec python3 -I -m http.server "$SYSUPDATE_WEB_APP_PORT" --bind 127.0.0.1 \
            --directory "$STUB_APP_DIR" >/dev/null 2>&1
        ;;
esac
exit 0
EOF

    local opener
    for opener in xdg-open gio open; do
        cat > "$SANDBOX/bin/$opener" << EOF
#!/usr/bin/env bash
echo "$opener \$*" >> "\$BROWSER_LOG"
EOF
    done

    chmod +x "$SANDBOX/bin"/*
}

# A directory served as "this project's app": the real web/index.html, so a
# marker renamed on one side of the contract and not the other fails here.
app_identity_dir() {
    local dir="$SANDBOX/fixtures/app-identity"
    mkdir -p "$dir"
    cp "$REPO_ROOT/web/index.html" "$dir/index.html"
    echo "$dir"
}

# A directory served as "somebody else's dev server": answers, carries no marker.
foreign_app_dir() {
    local dir="$SANDBOX/fixtures/foreign-app"
    mkdir -p "$dir"
    cat > "$dir/index.html" << 'EOF'
<!doctype html>
<html lang="en">
  <head><title>some other project</title></head>
  <body><div id="root"></div></body>
</html>
EOF
    echo "$dir"
}

# GET /api/health answering as our bridge does. `python3 -m http.server` maps
# that path onto the file api/health.
backend_identity_dir() {
    local dir="$SANDBOX/fixtures/backend-identity"
    mkdir -p "$dir/api"
    echo '{"status":"ok","backend":"sysupdate-local-bridge","host":"127.0.0.1"}' \
        > "$dir/api/health"
    echo "$dir"
}

# GET /api/health answering as something that is not our bridge.
foreign_backend_dir() {
    local dir="$SANDBOX/fixtures/foreign-backend"
    mkdir -p "$dir/api"
    echo '{"status":"ok","backend":"some-other-service"}' > "$dir/api/health"
    echo "$dir"
}

# Start a fake listener on <port> serving <dir>; echo its pid once it answers.
start_listener() {
    local port="$1" dir="$2" pid
    # 3>&- because BATS waits for its file descriptor 3 to close before it
    # finishes a run; a daemon that inherits it hangs the suite.
    python3 -I -m http.server "$port" --bind 127.0.0.1 --directory "$dir" \
        >/dev/null 2>&1 3>&- &
    pid=$!
    echo "$pid" >> "$LISTENER_PIDS"

    local waited=0
    while [ "$waited" -lt 100 ]; do
        if curl --silent --output /dev/null --max-time 1 "http://127.0.0.1:${port}/"; then
            echo "$pid"
            return 0
        fi
        waited=$((waited + 1))
        sleep 0.1
    done

    echo "fake listener on port $port never came up" >&2
    return 1
}

# True while something answers on <port>.
port_answers() {
    curl --silent --output /dev/null --max-time 1 "http://127.0.0.1:${1}/"
}

# Which pid holds <port> — asked the same two ways run_app.sh asks it, so a
# machine with only one of the tools still runs these assertions.
pid_holding_port() {
    if command -v lsof > /dev/null 2>&1; then
        lsof -tiTCP:"$1" -sTCP:LISTEN -Pn 2>/dev/null | head -n 1
        return
    fi
    if command -v ss > /dev/null 2>&1; then
        ss -ltnpH "sport = :$1" 2>/dev/null | grep -o 'pid=[0-9]*' | head -n 1 | cut -d= -f2
        return
    fi
    echo "neither lsof nor ss available to identify the owner of port $1" >&2
    return 1
}

# Assertions about what the launcher started. Spelled out with `if` and
# `return 1` rather than `! grep`, because a command prefixed with `!` is exempt
# from errexit and so can never fail a BATS test (ShellCheck SC2314).
assert_npm_ran() {
    if ! grep -q "run $1" "$NPM_LOG"; then
        echo "expected the launcher to run: npm run $1" >&2
        return 1
    fi
}

assert_npm_did_not_run() {
    if grep -q "run $1" "$NPM_LOG"; then
        echo "launcher ran 'npm run $1' instead of leaving that service alone" >&2
        return 1
    fi
}

assert_no_browser_opened() {
    if [ -s "$BROWSER_LOG" ]; then
        echo "launcher opened a browser: $(cat "$BROWSER_LOG")" >&2
        return 1
    fi
}

# Run the sandboxed copy of the launcher against this test's ports and stubs.
# `timeout` is the safety net for the bug class that started all this: a
# launcher that waits on a service it does not own never returns. Its children
# must not inherit BATS's file descriptor 3 either: should a regression leave a
# service running, the suite has to fail on the assertion rather than hang
# waiting for that descriptor to close.
run_launcher() {
    run env \
        PATH="$SANDBOX/bin:$PATH" \
        NPM_LOG="$NPM_LOG" \
        BROWSER_LOG="$BROWSER_LOG" \
        STUB_APP_DIR="$(app_identity_dir)" \
        STUB_BACKEND_DIR="$(backend_identity_dir)" \
        SYSUPDATE_WEB_APP_HOST=127.0.0.1 \
        SYSUPDATE_WEB_APP_PORT="$APP_PORT" \
        SYSUPDATE_WEB_HOST=127.0.0.1 \
        SYSUPDATE_WEB_PORT="$BACKEND_PORT" \
        timeout 90 bash "$SANDBOX/run_app.sh" 3>&-
}

# Evaluate <snippet> in a shell that has sourced the launcher's helpers and
# nothing else. Kept in its own process so the launcher's `set -euo pipefail`
# never leaks into the BATS shell.
probe() {
    run env \
        LAUNCHER="$LAUNCHER" \
        SYSUPDATE_RUN_APP_DEFINE_ONLY=1 \
        SYSUPDATE_WEB_APP_HOST=127.0.0.1 \
        SYSUPDATE_WEB_APP_PORT="$APP_PORT" \
        SYSUPDATE_WEB_HOST=127.0.0.1 \
        SYSUPDATE_WEB_PORT="$BACKEND_PORT" \
        bash -c 'source "$LAUNCHER"
'"$1"
}

# ---------------------------------------------------------------------------
# App port: reuse only what serves this app
# ---------------------------------------------------------------------------

@test "run_app.sh: an app-port listener serving the sysupdate marker is reused" {
    local dev_pid
    dev_pid="$(start_listener "$APP_PORT" "$(app_identity_dir)")"
    start_listener "$BACKEND_PORT" "$(backend_identity_dir)" >/dev/null

    run_launcher

    [ "$status" -eq 0 ]
    [[ "$output" == *"A sysupdate dev server is already listening on 127.0.0.1:${APP_PORT}"* ]]
    # No second dev server: npm was never asked for one, and the port is still
    # held by the listener this test started.
    assert_npm_did_not_run dev
    [ "$(pid_holding_port "$APP_PORT")" = "$dev_pid" ]
    # Having started neither service, the launcher must not block on them.
    [[ "$output" == *"Opening browser at"* ]]
}

@test "run_app.sh: an app-port listener without the marker aborts the launch" {
    start_listener "$APP_PORT" "$(foreign_app_dir)" >/dev/null
    start_listener "$BACKEND_PORT" "$(backend_identity_dir)" >/dev/null

    run_launcher

    [ "$status" -eq 1 ]
    [[ "$output" == *"is listening on 127.0.0.1:${APP_PORT}"* ]]
    [[ "$output" == *"SYSUPDATE_WEB_APP_PORT"* ]]
    # Aborting means aborting: no dev server, no browser pointed at the stranger.
    assert_npm_did_not_run dev
    assert_no_browser_opened
}

# ---------------------------------------------------------------------------
# Backend port: reuse only our own bridge
# ---------------------------------------------------------------------------

@test "run_app.sh: a backend-port listener identifying as the bridge is reused" {
    local backend_pid
    backend_pid="$(start_listener "$BACKEND_PORT" "$(backend_identity_dir)")"
    start_listener "$APP_PORT" "$(app_identity_dir)" >/dev/null

    run_launcher

    [ "$status" -eq 0 ]
    [[ "$output" == *"A backend bridge is already listening on 127.0.0.1:${BACKEND_PORT}"* ]]
    assert_npm_did_not_run backend
    [ "$(pid_holding_port "$BACKEND_PORT")" = "$backend_pid" ]
}

@test "run_app.sh: a backend-port listener that does not identify itself aborts the launch" {
    start_listener "$BACKEND_PORT" "$(foreign_backend_dir)" >/dev/null

    run_launcher

    [ "$status" -eq 1 ]
    [[ "$output" == *"is listening on 127.0.0.1:${BACKEND_PORT}"* ]]
    [[ "$output" == *"SYSUPDATE_WEB_PORT"* ]]
    # The backend decision comes first, so nothing else should have started.
    assert_npm_did_not_run backend
    assert_npm_did_not_run dev
    assert_no_browser_opened
}

# ---------------------------------------------------------------------------
# Aborting cleans up after itself
# ---------------------------------------------------------------------------

@test "run_app.sh: aborting on a foreign app server stops the backend it had started" {
    # Backend port deliberately left free, so the launcher spawns its own
    # backend and only then meets the stranger on the app port.
    start_listener "$APP_PORT" "$(foreign_app_dir)" >/dev/null

    run_launcher

    [ "$status" -eq 1 ]
    assert_npm_ran backend
    # The EXIT trap owes us that backend: nothing may still hold its port.
    local waited=0
    while port_answers "$BACKEND_PORT" && [ "$waited" -lt 30 ]; do
        waited=$((waited + 1))
        sleep 0.1
    done
    if port_answers "$BACKEND_PORT"; then
        echo "the backend the launcher started is still listening on $BACKEND_PORT" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# response_contains: what counts as an answer
# ---------------------------------------------------------------------------

@test "response_contains: a server answering with the wrong body is rejected without retrying" {
    start_listener "$APP_PORT" "$(foreign_app_dir)" >/dev/null

    probe 'start=$SECONDS
           if is_sysupdate_dev_server; then echo "RESULT=match"; else echo "RESULT=no-match"; fi
           echo "ELAPSED=$((SECONDS - start))"'

    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT=no-match"* ]]
    # A served answer is final. Retrying it would cost one second per attempt
    # (three by default) on every launch that hits an occupied port.
    local elapsed
    elapsed="$(sed -n 's/^ELAPSED=//p' <<< "$output")"
    [ "$elapsed" -lt 2 ]
}

@test "response_contains: a server that binds its port a moment later is still recognised" {
    # Nothing is listening when the probe starts; the marker only becomes
    # available on a later attempt, which is why connection errors are retried.
    ( sleep 2
      exec python3 -I -m http.server "$APP_PORT" --bind 127.0.0.1 \
          --directory "$(app_identity_dir)" >/dev/null 2>&1 ) 3>&- &
    echo "$!" >> "$LISTENER_PIDS"

    probe 'if response_contains "$APP_PROBE_URL" "$APP_IDENTITY_MARKER" 8; then
               echo "RESULT=match"
           else
               echo "RESULT=no-match"
           fi'

    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT=match"* ]]
}

@test "response_contains: a port nothing ever answers on is not mistaken for this app" {
    local dead_port
    dead_port="$(free_port "$APP_PORT" "$BACKEND_PORT")"

    probe 'if response_contains "http://127.0.0.1:'"$dead_port"'/" "$APP_IDENTITY_MARKER" 2; then
               echo "RESULT=match"
           else
               echo "RESULT=no-match"
           fi'

    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT=no-match"* ]]
}

# ---------------------------------------------------------------------------
# The marker contract spans two files on each side
# ---------------------------------------------------------------------------

@test "identity markers: the launcher probes for strings the app and the bridge really serve" {
    # web/index.html and APP_IDENTITY_MARKER, web/backend/server.js and the
    # /api/health probe: renaming either half alone breaks reuse silently.
    grep -q 'name="sysupdate-app"' "$REPO_ROOT/web/index.html"
    grep -q "backend: 'sysupdate-local-bridge'" "$REPO_ROOT/web/backend/server.js"

    probe 'echo "MARKER=$APP_IDENTITY_MARKER"'
    [[ "$output" == *'MARKER=name="sysupdate-app"'* ]]
}
