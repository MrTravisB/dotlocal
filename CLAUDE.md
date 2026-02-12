# Project Instructions

## Overview

**dotlocal** is a personal dotfiles and configuration synchronization tool for macOS. It manages shell configs, editor settings, git configuration, terminal emulator preferences, Homebrew packages, SSH config, and fonts across multiple machines.

## Architecture

### Core Principles

- **Symlink-based**: Config files live in this repo; symlinks point from target locations (e.g., `~/.zshrc`) back to the repo. Changes reflect immediately without re-running install.
- **No secrets**: API keys, tokens, and credentials are never stored in this repo. Use environment variables or separate secure storage.
- **Manifest-driven**: A `manifest.toml` file defines the mapping from repo paths to system destinations.
- **Idempotent scripts**: Running install multiple times produces the same result. Safe to re-run.

### Directory Structure

```
dotlocal/
├── CLAUDE.md              # This file
├── manifest.toml          # Source → destination mappings
├── local.toml             # Machine-specific overrides (gitignored)
├── local.toml.example     # Template for local overrides
├── .secrets               # Environment variables (gitignored)
├── .secrets.example       # Template for required secrets
├── install.sh             # Main install script
├── sync.sh                # Thin wrapper: git pull + install.sh
├── uninstall.sh           # Remove symlinks, restore backups
├── shell/                 # Shell configs (.zshrc, .zprofile, etc.)
├── git/                   # Git config (.gitconfig, .gitignore_global)
├── vim/                   # Vim configuration
├── editor/                # Editor/IDE settings (VS Code, Vim, etc.)
├── terminal/              # Terminal emulator configs (iTerm2, Alacritty, etc.)
├── ssh/                   # SSH config (not keys)
├── brew/                  # Brewfile and related
├── fonts/                 # Font files to install
├── repos/                 # External repo definitions
└── launchd/               # launchd plist for auto-sync
```

### Manifest Format

`manifest.toml` uses TOML format to define symlink mappings:

```toml
# Each section is a category (matches directory names)
# "source" is relative to repo root
# "target" supports ~ expansion

[[shell]]
source = "shell/.zshrc"
target = "~/.zshrc"

[[shell]]
source = "shell/.zprofile"
target = "~/.zprofile"

[[git]]
source = "git/.gitconfig"
target = "~/.gitconfig"

[[editor]]
source = "editor/vscode/settings.json"
target = "~/Library/Application Support/Code/User/settings.json"

# Fonts are copied, not symlinked
[[fonts]]
source = "fonts/"
target = "~/Library/Fonts/"
mode = "copy"
```

### Local Overrides

Machine-specific configurations are stored in `local.toml` (gitignored). This file allows you to:

- **Add entries**: Define additional symlinks not in `manifest.toml`
- **Skip manifest entries**: Use `[[skip]]` sections to exclude specific manifest entries on this machine
- **Skip apps**: Use `[apps].skip` to prevent installation of specific Homebrew packages

Example syntax:

```toml
# Add machine-specific symlinks
[[shell]]
source = "shell/.zshrc.local"
target = "~/.zshrc.local"

# Skip a manifest entry
[[skip]]
category = "shell"
source = "shell/.zprofile"

# Skip Homebrew apps
[apps]
skip = ["docker", "visual-studio-code"]
```

See `local.toml.example` for a complete reference.

### Secrets

Secrets and credentials are stored in `.secrets` (gitignored, sourced by `.zshrc`). The install script validates that all required secrets are present before proceeding.

Example format:

```bash
# Required
export GITHUB_TOKEN="ghp_..."
export OPENAI_API_KEY="sk-..."

# Optional
export ANTHROPIC_API_KEY="sk-ant-..."
```

See `.secrets.example` for the complete list of required and optional secrets.

### External Repositories

The `repos/` directory contains TOML definitions for external repositories to clone during installation. This mechanism (to be implemented via `repos.toml`) enables:

- Cloning third-party dotfiles (e.g., `amix/vimrc` to `~/.vim_runtime`)
- Cloning personal projects (e.g., `dotagent` to `~/workspace/dotagent`)

### Scripts

| Script         | Purpose                                                                 |
| -------------- | ----------------------------------------------------------------------- |
| `install.sh`   | First-time setup: parse manifest, back up existing files, create symlinks, install fonts, install Homebrew packages, register launchd job |
| `sync.sh`      | Thin wrapper: git pull, then exec install.sh                           |
| `uninstall.sh` | Remove all symlinks, restore backups, unregister launchd job           |

### Auto-Sync (launchd)

A launchd plist runs `sync.sh` every 15 minutes:

- Pulls from remote (if configured)
- Re-applies symlinks for any new/changed files
- Logs output to `~/Library/Logs/dotlocal/sync.log`

## Conventions

### Adding New Configs

1. Place the config file in the appropriate category directory
2. Add an entry to `manifest.toml` with source and target paths
3. Run `./install.sh` to apply

### Backup Strategy

- Before creating a symlink, `install.sh` checks if a real file exists at the target
- If yes, it moves the file to `~/.dotlocal-backup/<timestamp>/<original-path>`
- Backups are not deleted automatically; manage them manually

### SSH Config

- Only `~/.ssh/config` is synced (connection settings, aliases)
- SSH keys are never stored in this repo
- Use 1Password, Secretive, or similar for key management

### Fonts

- Fonts are copied (not symlinked) to `~/Library/Fonts/`
- macOS picks them up automatically; no restart required

### Dependency Installation

All dependencies follow a check-then-install pattern:

- **Homebrew**: Installed automatically if missing using the official install script
- **Non-Homebrew tools**: Tools like `bun` and `gcloud` use their official installer scripts when not available via Homebrew
- **Idempotency**: Install scripts check for existing installations before attempting to install

## Tech Stack

| Component     | Choice        |
| ------------- | ------------- |
| Platform      | macOS only    |
| Scripting     | Bash          |
| Config format | TOML          |
| Auto-sync     | launchd       |
| Linking       | Symlinks      |

## Development Guidelines

- Scripts must be POSIX-compatible where possible, but can use Bash 3.2+ features (macOS default)
- All scripts must be idempotent
- Use `set -euo pipefail` at the top of all scripts
- Log actions to stdout; errors to stderr
- Exit codes: 0 = success, 1 = error, 2 = partial success (some operations failed)
