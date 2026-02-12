export ZSH="/Users/t/.oh-my-zsh"

ZSH_THEME="agnoster"

plugins=(
    git
    colorize
    docker
    github
    golang
    iterm2
    # kubectl
    # minikube
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

zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

export DEFAULT_USER=`whoami`
export POWERLEVEL9K_ALWAYS_SHOW_USER=true

source $ZSH/oh-my-zsh.sh

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/opt/google-cloud-sdk/path.zsh.inc' ]; then . '/opt/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/opt/google-cloud-sdk/completion.zsh.inc' ]; then . '/opt/google-cloud-sdk/completion.zsh.inc'; fi

# Added by Antigravity
export PATH="/Users/t/.antigravity/antigravity/bin:$PATH"

# opencode
export PATH=/Users/t/.opencode/bin:$PATH

# bun completions
[ -s "/Users/t/.bun/_bun" ] && source "/Users/t/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
