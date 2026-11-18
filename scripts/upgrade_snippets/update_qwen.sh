#!/bin/bash
#
# update_qwen.sh - Qwen models served by Ollama
# SNIPPET_ID: qwen
# SNIPPET_NAME: Qwen Models (Ollama)
#
# Pulls the Qwen model Teacher Charles defaults to, and refreshes every Qwen
# model Ollama already has on disk.
#
# Ollama models carry no version number: a tag such as qwen3:4b is moved to a
# new manifest when the model is republished. So "update available" here means
# the registry's manifest digest differs from the local one. `ollama list`
# shows the first 12 hex digits of the sha256 of the manifest it stored, and
# that manifest is the registry's bytes verbatim, so hashing the registry's
# manifest gives a comparable digest without pulling anything.
#
# Version: 0.3.0
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#

if [ -z "$BLUE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../lib/core_lib.sh"
fi

# Teacher Charles's default model; pulled even if it is not downloaded yet.
# Space-separated; override with SYSUPDATE_QWEN_MODELS.
QWEN_WANTED_MODELS="${SYSUPDATE_QWEN_MODELS:-qwen3:4b}"
QWEN_REGISTRY_URL="${SYSUPDATE_OLLAMA_REGISTRY_URL:-https://registry.ollama.ai}"

# Path of the ollama binary, or empty. The user-local install
# (~/.local/ollama/bin) is often not on PATH, so look there too;
# SYSUPDATE_OLLAMA_BIN overrides both.
resolve_ollama_bin() {
    local candidate
    for candidate in "${SYSUPDATE_OLLAMA_BIN:-}" "$(command -v ollama 2>/dev/null || true)" \
                     "$HOME/.local/ollama/bin/ollama"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}
OLLAMA_BIN="$(resolve_ollama_bin || true)"

# Every qwen model already on disk, one "name id" pair per line. Matches the
# model's last path component, so namespaced (user/qwen3) and host-qualified
# (hf.co/Qwen/...) references count too. Fails when `ollama list` does, so a
# broken listing is not mistaken for "nothing installed".
list_installed_qwen_models() {
    local listing
    listing=$("$OLLAMA_BIN" list 2>/dev/null) || return 1
    awk 'NR>1 { n = tolower($1); sub(/.*\//, "", n); if (n ~ /^qwen/) print $1, $2 }' <<< "$listing"
}

# Registry manifest digest (first 12 hex) for a model reference, or empty.
# qwen3:4b -> /v2/library/qwen3/manifests/4b ; a bare name means tag latest;
# a namespaced name (user/model) keeps its namespace.
fetch_qwen_remote_digest() {
    local ref="$1" name tag repo manifest digest
    name="${ref%%:*}"
    tag="latest"
    [ "$name" != "$ref" ] && tag="${ref#*:}"
    case "$name" in
        # Host-qualified (hf.co/...): served by another registry; not checkable here.
        *.*/*) return 1 ;;
        */*)   repo="$name" ;;
        *)     repo="library/$name" ;;
    esac

    # Fetch first and check curl's own status: hashing a truncated body would
    # report a false update instead of an unknown result.
    manifest=$(curl -fsSL --max-time 20 \
        -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
        "$QWEN_REGISTRY_URL/v2/$repo/manifests/$tag" 2>/dev/null) || return 1
    [ -n "$manifest" ] || return 1

    # $(...) strips trailing newlines; the registry's manifest has none.
    digest=$(printf '%s' "$manifest" | sha256sum | cut -c1-12)
    [[ "$digest" =~ ^[0-9a-f]{12}$ ]] || return 1
    echo "$digest"
}

update_qwen_models() {
    if [ -z "$OLLAMA_BIN" ]; then
        print_warning "🦙 Ollama not installed - skipping Qwen model updates"
        print_status "💡 Install Ollama from https://ollama.com/download"
        emit_summary_event "qwen_models" "package_manager" "ollama" "status" "not_installed" "total_updates" "0"
        return 0
    fi

    print_operation_header "🔄 Checking Qwen models in Ollama..."

    print_status "Using $OLLAMA_BIN"
    if ! "$OLLAMA_BIN" list &> /dev/null; then
        print_warning "Ollama is not running - skipping Qwen model updates"
        print_status "Start it with 'ollama serve' or 'systemctl start ollama'"
        emit_summary_event "qwen_models" "package_manager" "ollama" "status" "unknown" "total_updates" "0"
        return 0
    fi

    # name -> local id; wanted models that are not installed get an empty id.
    local -A local_ids=()
    local name id model listing
    if ! listing=$(list_installed_qwen_models); then
        print_error "Could not list Ollama models"
        emit_summary_event "qwen_models" "package_manager" "ollama" "status" "unknown" "total_updates" "0"
        return 1
    fi
    while read -r name id; do
        [ -n "$name" ] && local_ids["$name"]="$id"
    done <<< "$listing"
    for model in $QWEN_WANTED_MODELS; do
        [ -n "${local_ids[$model]+x}" ] || local_ids["$model"]=""
    done

    local models
    mapfile -t models < <(printf '%s\n' "${!local_ids[@]}" | sort -u)
    print_status "Tracking ${#models[@]} Qwen model(s): ${models[*]}"

    if [ "$CHECK_ONLY_MODE" = true ]; then
        local pending=0 unknown=0 remote
        for model in "${models[@]}"; do
            if [ -z "${local_ids[$model]}" ]; then
                print_warning "$model not downloaded yet"
                pending=$((pending + 1))
                continue
            fi
            if ! remote=$(fetch_qwen_remote_digest "$model"); then
                print_warning "$model: could not read the registry manifest"
                unknown=$((unknown + 1))
                continue
            fi
            if [ "$remote" = "${local_ids[$model]}" ]; then
                print_success "$model is up to date ($remote)"
            else
                print_warning "$model update available: ${local_ids[$model]} → $remote"
                pending=$((pending + 1))
            fi
        done

        local status="up_to_date"
        if [ "$pending" -gt 0 ]; then
            status="update_available"
        elif [ "$unknown" -gt 0 ]; then
            status="unknown"
        fi
        emit_summary_event "qwen_models" "package_manager" "ollama" "status" "$status" "total_updates" "$pending"
        return 0
    fi

    local failed=0
    for model in "${models[@]}"; do
        print_status "==> ollama pull $model"
        if ! "$OLLAMA_BIN" pull "$model"; then
            print_error "Failed to pull $model"
            failed=$((failed + 1))
        fi
    done

    if [ "$failed" -gt 0 ]; then
        print_error "$failed Qwen model pull(s) failed"
        # The models that failed still need pulling, so they remain pending.
        emit_summary_event "qwen_models" "package_manager" "ollama" "status" "update_available" "total_updates" "$failed"
        return 1
    fi

    print_success "Qwen models are up to date"
    emit_summary_event "qwen_models" "package_manager" "ollama" "status" "up_to_date" "total_updates" "0"
    ask_continue
}

update_qwen_models
