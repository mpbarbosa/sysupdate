# Functional Requirements Document

## Oh-My-Bash Update Manager

**Script**: `update_oh_my_bash.sh`  
**Version**: 1.1.0-alpha  
**Date**: 2025-12-15  
**Status**: Non-production (Alpha)  
**Repository**: https://github.com/mpbarbosa/sysupdate  

---

## 1. Executive Summary

### 1.1 Purpose

The Oh-My-Bash Update Manager provides automated version checking and update capabilities for the oh-my-bash framework using Git-based version control. It implements a git commit-based versioning system to track and update oh-my-bash installations.

### 1.2 Scope

This script manages the complete lifecycle of oh-my-bash updates including:

- Installation detection and verification
- Installation guidance for missing or invalid installs
- Version checking via Git commits
- Automated updates via verified fast-forward git pull
- User interaction and workflow management

### 1.3 Target Users

- System administrators managing oh-my-bash installations
- Developers using oh-my-bash who want automated updates
- Users of the system update framework

---

## 2. System Overview

### 2.1 Architecture

- **Pattern**: Method 3 - Custom Update Logic (upgrade_script_pattern_documentation.md)
- **Version Tracking**: Git commit SHA (short format, 8 characters)
- **Remote Check Mechanism**: Read-only `git ls-remote --heads`
- **Update Mechanism**: `git pull --ff-only` from remote origin with post-update verification
- **Configuration**: YAML-based external configuration (oh_my_bash.yaml)
- **Library Dependencies**: upgrade_utils.sh, core_lib.sh

### 2.2 Dependencies

#### Required External Tools

- **git**: Version control operations (fetch, pull, rev-parse)
- **git**: Version control operations (ls-remote, pull, rev-parse)
- **bash**: Shell interpreter (v4.0+)

#### Required Internal Libraries

- **upgrade_utils.sh**: Common upgrade utilities and configuration management
- **core_lib.sh**: Core library for printing and user interaction

#### Configuration Files

- **oh_my_bash.yaml**: Application configuration, messages, and settings

---

## 3. Functional Requirements

### 3.1 Installation Detection and Verification

#### FR-1.1: Check Installation Directory

**Priority**: Critical  
**Description**: Verify that oh-my-bash is installed at the configured location  
**Input**: Installation directory path from configuration  
**Output**: Boolean success/failure  
**Behavior**:

- Read installation directory from YAML config: `application.installation_dir`
- Expand shell variables (e.g., `${HOME}`)
- Check if directory exists
- If not found, emit a `not_installed` summary and show installation guidance (FR-1.2)

#### FR-1.2: Show Installation Guidance

**Priority**: High  
**Description**: When oh-my-bash is not installed, provide safe next steps without mutating state  
**Input**: Installation directory path  
**Output**: Structured `not_installed` result and guidance output  
**Behavior**:

- Display not_installed message from config
- Show installation help instructions
- Do not perform installation automatically during version checking
- In `--check-only` mode, remain fully read-only
- Return a non-failure readiness status so the caller can show `ask_continue()`

#### FR-1.3: Verify Git Repository

**Priority**: Critical  
**Description**: Ensure installation directory is a valid Git repository  
**Input**: Installation directory path  
**Output**: Boolean success/failure  
**Behavior**:

- Check for `.git` subdirectory in installation path
- If missing:
  - Display not_git_repo warning message
  - Emit an `invalid_installation` summary
  - Provide manual installation guidance
  - Return a non-failure readiness status so the caller can show `ask_continue()`
- If present: Return success

### 3.2 Version Detection

#### FR-2.1: Get Current Commit Hash

**Priority**: Critical  
**Description**: Retrieve the current Git commit SHA of the local installation  
**Input**: Installation directory path from config  
**Output**: 8-character short commit hash (e.g., "63ebf650")  
**Behavior**:

- Navigate to installation directory
- Execute: `git rev-parse --short=8 HEAD`
- Validate output is non-empty
- Return commit hash or failure
- Error handling: Return failure if not a git repo or git command fails

#### FR-2.2: Get Remote Commit Hash

**Priority**: Critical  
**Description**: Retrieve the latest commit SHA from the remote repository  
**Input**: 

- Installation directory path from config
- Branch name from config (`update.branch`)
**Output**: 8-character short commit hash  
**Behavior**:
- Read `remote.origin.url` from the local Git configuration
- Query the remote branch head with: `git ls-remote --heads <remote_url> <branch>`
- Truncate the resulting SHA to 8 characters
- Validate output is non-empty
- Error messages must go to stderr to avoid pollution
- Return commit hash or failure

**Error Handling**:

- Display fetch_failed message on remote lookup failure
- Return failure if unable to determine remote commit

### 3.3 Version Comparison

#### FR-3.1: Compare Local vs Remote Commits

**Priority**: Critical  
**Description**: Determine if an update is available by comparing commits  
**Input**: Current commit hash, remote commit hash  
**Output**: VERSION_STATUS environment variable (0 or 2)  
**Behavior**:

- Compare current_commit with remote_commit
- If equal:
  - Set `VERSION_STATUS=0` (up-to-date)
  - Display already_updated success message
- If different:
  - Set `VERSION_STATUS=2` (update available)
  - Display update notification with commit hashes
  - Format: "oh-my-bash update available: <current> → <remote>"

#### FR-3.2: Store Version Information

**Priority**: High  
**Description**: Make version data available to the snippet workflow  
**Input**: Current and remote commit hashes  
**Output**: Shell variables  
**Behavior**:

- Set `CURRENT_VERSION` = current commit hash
- Set `LATEST_VERSION` = remote commit hash
- Set `APP_DISPLAY_NAME` from configuration
- Set `VERSION_STATUS` = 0 (up-to-date) or 2 (update available)

### 3.4 Update Execution

#### FR-4.1: Perform Git Pull Update

**Priority**: Critical  
**Description**: Update oh-my-bash by pulling latest changes from remote  
**Input**: 

- Installation directory from config
- Branch name from config
**Output**: Success/failure status  
**Behavior**:
- Display pulling_updates status message
- Navigate to installation directory
- Execute: `git pull --ff-only origin <branch>`
- Show git pull output to user
- On success:
  - Retrieve and verify the new local commit hash
  - Confirm the local commit changed from the previous value
  - Re-check the current remote branch head
  - Report success only when the local commit matches the remote branch head
  - Display update_success message and the verified commit hash
- On failure:
  - Display pull_failed error message
  - Return failure status

#### FR-4.2: Handle Update Workflow

**Priority**: High  
**Description**: Orchestrate the complete update process with user interaction  
**Input**: VERSION_STATUS, version information  
**Output**: Update success/failure  
**Behavior**:

- Skip update if VERSION_STATUS=0 (already up-to-date)
    - If the installation is missing or invalid, show guidance and stop without mutating state
    - For VERSION_STATUS=2 (update available):
      - Call `handle_update_prompt()` from upgrade_utils.sh
      - Pass display name, version status, and update command
      - Update command chain:
    1. Display updating status message
    2. Execute perform_oh_my_bash_update()
    3. Emit a refreshed `summary.updates` success state and optional installation info
    - Call `ask_continue()` after informative or failure exits
    - Return appropriate status

### 3.5 User Interaction

#### FR-5.1: Display Status Messages

**Priority**: Medium  
**Description**: Provide clear feedback throughout the update process  
**Input**: Message keys from YAML configuration  
**Output**: Formatted console output  
**Behavior**:

- All messages must be retrieved from oh_my_bash.yaml
- Use appropriate formatting functions:
  - `print_status()` for informational messages
  - `print_error()` for error messages
  - `print_success()` for success messages
- Support message templates with placeholders (e.g., {commit})
- Replace placeholders with actual values before display

#### FR-5.2: Prompt User Decisions

**Priority**: High  
**Description**: Request user input for critical decisions  
**Input**: Prompt message and type  
**Output**: User response (yes/no)  
**Behavior**:

- Use `prompt_yes_no()` from upgrade_utils.sh
- Supported prompt:
  - Update confirmation (via handle_update_prompt)
- Respect default values from configuration
- Handle invalid input gracefully

#### FR-5.3: Pause for User Acknowledgment

**Priority**: Low  
**Description**: Allow user to review output before continuing  
**Input**: None  
**Output**: User keypress  
**Behavior**:

- Call `ask_continue()` after version check
- Call `ask_continue()` after update completion or failure
- Prevents output from scrolling off screen

### 3.6 Configuration Management

#### FR-6.1: Load YAML Configuration

**Priority**: Critical  
**Description**: Load all settings from external YAML file  
**Input**: oh_my_bash.yaml file path  
**Output**: Configuration values accessible via get_config()  
**Behavior**:

- Set CONFIG_FILE to oh_my_bash.yaml path
- Configuration sections:
  - `application.*`: Name, display name, installation directory
  - `messages.*`: All user-facing messages
  - `prompts.*`: Update prompt configuration
  - `update.*`: Update method and branch
  - `version.*`: Version detection method
  - `installation.*`: Installation instructions

#### FR-6.2: Retrieve Configuration Values

**Priority**: Critical  
**Description**: Access configuration values using dot notation  
**Input**: Configuration key (e.g., "application.installation_dir")  
**Output**: Configuration value  
**Behavior**:

- Use `get_config()` from upgrade_utils.sh
- Support nested keys with dot notation
- Expand shell variables in values (e.g., ${HOME})
- Return empty string or error for missing keys

---

## 4. Non-Functional Requirements

### 4.1 Performance

- **NFR-1.1**: Script execution should complete within 30 seconds for normal update operations
- **NFR-1.2**: Network operations (`git ls-remote`, `git pull`) timeout should be reasonable (60s)
- **NFR-1.3**: Version check should complete within 10 seconds

### 4.2 Reliability

- **NFR-2.1**: All Git operations must handle network failures gracefully
- **NFR-2.2**: Script must not corrupt existing oh-my-bash installations
- **NFR-2.3**: Error messages must be clear and actionable
- **NFR-2.4**: Script must be idempotent (safe to run multiple times)
- **NFR-2.5**: `--check-only` mode must not mutate the local Git checkout or install state

### 4.3 Usability

- **NFR-3.1**: All messages must be user-friendly and non-technical when possible
- **NFR-3.2**: Progress feedback must be provided for long-running operations
- **NFR-3.3**: Color-coded output for success (green), error (red), info (blue)
- **NFR-3.4**: Default responses should favor safe operations (no auto-install)

### 4.4 Maintainability

- **NFR-4.1**: All user-facing strings must be externalized to YAML configuration
- **NFR-4.2**: Functions must be modular and single-purpose
- **NFR-4.3**: Code must include inline comments for complex logic
- **NFR-4.4**: Script must follow bash best practices (set -u, local variables, etc.)

### 4.5 Portability

- **NFR-5.1**: Must work on Linux, macOS, and WSL environments
- **NFR-5.2**: Require only standard Unix tools (bash, git, curl)
- **NFR-5.3**: Path handling must support home directory expansion
- **NFR-5.4**: Must handle different default shell environments

### 4.6 Security

- **NFR-6.1**: Installation script must be downloaded via HTTPS only
- **NFR-6.2**: No hardcoded credentials or sensitive data
- **NFR-6.3**: User must confirm before performing destructive operations
- **NFR-6.4**: Git operations should use standard authentication mechanisms
- **NFR-6.5**: Version checks must use read-only remote inspection rather than mutating fetches

---

## 5. Interface Specifications

### 5.1 Command Line Interface

#### Entry Point

```bash
./update_oh_my_bash.sh
```

#### Exit Codes

- **0**: Success (updated, already up-to-date, or user skipped)
- **1**: Failure (installation check failed, update failed, or git error)

#### Standard Output

- Status messages (informational)
- Success confirmations
- Version information
- Commit hashes

#### Standard Error

- Error messages
- Git operation failures
- Network errors

### 5.2 Configuration File Interface

#### File: oh_my_bash.yaml

**Required Sections**:

```yaml
application:
  name: string
  display_name: string
  installation_dir: string (supports ${HOME} expansion)
  git_repo: string (URL)

messages:
  checking_updates: string
  install_help: string (multiline)
  failed_get_version: string
  not_installed: string
  not_git_repo: string
  empty_git_repo: string
  missing_git_remote: string
  updating: string
  skipping_update: string
  fetch_failed: string
  pulling_updates: string
  pull_failed: string
  update_success: string
  verify_updated_failed: string
  update_no_change: string
  verify_remote_failed: string
  update_not_at_remote_head: string
  remote_advanced: string (supports {commit} placeholder)
  already_updated: string
  commit_info: string (supports {commit} placeholder)
  remote_commit_info: string (supports {commit} placeholder)

update:
  method: string ("git_pull")
  branch: string ("master")

prompts:
  perform_update:
    message: string
    type: string ("yes_no")
    default: string ("y" or "n")
  reinstall:
    message: string
    type: string ("yes_no")
    default: string
```

### 5.3 Library Dependencies Interface

#### From upgrade_utils.sh:

- `get_config(key)`: Retrieve configuration value
- `print_status(message)`: Display info message in blue
- `print_error(message)`: Display error message in red
- `print_success(message)`: Display success message in green
- `prompt_yes_no(prompt)`: Get yes/no user input
- `handle_update_prompt(app_name, status, command)`: Manage update workflow
- `ask_continue()`: Pause for user acknowledgment
- `show_installation_info(app_name, display_name)`: Display installation details

#### From core_lib.sh:

- Color constants: `$BLUE`, `$RED`, `$GREEN`, `$RESET`
- Base printing functions

---

## 6. Data Requirements

### 6.1 Input Data

#### Configuration Data

- **Source**: oh_my_bash.yaml
- **Format**: YAML key-value pairs
- **Required Fields**: All application.*, messages.*, update.* fields
- **Optional Fields**: prompts.*, installation.*

#### Environment Variables

- **HOME**: User home directory (expanded in paths)
- **BASH_SOURCE**: Script location (for relative path resolution)

#### User Input

- Yes/No responses for prompts
- Keypresses for continuation

### 6.2 Output Data

#### Environment Variables (Exported)

- `CURRENT_VERSION`: 7-character commit hash
- `LATEST_VERSION`: 7-character commit hash
- `APP_DISPLAY_NAME`: "Oh-My-Bash"
- `VERSION_STATUS`: Integer (0 or 2)

#### Console Output

- Informational messages
- Error messages
- Success messages
- Commit hash information
- Update progress

#### Side Effects

- Modified oh-my-bash installation (updated files)
- Updated Git repository state (HEAD commit)
- Modified local Git references

---

## 7. Error Handling

### 7.1 Installation Errors

#### Error: Installation Directory Not Found

- **Detection**: Directory check fails
- **Message**: Display messages.not_installed
- **Action**: Prompt for installation
- **Recovery**: User can install or skip

#### Error: Not a Git Repository

- **Detection**: .git subdirectory missing
- **Message**: Display messages.not_git_repo
- **Action**: Prompt for reinstallation with instructions
- **Recovery**: Manual reinstallation required

### 7.2 Version Detection Errors

#### Error: Cannot Get Current Commit

- **Detection**: git rev-parse fails or returns empty
- **Message**: Display messages.failed_get_version
- **Action**: Return failure status
- **Recovery**: User must fix Git repository

#### Error: Cannot Fetch Remote

- **Detection**: git fetch command fails
- **Message**: Display messages.fetch_failed
- **Action**: Return failure status
- **Recovery**: Check network connectivity and Git configuration

#### Error: Cannot Get Remote Commit

- **Detection**: git rev-parse fails for origin/branch
- **Message**: Display "Failed to fetch remote commit information"
- **Action**: Return failure status
- **Recovery**: Verify branch exists and is accessible

### 7.3 Update Errors

#### Error: Git Pull Fails

- **Detection**: git pull command exits non-zero
- **Message**: Display messages.pull_failed
- **Action**: Return failure status
- **Recovery**: User must resolve merge conflicts or Git issues

### 7.4 Configuration Errors

#### Error: YAML File Not Found

- **Detection**: CONFIG_FILE path invalid
- **Message**: upgrade_utils.sh error message
- **Action**: Script cannot continue
- **Recovery**: Ensure oh_my_bash.yaml exists in correct location

#### Error: Missing Configuration Key

- **Detection**: get_config() returns empty for required key
- **Message**: Key-specific error or generic failure
- **Action**: Script may fail or use fallback
- **Recovery**: Update YAML configuration file

---

## 8. Workflow Diagrams

### 8.1 Main Update Workflow

```text
START
  ↓
[Check if oh-my-bash installed] → NOT INSTALLED → [Prompt to install]
  ↓                                                      ↓
INSTALLED                                              YES → [Install] → Success/Fail
  ↓                                                      ↓
[Verify Git repository] → NOT GIT → [Prompt reinstall] → NO → FAIL
  ↓                                                      
VALID GIT                                              
  ↓
[Get current commit]
  ↓
[Fetch remote & get remote commit]
  ↓
[Compare commits]
  ↓
  ├─ EQUAL → [Display up-to-date] → END
  └─ DIFFERENT → [Display update available]
       ↓
     [Prompt user to update]
       ↓
       ├─ NO → [Skip update] → END
       └─ YES → [Perform git pull]
            ↓
            ├─ SUCCESS → [Display success + new commit] → END
            └─ FAIL → [Display error] → END
```

### 8.2 Installation Check Workflow

```text
[Check installation directory]
  ↓
  ├─ EXISTS → [Check .git directory]
  │             ↓
  │             ├─ EXISTS → VALID
  │             └─ NOT EXISTS → [Prompt reinstall] → User choice
  └─ NOT EXISTS → [Prompt install] → User choice
                      ↓
                      ├─ YES → [Download install script]
                      │          ↓
                      │          ├─ SUCCESS → INSTALLED
                      │          └─ FAIL → ERROR
                      └─ NO → NOT INSTALLED
```

### 8.3 Version Check Workflow

```text
[Start version check]
  ↓
[Get current commit: git rev-parse HEAD]
  ↓
  ├─ SUCCESS → [Store current_commit]
  └─ FAIL → ERROR: Cannot determine version
  ↓
[Fetch remote: git fetch origin master]
  ↓
  ├─ SUCCESS → [Get remote commit: git rev-parse origin/master]
  │              ↓
  │              ├─ SUCCESS → [Store remote_commit]
  │              └─ FAIL → ERROR: Cannot get remote version
  └─ FAIL → ERROR: Cannot fetch remote
  ↓
[Compare current_commit vs remote_commit]
  ↓
  ├─ EQUAL → VERSION_STATUS=0 (up-to-date)
  └─ DIFFERENT → VERSION_STATUS=2 (update available)
  ↓
[Export version variables]
  ↓
END
```

---

## 9. Testing Requirements

### 9.1 Unit Testing

#### Test Case UT-1: check_oh_my_bash_installed()

- **Scenario 1**: Directory exists and is Git repo → Returns 0
- **Scenario 2**: Directory does not exist → Returns 1, prompts install
- **Scenario 3**: Directory exists but not Git repo → Returns 1, prompts reinstall

#### Test Case UT-2: get_current_commit()

- **Scenario 1**: Valid Git repo with commits → Returns 7-char hash
- **Scenario 2**: Not a Git repo → Returns 1
- **Scenario 3**: Empty Git repo → Returns 1

#### Test Case UT-3: get_remote_commit()

- **Scenario 1**: Network available, remote exists → Returns 7-char hash
- **Scenario 2**: Network unavailable → Returns 1, displays error
- **Scenario 3**: Branch does not exist → Returns 1

#### Test Case UT-4: perform_oh_my_bash_update()

- **Scenario 1**: Clean working directory → git pull succeeds
- **Scenario 2**: Merge conflicts → git pull fails, displays error
- **Scenario 3**: Network unavailable → git pull fails

### 9.2 Integration Testing

#### Test Case IT-1: Fresh Installation

- **Setup**: oh-my-bash not installed
- **Expected**: Script prompts for installation, installs on yes

#### Test Case IT-2: Up-to-date Installation

- **Setup**: oh-my-bash installed, current = remote commit
- **Expected**: Displays "already up-to-date", skips update

#### Test Case IT-3: Outdated Installation

- **Setup**: oh-my-bash installed, current ≠ remote commit
- **Expected**: Displays update available, prompts for update, updates on yes

#### Test Case IT-4: Broken Git Repository

- **Setup**: Installation directory exists but .git is corrupted
- **Expected**: Detects not a git repo, prompts for reinstall

### 9.3 Error Handling Testing

#### Test Case EH-1: Network Failure During Fetch

- **Trigger**: Disconnect network before git fetch
- **Expected**: Displays fetch_failed error, returns failure

#### Test Case EH-2: Invalid YAML Configuration

- **Trigger**: Remove required key from oh_my_bash.yaml
- **Expected**: Script fails gracefully with config error

#### Test Case EH-3: Git Pull Merge Conflict

- **Trigger**: Modify local files, attempt update
- **Expected**: git pull fails, displays error, repository unchanged

---

## 10. Version History and Change Log

### Version 1.1.0-alpha (2025-11-29)

- **Changes**: Added installation prompt when oh-my-bash not installed
- **New Features**: 
  - Interactive installation workflow
  - Automatic installation script download
- **Impact**: Users can install directly from update script

### Version 1.0.0-alpha (2025-11-27)

- **Changes**: Initial alpha release
- **Features**:
  - Git commit-based versioning
  - Custom update logic (Method 3)
  - Git pull update mechanism
  - YAML configuration support
- **Status**: Aligned with upgrade script pattern v1.1.0

---

## 11. Future Enhancements

### Planned Features

1. **Backup Before Update**: Create backup of configuration before updating
2. **Rollback Support**: Allow reverting to previous commit
3. **Branch Selection**: Support multiple branches (stable, beta, dev)
4. **Conflict Resolution**: Automated handling of common merge conflicts
5. **Update Scheduling**: Automated periodic update checks
6. **Custom Themes**: Preserve custom themes during updates
7. **Plugin Management**: Update oh-my-bash plugins separately
8. **Dry Run Mode**: Preview changes without applying them

### Possible Improvements

- Add verbose mode for detailed Git output
- Support for non-standard installation locations
- Integration with system package managers
- Notification system for update availability
- Update history log
- Performance metrics collection

---

## 12. Dependencies and Prerequisites

### System Requirements

- **Operating System**: Linux, macOS, or WSL
- **Shell**: Bash 4.0 or higher
- **Git**: Version 2.0 or higher
- **curl**: For installation script download
- **Network**: Internet access for remote repository

### File System Requirements

- **Installation Directory**: ~/.oh-my-bash (default)
- **Configuration File**: oh_my_bash.yaml in script directory
- **Library Files**: 
  - ../lib/upgrade_utils.sh
  - ../lib/core_lib.sh

### Permissions

- Read access to configuration files
- Write access to oh-my-bash installation directory
- Execute permissions on script file
- Network access for Git operations

---

## 13. Compliance and Standards

### Coding Standards

- **Shell**: Bash best practices (ShellCheck compliant)
- **Style**: Consistent indentation (4 spaces)
- **Documentation**: Inline comments for complex logic
- **Error Handling**: Explicit error checking and messages

### Documentation Standards

- **Headers**: Script metadata (version, author, purpose)
- **Functions**: Purpose and parameter documentation
- **Version History**: Changelog in script header

### Security Standards

- **HTTPS Only**: All network operations use HTTPS
- **No Hardcoded Secrets**: No credentials in code
- **User Confirmation**: Prompt before destructive operations
- **Input Validation**: Validate all user input

---

## 14. Glossary

- **Commit Hash**: Git SHA-1 hash identifying a specific commit (shortened to 7 characters)
- **Git Repository**: Version control repository managed by Git
- **Oh-My-Bash**: Bash framework for managing bash configuration and themes
- **Origin**: Default name for remote Git repository
- **YAML**: YAML Ain't Markup Language - human-readable data serialization format
- **Upgrade Pattern**: Standardized approach for version checking and updates
- **VERSION_STATUS**: Integer code indicating update availability (0=up-to-date, 2=update available)

---

## 15. References

### External Documentation

- Oh-My-Bash: https://github.com/ohmybash/oh-my-bash
- Oh-My-Bash Wiki: https://github.com/ohmybash/oh-my-bash/wiki
- Git Documentation: https://git-scm.com/doc

### Internal Documentation

- upgrade_script_pattern_documentation.md
- upgrade_utils.sh documentation
- core_lib.sh documentation

### Related Scripts

- update_bash.sh
- update_tmux.sh
- Other upgrade snippet modules

---

**Document Version**: 1.0  
**Last Updated**: 2025-12-15  
**Approved By**: mpb  
**Status**: Draft
