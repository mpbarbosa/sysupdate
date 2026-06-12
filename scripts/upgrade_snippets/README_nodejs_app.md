# Node.js Application Update Script

A config-driven shell script to update Node.js applications from source code, following the upgrade script pattern v1.1.0.

## Features

- **Config-driven**: All settings in `nodejs_app.yaml` - no code changes needed
- **Version checking**: Compares current version with latest from GitHub/npm
- **Automated workflow**: Git pull → npm install → build → restart
- **Safe updates**: Prompts for confirmation before critical operations
- **Service integration**: Supports systemd, pm2, docker-compose, custom scripts
- **Flexible**: Works with any Node.js application

## Files

- `update_nodejs_app.sh` - Main update script
- `nodejs_app.yaml` - Configuration template (customize for your app)

## Prerequisites

- Bash shell
- Git (for repository operations)
- npm and Node.js (v18+ recommended)
- yq (YAML parser) - installed via upgrade_utils.sh
- Application cloned to local directory

## Quick Start

### 1. Configure Your Application

Edit `nodejs_app.yaml`:

```yaml
application:
  name: "my-app"
  display_name: "My Node.js App"
  directory: "/opt/my-nodejs-app"

version:
  command: "node -p \"require('./package.json').version\""
  source: "github"
  github_owner: "yourusername"
  github_repo: "your-repo"

update:
  git_pull_command: "git pull origin main"
  npm_install_command: "npm ci --production"
  build_command: "npm run build"
  restart_command: "sudo systemctl restart my-app"
```

### 2. Run the Script

```bash
./update_nodejs_app.sh
```

## Configuration Guide

### Application Settings

```yaml
application:
  name: "my-nodejs-app"              # Package name from package.json
  display_name: "My Node.js App"      # Human-readable name
  directory: "/opt/my-nodejs-app"     # Full path to app directory
```

### Version Detection

**Option 1: From package.json (recommended)**
```yaml
version:
  command: "node -p \"require('./package.json').version\""
  regex: '^([0-9]+\.[0-9]+\.[0-9]+.*)$'
  source: "github"
  github_owner: "username"
  github_repo: "repo-name"
```

**Option 2: From git tags**
```yaml
version:
  command: "git describe --tags --abbrev=0"
  regex: '^v?([0-9]+\.[0-9]+\.[0-9]+)$'
  source: "github"
  github_owner: "username"
  github_repo: "repo-name"
```

**Option 3: From npm registry**
```yaml
version:
  command: "node -p \"require('./package.json').version\""
  regex: '^([0-9]+\.[0-9]+\.[0-9]+.*)$'
  source: "npm"
  npm_package: "my-nodejs-app"
```

### Update Commands

Customize the update workflow:

```yaml
update:
  git_pull_command: "git pull origin main"
  npm_install_command: "npm ci --production"
  build_command: "npm run build"
  restart_command: "sudo systemctl restart my-app"
```

**npm install options:**
- `npm ci --production` - Clean install (production only, faster)
- `npm install` - Standard install (includes dev dependencies)
- `npm ci` - Clean install (all dependencies)

**Build command examples:**
- `npm run build` - Standard build script
- `npm run build:prod` - Production build
- `null` - No build step required

### Service Restart

**systemd:**
```yaml
restart_command: "sudo systemctl restart my-app"
```

**pm2:**
```yaml
restart_command: "pm2 restart my-app"
```

**docker-compose:**
```yaml
restart_command: "docker-compose restart my-app"
```

**Custom script:**
```yaml
restart_command: "/path/to/custom-restart.sh"
```

**No restart:**
```yaml
restart_command: null
```

## Workflow

1. **Check dependencies** - Verifies git, npm, Node.js are installed
2. **Check app directory** - Ensures application path exists
3. **Version check** - Compares current vs latest version
4. **Confirm update** - Prompts user for confirmation
5. **Pull changes** - `git pull origin <branch>`
6. **Install dependencies** - `npm ci` or `npm install`
7. **Build** - Runs build command (if configured)
8. **Restart service** - Restarts service (if confirmed)

## Examples

### Express.js API

```yaml
application:
  name: "express-api"
  display_name: "Express API Server"
  directory: "/opt/express-api"

version:
  command: "node -p \"require('./package.json').version\""
  regex: '^([0-9]+\.[0-9]+\.[0-9]+)$'
  source: "github"
  github_owner: "mycompany"
  github_repo: "express-api"

update:
  git_pull_command: "git pull origin production"
  npm_install_command: "npm ci --production"
  build_command: null
  restart_command: "pm2 restart express-api"
```

### React Application

```yaml
application:
  name: "react-dashboard"
  display_name: "React Dashboard"
  directory: "/var/www/react-dashboard"

update:
  git_pull_command: "git pull origin main"
  npm_install_command: "npm ci"
  build_command: "npm run build"
  restart_command: "sudo systemctl reload nginx"
```

### Next.js Application

```yaml
application:
  name: "nextjs-app"
  display_name: "Next.js Application"
  directory: "/opt/nextjs-app"

update:
  git_pull_command: "git pull origin main"
  npm_install_command: "npm ci --production"
  build_command: "npm run build"
  restart_command: "pm2 restart nextjs-app"
```

## Troubleshooting

### "Application directory not found"
- Verify `application.directory` path is correct
- Clone repository first: `git clone <url> /path/to/dir`

### "Failed to get current version"
- Check `version.command` works in app directory
- Verify `version.regex` matches command output
- Test: `cd /app/dir && <version.command>`

### "Failed to pull latest changes"
- Check git credentials are configured
- Verify correct branch in `git_pull_command`
- Ensure no uncommitted changes: `git status`

### "Failed to install npm dependencies"
- Check Node.js version compatibility
- Try `npm cache clean --force`
- Delete `node_modules` and retry

### Permission denied
- Add `sudo` to restart command if needed
- Configure passwordless sudo for service restart
- Or run script as appropriate user

## Advanced Usage

### Multiple Environments

Create separate configs:
```bash
nodejs_app_prod.yaml
nodejs_app_staging.yaml
nodejs_app_dev.yaml
```

Run with specific config:
```bash
CONFIG_FILE="nodejs_app_prod.yaml" ./update_nodejs_app.sh
```

### Pre/Post Update Hooks

Add custom logic in `perform_nodejs_app_update()`:

```bash
# Before update
run_database_backup
stop_background_jobs

# After update
run_database_migrations
start_background_jobs
```

## References

- [Upgrade Script Pattern Documentation](../../../docs/upgrade_script_pattern_documentation.md)
- [GitHub Actions: Update Node.js versions](https://github.com/marketplace/actions/update-node-js-versions)
- [npm CLI Documentation](https://docs.npmjs.com/cli/)
- [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices)

## Version History

- **1.0.0-alpha** (2025-11-26) - Initial release
  - Config-driven approach
  - Supports git pull, npm install, build, restart
  - Template for any Node.js application

## License

MIT - Part of sysupdate repository
