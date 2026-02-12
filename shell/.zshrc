# ==============================================================================
# .zshrc - Oh-My-Zsh Configuration
# ==============================================================================
# This file bootstraps oh-my-zsh and loads plugins. Personal customizations
# (aliases, functions, PATH, env vars) belong in travis.zsh.
# Secrets belong in ~/.secrets (sourced at the end).
# ==============================================================================

export ZSH="$HOME/.oh-my-zsh"

# Theme: using custom travis.zsh-theme
ZSH_THEME="travis"

# Plugins
plugins=(
    git
    colorize
    docker
    github
    golang
    iterm2
    kubectl
    node
    npm
    vscode
    pip
    python
    macos
    urltools
    zsh-syntax-highlighting
    zsh-autosuggestions
    zsh-completions
)

# Docker completion styling
zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

# Hide username in prompt when logged in as default user
export DEFAULT_USER=$(whoami)

# Initialize oh-my-zsh
source $ZSH/oh-my-zsh.sh

# Source secrets (API keys, tokens, etc.) if present
[[ -f "$HOME/.secrets" ]] && source "$HOME/.secrets"
