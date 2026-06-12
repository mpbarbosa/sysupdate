#!/bin/bash
#
# update_nodejs.sh - Node.js Update Manager
# SNIPPET_ID: nodejs
# SNIPPET_NAME: Node.js Runtime
#
# Handles version checking and updates for Node.js runtime from source code.
# Reference: https://github.com/nodejs/node
#
# Version: 1.0.0-alpha
# Date: 2025-11-26
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   1.0.0-alpha (2025-11-26) - Initial version following upgrade script pattern v1.1.0
#                            - Supports source build and binary installation
#                            - Version manager (nvm, n) detection
#                            - Custom update logic with multiple methods
#
# Dependencies:
#   - git (for source builds)
#   - python3 (required by Node.js build system)
#   - C++ compiler (g++ or clang++)
#   - make, pkg-config
#
# Usage:
#   ./update_nodejs.sh
#   Offers multiple update methods:
#   - Version managers (nvm, n, fnm)
#   - Official binaries
#   - Build from source

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/nodejs.yaml"

# Detect installed version managers
detect_version_manager() {
    if command -v nvm &> /dev/null || [ -f "$HOME/.nvm/nvm.sh" ]; then
        echo "nvm"
    elif command -v n &> /dev/null; then
        echo "n"
    elif command -v fnm &> /dev/null; then
        echo "fnm"
    else
        echo "none"
    fi
}

# Update Node.js via nvm
update_via_nvm() {
    local version="$1"
    print_status "Updating Node.js via nvm..."
    
    # Source nvm if available
    if [ -f "$HOME/.nvm/nvm.sh" ]; then
        source "$HOME/.nvm/nvm.sh"
    fi
    
    if ! command -v nvm &> /dev/null; then
        print_error "nvm not found in PATH"
        return 1
    fi
    
    print_status "Installing Node.js $version with nvm..."
    if nvm install "$version"; then
        nvm use "$version"
        nvm alias default "$version"
        print_success "Node.js $version installed and set as default"
        print_warning "Open a new terminal or run: source ~/.nvm/nvm.sh && nvm use $version"
        return 0
    else
        print_error "Failed to install Node.js via nvm"
        return 1
    fi
}

# Update Node.js via n version manager
update_via_n() {
    local version="$1"
    print_status "Updating Node.js via n..."
    
    if ! command -v n &> /dev/null; then
        print_error "n version manager not found"
        return 1
    fi
    
    print_status "Installing Node.js $version with n..."
    if sudo n "$version"; then
        print_success "Node.js $version installed"
        return 0
    else
        print_error "Failed to install Node.js via n"
        return 1
    fi
}

# Update Node.js via fnm
update_via_fnm() {
    local version="$1"
    print_status "Updating Node.js via fnm..."
    
    if ! command -v fnm &> /dev/null; then
        print_error "fnm not found"
        return 1
    fi
    
    print_status "Installing Node.js $version with fnm..."
    if fnm install "$version" && fnm default "$version"; then
        print_success "Node.js $version installed and set as default"
        return 0
    else
        print_error "Failed to install Node.js via fnm"
        return 1
    fi
}

# Install Node.js from official binaries
install_nodejs_binary() {
    local version="$1"
    local arch
    arch=$(uname -m)
    local os="linux"
    
    # Map architecture names
    case "$arch" in
        x86_64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l) arch="armv7l" ;;
        *) print_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    local download_url="https://nodejs.org/dist/v${version}/node-v${version}-${os}-${arch}.tar.xz"
    local install_dir="/usr/local"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    print_status "Downloading Node.js v${version} binary..."
    if ! curl -fsSL "$download_url" -o "$temp_dir/node.tar.xz"; then
        print_error "Failed to download Node.js binary"
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_status "Extracting Node.js binary..."
    if ! tar -xJf "$temp_dir/node.tar.xz" -C "$temp_dir"; then
        print_error "Failed to extract Node.js binary"
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_status "Installing Node.js to $install_dir..."
    local node_dir="$temp_dir/node-v${version}-${os}-${arch}"
    if sudo cp -rf "$node_dir"/{bin,include,lib,share} "$install_dir/"; then
        print_success "Node.js v${version} installed successfully"
        rm -rf "$temp_dir"
        return 0
    else
        print_error "Failed to install Node.js binary"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Build Node.js from source
build_nodejs_from_source() {
    local version=$1
    local build_dir
    
    print_operation_header "Building Node.js v${version} from source"
    
    # Check for required build dependencies
    if ! check_build_dependencies git make python3 g++; then
        print_error "Missing required build dependencies"
        print_status "Install: sudo apt install git make python3 g++ pkg-config"
        return 1
    fi
    
    # Create build directory
    build_dir=$(create_build_directory "nodejs")
    local original_dir
    original_dir=$(pwd)
    cd "$build_dir" || return 1
    
    # Clone repository
    print_step "1" "Cloning Node.js repository"
    if ! git clone --depth 1 --branch "v${version}" https://github.com/nodejs/node.git; then
        print_error "Failed to clone Node.js repository"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    print_success "Repository cloned"
    
    cd node || return 1
    
    # Configure
    print_step "2" "Configuring build"
    if ! ./configure; then
        print_error "Configuration failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    print_success "Configuration complete"
    
    # Build (this takes a long time)
    print_step "3" "Building Node.js (this may take 20-60 minutes)"
    print_warning "Building Node.js from source is very time-consuming. Consider using binaries instead."
    
    local cores
    cores=$(nproc 2>/dev/null || echo 2)
    print_status "Building with $cores parallel jobs..."
    
    if ! make -j"$cores"; then
        print_error "Build failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    print_success "Build complete"
    
    # Install
    print_step "4" "Installing Node.js"
    if ! sudo make install; then
        print_error "Installation failed"
        cleanup_build_directory "$build_dir" "$original_dir"
        return 1
    fi
    
    # Cleanup
    cleanup_build_directory "$build_dir" "$original_dir"
    
    print_success "Node.js v${version} built and installed successfully"
    show_installation_info "node" "Node.js"
    
    return 0
}

# Perform Node.js update with method selection
perform_nodejs_update() {
    local latest_version="$1"
    
    # Detect version manager
    local vm
    vm=$(detect_version_manager)
    
    # Build update options based on what's available
    local options=""
    local method_descriptions=""
    
    if [ "$vm" != "none" ]; then
        options="${options}v"
        method_descriptions="${method_descriptions}\n  v) Update via $vm version manager"
    fi
    
    options="${options}bsp"
    method_descriptions="${method_descriptions}\n  b) Install official binary (recommended, fast)"
    method_descriptions="${method_descriptions}\n  s) Build from source (slow, 20-60 minutes)"
    method_descriptions="${method_descriptions}\n  p) Update via package manager"
    
    # Display options
    echo -e "\nAvailable update methods:${method_descriptions}"
    
    local prompt_msg
    if [ "$vm" != "none" ]; then
        prompt_msg="Choose update method (v/b/s/p) [default: v]: "
        local default="v"
    else
        prompt_msg="Choose update method (b/s/p) [default: b]: "
        local default="b"
    fi
    
    local method
    method="$(prompt_input "${prompt_msg%: }" "$default" "v|b|s|p")"
    method=${method:-$default}
    
    case "$method" in
        v|V)
            if [ "$vm" = "nvm" ]; then
                update_via_nvm "$latest_version"
            elif [ "$vm" = "n" ]; then
                update_via_n "$latest_version"
            elif [ "$vm" = "fnm" ]; then
                update_via_fnm "$latest_version"
            else
                print_error "No version manager detected"
                return 1
            fi
            ;;
        b|B)
            install_nodejs_binary "$latest_version"
            ;;
        s|S)
            build_nodejs_from_source "$latest_version"
            ;;
        p|P)
            if update_via_package_manager "nodejs" "node"; then
                print_success "Node.js updated via package manager"
                show_installation_info "node" "Node.js"
            else
                print_error "Package manager update failed"
                return 1
            fi
            ;;
        *)
            print_error "Invalid option: $method"
            return 1
            ;;
    esac
}

# Update Node.js runtime
# Uses Method 3: Custom Update Logic
update_nodejs() {
    # Perform config-driven version check
    if ! config_driven_version_check; then
        ask_continue
        return 0
    fi
    
    # Show detected version manager
    local vm
    vm=$(detect_version_manager)
    if [ "$vm" != "none" ]; then
        print_status "Detected version manager: $vm"
    fi
    
    # Handle update workflow
    local app_name
    app_name=$(get_config "application.name")
    
    if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
        "perform_nodejs_update '$LATEST_VERSION'"; then
        ask_continue
        return 1
    fi
    
    return 0
}

update_nodejs
