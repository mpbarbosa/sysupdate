# Node.js Update Scripts - Quick Reference

## Two Different Scripts

### 1. update_nodejs.sh - Updates Node.js Runtime
**Purpose**: Upgrade the Node.js runtime itself (the `node` binary)

**Use when**: You want to update Node.js to a newer version

**Methods**:
- Version managers (nvm, n, fnm)
- Official binaries
- Build from source
- Package manager

**Example**: Upgrading from Node.js v18.x to v20.x

---

### 2. update_nodejs_app.sh - Updates Node.js Applications
**Purpose**: Update a Node.js application from source code

**Use when**: You want to update your app's code from git repository

**Workflow**: git pull → npm install → build → restart

**Example**: Updating your Express.js API or Next.js app

---

## Quick Start

### Update Node.js Runtime
```bash
cd scripts/upgrade_snippets
./update_nodejs.sh

# Select method:
# v = version manager (nvm/n/fnm)
# b = binary (fast, no compile)
# s = source (slow, 20-60 min)
# p = package manager
```

### Update Node.js Application
```bash
cd scripts/upgrade_snippets

# 1. Copy and configure
cp nodejs_app.yaml my_app.yaml
# Edit my_app.yaml with your app's settings

# 2. Run update
CONFIG_FILE="my_app.yaml" ./update_nodejs_app.sh
```

## Decision Tree

```
Need to update Node.js itself?
├─ YES → Use update_nodejs.sh
│         ├─ Have version manager? → Choose 'v'
│         ├─ Want fast install?    → Choose 'b' (binary)
│         ├─ Need custom build?    → Choose 's' (source)
│         └─ Use system packages?  → Choose 'p' (package)
│
└─ NO → Need to update your app?
          └─ YES → Use update_nodejs_app.sh
                   └─ Configure nodejs_app.yaml first
```

## Common Scenarios

### Scenario 1: New Node.js LTS Release
```bash
# Update runtime to latest LTS
./update_nodejs.sh
# Choose: v (if using nvm) or b (binary)
```

### Scenario 2: Deploy App Update
```bash
# Update your running application
./update_nodejs_app.sh
# Workflow: pull code → install deps → build → restart
```

### Scenario 3: Development Setup
```bash
# Install/update Node.js for development
./update_nodejs.sh
# Recommended: Choose 'v' with nvm for easy version switching

# Later, update your app code
./update_nodejs_app.sh
```

### Scenario 4: Production Server
```bash
# Update Node.js runtime (production)
./update_nodejs.sh
# Recommended: Choose 'b' (binary) - fast and reliable

# Update production app
./update_nodejs_app.sh
# Will pull latest code and restart service
```

## File Locations

```
scripts/upgrade_snippets/
├── update_nodejs.sh         ← Updates Node.js runtime
├── nodejs.yaml              ← Config for runtime updates
├── README_nodejs.md         ← Runtime update documentation
│
├── update_nodejs_app.sh     ← Updates Node.js applications
├── nodejs_app.yaml          ← Config template for apps
├── README_nodejs_app.md     ← App update documentation
│
└── examples/
    ├── nodejs_lts_example.yaml           ← LTS runtime config
    ├── nodejs_dev_example.yaml           ← Dev runtime config
    ├── nodejs_app_express_example.yaml   ← Express.js app
    └── nodejs_app_nextjs_example.yaml    ← Next.js app
```

## Key Differences

| Feature | update_nodejs.sh | update_nodejs_app.sh |
|---------|------------------|----------------------|
| **Updates** | Node.js runtime | Your application code |
| **Source** | nodejs.org / GitHub | Your git repository |
| **Methods** | 4 methods (vm/binary/source/pkg) | git pull + npm install |
| **Time** | 1-60 min (method dependent) | 1-5 min typically |
| **Frequency** | When new Node.js released | When you deploy changes |
| **Restarts** | N/A (version switch) | App service restart |

## Need Help?

- Runtime updates: Read `README_nodejs.md`
- App updates: Read `README_nodejs_app.md`
- Pattern docs: `docs/upgrade_script_pattern_documentation.md`

## Version

Both scripts: 1.0.0-alpha (2025-11-26)
