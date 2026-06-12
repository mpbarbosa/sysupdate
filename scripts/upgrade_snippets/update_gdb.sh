#!/bin/bash
#
# update_gdb.sh - GDB Update Manager
# SNIPPET_ID: gdb
# SNIPPET_NAME: GDB Debugger
#
# Handles version checking and updates for GNU Debugger (GDB).
# Reference: https://www.gnu.org/software/gdb/
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
#                            - Supports GNU FTP downloads
#                            - Comprehensive build from source support
#
# Dependencies:
#   - wget or curl (for downloading source)
#   - tar (for extracting archives)
#   - C/C++ compiler (gcc/g++ or clang)
#   - make, pkg-config
#   - texinfo (for documentation)
#   - Development libraries: libgmp, libmpfr, libexpat, ncurses, readline, python3
#

# Load upgrade utilities library
GDB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$GDB_SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/upgrade_utils.sh"

# Load configuration
CONFIG_FILE="$GDB_SCRIPT_DIR/gdb.yaml"

# Get latest GDB version from GNU FTP
get_latest_gdb_version() {
  local ftp_url
  ftp_url=$(get_config "version.ftp_base_url")
  local version_pattern
  version_pattern=$(get_config "version.version_pattern")
  
  # Try curl first, fallback to wget
  local listing
  if command -v curl &>/dev/null; then
    listing=$(curl -s "$ftp_url")
  elif command -v wget &>/dev/null; then
    listing=$(wget -qO- "$ftp_url")
  else
    print_error "Neither curl nor wget found. Please install one."
    return 1
  fi
  
  # Extract versions and sort to get latest
  local latest
  latest=$(echo "$listing" | grep -oE "$version_pattern" | \
    sed -nE "s/$version_pattern/\1/p" | \
    sort -V | tail -1)
  
  if [[ -n "$latest" ]]; then
    echo "$latest"
    return 0
  else
    return 1
  fi
}

# Build GDB from source
build_gdb_from_source() {
  local version=$1
  local build_dir
  
  local building_msg
  building_msg=$(get_config "messages.build.building")
  building_msg="${building_msg/\{version\}/$version}"
  print_status "$building_msg"
  
  # Check for required build dependencies
  if ! check_build_dependencies wget tar make gcc g++; then
    local install_deps
    install_deps=$(get_config "messages.build.install_deps")
    print_status "$install_deps"
    return 1
  fi
  
  # Check for compiler
  if ! command -v gcc &>/dev/null || ! command -v g++ &>/dev/null; then
    local missing_compiler
    missing_compiler=$(get_config "messages.build.missing_compiler")
    print_error "$missing_compiler"
    local install_compiler
    install_compiler=$(get_config "messages.build.install_compiler")
    print_status "$install_compiler"
    return 1
  fi
  
  # Check for required development libraries
  local missing_libs=()
  
  # Check for GMP headers
  if ! ldconfig -p | grep -q libgmp || ! [ -f /usr/include/gmp.h ]; then
    missing_libs+=("libgmp-dev")
  fi
  
  # Check for MPFR headers
  if ! ldconfig -p | grep -q libmpfr || ! [ -f /usr/include/mpfr.h ]; then
    missing_libs+=("libmpfr-dev")
  fi
  
  # Check for other important libraries
  if ! ldconfig -p | grep -q libexpat; then
    missing_libs+=("libexpat1-dev")
  fi
  
  if ! ldconfig -p | grep -q libncurses; then
    missing_libs+=("libncurses-dev")
  fi
  
  if ! ldconfig -p | grep -q libreadline; then
    missing_libs+=("libreadline-dev")
  fi
  
  if ! command -v python3 &>/dev/null; then
    missing_libs+=("python3-dev")
  fi
  
  if ! command -v makeinfo &>/dev/null; then
    missing_libs+=("texinfo")
  fi
  
  if [ ${#missing_libs[@]} -gt 0 ]; then
    print_warning "Missing required development libraries: ${missing_libs[*]}"
    
    if prompt_yes_no "Install missing dependencies now?"; then
      print_status "Installing dependencies..."
      
      # Detect package manager and install
      if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y "${missing_libs[@]}"
      elif command -v yum &>/dev/null; then
        # Convert debian package names to RPM equivalents
        local rpm_libs=()
        for lib in "${missing_libs[@]}"; do
          case "$lib" in
            libgmp-dev) rpm_libs+=("gmp-devel") ;;
            libmpfr-dev) rpm_libs+=("mpfr-devel") ;;
            libexpat1-dev) rpm_libs+=("expat-devel") ;;
            libncurses-dev) rpm_libs+=("ncurses-devel") ;;
            libreadline-dev) rpm_libs+=("readline-devel") ;;
            python3-dev) rpm_libs+=("python3-devel") ;;
            texinfo) rpm_libs+=("texinfo") ;;
            *) rpm_libs+=("$lib") ;;
          esac
        done
        sudo yum install -y "${rpm_libs[@]}"
      elif command -v dnf &>/dev/null; then
        local rpm_libs=()
        for lib in "${missing_libs[@]}"; do
          case "$lib" in
            libgmp-dev) rpm_libs+=("gmp-devel") ;;
            libmpfr-dev) rpm_libs+=("mpfr-devel") ;;
            libexpat1-dev) rpm_libs+=("expat-devel") ;;
            libncurses-dev) rpm_libs+=("ncurses-devel") ;;
            libreadline-dev) rpm_libs+=("readline-devel") ;;
            python3-dev) rpm_libs+=("python3-devel") ;;
            texinfo) rpm_libs+=("texinfo") ;;
            *) rpm_libs+=("$lib") ;;
          esac
        done
        sudo dnf install -y "${rpm_libs[@]}"
      else
        print_error "No supported package manager found (apt, yum, dnf)"
        local install_deps
        install_deps=$(get_config "messages.build.install_deps")
        print_status "$install_deps"
        return 1
      fi
      
      # Verify installation
      if ! ldconfig -p | grep -q libgmp || ! ldconfig -p | grep -q libmpfr; then
        print_error "Failed to install required dependencies"
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
  build_dir=$(create_build_directory "gdb")
  local original_dir
  original_dir=$(pwd)
  cd "$build_dir" || return 1
  
  # Download tarball
  local downloading_msg
  downloading_msg=$(get_config "messages.build.downloading")
  downloading_msg="${downloading_msg/\{version\}/$version}"
  print_status "$downloading_msg"
  
  local ftp_url
  ftp_url=$(get_config "version.ftp_base_url")
  local tarball="gdb-${version}.tar.xz"
  local download_url="${ftp_url}${tarball}"
  
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
  
  cd "gdb-${version}" || {
    print_error "Failed to enter gdb-${version} directory"
    cleanup_build_directory "$build_dir" "$original_dir"
    return 1
  }
  
  # Create separate build directory (recommended by GDB)
  local creating_build_msg
  creating_build_msg=$(get_config "messages.build.creating_build_dir")
  print_status "$creating_build_msg"
  mkdir build
  cd build || return 1
  
  # Configure
  local configure_msg
  configure_msg=$(get_config "messages.build.running_configure")
  print_status "$configure_msg"
  
  local configure_opts
  configure_opts=$(get_config "build_instructions.configure_options.default")
  
  if ! ../configure $configure_opts; then
    local configure_failed
    configure_failed=$(get_config "messages.build.configure_failed")
    print_error "$configure_failed"
    cleanup_build_directory "$build_dir" "$original_dir"
    return 1
  fi
  
  # Build with parallel jobs
  local make_msg
  make_msg=$(get_config "messages.build.building_make")
  print_status "$make_msg"
  
  local num_cores
  num_cores=$(nproc 2>/dev/null || echo 2)
  
  if ! make -j"$num_cores"; then
    local make_failed
    make_failed=$(get_config "messages.build.make_failed")
    print_error "$make_failed"
    cleanup_build_directory "$build_dir" "$original_dir"
    return 1
  fi
  
  # Install
  local installing_msg
  installing_msg=$(get_config "messages.build.installing")
  print_status "$installing_msg"
  
  if ! sudo make install; then
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
    print_success "GDB version installed: $new_version"
  fi
  
  # Cleanup
  cleanup_build_directory "$build_dir" "$original_dir"
  
  local success_msg
  success_msg=$(get_config "messages.build.build_success")
  print_success "$success_msg"
  show_installation_info "gdb" "GDB (GNU Debugger)"
  
  return 0
}

# Perform GDB update with method selection
perform_gdb_update() {
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
    build_gdb_from_source "$latest_version"
  else
    # Try package manager update
    local current_before_update="$CURRENT_VERSION"
    if update_via_package_manager "gdb"; then
      # Check if version actually changed
      local current_after_update
      local version_cmd
      version_cmd=$(get_config "version.command")
      local version_regex
      version_regex=$(get_config "version.regex")
      current_after_update=$($version_cmd 2>/dev/null | head -1 | sed -E "s/$version_regex/\1/")
      
      if [ "$current_after_update" != "$current_before_update" ]; then
        print_success "GDB updated via package manager: $current_before_update → $current_after_update"
        show_installation_info "gdb" "GDB (GNU Debugger)"
      else
        # Package manager didn't upgrade to latest version
        print_warning "Package manager has GDB but not the latest version ($latest_version)"
        local build_prompt
        build_prompt=$(get_config "prompts.build_from_source.message")
        if prompt_yes_no "$build_prompt"; then
          build_gdb_from_source "$latest_version"
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
          
          local configure_cmd
          configure_cmd=$(get_config "build_instructions.steps[2].command")
          configure_cmd="${configure_cmd/\{version\}/$latest_version}"
          print_status "4️⃣ Configure: $configure_cmd"
          
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
          print_status "📖 Reference: $ref_url"
          print_status "📚 Documentation: $doc_url"
        fi
      fi
    else
      # No package manager found, offer source build
      local build_prompt
      build_prompt=$(get_config "prompts.build_from_source.message")
      if prompt_yes_no "$build_prompt"; then
        build_gdb_from_source "$latest_version"
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
        
        local configure_cmd
        configure_cmd=$(get_config "build_instructions.steps[2].command")
        configure_cmd="${configure_cmd/\{version\}/$latest_version}"
        print_status "4️⃣ Configure: $configure_cmd"
        
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
        print_status "📖 Reference: $ref_url"
        print_status "📚 Documentation: $doc_url"
      fi
    fi
  fi
}

# Update GDB (GNU Debugger)
# Uses Method 3: Custom Update Logic (see upgrade_script_pattern_documentation.md)
update_gdb() {
  # Override version check for GNU FTP source
  local app_name
  app_name=$(get_config "application.name")
  local app_display_name
  app_display_name=$(get_config "application.display_name")
  local checking_msg
  checking_msg=$(get_config "messages.checking_updates")
  
  # Print operation header
  print_section_header "$app_display_name"
  print_status "$checking_msg"
  
  # Check if application is installed
  local app_cmd
  app_cmd=$(get_config "application.command")
  
  if ! command -v "$app_cmd" &>/dev/null; then
    emit_summary_event "version_check" "target" "$app_display_name" "status" "not_installed" "current_version" "unknown" "latest_version" "unknown"
    print_warning "GDB is not installed on this system."
    
    if prompt_yes_no "Would you like to install GDB now?"; then
      # Try package manager first
      if update_via_package_manager "gdb"; then
        # Verify installation
        if command -v "$app_cmd" &>/dev/null; then
          print_success "GDB installed successfully via package manager"
          local installed_version
          local version_cmd
          version_cmd=$(get_config "version.command")
          local version_regex
          version_regex=$(get_config "version.regex")
          installed_version=$($version_cmd 2>/dev/null | head -1 | sed -E "s/$version_regex/\1/")
          if [[ -n "$installed_version" ]]; then
            print_success "Installed version: $installed_version"
          fi
          show_installation_info "gdb" "GDB (GNU Debugger)"
        else
          print_error "Installation failed or GDB command not found after package manager install"
        fi
      else
        # Package manager failed, offer source build
        print_warning "Package manager installation not available"
        if prompt_yes_no "Would you like to build GDB from source?"; then
          # Get latest version for source build
          print_status "Checking GNU FTP for latest version..."
          local latest_ver
          latest_ver=$(get_latest_gdb_version)
          if [[ -n "$latest_ver" ]]; then
            build_gdb_from_source "$latest_ver"
          else
            print_error "Failed to fetch latest version from GNU FTP"
          fi
        else
          local install_help
          install_help=$(get_config "messages.install_help")
          print_status "$install_help"
        fi
      fi
    else
      local install_help
      install_help=$(get_config "messages.install_help")
      print_status "$install_help"
    fi
    ask_continue
    return 0
  fi
  
  # Get current version
  local version_cmd
  version_cmd=$(get_config "version.command")
  local version_regex
  version_regex=$(get_config "version.regex")
  local failed_msg
  failed_msg=$(get_config "messages.failed_get_version")
  
  CURRENT_VERSION=$($version_cmd 2>/dev/null | head -1 | sed -E "s/$version_regex/\1/")
  
  if [[ -z "$CURRENT_VERSION" ]]; then
    emit_summary_event "version_check" "target" "$app_display_name" "status" "unknown" "current_version" "unknown" "latest_version" "unknown"
    print_error "$failed_msg"
    ask_continue
    return 1
  fi
  
  print_status "Current version: $CURRENT_VERSION"
  
  # Get latest version from GNU FTP
  print_status "Checking GNU FTP for latest version..."
  LATEST_VERSION=$(get_latest_gdb_version)
  
  if [[ -z "$LATEST_VERSION" ]]; then
    emit_summary_event "version_check" "target" "$app_display_name" "status" "unknown" "current_version" "$CURRENT_VERSION" "latest_version" "unknown"
    print_error "Failed to fetch latest version from GNU FTP"
    ask_continue
    return 1
  fi
  
  print_status "Latest version: $LATEST_VERSION"
  
  # Compare versions
  compare_versions "$CURRENT_VERSION" "$LATEST_VERSION"
  VERSION_STATUS=$?
  APP_DISPLAY_NAME="$app_display_name"
  
  case $VERSION_STATUS in
    0)
      emit_summary_event "version_check" "target" "$app_display_name" "status" "up_to_date" "current_version" "$CURRENT_VERSION" "latest_version" "$LATEST_VERSION"
      print_success "🎯 $app_display_name is up to date (version $CURRENT_VERSION)"
      ask_continue
      return 0
      ;;
    1)
      emit_summary_event "version_check" "target" "$app_display_name" "status" "ahead_of_latest" "current_version" "$CURRENT_VERSION" "latest_version" "$LATEST_VERSION"
      print_warning "⚠️ Current version ($CURRENT_VERSION) is ahead of latest release ($LATEST_VERSION)"
      ask_continue
      return 0
      ;;
    2)
      emit_summary_event "version_check" "target" "$app_display_name" "status" "update_available" "current_version" "$CURRENT_VERSION" "latest_version" "$LATEST_VERSION"
      print_warning "⬆️ Update available: $CURRENT_VERSION → $LATEST_VERSION"
      ;;
  esac
  
  # Handle update workflow with custom perform_gdb_update logic
  if ! handle_update_prompt "$APP_DISPLAY_NAME" "$VERSION_STATUS" \
    "perform_gdb_update '$LATEST_VERSION'"; then
    ask_continue
    return 1
  fi
}

update_gdb
