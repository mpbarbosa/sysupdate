#!/bin/bash
#
# update_hexchat.sh - HexChat Update Manager
# SNIPPET_ID: hexchat
# SNIPPET_NAME: HexChat IRC Client
#
# Handles version checking and updates for HexChat IRC client.
# Reference: https://github.com/hexchat/hexchat
#
# Version: 0.1.0-alpha
# Date: 2025-12-13
# Author: mpb
# Repository: https://github.com/mpbarbosa/sysupdate
# Status: Non-production (Alpha)
#
# Version History:
#   0.1.0-alpha (2025-12-13) - Initial version
#                            - Uses Method 3: Custom Update Logic
#                            - Supports GitHub releases
#                            - Meson/Ninja build system
#                            - Python 3 plugin support
#
# Dependencies:
#   - meson (build system)
#   - ninja (build tool)
#   - Python 3 development files (python3-dev)
#   - GTK 3 development files (libgtk-3-dev)
#   - GLib development files (libglib2.0-dev)
#   - OpenSSL development files (libssl-dev)
#   - PCI utilities development files (libpci-dev)
#   - D-Bus development files (libdbus-1-dev)
#

# Load upgrade utilities library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/hexchat.yaml"

# Build HexChat from source
build_hexchat_from_source() {
  local version=$1
  local build_dir
  
  local building_msg
  building_msg=$(get_config "messages.build.building")
  building_msg="${building_msg/\{version\}/$version}"
  print_status "$building_msg"
  
  # Check for required build dependencies
  if ! check_build_dependencies wget tar meson ninja; then
    local install_deps
    install_deps=$(get_config "messages.build.install_deps")
    print_status "$install_deps"
    return 1
  fi
  
  # Check for compiler
  if ! command -v gcc &>/dev/null && ! command -v clang &>/dev/null; then
    local missing_compiler
    missing_compiler=$(get_config "messages.build.missing_compiler")
    print_error "$missing_compiler"
    local install_compiler
    install_compiler=$(get_config "messages.build.install_compiler")
    print_status "$install_compiler"
    return 1
  fi
  
  # Check for Python 3 development files
  if ! command -v python3-config &>/dev/null && ! [ -f /usr/include/python3.*/Python.h ]; then
    local missing_python
    missing_python=$(get_config "messages.build.missing_python")
    print_warning "$missing_python"
    local install_python
    install_python=$(get_config "messages.build.install_python")
    print_status "$install_python"
  fi
  
  # Check for required development libraries
  local missing_libs=()
  
  # Check for GTK 3
  if ! pkg-config --exists gtk+-3.0; then
    missing_libs+=("libgtk-3-dev")
  fi
  
  # Check for GLib 2.0
  if ! pkg-config --exists glib-2.0; then
    missing_libs+=("libglib2.0-dev")
  fi
  
  # Check for OpenSSL
  if ! pkg-config --exists openssl; then
    missing_libs+=("libssl-dev")
  fi
  
  # Check for D-Bus
  if ! pkg-config --exists dbus-1; then
    missing_libs+=("libdbus-1-dev")
  fi
  
  if [ ${#missing_libs[@]} -gt 0 ]; then
    print_warning "Missing required development libraries: ${missing_libs[*]}"
    
    if prompt_yes_no "Install missing dependencies now?"; then
      print_status "Installing dependencies..."
      
      # Detect package manager and install
      if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y "${missing_libs[@]}" python3-dev
      elif command -v yum &>/dev/null; then
        # Convert debian package names to RPM equivalents
        local rpm_libs=()
        for lib in "${missing_libs[@]}"; do
          case "$lib" in
            libgtk-3-dev) rpm_libs+=("gtk3-devel") ;;
            libglib2.0-dev) rpm_libs+=("glib2-devel") ;;
            libssl-dev) rpm_libs+=("openssl-devel") ;;
            libdbus-1-dev) rpm_libs+=("dbus-devel") ;;
            *) rpm_libs+=("$lib") ;;
          esac
        done
        rpm_libs+=("python3-devel")
        sudo yum install -y "${rpm_libs[@]}"
      elif command -v dnf &>/dev/null; then
        local rpm_libs=()
        for lib in "${missing_libs[@]}"; do
          case "$lib" in
            libgtk-3-dev) rpm_libs+=("gtk3-devel") ;;
            libglib2.0-dev) rpm_libs+=("glib2-devel") ;;
            libssl-dev) rpm_libs+=("openssl-devel") ;;
            libdbus-1-dev) rpm_libs+=("dbus-devel") ;;
            *) rpm_libs+=("$lib") ;;
          esac
        done
        rpm_libs+=("python3-devel")
        sudo dnf install -y "${rpm_libs[@]}"
      else
        print_error "No supported package manager found (apt, yum, dnf)"
        local install_deps
        install_deps=$(get_config "messages.build.install_deps")
        print_status "$install_deps"
        return 1
      fi
      
      print_success "Dependencies installed successfully"
    else
      local install_deps
      install_deps=$(get_config "messages.build.install_deps")
      print_status "$install_deps"
      return 1
    fi
  fi
  
  # Create build directory
  build_dir=$(create_build_directory "hexchat")
  local original_dir
  original_dir=$(pwd)
  cd "$build_dir" || return 1
  
  # Download tarball
  local downloading_msg
  downloading_msg=$(get_config "messages.build.downloading")
  downloading_msg="${downloading_msg/\{version\}/$version}"
  print_status "$downloading_msg"
  
  local tarball="hexchat-${version}.tar.xz"
  local download_url="https://github.com/hexchat/hexchat/releases/download/v${version}/${tarball}"
  
  if ! wget --no-verbose "$download_url"; then
    local download_failed
    download_failed=$(get_config "messages.build.download_failed")
    print_error "$download_failed"
    cleanup_build_directory "$build_dir" "$original_dir"
    return 1
  fi
  
  # Extract tarball
  local extracting_msg
  extracting_msg=$(get_config "messages.build.extracting")
  print_status "$extracting_msg"
  
  if ! tar -xf "$tarball"; then
    local extract_failed
    extract_failed=$(get_config "messages.build.extract_failed")
    print_error "$extract_failed"
    cleanup_build_directory "$build_dir" "$original_dir"
    return 1
  fi
  
  cd "hexchat-${version}" || {
    print_error "Failed to enter hexchat-${version} directory"
    cleanup_build_directory "$build_dir" "$original_dir"
    return 1
  }
  
  # Setup build with meson
  local meson_msg
  meson_msg=$(get_config "messages.build.running_meson")
  print_status "$meson_msg"
  
  local meson_opts
  meson_opts=$(get_config "build_instructions.meson_options.default")
  
  if ! meson setup build $meson_opts; then
    local meson_failed
    meson_failed=$(get_config "messages.build.meson_failed")
    print_error "$meson_failed"
    cleanup_build_directory "$build_dir" "$original_dir"
    return 1
  fi
  
  # Build with ninja
  local ninja_msg
  ninja_msg=$(get_config "messages.build.building_ninja")
  print_status "$ninja_msg"
  
  if ! ninja -C build; then
    local ninja_failed
    ninja_failed=$(get_config "messages.build.ninja_failed")
    print_error "$ninja_failed"
    cleanup_build_directory "$build_dir" "$original_dir"
    return 1
  fi
  
  # Install
  local installing_msg
  installing_msg=$(get_config "messages.build.installing")
  print_status "$installing_msg"
  
  if ! sudo ninja -C build install; then
    local install_failed
    install_failed=$(get_config "messages.build.install_failed")
    print_error "$install_failed"
    cleanup_build_directory "$build_dir" "$original_dir"
    return 1
  fi
  
  # Verify installation
  local verify_msg
  verify_msg=$(get_config "messages.build.verify_version")
  print_status "$verify_msg"
  
  local new_version
  local version_cmd
  version_cmd=$(get_config "version.command")
  local version_regex
  version_regex=$(get_config "version.regex")
  new_version=$($version_cmd 2>/dev/null | head -1 | sed -E "s/$version_regex/\1/")
  
  if [[ -n "$new_version" ]]; then
    print_success "HexChat version installed: $new_version"
  fi
  
  # Cleanup
  cleanup_build_directory "$build_dir" "$original_dir"
  
  local success_msg
  success_msg=$(get_config "messages.build.build_success")
  print_success "$success_msg"
  show_installation_info "hexchat" "HexChat"
  
  return 0
}

# Perform HexChat update with method selection
perform_hexchat_update() {
  local latest_version="$1"
  
  # Read prompts from config
  local prompt_msg
  local prompt_opts
  local prompt_default
  prompt_msg=$(get_config "prompts.update_method.message")
  prompt_opts=$(get_config "prompts.update_method.options")
  prompt_default=$(get_config "prompts.update_method.default")
  
  # Ask for update method
  local method
  method=$(prompt_choice "$prompt_msg" "$prompt_opts" "$prompt_default")
  
  if [[ "$method" =~ ^[Ss]$ ]]; then
    build_hexchat_from_source "$latest_version"
  else
    # Try package manager update
    local current_before_update="$CURRENT_VERSION"
    if update_via_package_manager "hexchat-python3"; then
      # Check if version actually changed
      local current_after_update
      local version_cmd
      version_cmd=$(get_config "version.command")
      local version_regex
      version_regex=$(get_config "version.regex")
      current_after_update=$($version_cmd 2>/dev/null | head -1 | sed -E "s/$version_regex/\1/")
      
      if [ "$current_after_update" != "$current_before_update" ]; then
        print_success "HexChat updated via package manager: $current_before_update → $current_after_update"
        show_installation_info "hexchat" "HexChat"
      else
        # Package manager didn't upgrade to latest version
        print_warning "Package manager has HexChat but not the latest version ($latest_version)"
        local build_prompt
        build_prompt=$(get_config "prompts.build_from_source.message")
        if prompt_yes_no "$build_prompt"; then
          build_hexchat_from_source "$latest_version"
        else
          # Display build instructions from config
          print_status "📋 Build from source instructions:"
          
          # Get dependencies list
          local deps
          deps=$(yq -r '.build_instructions.dependencies[]' "$CONFIG_FILE" | tr '\n' ' ')
          print_status "1️⃣ Install dependencies: $deps"
          
          # Optional dependencies
          local optional_deps
          optional_deps=$(yq -r '.build_instructions.optional_dependencies[]' "$CONFIG_FILE" | tr '\n' ' ')
          print_status "   Optional dependencies: $optional_deps"
          
          # Get build steps
          local download_cmd
          download_cmd=$(get_config "build_instructions.steps[0].command")
          download_cmd="${download_cmd/\{version\}/$latest_version}"
          print_status "2️⃣ Download: $download_cmd"
          
          local extract_cmd
          extract_cmd=$(get_config "build_instructions.steps[1].command")
          extract_cmd="${extract_cmd/\{version\}/$latest_version}"
          print_status "3️⃣ Extract: $extract_cmd"
          
          local setup_cmd
          setup_cmd=$(get_config "build_instructions.steps[2].command")
          setup_cmd="${setup_cmd/\{version\}/$latest_version}"
          print_status "4️⃣ Setup: $setup_cmd"
          
          local build_cmd
          build_cmd=$(get_config "build_instructions.steps[3].command")
          print_status "5️⃣ Build: $build_cmd"
          
          local install_cmd
          install_cmd=$(get_config "build_instructions.steps[4].command")
          print_status "6️⃣ Install: $install_cmd"
          
          local ref_url
          ref_url=$(get_config "build_instructions.reference.url")
          local doc_url
          doc_url=$(get_config "build_instructions.reference.documentation")
          local build_url
          build_url=$(get_config "build_instructions.reference.build_guide")
          print_status "📖 Reference: $ref_url"
          print_status "📚 Documentation: $doc_url"
          print_status "🔨 Build Guide: $build_url"
        fi
      fi
    else
      # No package manager found, offer source build
      local build_prompt
      build_prompt=$(get_config "prompts.build_from_source.message")
      if prompt_yes_no "$build_prompt"; then
        build_hexchat_from_source "$latest_version"
      else
        # Display build instructions from config
        print_status "📋 Build from source instructions:"
        
        # Get dependencies list
        local deps
        deps=$(yq -r '.build_instructions.dependencies[]' "$CONFIG_FILE" | tr '\n' ' ')
        print_status "1️⃣ Install dependencies: $deps"
        
        # Optional dependencies
        local optional_deps
        optional_deps=$(yq -r '.build_instructions.optional_dependencies[]' "$CONFIG_FILE" | tr '\n' ' ')
        print_status "   Optional dependencies: $optional_deps"
        
        # Get build steps
        local download_cmd
        download_cmd=$(get_config "build_instructions.steps[0].command")
        download_cmd="${download_cmd/\{version\}/$latest_version}"
        print_status "2️⃣ Download: $download_cmd"
        
        local extract_cmd
        extract_cmd=$(get_config "build_instructions.steps[1].command")
        extract_cmd="${extract_cmd/\{version\}/$latest_version}"
        print_status "3️⃣ Extract: $extract_cmd"
        
        local setup_cmd
        setup_cmd=$(get_config "build_instructions.steps[2].command")
        setup_cmd="${setup_cmd/\{version\}/$latest_version}"
        print_status "4️⃣ Setup: $setup_cmd"
        
        local build_cmd
        build_cmd=$(get_config "build_instructions.steps[3].command")
        print_status "5️⃣ Build: $build_cmd"
        
        local install_cmd
        install_cmd=$(get_config "build_instructions.steps[4].command")
        print_status "6️⃣ Install: $install_cmd"
        
        local ref_url
        ref_url=$(get_config "build_instructions.reference.url")
        local doc_url
        doc_url=$(get_config "build_instructions.reference.documentation")
        local build_url
        build_url=$(get_config "build_instructions.reference.build_guide")
        print_status "📖 Reference: $ref_url"
        print_status "📚 Documentation: $doc_url"
        print_status "🔨 Build Guide: $build_url"
      fi
    fi
  fi
}

# Update HexChat IRC client
# Uses Method 3: Custom Update Logic (see upgrade_script_pattern_documentation.md)
update_hexchat() {
  # Perform config-driven version check
  if ! config_driven_version_check; then
    ask_continue
    return 0
  fi
  
  # Handle update workflow with custom perform_hexchat_update logic
  if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
    "perform_hexchat_update '$LATEST_VERSION'"; then
    ask_continue
    return 1
  fi
}

update_hexchat
