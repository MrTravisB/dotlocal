#!/bin/bash
input=$(cat)
MODEL=$(echo "$input" | jq -r '.model.display_name')
RAW_DIR=$(echo "$input" | jq -r '.workspace.current_dir')
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | awk '{printf "%.0f", $1}')
DIR="${RAW_DIR/#$HOME/~}"
BRANCH=$(cd "$RAW_DIR" && git branch --show-current 2>/dev/null)

CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
RESET='\033[0m'

if [ "$CTX" -ge 80 ]; then
  CTX_COLOR="$RED"
elif [ "$CTX" -ge 50 ]; then
  CTX_COLOR="$YELLOW"
else
  CTX_COLOR="$GREEN"
fi
CTX_DISPLAY="${CTX_COLOR}${CTX}%${RESET}"

if [ -n "$BRANCH" ]; then
  DIRTY=""
  BRANCH_COLOR="$GREEN"
  if ! (cd "$RAW_DIR" && git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]); then
    DIRTY="*"
    BRANCH_COLOR="$YELLOW"
  fi
  printf '%b' "${CYAN}${DIR}${RESET} ${BRANCH_COLOR}($BRANCH${DIRTY})${RESET} ${DIM}|${RESET} $MODEL ${DIM}|${RESET} ${CTX_DISPLAY}"
else
  printf '%b' "${CYAN}${DIR}${RESET} ${DIM}|${RESET} $MODEL ${DIM}|${RESET} ${CTX_DISPLAY}"
fi
