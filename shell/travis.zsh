
#################################
# git helpers

grmbr() {
    git branch -D "$1";
    git push origin --delete "$1";
}

parse_git_branch() {
    git_branch=`git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'`;
    echo $git_branch
}

git_commit_branch() {
    BR=`parse_git_branch`
    if [[ "$BR" == "master" || "$BR" == "main" ]]; then
        BR="";
    else
        BR="$BR ";
    fi
    echo $BR;
}

# end git helpers
#################################

#mkdir and cd
function mkcd() { mkdir -p "$@" && cd "$_"; }

alias g='git'
alias gp='g push origin $(parse_git_branch)'
alias gb='g br'
alias gs='g st'
alias gd='g d'
alias gl='g l'
alias gcm='g cm'

alias base='g rebase -i ${1}'
alias cont='g rebase --continue'
alias abort='g rebase --abort'

alias tf='terraform'
# alias k='kubectl'
# alias kx='kubectx'
alias d='docker'
alias p='podman'
alias mk='minikube'
alias k='kubectl'
alias op='operator-sdk'

alias _s='source ~/.zshrc'

alias ls='exa -lah -t modified --git --time-style long-iso'
alias ls-t='exa -lh -t modified --git --time-style long-iso --tree'
alias cat='bat'
alias ccat='/bin/cat'
alias rmf='rm -rf'

alias mgo='# TODO: add MongoDB alias to .secrets'
alias tau='. _tau'

export WORKSPACE=~/workspace
export TAU_WORKSPACE=$WORKSPACE/acolyte/tau

export PATH=./node_modules/.bin:$PATH
export PATH=/opt/bin:/opt/homebrew/bin:$PATH
export PATH=$HOME/go/bin:$PATH
export PATH=/usr/local/go/bin:$PATH
export PATH=/usr/local/bin:$PATH
export PATH=$HOME/workspace/acolyte/dev/bin:$PATH
export PATH=$HOME/.local/bin:$PATH
export PATH=$PATH:/opt/homebrew/opt/mysql-client/bin
export PATH=$PATH:/opt/homebrew/opt/postgresql@16/bin
export PATH=~/.npm-global/bin:$PATH

export ZSH_DISABLE_COMPFIX=true
export EDITOR="vim"
export CLICOLOR="xterm-color"
export DISPLAY=:0.0

export JAVA_HOME=$(/usr/libexec/java_home)

unsetopt share_history
setopt APPEND_HISTORY

# make grep highlight results using color
export GREP_OPTIONS='--color=auto'

# Add some colour to LESS/MAN pages
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;33m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;42;30m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;36m'

export KUBECTX_IGNORE_FZF=1

export LANGFUSE_SECRET_KEY=""
export LANGFUSE_PUBLIC_KEY=""
export LANGFUSE_BASEURL="http://localhost:6543"

GCP_ZSH_PATH='/opt/google-cloud-sdk/path.zsh.inc'
GCP_ZSH_COMPLETION='/opt/google-cloud-sdk/completion.zsh.inc'
[ -f $GCP_ZSH_PATH ] && source $GCP_ZSH_PATH
[ -f $GCP_ZSH_COMPLETION ] && source $GCP_ZSH_COMPLETION

[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh

fpath=(~/.zsh/completions $fpath)
autoload -U compinit && compinit

if [ $ITERM_SESSION_ID ]; then
  export PROMPT_COMMAND='echo -ne "\033];${PWD##*/}\007"; ':"$PROMPT_COMMAND";
fi

bt() {
	BIGTABLE_EMULATOR_HOST=localhost:9035 cbt -creds=1 $@
}

#compdef gt
###-begin-gt-completions-###
#
# yargs command completion script
#
# Installation: gt completion >> ~/.zshrc
#    or gt completion >> ~/.zprofile on OSX.
#
_gt_yargs_completions()
{
  local reply
  local si=$IFS
  IFS=$'
' reply=($(COMP_CWORD="$((CURRENT-1))" COMP_LINE="$BUFFER" COMP_POINT="$CURSOR" gt --get-yargs-completions "${words[@]}"))
  IFS=$si
  _describe 'values' reply
}
compdef _gt_yargs_completions gt
###-end-gt-completions-###

export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"


