#!/usr/bin/env bats
#
# Tests for scripts/upgrade_snippets/update_qwen.sh
#
# Ollama models carry no version number, so this snippet decides "up to date"
# by hashing the registry's manifest bytes and comparing the first 12 hex
# digits against what `ollama list` stored. That makes two kinds of mistake
# possible, and both are silent:
#
#   1. A digest computed from something other than the registry's exact bytes
#      -- a truncated body, an error page, an empty response -- compares
#      unequal and reports an update that does not exist.
#   2. A listing that could not be read, mistaken for "nothing installed",
#      reports every model up to date because there is nothing left to check.
#
# The tests for those two live under "the guards" below; each one goes red when
# its guard is deleted.
#
# Nothing here touches the network or a real Ollama: `ollama` and `curl` are
# shadowed on PATH and every path is inside $BATS_TEST_TMPDIR.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    exec 0</dev/null
    export NO_COLOR=1
    QUIET_MODE=true
    CHECK_ONLY_MODE=true
    VERBOSE_MODE=false
    export BATS_TEST_TMPDIR
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    # Nothing is found unless a test arranges it, so a stray ollama on the
    # developer's machine cannot reach these tests: the override is blanked,
    # $HOME is repointed away from the user-local install, and any directory
    # holding an ollama is dropped from PATH. Without that last part
    # `command -v ollama` would find the real binary, and the tests that assert
    # "no Ollama" would pass only on a machine that happens not to have it.
    PATH="$STUB_BIN:$(path_without_ollama)"
    SYSUPDATE_OLLAMA_BIN=""
    HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    SYSUPDATE_OLLAMA_REGISTRY_URL="https://registry.example.invalid"
    # Inherited values of these three change what the snippet does: a non-empty
    # BLUE makes it skip sourcing core_lib.sh (so print_* and the event helpers
    # would be undefined), SYSUPDATE_QWEN_MODELS adds models no test listing
    # covers and shifts the pending count, and SYSUPDATE_JSON_EVENTS would put
    # event lines into the output of every test that is not about events.
    unset BLUE SYSUPDATE_QWEN_MODELS SYSUPDATE_JSON_EVENTS
}

# $PATH with every directory that holds an executable `ollama` removed.
path_without_ollama() {
    local dir kept=""
    local IFS=:
    for dir in $PATH; do
        [ -n "$dir" ] || continue
        if [ -x "$dir/ollama" ]; then
            continue
        fi
        kept="${kept:+$kept:}$dir"
    done
    printf '%s' "$kept"
}

# Load the snippet's functions without its trailing entry call, keeping its own
# `../lib` lookup working.
#
# OLLAMA_BIN is resolved at source time, so every stub a test needs must be in
# place before this is called -- which is also what makes resolve_ollama_bin's
# precedence observable.
source_qwen_functions() {
    local snippets_dir="$BATS_TEST_TMPDIR/pkg/upgrade_snippets"
    mkdir -p "$snippets_dir"
    ln -sfn "$REPO_ROOT/scripts/lib" "$BATS_TEST_TMPDIR/pkg/lib"
    sed '$d' "$REPO_ROOT/scripts/upgrade_snippets/update_qwen.sh" \
        > "$snippets_dir/update_qwen.sh"
    # shellcheck disable=SC1090
    source "$snippets_dir/update_qwen.sh"
}

# An `ollama` that serves a canned listing and records every pull.
#
# It is an executable rather than a shell function because the snippet invokes
# "$OLLAMA_BIN", a path, and a function could never be reached that way.
stub_ollama() {
    local where="${1:-$STUB_BIN/ollama}"
    mkdir -p "$(dirname "$where")"
    : > "$BATS_TEST_TMPDIR/pulls.log"
    cat > "$where" <<'STUB'
#!/bin/bash
case "$1" in
    list)
        cat "$BATS_TEST_TMPDIR/ollama_list.txt" 2>/dev/null
        exit "$(cat "$BATS_TEST_TMPDIR/ollama_list_rc" 2>/dev/null || echo 0)"
        ;;
    pull)
        echo "$2" >> "$BATS_TEST_TMPDIR/pulls.log"
        exit "$(cat "$BATS_TEST_TMPDIR/ollama_pull_rc" 2>/dev/null || echo 0)"
        ;;
esac
exit 0
STUB
    chmod +x "$where"
    echo 0 > "$BATS_TEST_TMPDIR/ollama_list_rc"
    echo 0 > "$BATS_TEST_TMPDIR/ollama_pull_rc"
    set_ollama_listing ""
}

# `ollama list` output: the real header row, then whatever rows are given.
set_ollama_listing() {
    {
        printf 'NAME\tID\tSIZE\tMODIFIED\n'
        # An `if` rather than `[ -n ... ] &&`: with no rows the test would be
        # the function's last command, so it would return 1 for an empty
        # listing and abort the calling test before the snippet ever ran.
        if [ -n "${1:-}" ]; then
            printf '%s\n' "$1"
        fi
    } > "$BATS_TEST_TMPDIR/ollama_list.txt"
}

# A `curl` that serves a fixed body and records every URL it was asked for.
stub_curl() {
    : > "$BATS_TEST_TMPDIR/curl_urls.log"
    printf '%s' "${1-}" > "$BATS_TEST_TMPDIR/manifest.json"
    echo "${2:-0}" > "$BATS_TEST_TMPDIR/curl_rc"
    cat > "$STUB_BIN/curl" <<'STUB'
#!/bin/bash
out=""
prev=""
for arg in "$@"; do
    [ "$prev" = "-o" ] && out="$arg"
    case "$arg" in
        http*) echo "$arg" >> "$BATS_TEST_TMPDIR/curl_urls.log" ;;
    esac
    prev="$arg"
done
rc=$(cat "$BATS_TEST_TMPDIR/curl_rc" 2>/dev/null || echo 0)
# A transfer that fails part-way has already written what it received, so the
# body is NOT empty on failure. That is what makes checking curl's exit status
# load-bearing rather than redundant with the empty-body check.
#
# Both destinations are served, so a snippet that stopped passing -o would hash
# an empty file rather than quietly keep passing.
if [ -n "$out" ]; then
    cat "$BATS_TEST_TMPDIR/manifest.json" > "$out"
else
    cat "$BATS_TEST_TMPDIR/manifest.json"
fi
exit "$rc"
STUB
    chmod +x "$STUB_BIN/curl"
}

# The digest the snippet should arrive at for a given body.
digest_of() {
    printf '%s' "$1" | sha256sum | cut -c1-12
}

# Capture only the JSON events, which go to stderr.
qwen_events() {
    enable_json_events
    update_qwen_models 2>&1 1>/dev/null
}

# ---------------------------------------------------------------------------
# resolve_ollama_bin
#
# The user-local install (~/.local/ollama/bin) is routinely absent from PATH on
# this project's own machine, which is the reason this function exists at all.
# ---------------------------------------------------------------------------

@test "resolve_ollama_bin: finds ollama on PATH" {
    stub_ollama
    source_qwen_functions
    [ "$OLLAMA_BIN" = "$STUB_BIN/ollama" ]
}

@test "resolve_ollama_bin: finds the user-local install when it is not on PATH" {
    stub_ollama "$HOME/.local/ollama/bin/ollama"
    source_qwen_functions
    [ "$OLLAMA_BIN" = "$HOME/.local/ollama/bin/ollama" ]
}

@test "resolve_ollama_bin: SYSUPDATE_OLLAMA_BIN wins over both" {
    stub_ollama
    stub_ollama "$HOME/.local/ollama/bin/ollama"
    stub_ollama "$BATS_TEST_TMPDIR/elsewhere/ollama"
    SYSUPDATE_OLLAMA_BIN="$BATS_TEST_TMPDIR/elsewhere/ollama"
    source_qwen_functions
    [ "$OLLAMA_BIN" = "$BATS_TEST_TMPDIR/elsewhere/ollama" ]
}

@test "resolve_ollama_bin: a candidate that is not executable is skipped" {
    # A non-executable file at the override path must not shadow a working one.
    mkdir -p "$BATS_TEST_TMPDIR/broken"
    : > "$BATS_TEST_TMPDIR/broken/ollama"
    chmod -x "$BATS_TEST_TMPDIR/broken/ollama"
    SYSUPDATE_OLLAMA_BIN="$BATS_TEST_TMPDIR/broken/ollama"
    stub_ollama
    source_qwen_functions
    [ "$OLLAMA_BIN" = "$STUB_BIN/ollama" ]
}

@test "resolve_ollama_bin: reports nothing found rather than an empty path that looks valid" {
    source_qwen_functions
    [ -z "$OLLAMA_BIN" ]
    run resolve_ollama_bin
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# list_installed_qwen_models
# ---------------------------------------------------------------------------

@test "list_installed_qwen_models: skips the header row" {
    stub_ollama
    set_ollama_listing "qwen3:4b	359d7dd4bcda	2.6 GB	2 days ago"
    source_qwen_functions
    run list_installed_qwen_models
    [ "$status" -eq 0 ]
    [ "$output" = "qwen3:4b 359d7dd4bcda" ]
    [[ "$output" != *NAME* ]]
}

@test "list_installed_qwen_models: ignores models from other families" {
    stub_ollama
    set_ollama_listing "llama3:8b	aaaaaaaaaaaa	4.7 GB	1 day ago
qwen3:4b	359d7dd4bcda	2.6 GB	2 days ago
mistral:7b	bbbbbbbbbbbb	4.1 GB	3 days ago"
    source_qwen_functions
    run list_installed_qwen_models
    [ "$output" = "qwen3:4b 359d7dd4bcda" ]
}

@test "list_installed_qwen_models: matches a namespaced model by its last path component" {
    stub_ollama
    set_ollama_listing "someuser/qwen3:4b	cccccccccccc	2.6 GB	1 day ago"
    source_qwen_functions
    run list_installed_qwen_models
    [ "$output" = "someuser/qwen3:4b cccccccccccc" ]
}

@test "list_installed_qwen_models: matches a host-qualified model and keeps its full reference" {
    stub_ollama
    set_ollama_listing "hf.co/Qwen/Qwen3-4B-GGUF:Q4_K_M	dddddddddddd	2.5 GB	1 day ago"
    source_qwen_functions
    run list_installed_qwen_models
    # The printed name must stay the full reference, since that is what gets
    # passed back to `ollama pull`.
    [ "$output" = "hf.co/Qwen/Qwen3-4B-GGUF:Q4_K_M dddddddddddd" ]
}

@test "list_installed_qwen_models: is case-insensitive about the family name" {
    stub_ollama
    set_ollama_listing "Qwen3:4B	eeeeeeeeeeee	2.6 GB	1 day ago"
    source_qwen_functions
    run list_installed_qwen_models
    [ "$output" = "Qwen3:4B eeeeeeeeeeee" ]
}

@test "list_installed_qwen_models: a name that merely contains qwen is not a Qwen model" {
    stub_ollama
    set_ollama_listing "myqwen-finetune:latest	ffffffffffff	2.6 GB	1 day ago
notqwen:7b	111111111111	4.1 GB	1 day ago"
    source_qwen_functions
    run list_installed_qwen_models
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# fetch_qwen_remote_digest: reference to registry URL
#
# Getting this mapping wrong does not error -- it fetches some other model's
# manifest, or a 404 page, and reports a confident wrong answer.
# ---------------------------------------------------------------------------

@test "fetch_qwen_remote_digest: a library model maps to /v2/library/<name>/manifests/<tag>" {
    stub_ollama
    stub_curl '{"schemaVersion":2}'
    source_qwen_functions
    run fetch_qwen_remote_digest "qwen3:4b"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/curl_urls.log")" = \
      "https://registry.example.invalid/v2/library/qwen3/manifests/4b" ]
}

@test "fetch_qwen_remote_digest: a bare name asks for the latest tag" {
    stub_ollama
    stub_curl '{"schemaVersion":2}'
    source_qwen_functions
    run fetch_qwen_remote_digest "qwen3"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/curl_urls.log")" = \
      "https://registry.example.invalid/v2/library/qwen3/manifests/latest" ]
}

@test "fetch_qwen_remote_digest: a namespaced name keeps its namespace instead of gaining library/" {
    stub_ollama
    stub_curl '{"schemaVersion":2}'
    source_qwen_functions
    run fetch_qwen_remote_digest "someuser/qwen3:4b"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/curl_urls.log")" = \
      "https://registry.example.invalid/v2/someuser/qwen3/manifests/4b" ]
}

@test "fetch_qwen_remote_digest: a tag containing a colon is kept whole" {
    stub_ollama
    stub_curl '{"schemaVersion":2}'
    source_qwen_functions
    run fetch_qwen_remote_digest "qwen3:4b-instruct-q4_K_M"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/curl_urls.log")" = \
      "https://registry.example.invalid/v2/library/qwen3/manifests/4b-instruct-q4_K_M" ]
}

@test "fetch_qwen_remote_digest: the digest is the first 12 hex of the sha256 of the body" {
    stub_ollama
    local body='{"schemaVersion":2,"layers":[{"size":123}]}'
    stub_curl "$body"
    source_qwen_functions
    run fetch_qwen_remote_digest "qwen3:4b"
    [ "$status" -eq 0 ]
    [ "$output" = "$(digest_of "$body")" ]
    [[ "$output" =~ ^[0-9a-f]{12}$ ]]
}

@test "fetch_qwen_remote_digest: a body ending in a newline hashes those bytes, not a stripped copy" {
    stub_ollama
    # `ollama list` stores the sha256 of the manifest as the registry served
    # it, so the comparison is only valid if the snippet hashes those exact
    # bytes. Capturing the body in a shell variable would drop trailing
    # newlines, and the digest of the stripped copy differs from every stored
    # one -- an update reported for every model, on every run, from a byte
    # nobody can see. The live registry happens to send no trailing newline
    # today, which is why this is asserted rather than assumed.
    local body=$'{"schemaVersion":2,"layers":[{"size":123}]}\n'
    stub_curl "$body"
    source_qwen_functions
    run fetch_qwen_remote_digest "qwen3:4b"
    [ "$status" -eq 0 ]
    [ "$output" = "$(digest_of "$body")" ]
    [ "$output" != "$(digest_of "${body%$'\n'}")" ]
}

# ---------------------------------------------------------------------------
# the guards
#
# Each test in this section goes red when the guard named in its comment is
# removed from the snippet.
# ---------------------------------------------------------------------------

# Guard: the `|| return 1` on curl in fetch_qwen_remote_digest.
#
# Without it a failed fetch leaves an empty or partial body, whose hash differs
# from the stored digest -- so an unreachable registry would be reported as an
# update to every model, and `ollama pull` would run against a registry that is
# not answering.
@test "fetch_qwen_remote_digest: a transfer that fails part-way is unknown, not a digest of what arrived" {
    stub_ollama
    # curl exits non-zero having already written a prefix of the manifest. The
    # bytes are real, just incomplete, so nothing downstream can tell they are
    # partial -- only curl's exit status can.
    local partial='{"schemaVersion":2,"mediaType":"applicat'
    stub_curl "$partial" 18
    source_qwen_functions
    run fetch_qwen_remote_digest "qwen3:4b"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    # Spelled out because this is the whole point: hashing what arrived would
    # produce a well-formed digest that differs from every stored one, and so
    # report an update for every model whenever the network hiccups.
    [ "$output" != "$(digest_of "$partial")" ]
}

# Guard: `[ -n "$manifest" ] || return 1`.
#
# curl can exit 0 having written nothing. The sha256 of an empty body is a
# perfectly well-formed 12-hex digest, so without this check the snippet
# reports that constant as the registry's answer -- the same false update for
# every model, and a stable one, which is what makes it hard to notice.
@test "fetch_qwen_remote_digest: an empty body is not hashed into a plausible digest" {
    stub_ollama
    stub_curl ''
    source_qwen_functions
    run fetch_qwen_remote_digest "qwen3:4b"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    # Spelled out so the failure message is unambiguous if this ever regresses.
    [ "$output" != "$(digest_of '')" ]
}

# Guard: the `*.*/*) return 1` arm.
#
# A host-qualified model is served by another registry entirely. Asking
# registry.ollama.ai for it would answer about a different model or 404; either
# way the honest result is "unknown", and no request should be made at all.
@test "fetch_qwen_remote_digest: a host-qualified model is unknown without a request" {
    stub_ollama
    stub_curl '{"schemaVersion":2}'
    source_qwen_functions
    run fetch_qwen_remote_digest "hf.co/Qwen/Qwen3-4B-GGUF:Q4_K_M"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    [ ! -s "$BATS_TEST_TMPDIR/curl_urls.log" ]
}

# Guard: `|| return 1` on `ollama list` inside list_installed_qwen_models.
#
# An unreadable listing must not look like an empty one. If it did, every
# installed model would drop out of the loop and the snippet would emit
# up_to_date with nothing checked -- a green answer that means nothing.
@test "list_installed_qwen_models: a failing listing is an error, not an empty list" {
    stub_ollama
    set_ollama_listing "qwen3:4b	359d7dd4bcda	2.6 GB	2 days ago"
    echo 1 > "$BATS_TEST_TMPDIR/ollama_list_rc"
    source_qwen_functions
    run list_installed_qwen_models
    [ "$status" -ne 0 ]
}

# Guard: the `pending -gt 0` / `elif unknown -gt 0` precedence.
#
# A run that found both a real update and an unreadable model must report the
# update. Reporting "unknown" instead would hide a pull that is genuinely due.
@test "update_qwen_models: a real update outranks an unknown in the summary status" {
    stub_ollama
    set_ollama_listing "qwen3:4b	359d7dd4bcda	2.6 GB	2 days ago
hf.co/Qwen/Qwen3-4B-GGUF:Q4_K_M	dddddddddddd	2.5 GB	1 day ago"
    stub_curl '{"schemaVersion":2}'
    SYSUPDATE_QWEN_MODELS=""
    source_qwen_functions
    run qwen_events
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"update_available"'* ]]
    [[ "$output" == *'"total_updates":1}'* ]]
    [[ "$output" != *'"status":"unknown"'* ]]
}

# ---------------------------------------------------------------------------
# update_qwen_models: the summary event
#
# Every snippet must emit exactly one summary.updates event, and consumers read
# status and total_updates from it.
# ---------------------------------------------------------------------------

@test "update_qwen_models: no Ollama reports not_installed and does not fail the run" {
    source_qwen_functions
    [ -z "$OLLAMA_BIN" ]
    run qwen_events
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"not_installed"'* ]]
    [[ "$output" == *'"total_updates":0}'* ]]
}

@test "update_qwen_models: an Ollama that is not answering reports unknown, not up_to_date" {
    stub_ollama
    echo 1 > "$BATS_TEST_TMPDIR/ollama_list_rc"
    source_qwen_functions
    run qwen_events
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"unknown"'* ]]
    [[ "$output" != *'"status":"up_to_date"'* ]]
}

@test "update_qwen_models: a matching digest reports up_to_date with no updates" {
    stub_ollama
    local body='{"schemaVersion":2,"layers":[{"size":1}]}'
    set_ollama_listing "qwen3:4b	$(digest_of "$body")	2.6 GB	2 days ago"
    stub_curl "$body"
    source_qwen_functions
    run qwen_events
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"up_to_date"'* ]]
    [[ "$output" == *'"total_updates":0}'* ]]
}

@test "update_qwen_models: a republished tag is reported as an update" {
    stub_ollama
    set_ollama_listing "qwen3:4b	000000000000	2.6 GB	2 days ago"
    stub_curl '{"schemaVersion":2,"layers":[{"size":2}]}'
    source_qwen_functions
    run qwen_events
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"update_available"'* ]]
    [[ "$output" == *'"total_updates":1}'* ]]
}

@test "update_qwen_models: a wanted model that is not downloaded counts as pending" {
    stub_ollama
    SYSUPDATE_QWEN_MODELS="qwen3:4b"
    source_qwen_functions
    run qwen_events
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"update_available"'* ]]
    [[ "$output" == *'"total_updates":1}'* ]]
}

@test "update_qwen_models: an unreadable registry reports unknown with no updates claimed" {
    stub_ollama
    set_ollama_listing "qwen3:4b	359d7dd4bcda	2.6 GB	2 days ago"
    stub_curl '{"schemaVersion":2}' 22
    SYSUPDATE_QWEN_MODELS=""
    source_qwen_functions
    run qwen_events
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status":"unknown"'* ]]
    [[ "$output" == *'"total_updates":0}'* ]]
}

@test "update_qwen_models: emits exactly one summary.updates event" {
    stub_ollama
    local body='{"schemaVersion":2}'
    set_ollama_listing "qwen3:4b	$(digest_of "$body")	2.6 GB	2 days ago"
    stub_curl "$body"
    SYSUPDATE_QWEN_MODELS=""
    source_qwen_functions
    run qwen_events
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | grep -c '"event_type":"summary.updates"')" -eq 1 ]
    [[ "$output" == *'"package_manager":"ollama"'* ]]
    [[ "$output" == *'"summary_name":"qwen_models"'* ]]
}

# ---------------------------------------------------------------------------
# update_qwen_models: which models get tracked
# ---------------------------------------------------------------------------

@test "update_qwen_models: tracks the union of installed and wanted models, deduplicated" {
    stub_ollama
    set_ollama_listing "qwen3:4b	359d7dd4bcda	2.6 GB	2 days ago
qwen2.5:7b-instruct-q4_K_M	845dbda0ea48	4.7 GB	5 days ago"
    stub_curl '{"schemaVersion":2}'
    # qwen3:4b is already installed, so the wanted list must not double it.
    SYSUPDATE_QWEN_MODELS="qwen3:4b qwen3.5:4b"
    source_qwen_functions
    run update_qwen_models
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tracking 3 Qwen model(s)"* ]]
    [[ "$output" == *"qwen2.5:7b-instruct-q4_K_M"* ]]
    [[ "$output" == *"qwen3.5:4b"* ]]
}

# ---------------------------------------------------------------------------
# update_qwen_models: the pull path
# ---------------------------------------------------------------------------

@test "update_qwen_models: pulls every tracked model when not in check-only mode" {
    stub_ollama
    CHECK_ONLY_MODE=false
    set_ollama_listing "qwen3:4b	359d7dd4bcda	2.6 GB	2 days ago"
    SYSUPDATE_QWEN_MODELS="qwen3.5:4b"
    source_qwen_functions
    run update_qwen_models
    [ "$status" -eq 0 ]
    # Which models, not in which order: the snippet sorts its tracking list and
    # '.' collates before ':', so qwen3.5:4b legitimately comes first.
    run grep -c . "$BATS_TEST_TMPDIR/pulls.log"
    [ "$output" = "2" ]
    run grep -Fx "qwen3:4b" "$BATS_TEST_TMPDIR/pulls.log"
    [ "$status" -eq 0 ]
    run grep -Fx "qwen3.5:4b" "$BATS_TEST_TMPDIR/pulls.log"
    [ "$status" -eq 0 ]
}

@test "update_qwen_models: a failed pull fails the snippet and leaves the model pending" {
    stub_ollama
    CHECK_ONLY_MODE=false
    set_ollama_listing "qwen3:4b	359d7dd4bcda	2.6 GB	2 days ago"
    SYSUPDATE_QWEN_MODELS=""
    echo 1 > "$BATS_TEST_TMPDIR/ollama_pull_rc"
    source_qwen_functions
    run qwen_events
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status":"update_available"'* ]]
    [[ "$output" == *'"total_updates":1}'* ]]
}

@test "update_qwen_models: the check-only path pulls nothing" {
    stub_ollama
    set_ollama_listing "qwen3:4b	000000000000	2.6 GB	2 days ago"
    stub_curl '{"schemaVersion":2}'
    source_qwen_functions
    run update_qwen_models
    [ "$status" -eq 0 ]
    # An update was reported; even so, nothing may be downloaded.
    [ ! -s "$BATS_TEST_TMPDIR/pulls.log" ]
}
