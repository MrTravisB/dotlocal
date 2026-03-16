# Project Instructions

## Overview

**dotlocal** is a personal dotfiles and configuration synchronization tool for macOS. It manages shell configs, editor settings, git configuration, terminal emulator preferences, Homebrew packages, SSH config, fonts, macOS system preferences, and services across multiple machines.

## Architecture

### Core Principles

- **Declarative**: A single `dotlocal.toml` file declares all desired system state. The sync tool computes a diff and applies only what's needed.
- **Symlink-based**: Config files live in this repo; symlinks point from target locations (e.g., `~/.zshrc`) back to the repo. Changes reflect immediately.
- **No secrets**: API keys, tokens, and credentials are never stored in this repo. Use `~/.secrets` or 1Password.
- **Idempotent**: Running `dotlocal sync` multiple times produces the same result. Safe to re-run.

### Directory Structure

```
dotlocal/
├── CLAUDE.md              # This file
├── dotlocal.toml          # Single source of truth for all configuration
├── local.toml             # Machine-specific overrides (gitignored)
├── local.toml.example     # Template for local overrides
├── .secrets.example       # Template for required secrets
├── cmd/dotlocal/          # Go CLI entry point
├── internal/              # Go packages
│   ├── config/            # TOML config parsing, local.toml merging
│   ├── engine/            # Sync engine (check-plan-apply), dependency resolution
│   ├── primitive/         # All primitive type implementations
│   ├── runner/            # Shell command execution
│   └── ui/                # Terminal output formatting
├── shell/                 # Shell configs (.zshrc, etc.)
├── git/                   # Git config (.gitconfig, .gitignore)
├── vim/                   # Vim configuration
├── editor/                # Editor settings, keybindings, extensions list
├── terminal/              # Terminal configs (Ghostty)
├── claude/                # Claude Code settings
├── fonts/                 # Font files (copied, not symlinked)
├── infra/langfuse/        # Langfuse docker-compose stack
├── macos/                 # macOS defaults (legacy, now in dotlocal.toml)
├── launchd/               # launchd plist for auto-sync
└── brew/                  # Legacy Brewfile (now in dotlocal.toml)
```

### Sync Tool

The `dotlocal` CLI is a compiled Go binary. It reads `dotlocal.toml` and synchronizes the machine to match.

```bash
dotlocal sync              # Apply changes
dotlocal sync --dry-run    # Preview what would change
dotlocal status            # Show drift from desired state
dotlocal list              # Show all managed primitives
dotlocal sync --type=symlink,brew_formula  # Filter by type
```

#### Three-Phase Engine

1. **Check**: Read-only scan of every primitive's current state (current, missing, drift, error)
2. **Plan**: For non-current primitives, compute what Apply would do. In `--dry-run`, print and exit.
3. **Apply**: Topologically sort by dependencies, then apply in order. Fail-forward by default.

#### Primitive Types

| Type | Description | State Check |
|------|-------------|-------------|
| `brew_tap` | Homebrew tap | `brew tap` output |
| `brew_formula` | Homebrew CLI tool | `brew list <name>` |
| `brew_cask` | Homebrew cask (fonts) | `brew list --cask <name>` |
| `app` | Desktop app (manual install) | `/Applications/<name>.app` exists |
| `cli_installer` | Tool via curl/sh script | `command -v <name>` |
| `symlink` | Config file symlink | `readlink` matches source |
| `copy` | File copy (fonts) | Binary comparison |
| `git_repo` | External git repo | Directory exists with `.git` |
| `editor_extension` | VS Code/editor extension | `--list-extensions` output |
| `macos_default` | macOS system preference | `defaults read` |
| `launchd` | Background service | Plist file exists |
| `docker_stack` | Docker compose stack | `docker compose ps` |
| `secret` | Required env variable | `os.Getenv` |
| `prompt` | Interactive one-time setup | Check command exit code |
| `encrypted` | 1Password + age asset | Key cache file exists |
| `patch` | File modification | Check command exit code |

### Config: `dotlocal.toml`

All desired state is declared in a single TOML file. Each entry uses `[[type]]` array-of-tables syntax:

```toml
[[brew_formula]]
name = "bat"

[[symlink]]
source = "shell/.zshrc"
target = "~/.zshrc"

[[app]]
name = "Slack"
url = "https://slack.com/downloads/mac"

[[macos_default]]
domain = "com.apple.dock"
key = "tilesize"
type = "int"
value = "41"
```

### Local Overrides

Machine-specific configurations are stored in `local.toml` (gitignored):

```toml
# Skip entries from dotlocal.toml
[[skip]]
type = "app"
name = "Docker Desktop"

# Add machine-specific symlinks
[[symlink]]
source = "shell/.zshrc.work"
target = "~/.zshrc.work"
```

### Dependency Resolution

Primitives can declare dependencies via `depends_on`. The engine topologically sorts before applying:

```toml
[[symlink]]
source = "shell/travis.zsh"
target = "~/.oh-my-zsh/custom/travis.zsh"
depends_on = ["git_repo:ohmyzsh"]
```

### Secrets

Secrets are stored in `~/.secrets` (gitignored, sourced by `.zshrc`). The sync tool validates required secrets are set. See `.secrets.example` for the template.

## Conventions

### Adding New Configs

1. Place the config file in the appropriate category directory
2. Add an entry to `dotlocal.toml`
3. Run `dotlocal sync` to apply

### Adding New Primitive Types

1. Create `internal/primitive/<type>.go` implementing the `Primitive` interface
2. Add config struct to `internal/config/config.go`
3. Wire into `buildPrimitives()` in `cmd/dotlocal/main.go`

## Tech Stack

| Component     | Choice        |
| ------------- | ------------- |
| Platform      | macOS only    |
| CLI tool      | Go            |
| Config format | TOML          |
| Auto-sync     | launchd       |
| Linking       | Symlinks      |

## Development Guidelines

- Keep primitives simple: Check reads state, Apply makes changes
- Use `runner.Run()` for shell commands, not `os/exec` directly
- Fail-forward by default (log error, continue to next primitive)
- Exit codes: 0 = success, 1 = fatal error, 2 = partial success
