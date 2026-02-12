#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# dotlocal sync script
# ==============================================================================
# Thin wrapper that pulls latest changes and runs install.sh
# This is the entry point for the launchd auto-sync job.
#
# Usage: ./sync.sh [OPTIONS]
#   All options are passed through to install.sh
#
# Examples:
#   ./sync.sh                 # Pull and install
#   ./sync.sh --dry-run       # Pull and preview changes
# ==============================================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${HOME}/Library/Logs/dotlocal/sync.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Log function for sync-specific messages
log_sync() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

log_sync "Starting dotlocal sync..."

# Change to repo directory
cd "$REPO_DIR"

# Pull latest changes (if remote is configured)
if git remote | grep -q .; then
    log_sync "Pulling latest changes..."
    if ! git pull --ff-only 2>&1 | tee -a "$LOG_FILE"; then
        log_sync "ERROR: git pull failed. There may be local changes or conflicts."
        log_sync "Resolve conflicts manually, then re-run sync."
        exit 1
    fi
else
    log_sync "No remote configured, skipping git pull."
fi

# Run install.sh, passing through all arguments
log_sync "Running install.sh $*"
exec "$REPO_DIR/install.sh" "$@"
