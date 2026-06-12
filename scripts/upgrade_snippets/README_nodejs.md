# Node.js Runtime Update Script

A config-driven shell script to update/upgrade Node.js runtime itself from source code or binaries, following the upgrade script pattern v1.1.0.

## Overview

This script updates the **Node.js runtime** (not Node.js applications). It supports multiple installation methods:

1. **Version Managers** (nvm, n, fnm) - Auto-detected, recommended
2. **Official Binaries** - Fast, no compilation needed
3. **Build from Source** - Full control, but slow (20-60 minutes)
4. **Package Manager** - System package manager (apt, dnf, pacman)

## Features

- ✅ **Multi-method support** - Choose the best method for your setup
- ✅ **Auto-detection** - Detects installed version managers
- ✅ **Version checking** - Compares current vs latest from GitHub
- ✅ **Config-driven** - All settings in YAML
- ✅ **Safe builds** - Dependency checking before compilation
- ✅ **Optimized compilation** - Uses multiple cores for faster builds
- ✅ **Architecture support** - x64, arm64, armv7l

## Files

- `update_nodejs.sh` - Main update script
- `nodejs.yaml` - Configuration file

## Prerequisites

### For All Methods
- Bash shell
- curl (for downloading)
- Internet connection

### For Binary Installation
- tar with xz support
- sudo access

### For Source Builds
- git
- python3 (required by Node.js build system)
- C++ compiler (g++ or clang++)
- make
- pkg-config
- 8GB+ RAM
- 2GB+ free disk space
- 20-60 minutes of time

### For Version Managers
- **nvm**: Bash/Zsh shell
- **n**: Existing Node.js installation
- **fnm**: Modern shell (bash, zsh, fish)

## Quick Start

### Basic Usage

```bash
./update_nodejs.sh
```

The script will:
1. Check your current Node.js version
2. Fetch the latest version from GitHub
3. Auto-detect any installed version managers
4. Offer available update methods
5. Guide you through the update process

## Update Methods

### 1. Version Manager (Recommended)

**Best for**: Developers who manage multiple Node.js versions

The script auto-detects installed version managers:

#### nvm (Node Version Manager)
```bash
# Install nvm first if not installed:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Then run update script
./update_nodejs.sh
# Choose option: v (version manager)
```

**Pros**: 
- Manages multiple Node.js versions
- Per-user installation (no sudo)
- Easy version switching
- Most popular choice

#### n (Simple Version Manager)
```bash
# Install n first (requires existing Node.js):
npm install -g n

# Then run update script
./update_nodejs.sh
# Choose option: v (version manager)
```

**Pros**:
- Simple and straightforward
- System-wide installation
- Lightweight

#### fnm (Fast Node Manager)
```bash
# Install fnm first:
curl -fsSL https://fnm.vercel.app/install | bash

# Then run update script
./update_nodejs.sh
# Choose option: v (version manager)
```

**Pros**:
- Very fast (written in Rust)
- Cross-platform
- Modern features

### 2. Official Binary (Fast)

**Best for**: Production servers, quick updates without compilation

```bash
./update_nodejs.sh
# Choose option: b (binary)
```

**Process**:
1. Downloads pre-compiled binary from nodejs.org
2. Extracts to /usr/local
3. No compilation needed
4. Completes in 1-2 minutes

**Pros**:
- Very fast (no compilation)
- Official builds
- Reliable

**Cons**:
- Requires sudo access
- System-wide installation

### 3. Build from Source

**Best for**: Custom builds, specific optimizations, learning

```bash
./update_nodejs.sh
# Choose option: s (source)
```

**Process**:
1. Clones Node.js repository
2. Configures build
3. Compiles (20-60 minutes)
4. Installs to /usr/local

**Requirements**:
- 8GB+ RAM
- 2GB+ disk space
- Build tools installed

**Pros**:
- Full control over build
- Latest source code
- Custom optimizations possible

**Cons**:
- Very slow (20-60 minutes)
- Requires significant resources
- More complex

### 4. Package Manager

**Best for**: System administrators, standard installations

```bash
./update_nodejs.sh
# Choose option: p (package manager)
```

Attempts to update via:
- Ubuntu/Debian: `apt`
- Fedora/RHEL: `dnf`/`yum`
- Arch: `pacman`
- macOS: `brew`

**Pros**:
- Integrated with system
- Easy to maintain
- Managed updates

**Cons**:
- Often outdated versions
- May not have latest release

## Configuration

The `nodejs.yaml` file controls all behavior:

```yaml
# Application identifiers
application:
  name: "node"
  command: "node"
  display_name: "Node.js"

# Version detection
version:
  command: "node --version"
  regex: '^v([0-9]+\.[0-9]+\.[0-9]+)$'
  source: "github"
  github_owner: "nodejs"
  github_repo: "node"

# Update methods
update:
  nvm_command: "nvm install {version} && nvm use {version}"
  n_command: "sudo n {version}"
  fnm_command: "fnm install {version} && fnm default {version}"
  binary_url: "https://nodejs.org/dist/v{version}/node-v{version}-linux-{arch}.tar.xz"
  source_repo: "https://github.com/nodejs/node.git"
```

## Examples

### Example 1: Update via nvm

```bash
$ ./update_nodejs.sh

Checking for Node.js updates...
Current version: 20.10.0
Latest version:  21.5.0
Status: Update available

Detected version manager: nvm

Available update methods:
  v) Update via nvm version manager
  b) Install official binary (recommended, fast)
  s) Build from source (slow, 20-60 minutes)
  p) Update via package manager

Choose update method (v/b/s/p) [default: v]: v

Installing Node.js 21.5.0 with nvm...
Downloading and installing Node.js v21.5.0...
Node.js v21.5.0 installed and set as default
✓ Node.js updated successfully
```

### Example 2: Install Binary

```bash
$ ./update_nodejs.sh

Choose update method (v/b/s/p) [default: b]: b

Downloading Node.js v21.5.0 binary...
Extracting Node.js binary...
Installing Node.js to /usr/local...
✓ Node.js v21.5.0 installed successfully

Version: v21.5.0
```

### Example 3: Build from Source

```bash
$ ./update_nodejs.sh

Choose update method (v/b/s/p) [default: b]: s

Building Node.js v21.5.0 from source

Step 1: Cloning Node.js repository
✓ Repository cloned

Step 2: Configuring build
✓ Configuration complete

Step 3: Building Node.js (this may take 20-60 minutes)
⚠ Building Node.js from source is very time-consuming.
Building with 8 parallel jobs...
[... compilation output ...]
✓ Build complete

Step 4: Installing Node.js
✓ Node.js v21.5.0 built and installed successfully
```

## Workflow

```
Start
  ↓
Check current version (node --version)
  ↓
Fetch latest version (GitHub API)
  ↓
Compare versions
  ↓
Detect version manager (nvm, n, fnm)
  ↓
Display available methods
  ↓
User selects method
  ↓
┌─────────────────────────────────┐
│  v: Version Manager             │ → Install via nvm/n/fnm
│  b: Binary                      │ → Download and extract binary
│  s: Source                      │ → Clone, build, install (20-60 min)
│  p: Package Manager             │ → apt/dnf/pacman install
└─────────────────────────────────┘
  ↓
Verify installation
  ↓
Display new version
  ↓
Complete
```

## Troubleshooting

### "No version manager detected"
- Install a version manager first (nvm recommended)
- Or choose binary/source/package manager method

### "Failed to download binary"
- Check internet connection
- Verify architecture is supported (x64, arm64, armv7l)
- Try source build instead

### "Build failed" (source builds)
- Check you have 8GB+ RAM
- Install all dependencies: `sudo apt install git python3 g++ make pkg-config`
- Try building with fewer cores: edit script to reduce `$(nproc)`

### "Missing required build dependencies"
```bash
# Ubuntu/Debian
sudo apt install git python3 g++ make pkg-config

# Fedora/RHEL
sudo dnf install git python3 gcc-c++ make pkgconfig

# Arch
sudo pacman -S git python gcc make pkg-config
```

### Version manager not detected after installation
- Restart your shell: `exec bash`
- Or source the config: `source ~/.bashrc` or `source ~/.nvm/nvm.sh`

## Performance Notes

### Installation Time Comparison

| Method | Time | Download Size | Disk Space |
|--------|------|---------------|------------|
| Version Manager | 1-3 min | ~30MB | ~50MB |
| Binary | 1-2 min | ~30MB | ~50MB |
| Source Build | 20-60 min | ~200MB | ~2GB |
| Package Manager | 1-5 min | Varies | Varies |

### Recommended Methods by Use Case

- **Development**: nvm (easy version switching)
- **Production Server**: Binary or package manager
- **CI/CD**: Binary (fast, consistent)
- **Learning/Custom**: Source build
- **Multiple versions**: nvm or fnm

## Advanced Usage

### Install Specific Version

Edit `nodejs.yaml` to pin a specific version:

```yaml
version:
  # Override latest detection
  force_version: "20.10.0"
```

### Custom Installation Directory

For binary installations, edit:

```yaml
update:
  binary_install_dir: "/opt/nodejs"
```

### Multiple Node.js Versions

Use nvm or fnm to manage multiple versions:

```bash
# With nvm
nvm install 20
nvm install 21
nvm use 20  # Switch to Node.js 20
nvm use 21  # Switch to Node.js 21
```

## References

- [Node.js Official Website](https://nodejs.org/)
- [Node.js GitHub Repository](https://github.com/nodejs/node)
- [Node.js Building Guide](https://github.com/nodejs/node/blob/main/BUILDING.md)
- [nvm Documentation](https://github.com/nvm-sh/nvm)
- [n Documentation](https://github.com/tj/n)
- [fnm Documentation](https://github.com/Schniz/fnm)
- [Upgrade Script Pattern](../../../docs/upgrade_script_pattern_documentation.md)

## Version History

- **1.0.0-alpha** (2025-11-26) - Initial release
  - Multi-method support (version managers, binary, source, package)
  - Auto-detection of version managers
  - Config-driven approach
  - Optimized source builds

## License

MIT - Part of sysupdate repository
