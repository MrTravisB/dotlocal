function prompt_char {
    git branch >/dev/null 2>/dev/null && echo ' ●' && return
    echo ' ○'
}

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[magenta]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[yellow]%}!"
ZSH_THEME_GIT_PROMPT_UNTRACKED="%{$fg[yellow]%}?"
ZSH_THEME_GIT_PROMPT_CLEAN=""

PROMPT='%{$bg[red]%}%{$reset_color%}%{$fg[green]%}${PWD/#$HOME/~}/:%{$reset_color%}$(git_prompt_info)%{$fg[green]%}$(prompt_char)%{$reset_color%} '
