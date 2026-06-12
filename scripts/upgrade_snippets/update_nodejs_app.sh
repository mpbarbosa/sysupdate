#!/bin/bash
#
# update_nodejs_app.sh - Node.js Application Update Manager
# SNIPPET_ID: nodejs-app
# SNIPPET_NAME: Node.js Application
#
# Updates a Node.js application from source code with version checking.
# Handles npm dependencies, build steps, and service restart.
#
# Version: 1.0.0-alpha
# Date: 2025-11-26
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   1.0.0-alpha (2025-11-26) - Initial version following upgrade script pattern v1.1.0
#                            - Config-driven approach for Node.js apps
#                            - Supports git pull, npm install, build, and restart
#
# Dependencies:
#   - git (for pulling updates)
#   - npm (Node Package Manager)
#   - Node.js (required by npm)
#
# Usage:
#   ./update_nodejs_app.sh
#   or edit nodejs_app.yaml to configure your specific app

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/nodejs_app.yaml"

# Update Node.js application from source
update_nodejs_app() {
    # Check git dependency first
    local git_dep_name
    git_dep_name=$(get_config "dependencies[0].name")
    local git_dep_cmd
    git_dep_cmd=$(get_config "dependencies[0].command")
    local git_dep_help
    git_dep_help=$(get_config "dependencies[0].help")
    
    if ! check_app_installed_or_help "$git_dep_name" "$git_dep_cmd" "$git_dep_help"; then
        ask_continue
        return 0
    fi
    
    # Check npm dependency
    local npm_dep_name
    npm_dep_name=$(get_config "dependencies[1].name")
    local npm_dep_cmd
    npm_dep_cmd=$(get_config "dependencies[1].command")
    local npm_dep_help
    npm_dep_help=$(get_config "dependencies[1].help")
    
    if ! check_app_installed_or_help "$npm_dep_name" "$npm_dep_cmd" "$npm_dep_help"; then
        ask_continue
        return 0
    fi
    
    # Check if app directory exists
    local app_dir
    app_dir=$(get_config "application.directory")
    
    if [ ! -d "$app_dir" ]; then
        print_error "Application directory not found: $app_dir"
        local install_help
        install_help=$(get_config "messages.install_help")
        echo "$install_help"
        ask_continue
        return 1
    fi
    
    # Perform config-driven version check
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi
    
    # Handle update workflow
    local app_name
    app_name=$(get_config "application.name")
    local display_name
    display_name=$(get_config "application.display_name")
    
    # Only proceed if update is available (VERSION_STATUS == 2)
    if [ "$VERSION_STATUS" -eq 2 ]; then
        if ! perform_nodejs_app_update "$app_dir" "$app_name" "$display_name"; then
            ask_continue
            return 1
        fi
    fi
    
    ask_continue
    return 0
}

# Perform Node.js application update from source
# Args: $1 = app_dir, $2 = app_name, $3 = display_name
perform_nodejs_app_update() {
    local app_dir="$1"
    local app_name="$2"
    local display_name="$3"
    
    # Confirm update
    local update_prompt
    update_prompt=$(get_config "prompts.confirm_update.message")
    if ! prompt_yes_no "$update_prompt"; then
        print_info "Update cancelled by user"
        return 0
    fi
    
    print_operation_header "Updating $display_name from source"
    
    # Step 1: Pull latest changes
    print_step "1" "Pulling latest changes from repository"
    cd "$app_dir" || { print_error "Failed to change directory to $app_dir"; return 1; }
    
    local git_pull_cmd
    git_pull_cmd=$(get_config "update.git_pull_command")
    if ! eval "$git_pull_cmd"; then
        print_error "Failed to pull latest changes"
        return 1
    fi
    print_success "Successfully pulled latest changes"
    
    # Step 2: Install/update dependencies
    print_step "2" "Installing/updating npm dependencies"
    local npm_install_cmd
    npm_install_cmd=$(get_config "update.npm_install_command")
    if ! eval "$npm_install_cmd"; then
        print_error "Failed to install npm dependencies"
        return 1
    fi
    print_success "Successfully installed dependencies"
    
    # Step 3: Build application (if build command is configured)
    local build_cmd
    build_cmd=$(get_config "update.build_command")
    if [ -n "$build_cmd" ] && [ "$build_cmd" != "null" ]; then
        print_step "3" "Building application"
        if ! eval "$build_cmd"; then
            print_error "Failed to build application"
            return 1
        fi
        print_success "Successfully built application"
    fi
    
    # Step 4: Restart service (if configured)
    local restart_cmd
    restart_cmd=$(get_config "update.restart_command")
    if [ -n "$restart_cmd" ] && [ "$restart_cmd" != "null" ]; then
        local restart_prompt
        restart_prompt=$(get_config "prompts.restart_service.message")
        if prompt_yes_no "$restart_prompt"; then
            print_step "4" "Restarting service"
            if ! eval "$restart_cmd"; then
                print_error "Failed to restart service"
                return 1
            fi
            print_success "Successfully restarted service"
        else
            print_warning "Service not restarted. Manual restart may be required."
        fi
    fi
    
    # Display success message
    local success_msg
    success_msg=$(get_config "messages.update_success")
    print_success "$success_msg"
    
    # Show version info
    show_installation_info "$app_name" "$display_name"
    
    return 0
}

# Execute main function
update_nodejs_app
