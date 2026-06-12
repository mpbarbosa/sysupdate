#!/bin/bash
#
# apt_manager.sh - APT Package Manager Operations
#
# Handles all APT/DPKG package operations including updates, upgrades,
# dependency management, and cleanup operations.
#
# Version: 0.4.3
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# License: MIT
#

# Source core library if not already sourced
if [ -z "$BLUE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/core_lib.sh"
fi

#=============================================================================
# APT PACKAGE MANAGER FUNCTIONS
#=============================================================================

apt_emit_output_line() {
    local display_line="$1"
    local line_type="${2:-output}"

    printf '%s\n' "$display_line"
    emit_terminal_event "$line_type" "$display_line"
}

apt_render_command_output_line() {
    local mode="$1"
    local line="$2"

    case "$line" in
        "")
            printf '\n'
            return 0
            ;;
        *"ERROR"*|*"Error"*|*"error"*|*"E:"*)
            apt_emit_output_line "❌ $line" "error"
            return 0
            ;;
        *"WARNING"*|*"Warning"*|*"warning"*|*"W:"*)
            apt_emit_output_line "⚠️  $line" "warning"
            return 0
            ;;
    esac

    case "$mode" in
        update)
            case "$line" in
                Hit:*|Get:*) apt_emit_output_line "💻 $line" ;;
                *"Reading package lists"*) apt_emit_output_line "📖 $line" ;;
                *"Building dependency tree"*) apt_emit_output_line "🌳 $line" ;;
                *"Reading state information"*) apt_emit_output_line "🔍 $line" ;;
                *) apt_emit_output_line "💬 $line" ;;
            esac
            ;;
        upgrade|dist-upgrade)
            case "$line" in
                *"Reading package lists"*) apt_emit_output_line "📖 $line" ;;
                *"Building dependency tree"*) apt_emit_output_line "🌳 $line" ;;
                *"Reading state information"*) apt_emit_output_line "🔍 $line" ;;
                *"Calculating upgrade"*) apt_emit_output_line "🧮 $line" ;;
                *"The following packages will be upgraded:"*) apt_emit_output_line "🔄 $line" ;;
                *"The following packages have been kept back:"*) apt_emit_output_line "⏸️  $line" "warning" ;;
                *"The following NEW packages will be installed:"*) apt_emit_output_line "🆕 $line" ;;
                *"The following packages will be REMOVED:"*) apt_emit_output_line "🗑️  $line" ;;
                *"upgraded,"*|*"newly installed,"*|*"to remove"*) apt_emit_output_line "📊 $line" ;;
                *"Need to get"*) apt_emit_output_line "📥 $line" ;;
                *"After this operation"*) apt_emit_output_line "💾 $line" ;;
                Get:*) apt_emit_output_line "💻 $line" ;;
                *"Fetched"*) apt_emit_output_line "✅ $line" ;;
                *"Unpacking"*) apt_emit_output_line "📦 $line" ;;
                *"Setting up"*) apt_emit_output_line "⚙️  $line" ;;
                *"Processing triggers"*) apt_emit_output_line "🔄 $line" ;;
                *) apt_emit_output_line "💬 $line" ;;
            esac
            ;;
        autoremove)
            case "$line" in
                *"Reading package lists"*) apt_emit_output_line "📖 $line" ;;
                *"Building dependency tree"*) apt_emit_output_line "🌳 $line" ;;
                *"Reading state information"*) apt_emit_output_line "🔍 $line" ;;
                *"The following packages will be REMOVED:"*) apt_emit_output_line "🗑️  $line" ;;
                *"upgraded,"*|*"newly installed,"*|*"to remove"*) apt_emit_output_line "📊 $line" ;;
                *"After this operation"*) apt_emit_output_line "💾 $line" ;;
                *"Removing"*) apt_emit_output_line "🗂️  $line" ;;
                *"Processing triggers"*) apt_emit_output_line "🔄 $line" ;;
                *) apt_emit_output_line "💬 $line" ;;
            esac
            ;;
        autoclean)
            case "$line" in
                *"Reading package lists"*) apt_emit_output_line "📖 $line" ;;
                *"Del "*) apt_emit_output_line "🧽 $line" ;;
                *"Removing obsolete package files"*) apt_emit_output_line "🗂️  $line" ;;
                *"Cleaned"*) apt_emit_output_line "✨ $line" ;;
                *) apt_emit_output_line "💬 $line" ;;
            esac
            ;;
        *)
            apt_emit_output_line "$line"
            ;;
    esac
}

apt_emit_command_output() {
    local output="$1"
    local mode="$2"
    local dedupe="${3:-false}"
    local line
    local previous_line=""

    while IFS= read -r line; do
        if [ "$dedupe" = true ] && [ "$line" = "$previous_line" ]; then
            continue
        fi

        previous_line="$line"
        apt_render_command_output_line "$mode" "$line"
    done <<< "$output"
}

apt_skip_if_check_only() {
    local action_description="$1"

    if [ "${CHECK_ONLY_MODE:-false}" = "true" ]; then
        print_status "Check-only mode - skipping $action_description"
        ask_continue
        return 0
    fi

    return 1
}

apt_has_repository_update_issue() {
    local apt_output="$1"
    grep -qi "does not have a Release file\|404.*Not Found\|Failed to fetch" <<< "$apt_output"
}

apt_extract_broken_repositories() {
    local apt_output="$1"

    awk '
        /404.*Not Found/ {
            if (prev ~ /^Err:[0-9]+ https?:\/\//) {
                match(prev, /https?:\/\/[^ ]+/)
                pattern = substr(prev, RSTART, RLENGTH)
                print pattern
            }
        }
        {prev = $0}
    ' <<< "$apt_output" | sort -u
}

apt_disable_broken_repositories() {
    local broken_repos="$1"
    local sources_list_modified=false
    local repo_pattern
    local escaped_pattern
    local sources_file

    if [ "${VERBOSE_MODE:-false}" = "true" ]; then
        print_status "Searching for broken repository entries in APT sources..."
        print_status "Broken repository patterns to disable:"
        printf '%s\n' "$broken_repos"
    fi

    while IFS= read -r repo_pattern; do
        [ -n "$repo_pattern" ] || continue

        if [ "${VERBOSE_MODE:-false}" = "true" ]; then
            print_status "Processing pattern: $repo_pattern"
        fi

        escaped_pattern=$(echo "$repo_pattern" | sed 's/[\/&]/\\&/g')

        if [ "${VERBOSE_MODE:-false}" = "true" ]; then
            print_status "Escaped pattern for sed: $escaped_pattern"
        fi

        if grep -qF "$repo_pattern" /etc/apt/sources.list 2>/dev/null; then
            print_status "📝 Commenting out entries in /etc/apt/sources.list for: $repo_pattern"
            run_with_sudo sed -i.bak "/^[^#].*${escaped_pattern}/s/^/# [DISABLED - 404 Error] /" /etc/apt/sources.list
            sources_list_modified=true
        fi

        if [ -d /etc/apt/sources.list.d ]; then
            for sources_file in /etc/apt/sources.list.d/*.list; do
                if [ -f "$sources_file" ] && grep -qF "$repo_pattern" "$sources_file" 2>/dev/null; then
                    print_status "📝 Commenting out entries in $sources_file for: $repo_pattern"
                    run_with_sudo sed -i.bak "/^[^#].*${escaped_pattern}/s/^/# [DISABLED - 404 Error] /" "$sources_file"
                    sources_list_modified=true
                fi
            done

            for sources_file in /etc/apt/sources.list.d/*.sources; do
                if [ -f "$sources_file" ] && grep -qF "$repo_pattern" "$sources_file" 2>/dev/null; then
                    print_status "📝 Disabling $sources_file (contains: $repo_pattern)"
                    run_with_sudo mv "$sources_file" "${sources_file}.disabled"
                    sources_list_modified=true
                fi
            done
        fi
    done <<< "$broken_repos"

    [ "$sources_list_modified" = true ]
}

apt_handle_repository_update_failure() {
    local apt_output="$1"
    local rerun_output

    if ! apt_has_repository_update_issue "$apt_output"; then
        print_error "🌐 Critical failure updating package list"
        print_error "🔍 Common causes: network connectivity, repository issues, GPG key problems"
        print_error "🛠️  Check network connection and repository configuration"
        return 1
    fi

    print_warning "🌐 Some repositories failed to update"
    print_status "🔍 Repository issues detected - continuing with available repositories"

    if ! grep -qi "404.*Not Found" <<< "$apt_output"; then
        print_status "💡 You may want to review repository configuration later"
        return 0
    fi

    print_status ""
    print_warning "🔴 404 Not Found errors detected in repository updates"

    local broken_repos
    broken_repos=$(apt_extract_broken_repositories "$apt_output")

    if [ -z "$broken_repos" ]; then
        print_status "💡 You may want to review repository configuration later"
        return 0
    fi

    print_status "📋 Broken repositories identified:"
    while IFS= read -r repo_pattern; do
        [ -n "$repo_pattern" ] || continue
        print_status "   • $repo_pattern"
    done <<< "$broken_repos"

    if [[ "${QUIET_MODE:-false}" == "false" ]]; then
        echo ""
        print_status "💡 These repositories may need to be removed or updated"
        echo ""

        if prompt_yes_no "Would you like to disable/comment out these broken repositories?" "N"; then
            print_operation_header "🔧 Fixing broken repositories..."

            if apt_disable_broken_repositories "$broken_repos"; then
                print_success "✅ Broken repositories have been disabled"
                print_status "💾 Backup files created with .bak extension"
                print_status "🔄 Re-running apt-get update..."
                echo ""

                rerun_output=$(run_with_sudo apt-get update 2>&1)
                local rerun_exit_code=$?
                apt_emit_command_output "$rerun_output" "update"

                if [ $rerun_exit_code -eq 0 ]; then
                    print_success "📋 Package list updated successfully after fixing repositories"
                else
                    print_warning "⚠️  Some issues may still remain - please review manually"
                fi
            else
                print_warning "No matching repository entries found to disable"
            fi
        else
            print_status "💡 You may want to review repository configuration later"
        fi
    else
        print_status "💡 Run in interactive mode to fix broken repositories"
    fi

    return 0
}

apt_extract_kept_back_packages() {
    local upgrade_output="$1"
    grep -A 1 "kept back:" <<< "$upgrade_output" | tail -1 | xargs
}

apt_print_kept_back_package_summary() {
    local package="$1"
    local suffix="${2:-}"
    local policy_output

    policy_output=$(apt-cache policy "$package" 2>/dev/null)
    if grep -q "Installed:" <<< "$policy_output"; then
        local installed_version
        local candidate_version

        installed_version=$(awk '/Installed:/ {print $2; exit}' <<< "$policy_output")
        candidate_version=$(awk '/Candidate:/ {print $2; exit}' <<< "$policy_output")

        if [ -n "$candidate_version" ] && [ "$candidate_version" != "(none)" ]; then
            print_status "  $package: $installed_version → $candidate_version${suffix}"
        else
            print_status "  $package: $installed_version${suffix}"
        fi
    fi
}

apt_install_named_packages() {
    local packages_string="$1"
    local -a packages=()

    read -r -a packages <<< "$packages_string"
    [ ${#packages[@]} -gt 0 ] || return 1

    run_with_sudo apt-get install "${packages[@]}" -y
}

update_package_list() {
    print_operation_header "🔄 Updating package list from repositories..."
    print_status "⏳ This may take a few moments depending on network speed and repository count"

    if apt_skip_if_check_only "APT package list update"; then
        return 0
    fi
    
    local apt_output
    apt_output=$(run_with_sudo apt-get update 2>&1)
    local exit_code=$?
    
    apt_emit_command_output "$apt_output" "update"
    
    if [ $exit_code -eq 0 ]; then
        print_success "📋 Package list updated successfully - local cache now current"
    else
        if ! apt_handle_repository_update_failure "$apt_output"; then
            return 1
        fi
    fi
    
    ask_continue
}

check_unattended_upgrades() {
    print_operation_header "🔒 Checking unattended upgrades configuration..."
    
    if [ ! -f "/etc/apt/apt.conf.d/20auto-upgrades" ]; then
        print_warning "Unattended upgrades configuration file not found"
        print_status "File: /etc/apt/apt.conf.d/20auto-upgrades"
        print_status "Unattended upgrades may not be configured on this system"
        return 0
    fi
    
    local unattended_config
    unattended_config=$(grep "APT::Periodic::Unattended-Upgrade" /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null | grep -o '"[0-9]*"' | tr -d '"')
    
    if [ -z "$unattended_config" ]; then
        print_warning "Unattended-Upgrade setting not found in configuration"
        print_status "The system may not have unattended upgrades properly configured"
        return 0
    fi
    
    print_status "Current unattended upgrades setting: $unattended_config"
    
    if [ "$unattended_config" = "1" ]; then
        print_success "✅ Unattended upgrades are ENABLED"
        print_status "🔒 Your system will automatically install security updates"
        print_status "📋 Configuration: APT::Periodic::Unattended-Upgrade \"1\""
    else
        print_warning "⚠️  Unattended upgrades are DISABLED"
        print_status "🔓 Your system will NOT automatically install security updates"
        print_status "📋 Current configuration: APT::Periodic::Unattended-Upgrade \"$unattended_config\""
        print_status ""
        
        if [ "${CHECK_ONLY_MODE:-false}" = "true" ]; then
            print_status "Check-only mode - unattended upgrades configuration changes are disabled"
            print_status "💡 Consider enabling unattended upgrades for automatic security updates"
            print_status "   Command: sudo dpkg-reconfigure unattended-upgrades"
        elif [[ "${QUIET_MODE:-false}" == "false" ]]; then
            print_status "💡 Enabling unattended upgrades is recommended for security"
            print_status "   • Automatic installation of security updates"
            print_status "   • Reduces exposure to known vulnerabilities"
            print_status "   • Only installs updates from security repositories"
            print_status ""
            
            if prompt_yes_no "Would you like to enable unattended upgrades?" "N"; then
                print_status "🔧 Enabling unattended upgrades..."
                
                local backup_path
                backup_path="/etc/apt/apt.conf.d/20auto-upgrades.backup.$(date +%Y%m%d_%H%M%S)"
                if run_with_sudo cp /etc/apt/apt.conf.d/20auto-upgrades "$backup_path"; then
                    print_status "📋 Configuration backup created"
                fi
                
                if run_with_sudo sed -i 's/APT::Periodic::Unattended-Upgrade "0"/APT::Periodic::Unattended-Upgrade "1"/' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null; then
                    local new_config
                    new_config=$(grep "APT::Periodic::Unattended-Upgrade" /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null | grep -o '"[0-9]*"' | tr -d '"')
                    
                    if [ "$new_config" = "1" ]; then
                        print_success "✅ Unattended upgrades successfully enabled!"
                        print_status "🔒 Your system will now automatically install security updates"
                        print_status "📅 Updates typically check daily and install during low-usage hours"
                        print_status "📝 You can check logs in: /var/log/unattended-upgrades/"
                    else
                        print_error "❌ Failed to verify unattended upgrades configuration change"
                    fi
                else
                    print_error "❌ Failed to enable unattended upgrades"
                    print_status "You may need to manually edit: /etc/apt/apt.conf.d/20auto-upgrades"
                fi
            else
                print_status "⏭️  Unattended upgrades remain disabled"
                print_status "💡 You can enable them later by running: sudo dpkg-reconfigure unattended-upgrades"
            fi
        else
            print_status "💡 Consider enabling unattended upgrades for automatic security updates"
            print_status "   Command: sudo dpkg-reconfigure unattended-upgrades"
        fi
    fi
    
    ask_continue
}

check_updates_available() {
    print_operation_header "🔍 Checking for available package updates..."
    
    if [ ! -x "/usr/lib/update-notifier/apt-check" ]; then
        print_warning "apt-check utility not found at /usr/lib/update-notifier/apt-check"
        print_status "Proceeding with upgrade check using alternative method..."
        
        local upgradable_count
        upgradable_count=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
        if [ "$upgradable_count" -gt 0 ]; then
            print_status "Found $upgradable_count packages available for upgrade (via apt list)"
            emit_summary_event "apt_updates" "package_manager" "apt" "status" "update_available" "total_updates" "$upgradable_count" "security_updates" "unknown"
            return 0
        else
            print_success "No packages available for upgrade (via apt list)"
            emit_summary_event "apt_updates" "package_manager" "apt" "status" "up_to_date" "total_updates" "0" "security_updates" "unknown"
            return 1
        fi
    fi
    
    local check_output
    check_output=$(/usr/lib/update-notifier/apt-check 2>&1)
    local check_exit_code=$?

    if [ $check_exit_code -ne 0 ]; then
        print_warning "apt-check returned error code $check_exit_code"
        print_status "Proceeding with upgrade operation anyway..."
        emit_summary_event "apt_updates" "package_manager" "apt" "status" "unknown" "total_updates" "unknown" "security_updates" "unknown"
        return 0
    fi

    local total_updates
    total_updates=$(echo "$check_output" | cut -d';' -f1)
    local security_updates
    security_updates=$(echo "$check_output" | cut -d';' -f2)

    if ! [[ "$total_updates" =~ ^[0-9]+$ ]] || ! [[ "$security_updates" =~ ^[0-9]+$ ]]; then
        print_warning "Unable to parse apt-check output: '$check_output'"
        print_status "Proceeding with upgrade operation anyway..."
        emit_summary_event "apt_updates" "package_manager" "apt" "status" "unknown" "total_updates" "unknown" "security_updates" "unknown"
        return 0
    fi
    
    if [ "$total_updates" -eq 0 ]; then
        print_success "✅ No package updates available - system is up to date"
        emit_summary_event "apt_updates" "package_manager" "apt" "status" "up_to_date" "total_updates" "$total_updates" "security_updates" "$security_updates"
        return 1
    else
        print_status "📊 Update summary:"
        print_status "  📦 Total updates available: $total_updates"
        if [ "$security_updates" -gt 0 ]; then
            print_status "  🔒 Security updates available: $security_updates"
            print_warning "Security updates should be installed promptly"
        else
            print_status "  🔒 Security updates available: 0"
        fi
        print_status "Proceeding with package upgrade operation..."
        emit_summary_event "apt_updates" "package_manager" "apt" "status" "update_available" "total_updates" "$total_updates" "security_updates" "$security_updates"
        return 0
    fi
}

upgrade_packages() {
    if apt_skip_if_check_only "APT package upgrades"; then
        return 0
    fi

    if ! check_updates_available; then
        print_success "🎯 Skipping upgrade operation - no updates available"
        ask_continue
        return 0
    fi
    
    print_operation_header "🔄 Upgrading installed packages to latest versions..."
    
    local upgrade_output
    upgrade_output=$(run_with_sudo apt upgrade -y -o Acquire::Retries=3 2>&1)
    local upgrade_exit_code=$?
    
    apt_emit_command_output "$upgrade_output" "upgrade" true
    
    if [ $upgrade_exit_code -eq 0 ]; then
        if echo "$upgrade_output" | grep -q "kept back"; then
            local kept_back_packages
            kept_back_packages=$(apt_extract_kept_back_packages "$upgrade_output")
            local kept_back_count
            kept_back_count=$(echo "$kept_back_packages" | wc -w)
            
            print_warning "$kept_back_count packages were kept back: $kept_back_packages"
            print_status "📝 Kept back packages usually need 'dist-upgrade' or have dependency conflicts"
            print_status "💡 This happens when upgrading would require installing/removing dependencies"
            
            if [ "$QUIET_MODE" = false ]; then
                echo
                print_status "💡 Kept back packages can often be resolved with targeted installation"
                if prompt_yes_no "Do you want to try upgrading kept back packages with individual install?" "Y"; then
                    print_operation_header "🔧 Attempting to upgrade kept back packages individually..."
                    print_status "🔧 Using 'apt-get install' instead of 'upgrade' to resolve dependencies"
                    
                    local dist_upgrade_output
                    dist_upgrade_output=$(apt_install_named_packages "$kept_back_packages" 2>&1)
                    local dist_upgrade_exit_code=$?
                    apt_emit_command_output "$dist_upgrade_output" "dist-upgrade"

                    if [ $dist_upgrade_exit_code -eq 0 ]; then
                        print_success "Successfully upgraded kept back packages"
                        print_success "All packages are now up to date"
                    else
                        print_warning "Some kept back packages could not be upgraded"
                        print_status "This indicates complex dependency conflicts that require manual resolution"
                        print_status ""
                        print_status "Common reasons for upgrade failures:"
                        print_status "  - Complex dependency conflicts between packages"
                        print_status "  - Packages requiring manual configuration changes"
                        print_status "  - Packages pinned by system policy or held back intentionally"
                        print_status "  - Repository inconsistencies or missing dependencies"
                        print_status ""
                        print_status "Manual resolution options:"
                        print_status "Consider running 'apt-get install <package>' manually for each package"
                        print_status "Or try 'apt-get dist-upgrade' to allow dependency changes"
                        
                        print_status ""
                        print_status "Analyzing individual kept back packages:"
                        local -a kept_back_package_array=()
                        local package
                        read -r -a kept_back_package_array <<< "$kept_back_packages"
                        for package in "${kept_back_package_array[@]}"; do
                            print_status "Checking $package..."
                            apt_print_kept_back_package_summary "$package" " (upgrade available)"
                        done
                    fi
                else
                    print_status "Skipping manual upgrade of kept back packages"
                    print_status "You can manually upgrade them later with: apt install <package-name>"
                fi
            else
                print_status "In quiet mode - skipping interactive upgrade of kept back packages"
                print_status "Automated systems should handle kept back packages in post-processing"
                print_status "Manual intervention options:"
                print_status "  - Run 'apt-get dist-upgrade' to allow dependency changes"
                print_status "  - Install packages individually: apt install <package-name>"
                
                print_status ""
                print_status "Kept back package analysis (quiet mode):"
                local -a kept_back_package_array=()
                local package
                read -r -a kept_back_package_array <<< "$kept_back_packages"
                for package in "${kept_back_package_array[@]}"; do
                    apt_print_kept_back_package_summary "$package"
                done
            fi
        fi
        
        if echo "$upgrade_output" | grep -q "0 upgraded, 0 newly installed"; then
            if echo "$upgrade_output" | grep -q "kept back"; then
                print_warning "🔄 No packages were upgraded (some packages were kept back)"
                print_status "⚠️  System is partially up to date - manual intervention needed for kept back packages"
            else
                print_success "🎯 All packages are already up to date"
                print_success "🛡️  System is current with latest available package versions"
            fi
        else
            local upgraded_count
            upgraded_count=$(echo "$upgrade_output" | grep -o '[0-9]\+ upgraded' | grep -o '[0-9]\+' | head -1)
            local installed_count
            installed_count=$(echo "$upgrade_output" | grep -o '[0-9]\+ newly installed' | grep -o '[0-9]\+' | head -1)
            
            if [ -n "$upgraded_count" ] && [ "$upgraded_count" -gt 0 ]; then
                print_success "Successfully upgraded $upgraded_count packages to newer versions"
            fi
            if [ -n "$installed_count" ] && [ "$installed_count" -gt 0 ]; then
                print_success "Successfully installed $installed_count new dependency packages"
            fi
            
            print_success "Package upgrade operation completed successfully"
        fi
    else
        print_warning "apt upgrade failed (exit code $upgrade_exit_code) - retrying with --fix-missing and Acquire::Retries=3 to handle transient network errors..."
        echo
        local fix_missing_output
        fix_missing_output=$(run_with_sudo apt upgrade -y --fix-missing -o Acquire::Retries=3 2>&1)
        local fix_missing_exit_code=$?
        apt_emit_command_output "$fix_missing_output" "upgrade"
        if [ $fix_missing_exit_code -eq 0 ]; then
            print_success "Package upgrade completed with --fix-missing (some packages may have been skipped due to fetch errors)"
        else
            print_warning "Retry with --fix-missing also failed (exit code $fix_missing_exit_code) - attempting one more retry after a short delay..."
            sleep 5
            local final_retry_output
            final_retry_output=$(run_with_sudo apt upgrade -y --fix-missing -o Acquire::Retries=3 2>&1)
            local final_retry_exit_code=$?
            apt_emit_command_output "$final_retry_output" "upgrade"
            if [ $final_retry_exit_code -eq 0 ]; then
                print_success "Package upgrade completed on final retry with --fix-missing"
            else
                print_error "Failed to upgrade packages - apt-get upgrade returned error code $upgrade_exit_code"
                print_error ""
                print_error "Common causes and solutions:"
                print_error "  - Network connectivity issues:"
                print_error "    * Check internet connection and DNS resolution"
                print_error "    * Verify repository URLs are accessible"
                print_error "  - Repository problems:"
                print_error "    * Run 'apt-get update' to refresh repository information"
                print_error "    * Check /etc/apt/sources.list for invalid entries"
                print_error "  - Dependency conflicts:"
                print_error "    * Try 'apt-get -f install' to fix broken dependencies"
                print_error "    * Consider 'apt-get dist-upgrade' for complex dependency changes"
                print_error "  - Insufficient disk space:"
                print_error "    * Check available space with 'df -h'"
                print_error "    * Clean package cache with 'apt-get clean'"
                print_error "  - Permission issues:"
                print_error "    * Ensure script is running with sufficient privileges"
                print_error ""
                print_error "Review the detailed output above for specific error messages"
                print_error "Manual intervention may be required to resolve the issue"
                return 1
            fi
        fi
    fi
    
    ask_continue
}

full_upgrade() {
    if apt_skip_if_check_only "APT dist-upgrade"; then
        return 0
    fi

    if ! check_updates_available; then
        print_success "🎯 Skipping dist-upgrade operation - no updates available"
        ask_continue
        return 0
    fi

    print_operation_header "⚡ Performing comprehensive system upgrade (dist-upgrade)..."
    print_status "WARNING: This operation may install new packages or remove existing ones"
    print_status "This is more aggressive than regular upgrade and can change system behavior"
    print_status ""
    print_operation_header "🚀 Starting dist-upgrade operation..."
    
    local dist_upgrade_output
    dist_upgrade_output=$(run_with_sudo apt-get dist-upgrade -y 2>&1)
    local exit_code=$?
    
    apt_emit_command_output "$dist_upgrade_output" "dist-upgrade" true
    
    if [ $exit_code -eq 0 ]; then
        print_success "Full system upgrade completed successfully"
        print_success "System has been upgraded with all available dependency changes"
        print_status "Some services may require restart to use new versions"
    else
        print_error "Failed to perform full system upgrade"
        print_error "This could indicate serious system issues or conflicts"
        print_error "Manual intervention may be required"
        print_error "Consider running 'apt-get -f install' to fix broken dependencies"
        return 1
    fi
    
    ask_continue
}

cleanup() {
    print_operation_header "🧹 Performing comprehensive system cleanup..."
    print_status "🗑️  This will remove unnecessary packages and clean cached files"

    if apt_skip_if_check_only "APT cleanup"; then
        return 0
    fi
    
    print_operation_header "📦 Removing orphaned packages (autoremove)..."
    print_status "🔍 Identifying packages that were automatically installed but are no longer needed"
    
    local autoremove_output
    autoremove_output=$(run_with_sudo apt-get autoremove -y 2>&1)
    local autoremove_exit_code=$?
    
    apt_emit_command_output "$autoremove_output" "autoremove"
    
    if [ $autoremove_exit_code -eq 0 ]; then
        print_success "🗂️  Successfully removed orphaned packages"
    else
        print_warning "⚠️  Some orphaned packages could not be removed"
    fi
    
    print_operation_header "💾 Cleaning outdated package cache files (autoclean)..."
    print_status "🗄️  Removing cached packages that are no longer available in repositories"
    
    local autoclean_output
    autoclean_output=$(run_with_sudo apt-get autoclean 2>&1)
    local autoclean_exit_code=$?
    
    apt_emit_command_output "$autoclean_output" "autoclean"
    
    if [ $autoclean_exit_code -eq 0 ]; then
        print_success "🧽 Successfully cleaned outdated package cache"
    else
        print_warning "⚠️  Package cache cleaning encountered issues"
    fi
    
    print_success "🎉 System cleanup completed successfully"
    print_status "💽 Disk space has been reclaimed and system maintenance performed"
    
    ask_continue
}

check_broken_packages() {
    print_operation_header "🔍 Performing comprehensive package integrity check..."
    
    local audit_output
    audit_output=$(dpkg --audit 2>/dev/null)
    
    if echo "$audit_output" | grep -q .; then
        print_warning "Found broken or partially configured packages"
        if [ "$CHECK_ONLY_MODE" = true ]; then
            print_status "Check-only mode - package integrity issues detected, automatic repair skipped"
            emit_summary_event "package_integrity" "package_manager" "dpkg" "status" "issues_detected"
            ask_continue
            return 0
        fi
        print_status "Package integrity issues detected - attempting automatic repair"
        
        print_operation_header "🔧 Step 1: Attempting to fix broken dependencies..."
        if run_with_sudo apt-get install -f -y >/dev/null 2>&1; then
            print_success "Successfully fixed broken dependencies"
        else
            print_warning "Some dependency issues could not be automatically resolved"
        fi
        
        print_operation_header "⚙️ Step 2: Configuring partially installed packages..."
        if run_with_sudo dpkg --configure -a >/dev/null 2>&1; then
            print_success "Successfully configured all pending packages"
        else
            print_warning "Some packages could not be properly configured"
            print_status "Manual intervention may be required for complex configuration issues"
        fi
        
        local post_repair_audit
        post_repair_audit=$(dpkg --audit 2>/dev/null)
        if echo "$post_repair_audit" | grep -q .; then
            print_warning "Some package issues remain after automatic repair"
            print_status "Consider manual package management for remaining issues"
        else
            print_success "All package integrity issues have been resolved"
        fi
    else
        print_success "No broken packages found - system package integrity is good"
        emit_summary_event "package_integrity" "package_manager" "dpkg" "status" "healthy"
    fi
    
    ask_continue
}
