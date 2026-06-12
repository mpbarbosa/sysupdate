# GDB Update Manager

Automated version checking and upgrade script for GNU Debugger (GDB).

## Overview

The `update_gdb.sh` script provides a comprehensive solution for managing GDB updates, with support for both package manager updates and building from source. It follows the **Upgrade Script Pattern** established in this repository (see `docs/upgrade_script_pattern_documentation.md`).

## Features

- ✅ **Automated Version Checking**: Compares installed version with latest GNU FTP release
- 📦 **Package Manager Support**: Attempts update via system package manager first
- 🔨 **Source Build Support**: Complete automated build from source workflow
- 🎯 **Interactive Prompts**: User-friendly method selection
- 📋 **Comprehensive Instructions**: Displays manual build steps when needed
- 🛡️ **Error Handling**: Robust error checking throughout build process
- 🧹 **Automatic Cleanup**: Removes temporary build files on completion

## Requirements

### For Version Checking
- `gdb` (to check current version)
- `wget` or `curl` (to fetch version information)
- `yq` (YAML parser for configuration)

### For Package Manager Update
- `apt`, `yum`, `dnf`, `pacman`, `zypper`, or `brew`

### For Building from Source

**Required Dependencies:**
- `build-essential` (gcc, g++, make)
- `wget` or `curl`
- `tar`
- `texinfo`
- `libgmp-dev`
- `libmpfr-dev`
- `libexpat1-dev`
- `libncurses-dev`
- `libreadline-dev`
- `python3-dev`

**Optional Dependencies (for enhanced features):**
- `liblzma-dev` (XZ compression support)
- `zlib1g-dev` (compression support)
- `libzstd-dev` (Zstandard compression)
- `libbabeltrace-dev` (trace support)
- `libsource-highlight-dev` (source code highlighting)

### Installation on Debian/Ubuntu

```bash
# Required dependencies
sudo apt-get install -y build-essential texinfo libgmp-dev libmpfr-dev \
  libexpat1-dev libncurses-dev libreadline-dev python3-dev wget

# Optional dependencies (recommended)
sudo apt-get install -y liblzma-dev zlib1g-dev libzstd-dev \
  libbabeltrace-dev libsource-highlight-dev
```

## Usage

### Basic Usage

```bash
./update_gdb.sh
```

The script will:
1. Check current GDB version
2. Fetch latest version from GNU FTP
3. Compare versions and report status
4. If update available, prompt for update method
5. Execute chosen update method

### Update Methods

#### Method 1: Package Manager (Recommended)
```
Update method: (p)ackage manager or (s)ource build? p
```

The script will attempt to update GDB using your system's package manager (apt, yum, etc.).

**Advantages:**
- Fastest installation
- Automatic dependency management
- System integration
- Easy updates via normal system updates

**Limitations:**
- May not have the absolute latest version
- Limited customization options

#### Method 2: Build from Source
```
Update method: (p)ackage manager or (s)ource build? s
```

The script will download, compile, and install GDB from GNU official source.

**Advantages:**
- Latest stable release
- Full control over build options
- Custom feature selection

**Considerations:**
- Longer installation time (10-30 minutes)
- Requires build dependencies
- Requires compilation resources

## Build Process Details

When building from source, the script performs these steps:

1. **Dependency Check**: Verifies all required build tools are installed
2. **Download**: Fetches source tarball from GNU FTP
3. **Extract**: Unpacks the tarball
4. **Configure**: Runs `./configure` with optimized flags
   - Default options: `--prefix=/usr/local --enable-tui`
   - Installs to `/usr/local/bin` (separate from system GDB)
   - Enables Text User Interface (TUI) mode
5. **Build**: Compiles using parallel jobs (`make -j$(nproc)`)
6. **Install**: Installs binaries with `sudo make install`
7. **Verify**: Confirms successful installation
8. **Cleanup**: Removes temporary build directory

## Configuration

The script uses a YAML configuration file (`gdb.yaml`) that defines:

- Application metadata
- Version extraction patterns
- GNU FTP URLs and patterns
- User messages and prompts
- Build instructions
- Configure options

### Configure Options

You can customize the build by editing `gdb.yaml`:

```yaml
configure_options:
  default: "--prefix=/usr/local --enable-tui"
  recommended: "--prefix=/usr/local --enable-tui --with-python=/usr/bin/python3"
  minimal: "--prefix=/usr/local"
```

**Common options:**
- `--prefix=/usr/local` - Install location
- `--enable-tui` - Enable Text User Interface
- `--with-python=/usr/bin/python3` - Python scripting support
- `--with-expat` - XML parsing support
- `--enable-targets=all` - Support debugging all architectures

## Output Examples

### Up to Date
```
🔍 Checking GDB updates...
Current version: 15.1
Latest version: 15.1
🎯 GDB (GNU Debugger) is up to date (version 15.1)
```

### Update Available
```
🔍 Checking GDB updates...
Current version: 13.2
Latest version: 15.1
⬆️ Update available: 13.2 → 15.1
Update GDB (GNU Debugger)? (y/n) [y]: y
Update method: (p)ackage manager or (s)ource build? [p]: s
🔨 Building GDB 15.1 from source...
📥 Downloading GDB 15.1...
📦 Extracting GDB tarball...
📁 Creating build directory...
⚙️ Running configure (this may take several minutes)...
🔨 Building GDB (this may take 10-30 minutes depending on your system)...
📥 Installing GDB...
🔍 Verifying installation...
✅ GDB built and installed from source successfully
```

## Troubleshooting

### Version Detection Issues

If the script fails to detect your GDB version:
```bash
# Test version command manually
gdb --version

# Check regex pattern in gdb.yaml
```

### Download Failures

If source download fails:
```bash
# Test GNU FTP connectivity
wget https://ftp.gnu.org/gnu/gdb/

# Try alternative mirror
# Edit gdb.yaml and change ftp_base_url
```

### Build Failures

Common issues and solutions:

1. **Missing Dependencies**
   ```bash
   sudo apt-get install build-essential texinfo
   ```

2. **Python Development Headers**
   ```bash
   sudo apt-get install python3-dev
   ```

3. **Configure Fails**
   - Check `config.log` in build directory
   - Install missing development libraries

4. **Make Fails**
   - Check available disk space
   - Review compiler errors
   - Try building without parallel jobs: `make` instead of `make -j$(nproc)`

5. **Permission Denied**
   ```bash
   # Ensure sudo access for installation
   sudo -v
   ```

## Manual Build Instructions

If you prefer to build manually:

```bash
# Download
wget https://ftp.gnu.org/gnu/gdb/gdb-15.1.tar.xz

# Extract
tar -xf gdb-15.1.tar.xz
cd gdb-15.1

# Configure (out-of-tree build recommended)
mkdir build
cd build
../configure --prefix=/usr/local --enable-tui --with-python=/usr/bin/python3

# Build (use all CPU cores)
make -j$(nproc)

# Install
sudo make install

# Verify
gdb --version
```

## Integration

This script follows the **Upgrade Script Pattern** and integrates with:

- `scripts/lib/upgrade_utils.sh` - Shared utility functions
- `scripts/system_update.sh` - System-wide update orchestration

## Version History

- **0.1.0-alpha** (2025-12-13) - Initial release
  - GNU FTP version checking
  - Package manager support
  - Complete source build workflow
  - Interactive prompts
  - Comprehensive error handling

## References

- **GDB Official Site**: https://www.gnu.org/software/gdb/
- **GDB Documentation**: https://sourceware.org/gdb/documentation/
- **GNU FTP Mirror**: https://ftp.gnu.org/gnu/gdb/
- **Upgrade Pattern Docs**: `docs/upgrade_script_pattern_documentation.md`

## Contributing

When modifying this script:

1. Follow the established upgrade script pattern
2. Update version history in both files
3. Test with and without GDB installed
4. Validate YAML syntax: `yq . gdb.yaml`
5. Validate shell syntax: `bash -n update_gdb.sh`
6. Update this README with any changes

## License

Part of the sysupdate repository. See the repository LICENSE file.
