# Firmware Update Script (fwupd)

## Overview

The `update_fwupd.sh` script manages firmware updates for your system using the Linux Firmware Update Daemon (fwupd). It follows the standardized Upgrade Script Pattern and handles both the fwupd package itself and firmware updates for system devices.

## Features

- **Config-driven**: All messages, commands, and settings in `fwupd.yaml`
- **Dual-purpose**: Updates both fwupd package and system firmware
- **Version checking**: Compares current vs. latest fwupd version via apt
- **Automatic metadata refresh**: Refreshes firmware repositories before checking
- **Interactive prompts**: Confirms before applying firmware updates
- **Safe updates**: Non-destructive checks with explicit confirmation

## Requirements

- **fwupd**: Linux Firmware Update Daemon
  - Install: `sudo apt install fwupd`
- **apt**: Package manager (Debian/Ubuntu)
- **Permissions**: Some operations may require sudo

## Usage

```bash
# Run the update script
./update_fwupd.sh

# The script will:
# 1. Check fwupd package version
# 2. Offer to update fwupd if newer version available
# 3. Check for firmware updates for system devices
# 4. Prompt to apply firmware updates if available
```

## Configuration

The script uses `fwupd.yaml` for configuration:

```yaml
application:
  name: "fwupd"
  command: "fwupdmgr"
  display_name: "fwupd (Firmware Updater)"

version:
  command: "fwupdmgr --version"
  regex: '.*org.freedesktop.fwupd[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*'
  source: "apt"

firmware:
  refresh_command: "fwupdmgr refresh"
  check_command: "fwupdmgr get-updates"
  update_command: "fwupdmgr update"
```

## Workflow

1. **Check fwupd version**
   - Extracts current version from `fwupdmgr --version`
   - Queries apt for latest available version
   - Compares and reports status

2. **Update fwupd package** (if needed)
   - Prompts for confirmation
   - Runs: `sudo apt-get update && sudo apt-get install --only-upgrade -y fwupd`
   - Reports success/failure

3. **Check firmware updates**
   - Refreshes firmware metadata: `fwupdmgr refresh`
   - Checks for device updates: `fwupdmgr get-updates`
   - Lists available firmware updates

4. **Apply firmware updates** (if available)
   - Prompts for confirmation
   - Runs: `fwupdmgr update`
   - Displays update results
   - Warns if reboot required

## Exit Codes

- **0**: Success or no updates needed
- **1**: Error during update process

## Common Scenarios

### Scenario 1: fwupd is up to date, no firmware updates

```
Checking fwupd updates...
Current version: 2.0.16
Latest version: 2.0.16
✓ fwupd is already up to date

Checking for firmware updates...
✓ No firmware updates available
```

### Scenario 2: fwupd needs update, firmware updates available

```
Checking fwupd updates...
Current version: 2.0.15
Latest version: 2.0.16
⚠ Update available: 2.0.15 → 2.0.16

Update fwupd (Firmware Updater)? (y/n) y
Updating fwupd...
✓ fwupd updated successfully

Checking for firmware updates...
✓ Firmware updates available
<device list>
Update firmware now? (y/n) y
Updating firmware...
✓ Firmware updated successfully
⚠ Note: Some firmware updates may require a system reboot to take effect
```

### Scenario 3: Check only, skip updates

```
Checking fwupd updates...
Current version: 2.0.16
Latest version: 2.0.16
✓ fwupd is already up to date

Checking for firmware updates...
✓ Firmware updates available
<device list>
Update firmware now? (y/n) n
Skipping firmware update
```

## Safety Notes

1. **Backup**: Always backup important data before firmware updates
2. **Power**: Ensure stable power supply during firmware updates
3. **Reboot**: Some firmware updates require a system reboot
4. **Compatibility**: fwupd only updates devices with LVFS support
5. **Interruption**: Never interrupt a firmware update in progress

## Troubleshooting

### Issue: "Failed to refresh firmware metadata"

**Cause**: Network issues or repository unavailable

**Solution**: Check internet connection and try again

### Issue: "No firmware updates available" (but you expect updates)

**Cause**: Device not supported by LVFS or metadata not current

**Solution**: 
- Verify device support: `fwupdmgr get-devices`
- Manually refresh: `fwupdmgr refresh --force`

### Issue: Firmware update fails

**Cause**: Incompatible firmware, insufficient permissions, or hardware issue

**Solution**:
- Check logs: `journalctl -u fwupd`
- Try with elevated privileges if needed
- Verify device compatibility

## References

- **fwupd Documentation**: https://fwupd.org/
- **LVFS (Linux Vendor Firmware Service)**: https://fwupd.org/lvfs/
- **GitHub**: https://github.com/fwupd/fwupd
- **Upgrade Script Pattern**: See `docs/upgrade_script_pattern_documentation.md`

## Version

- **Script Version**: 0.1.0-alpha
- **Date**: 2025-12-18
- **Status**: Non-production (Alpha)
