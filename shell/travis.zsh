# ==============================================================================
# travis.zsh - Personal Shell Customizations
# ==============================================================================
# This file contains aliases, functions, PATH modifications, and environment
# variables. It is sourced by oh-my-zsh as a custom plugin.
#
# Secrets (API keys, passwords, tokens) should NOT be in this file.
# Put them in ~/.secrets instead.
# ==============================================================================

# ==============================================================================
# PATH Configuration
# ==============================================================================
# Consolidated PATH exports. Order matters: earlier entries take precedence.

# Local binaries
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"

# Project-local node modules
export PATH="./node_modules/.bin:$PATH"

# Homebrew (Apple Silicon and Intel)
export PATH="/opt/homebrew/bin:/opt/bin:/usr/local/bin:$PATH"

# Go
export PATH="/usr/local/go/bin:$PATH"

# Database clients (optional, via Homebrew)
export PATH="$PATH:/opt/homebrew/opt/mysql-client/bin"
export PATH="$PATH:/opt/homebrew/opt/postgresql@16/bin"

# Tool-specific paths (added by installers)
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
export PATH="$HOME/.opencode/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

# ==============================================================================
# Environment Variables
# ==============================================================================

export WORKSPACE="$HOME/workspace"
export EDITOR="vim"
export CLICOLOR="xterm-color"
export BUN_INSTALL="$HOME/.bun"
export JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null)

# Disable oh-my-zsh compfix warnings
export ZSH_DISABLE_COMPFIX=true

# Kubernetes
export KUBECTX_IGNORE_FZF=1

# ==============================================================================
# Shell Options
# ==============================================================================

unsetopt share_history      # Don't share history between sessions
setopt APPEND_HISTORY       # Append to history file, don't overwrite

# ==============================================================================
# Aliases: Git
# ==============================================================================

alias g='git'
alias gp='git push origin $(git branch --show-current)'
alias gb='git branch'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline -20'
alias gcm='git commit -m'

alias base='git rebase -i'
alias cont='git rebase --continue'
alias abort='git rebase --abort'

# Delete branch locally and on remote
grmbr() {
    git branch -D "$1"
    git push origin --delete "$1"
}

# ==============================================================================
# Aliases: Docker & Kubernetes
# ==============================================================================

alias d='docker'
alias p='podman'
alias k='kubectl'
alias mk='minikube'
alias tf='terraform'

# ==============================================================================
# Aliases: File Operations
# ==============================================================================

alias ls='eza -lah -t modified --git --time-style long-iso'
alias ls-t='eza -lh -t modified --git --time-style long-iso --tree'
alias cat='bat'
alias ccat='/bin/cat'
alias rmf='rm -rf'

# ==============================================================================
# Aliases: Shell Management
# ==============================================================================

alias _s='source ~/.zshrc'

# ==============================================================================
# Functions
# ==============================================================================

# mkdir and cd into it
mkcd() { mkdir -p "$@" && cd "$_"; }

# BigTable emulator helper
bt() {
    BIGTABLE_EMULATOR_HOST=localhost:9035 cbt -creds=1 "$@"
}

# ==============================================================================
# Completions & Tool Integrations
# ==============================================================================

# Google Cloud SDK
if [[ -f '/opt/google-cloud-sdk/path.zsh.inc' ]]; then
    source '/opt/google-cloud-sdk/path.zsh.inc'
fi
if [[ -f '/opt/google-cloud-sdk/completion.zsh.inc' ]]; then
    source '/opt/google-cloud-sdk/completion.zsh.inc'
fi

# Bun completions
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

# Zoxide (smart cd)
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# Custom completions
fpath=(~/.zsh/completions $fpath)
autoload -U compinit && compinit

# ==============================================================================
# Terminal Integration
# ==============================================================================

# iTerm2: Set tab title to current directory name
if [[ -n "$ITERM_SESSION_ID" ]]; then
    export PROMPT_COMMAND='echo -ne "\033];${PWD##*/}\007"'
fi

# Colored man pages
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;33m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;42;30m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;36m'
