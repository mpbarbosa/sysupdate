# Google Chrome Update Manager

Automated installation and update manager for Google Chrome on Debian/Ubuntu systems.

## Overview

This script handles:
- **Version Checking**: Detects current Chrome version and available updates
- **First-time Installation**: Sets up Chrome repository and installs Chrome
- **Automatic Updates**: Updates Chrome via apt when new versions are available
- **Repository Configuration**: Automatically configures Chrome's apt repository

## Files

- `update_google_chrome.sh` - Main update script
- `google_chrome.yaml` - Configuration file (versions, messages, commands)

## Requirements

### System Requirements
- Debian/Ubuntu-based Linux distribution
- `apt` package manager
- `wget` (for downloading signing keys)
- `sudo` privileges (for installation/updates)

### Dependencies
The script will automatically check for:
- `wget` - Required for repository setup

## Usage

### Basic Usage

```bash
./update_google_chrome.sh
```

### What Happens

#### If Chrome is NOT installed:
1. Prompts to install Chrome
2. Downloads and adds Google's signing key
3. Configures Chrome apt repository
4. Installs Google Chrome stable

#### If Chrome IS installed:
1. Checks current version
2. Checks for available updates
3. Prompts to update if newer version available
4. Updates via `apt-get upgrade`

## Installation Process

The script follows Google's official installation procedure:

1. **Add Signing Key**
   ```bash
   wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | \
     sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
   ```

2. **Configure Repository**
   ```bash
   echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] \
     http://dl.google.com/linux/chrome/deb/ stable main" | \
     sudo tee /etc/apt/sources.list.d/google-chrome.list
   ```

3. **Update and Install**
   ```bash
   sudo apt-get update
   sudo apt-get install -y google-chrome-stable
   ```

## Configuration

All settings are stored in `google_chrome.yaml`:

### Key Configuration Sections

- **Application Details**: Command names, display name
- **Version Extraction**: Regex pattern to extract version from `--version`
- **Messages**: Customizable user-facing messages
- **Update Commands**: Installation and update commands
- **Dependencies**: Required tools (wget)

### Example Configuration

```yaml
application:
  name: "google-chrome-stable"
  command: "google-chrome-stable"
  display_name: "Google Chrome"

version:
  command: "google-chrome-stable --version"
  regex: 'Google Chrome ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)'
```

## Architecture

This script follows the **Upgrade Script Pattern v1.1.0**:

- **Config-Driven**: All strings and commands in YAML
- **Reusable Libraries**: Uses `upgrade_utils.sh` for common functions
- **Separation of Concerns**: Logic vs. configuration
- **Custom Update Method**: Specialized for apt-based installation

See `../../docs/upgrade_script_pattern_documentation.md` for details.

## Version Detection

The script extracts version from:
```
$ google-chrome-stable --version
Google Chrome 141.0.7390.76
```

Regex: `Google Chrome ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)`

## Security

- Uses Google's official signing key
- Verifies packages with GPG signatures
- Repository configured with signed-by directive
- Requires sudo for privileged operations

## Troubleshooting

### "wget not found"
Install wget:
```bash
sudo apt-get install -y wget
```

### "Failed to add Google signing key"
- Check internet connectivity
- Verify URL: https://dl.google.com/linux/linux_signing_key.pub
- Check `/usr/share/keyrings/` permissions

### "Repository configuration failed"
- Ensure sudo privileges
- Check `/etc/apt/sources.list.d/` permissions
- Verify not running as root (use sudo instead)

### Chrome already installed but updates fail
The script will automatically configure the repository if it's missing.

### Manual Repository Check
```bash
cat /etc/apt/sources.list.d/google-chrome.list
ls -la /usr/share/keyrings/google-chrome.gpg
```

## Reference

- [Google Chrome Enterprise Admin Guide](https://support.google.com/chrome/a/answer/9025903?hl=en)
- Official Chrome Linux installation documentation
- Upgrade Script Pattern Documentation: `../../docs/upgrade_script_pattern_documentation.md`

## Version History

### 0.1.0-alpha (2025-11-29)
- Initial alpha release
- Supports apt-based installation
- Auto-configures Chrome repository
- Handles both fresh install and updates
- Follows upgrade script pattern v1.1.0

## Status

**Non-production (Alpha)** - Not ready for production use

## License

Part of sysupdate repository - MIT License

## Author

mpb - https://github.com/mpbarbosa/sysupdate
