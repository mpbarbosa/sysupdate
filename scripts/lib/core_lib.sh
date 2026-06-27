#!/bin/bash
#
# core_lib.sh - Core utilities and output formatting functions
#
# Provides color definitions, formatted output functions, and common utilities
# used across all package manager modules.
#
# Version: 0.5.0
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#

#=============================================================================
# COLOR DEFINITIONS AND OUTPUT FORMATTING
#=============================================================================
# ANSI color codes for consistent, colored terminal output

RED='\033[0;31m'      # Error messages and critical issues
GREEN='\033[0;32m'    # Success messages and positive outcomes  
YELLOW='\033[1;33m'   # Warning messages and cautionary information
BLUE='\033[0;34m'     # Section headers and operation titles
CYAN='\033[0;36m'     # Informational messages and status updates
MAGENTA='\033[0;35m'  # User prompts and interactive elements
NC='\033[0m'          # No Color - resets terminal color to default

#=============================================================================
# MACHINE-READABLE EVENT STREAM SUPPORT
#=============================================================================

SYSUPDATE_JSON_EVENTS="${SYSUPDATE_JSON_EVENTS:-false}"
SYSUPDATE_EVENT_SEQUENCE="${SYSUPDATE_EVENT_SEQUENCE:-0}"
SYSUPDATE_RUN_ID="${SYSUPDATE_RUN_ID:-}"
SYSUPDATE_PROMPT_INPUT="${SYSUPDATE_PROMPT_INPUT:-}"
CHECK_ONLY_MODE="${CHECK_ONLY_MODE:-false}"
SYSUPDATE_STATE_DIR="${SYSUPDATE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/sysupdate}"
SYSUPDATE_LOG_FILE="${SYSUPDATE_LOG_FILE:-$SYSUPDATE_STATE_DIR/run-history.jsonl}"

enable_json_events() {
    SYSUPDATE_JSON_EVENTS=true

    if [ -z "$SYSUPDATE_RUN_ID" ]; then
        SYSUPDATE_RUN_ID="sysupdate-$(date +%Y%m%dT%H%M%S)-$$"
    fi
}

json_escape() {
    local value="${1:-}"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}

    printf '%s' "$value"
}

json_value() {
    local value="${1:-}"

    if [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || [ "$value" = "true" ] || [ "$value" = "false" ] || [ "$value" = "null" ]; then
        printf '%s' "$value"
    else
        printf '"%s"' "$(json_escape "$value")"
    fi
}

next_event_sequence() {
    SYSUPDATE_EVENT_SEQUENCE=$((SYSUPDATE_EVENT_SEQUENCE + 1))
}

resolve_event_source() {
    local i

    for ((i=1; i<${#BASH_SOURCE[@]}; i++)); do
        local source_file="${BASH_SOURCE[$i]}"
        local source_basename
        source_basename="$(basename "$source_file")"

        if [ "$source_basename" != "core_lib.sh" ] && [ "$source_basename" != "upgrade_utils.sh" ]; then
            local source_function="${FUNCNAME[$i]:-main}"
            printf '%s|%s|%s:%s' "$source_basename" "$source_function" "$source_basename" "$source_function"
            return 0
        fi
    done

    printf 'core_lib.sh|main|core_lib.sh:main'
}

emit_event() {
    if [ "$SYSUPDATE_JSON_EVENTS" != true ]; then
        return 0
    fi

    local event_type="$1"
    shift

    if [ -z "$SYSUPDATE_RUN_ID" ]; then
        enable_json_events
    fi

    local event_timestamp
    event_timestamp="$(date -Iseconds)"
    next_event_sequence
    local event_sequence="$SYSUPDATE_EVENT_SEQUENCE"

    local module_name function_name source_name
    IFS='|' read -r module_name function_name source_name < <(resolve_event_source)

    local json_output
    json_output="{"
    json_output+="\"event_type\":$(json_value "$event_type")"
    json_output+=",\"timestamp\":$(json_value "$event_timestamp")"
    json_output+=",\"sequence\":$(json_value "$event_sequence")"
    json_output+=",\"pid\":$(json_value "$$")"
    json_output+=",\"run_id\":$(json_value "$SYSUPDATE_RUN_ID")"
    json_output+=",\"module\":$(json_value "$module_name")"
    json_output+=",\"function\":$(json_value "$function_name")"
    json_output+=",\"source\":$(json_value "$source_name")"

    while [ "$#" -ge 2 ]; do
        local key="$1"
        local value="$2"
        shift 2
        json_output+=",\"$key\":$(json_value "$value")"
    done

    json_output+="}"
    printf '%s\n' "$json_output" >&2
}

emit_terminal_event() {
    local line_type="$1"
    local message="$2"
    emit_event "terminal.line" "line_type" "$line_type" "message" "$message"
}

emit_summary_event() {
    local summary_name="$1"
    shift
    emit_event "summary.updates" "summary_name" "$summary_name" "$@"
}

ensure_sysupdate_state_dir() {
    mkdir -p "$SYSUPDATE_STATE_DIR" 2>/dev/null
}

persist_log_entry() {
    local category="$1"
    local target="$2"
    local action="$3"
    local status="$4"
    local details="$5"
    local duration="$6"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    ensure_sysupdate_state_dir || return 0

    local log_json
    log_json="{"
    log_json+="\"id\":$(json_value "${SYSUPDATE_RUN_ID}-log-${SYSUPDATE_EVENT_SEQUENCE}")"
    log_json+=",\"timestamp\":$(json_value "$timestamp")"
    log_json+=",\"category\":$(json_value "$category")"
    log_json+=",\"target\":$(json_value "$target")"
    log_json+=",\"action\":$(json_value "$action")"
    log_json+=",\"status\":$(json_value "$status")"
    log_json+=",\"details\":$(json_value "$details")"
    log_json+=",\"duration\":$(json_value "$duration")"
    log_json+=",\"run_id\":$(json_value "$SYSUPDATE_RUN_ID")"
    log_json+=",\"check_only_mode\":$(json_value "$CHECK_ONLY_MODE")"
    log_json+="}"

    printf '%s\n' "$log_json" >> "$SYSUPDATE_LOG_FILE" 2>/dev/null || true
}

emit_log_event() {
    local action="$1"
    local target="$2"
    local status="$3"
    shift 3
    local extras=("$@")
    local category="system"
    local details=""
    local duration=""
    local i

    for ((i=0; i<${#extras[@]}-1; i+=2)); do
        case "${extras[$i]}" in
            category) category="${extras[$((i + 1))]}" ;;
            details) details="${extras[$((i + 1))]}" ;;
            duration) duration="${extras[$((i + 1))]}" ;;
        esac
    done

    emit_event "log.entry" "action" "$action" "target" "$target" "status" "$status" "${extras[@]}"
    persist_log_entry "$category" "$target" "$action" "$status" "$details" "$duration"
}

#=============================================================================
# UTILITY FUNCTIONS FOR FORMATTED OUTPUT
#=============================================================================

print_operation_header() {
    echo -e "\n${BLUE}\033[1m$1\033[0m"
    emit_terminal_event "operation_header" "$1"
}

print_status() {
    echo -e "${CYAN}ℹ️${NC} $1"
    emit_terminal_event "info" "$1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
    emit_terminal_event "success" "$1"
}

print_warning() {
    echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"
    emit_terminal_event "warning" "$1"
}

print_error() {
    echo -e "${RED}❌ [ERROR]${NC} $1"
    emit_terminal_event "error" "$1"
}

print_section_header() {
    local section_name="$1"
    local emoji=""
    
    case "$section_name" in
        *"APT"*) emoji="📦" ;;
        *"PACMAN"*) emoji="🏹" ;;
        *"DPKG"*) emoji="🔧" ;;
        *"SNAP"*) emoji="📱" ;;
        *"RUST"*|*"CARGO"*) emoji="🦀" ;;
        *"PYTHON"*|*"PIP"*) emoji="🐍" ;;
        *"NODE"*|*"NPM"*) emoji="📗" ;;
        *"KITTY"*) emoji="🐱" ;;
        *"COPILOT"*|*"GITHUB"*) emoji="🤖" ;;
        *"CALIBRE"*) emoji="📚" ;;
        *"SYSTEM"*|*"UPGRADE"*) emoji="⚡" ;;
        *"INFORMATION"*|*"SUMMARY"*) emoji="ℹ️" ;;
        *) emoji="🔧" ;;
    esac
    
    local section_with_emoji="$emoji $section_name"
    local line_length=80
    local padding_length=$(( (line_length - ${#section_with_emoji} - 2) / 2 ))
    local padding
    padding=$(printf "%*s" "$padding_length" "")
    
    echo -e "\033[44;37m${padding} ${section_with_emoji} ${padding}\033[0m"
    emit_terminal_event "section_header" "$section_with_emoji"
}

#=============================================================================
# UTILITY HELPER FUNCTIONS
#=============================================================================

resolve_prompt_response() {
    local prompt_type="$1"
    local prompt_message="$2"
    local default_response="${3:-}"
    local prompt_display="${4:-}"
    local options="${5:-}"
    local response_var_name="$6"
    local quiet_mode_value="${QUIET_MODE:-false}"
    local resolved_response=""
    local response_source="tty"

    emit_event "prompt.requested" \
        "prompt_type" "$prompt_type" \
        "prompt_message" "$prompt_message" \
        "default_response" "$default_response" \
        "options" "$options" \
        "check_only_mode" "$CHECK_ONLY_MODE" \
        "quiet_mode" "$quiet_mode_value"

    if [ "$CHECK_ONLY_MODE" = true ]; then
        resolved_response="$default_response"
        response_source="check-only-default"
    elif [ "$quiet_mode_value" = true ]; then
        resolved_response="$default_response"
        response_source="quiet-default"
    elif [ -n "$SYSUPDATE_PROMPT_INPUT" ]; then
        IFS= read -r resolved_response < "$SYSUPDATE_PROMPT_INPUT"
        response_source="external-input"
    elif [ -t 0 ]; then
        if [ -n "$prompt_display" ]; then
            printf '%b' "$prompt_display"
        fi
        IFS= read -r resolved_response
        response_source="tty"
    else
        resolved_response="$default_response"
        response_source="no-tty-default"
    fi

    emit_event "prompt.resolved" \
        "prompt_type" "$prompt_type" \
        "prompt_message" "$prompt_message" \
        "default_response" "$default_response" \
        "response" "$resolved_response" \
        "response_source" "$response_source" \
        "check_only_mode" "$CHECK_ONLY_MODE" \
        "quiet_mode" "$quiet_mode_value"

    local -n response_ref="$response_var_name"
    # shellcheck disable=SC2034
    response_ref="$resolved_response"
}

prompt_yes_no() {
    local question="$1"
    local default="${2:-N}"
    local prompt_suffix

    if [ "$default" = "Y" ] || [ "$default" = "y" ]; then
        prompt_suffix="(Y/n)"
    else
        prompt_suffix="(y/N)"
    fi

    local prompt_text="$question $prompt_suffix: "
    local prompt_display="${MAGENTA}❓ [PROMPT]${NC} $prompt_text"
    local effective_default="$default"
    local response
    if [ "$CHECK_ONLY_MODE" = true ]; then
        effective_default="N"
    fi
    resolve_prompt_response "yes_no" "$question" "$effective_default" "$prompt_display" "$prompt_suffix" response

    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        [Nn]|[Nn][Oo])
            return 1
            ;;
        "")
            [ "$default" = "Y" ] || [ "$default" = "y" ]
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

prompt_choice() {
    local question="$1"
    local options="$2"
    local default="$3"
    local prompt_display="${MAGENTA}❓ [PROMPT]${NC} $question ($options): "
    local response

    resolve_prompt_response "choice" "$question" "$default" "$prompt_display" "$options" response

    if [ -z "$response" ]; then
        echo "$default"
    else
        echo "$response"
    fi
}

prompt_input() {
    local question="$1"
    local default="${2:-}"
    local options="${3:-}"
    local prompt_display="${MAGENTA}❓ [PROMPT]${NC} $question"
    if [ -n "$default" ]; then
        prompt_display="$prompt_display [default: $default]"
    fi
    prompt_display="$prompt_display: "

    local response
    resolve_prompt_response "input" "$question" "$default" "$prompt_display" "$options" response

    if [ -z "$response" ]; then
        echo "$default"
    else
        echo "$response"
    fi
}

# Ensure standard per-user binary directories are on PATH.
# Native installers (Claude Code's install.sh, pipx, pip --user, etc.) place
# executables under XDG/user-local bin dirs that a non-login or sanitized-PATH
# invocation of this script may omit. Without them, `command -v <tool>` reports
# an installed tool as missing — e.g. ~/.local/bin/claude looking "not
# installed". Prepend the well-known dirs idempotently so detection matches what
# an interactive shell sees. Only directories that exist are added.
ensure_user_paths() {
    local dir
    for dir in "$HOME/.local/bin" "$HOME/bin"; do
        [ -d "$dir" ] || continue
        case ":$PATH:" in
            *":$dir:"*) ;;            # already present — skip
            *) PATH="$dir:$PATH" ;;
        esac
    done
    export PATH
}

sudo_credentials_cached() {
    sudo -n true >/dev/null 2>&1
}

# Returns 0 when a sudo command can succeed without a manual password prompt
# being impossible: either credentials are already cached, or there is a TTY on
# stdin to prompt against. In non-interactive contexts (e.g. the web backend)
# with no cached credentials this returns 1, letting callers skip work early
# instead of failing after side effects such as downloads.
sudo_can_run() {
    sudo_credentials_cached || [ -t 0 ]
}

emit_sudo_required_event() {
    local command_preview="$1"
    local cached_credentials="$2"
    local has_tty="false"

    if [ -t 0 ]; then
        has_tty="true"
    fi

    emit_event "sudo.required" \
        "command" "$command_preview" \
        "cached_credentials" "$cached_credentials" \
        "has_tty" "$has_tty"
}

run_with_sudo() {
    local command_preview="$*"
    local cached_credentials="false"

    if sudo_credentials_cached; then
        cached_credentials="true"
    fi

    emit_sudo_required_event "$command_preview" "$cached_credentials"

    if ! sudo_can_run; then
        print_error "Sudo credentials required for command: $command_preview"
        print_error "Re-run in an interactive terminal or authenticate sudo before using non-interactive mode"
        return 1
    fi

    sudo "$@"
}

ask_continue() {
    local prompt_message="Press Enter to continue or Ctrl+C to exit..."

    if [ "$QUIET_MODE" = true ] || [ "$CHECK_ONLY_MODE" = true ]; then
        local response_source="quiet-default"
        if [ "$CHECK_ONLY_MODE" = true ]; then
            response_source="check-only-default"
        fi
        emit_event "prompt.requested" "prompt_type" "continue" "prompt_message" "$prompt_message" "default_response" "" "options" "" "check_only_mode" "$CHECK_ONLY_MODE" "quiet_mode" "$QUIET_MODE"
        emit_event "prompt.resolved" "prompt_type" "continue" "prompt_message" "$prompt_message" "response" "auto-continue" "response_source" "$response_source" "check_only_mode" "$CHECK_ONLY_MODE" "quiet_mode" "$QUIET_MODE"
        return 0
    fi
    
    echo ""
    local continue_response
    resolve_prompt_response "continue" "$prompt_message" "" "$prompt_message" "" continue_response
    : "$continue_response"
    echo ""
}

detect_package_manager() {
    if command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v apt-get &> /dev/null; then
        echo "apt"
    else
        echo "unknown"
    fi
}

normalize_version_for_comparison() {
    local version="$1"

    version=$(printf '%s' "$version" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    version="${version#v}"

    if [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        local -a parts=()
        local last_index
        local joined_version

        IFS=. read -r -a parts <<< "$version"
        last_index=$((${#parts[@]} - 1))

        while [ "$last_index" -gt 0 ] && [ "${parts[$last_index]}" = "0" ]; do
            unset 'parts[$last_index]'
            ((last_index--))
        done

        local IFS=.
        joined_version="${parts[*]}"
        echo "$joined_version"
        return 0
    fi

    echo "$version"
}

compare_versions() {
    local version1="$1"
    local version2="$2"

    local normalized1
    local normalized2
    normalized1=$(normalize_version_for_comparison "$version1")
    normalized2=$(normalize_version_for_comparison "$version2")

    if [ "$normalized1" = "$normalized2" ]; then
        return 0
    fi

    # Use dpkg for plain dotted numeric versions.
    # Suffixed versions like 25.0.3-ea need custom prerelease ordering where
    # the stable release is newer than the prerelease.
    if [[ "$normalized1" =~ ^[0-9]+(\.[0-9]+)*$ ]] && \
        [[ "$normalized2" =~ ^[0-9]+(\.[0-9]+)*$ ]] && \
        command -v dpkg &>/dev/null; then
        if dpkg --compare-versions "$normalized1" eq "$normalized2" 2>/dev/null; then
            return 0
        elif dpkg --compare-versions "$normalized1" gt "$normalized2" 2>/dev/null; then
            return 1
        elif dpkg --compare-versions "$normalized1" lt "$normalized2" 2>/dev/null; then
            return 2
        fi
    fi

    # Fallback to custom comparison
    local i
    local -a ver1=()
    local -a ver2=()

    IFS=. read -r -a ver1 <<< "$normalized1"
    IFS=. read -r -a ver2 <<< "$normalized2"

    for ((i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++)); do
        local part1=${ver1[i]:-0}
        local part2=${ver2[i]:-0}

        # Extract numeric and alphabetic parts separately
        local num1
        local num2
        local alpha1
        local alpha2
        num1="${part1%%[^0-9]*}"
        num2="${part2%%[^0-9]*}"
        alpha1="${part1#"$num1"}"
        alpha2="${part2#"$num2"}"

        # Default to 0 if empty
        num1=${num1:-0}
        num2=${num2:-0}

        # Compare numeric parts
        if ((10#$num1 > 10#$num2)); then
            return 1
        elif ((10#$num1 < 10#$num2)); then
            return 2
        fi

        # If numeric parts are equal, compare alphabetic suffixes
        if [ "$alpha1" != "$alpha2" ]; then
            if [ -z "$alpha1" ] && [ -n "$alpha2" ]; then
                # 3.6 > 3.6a (stable release is newer than suffixed prerelease)
                return 1
            elif [ -n "$alpha1" ] && [ -z "$alpha2" ]; then
                # 3.6a < 3.6
                return 2
            elif [[ "$alpha1" > "$alpha2" ]]; then
                return 1
            else
                return 2
            fi
        fi
    done

    return 0
}
