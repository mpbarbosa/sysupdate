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
# Version: 0.1.0
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

# Every qwen model already on disk, one "name id" pair per line.
list_installed_qwen_models() {
    ollama list 2>/dev/null | awk 'NR>1 && $1 ~ /^qwen/ {print $1, $2}' || true
}

# Registry manifest digest (first 12 hex) for a model reference, or empty.
# qwen3:4b -> /v2/library/qwen3/manifests/4b ; a bare name means tag latest;
# a namespaced name (user/model) keeps its namespace.
fetch_qwen_remote_digest() {
    local ref="$1" name tag repo digest
    name="${ref%%:*}"
    tag="latest"
    [ "$name" != "$ref" ] && tag="${ref#*:}"
    case "$name" in
        */*) repo="$name" ;;
        *)   repo="library/$name" ;;
    esac

    digest=$(curl -fsSL --max-time 20 \
        -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
        "$QWEN_REGISTRY_URL/v2/$repo/manifests/$tag" 2>/dev/null \
        | sha256sum | cut -c1-12) || true

    # sha256 of empty input means the fetch failed; reject anything not hex.
    if [ "$digest" = "e3b0c44298fc" ] || ! [[ "$digest" =~ ^[0-9a-f]{12}$ ]]; then
        return 1
    fi
    echo "$digest"
}

update_qwen_models() {
    if ! command -v ollama &> /dev/null; then
        print_warning "🦙 Ollama not installed - skipping Qwen model updates"
        print_status "💡 Install Ollama from https://ollama.com/download"
        return 0
    fi

    print_operation_header "🔄 Checking Qwen models in Ollama..."

    if ! ollama list &> /dev/null; then
        print_warning "Ollama is not running - skipping Qwen model updates"
        print_status "Start it with 'ollama serve' or 'systemctl start ollama'"
        emit_summary_event "qwen_models" "package_manager" "ollama" "status" "unknown" "total_updates" "0"
        return 0
    fi

    # name -> local id; wanted models that are not installed get an empty id.
    local -A local_ids=()
    local name id model
    while read -r name id; do
        [ -n "$name" ] && local_ids["$name"]="$id"
    done < <(list_installed_qwen_models)
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
        if ! ollama pull "$model"; then
            print_error "Failed to pull $model"
            failed=$((failed + 1))
        fi
    done

    if [ "$failed" -gt 0 ]; then
        print_error "$failed Qwen model pull(s) failed"
        emit_summary_event "qwen_models" "package_manager" "ollama" "status" "failed" "total_updates" "0"
        return 1
    fi

    print_success "Qwen models are up to date"
    emit_summary_event "qwen_models" "package_manager" "ollama" "status" "up_to_date" "total_updates" "0"
    ask_continue
}

update_qwen_models
