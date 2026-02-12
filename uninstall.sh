#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# dotlocal uninstall script
# ==============================================================================
# Removes symlinks created by install.sh and optionally restores backups.
#
# Usage: ./uninstall.sh [OPTIONS]
#
# Options:
#   --dry-run       Show what would be done without making changes
#   --home <dir>    Use <dir> instead of $HOME (for testing)
#   --restore       Restore files from most recent backup (if available)
#   --help          Show this help message
#
# Examples:
#   ./uninstall.sh --dry-run           # Preview what would be removed
#   ./uninstall.sh                     # Remove symlinks only
#   ./uninstall.sh --restore           # Remove symlinks and restore backups
# ==============================================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${HOME}"
DRY_RUN=false
RESTORE_BACKUP=false
CHANGES_MADE=0

# Manifest data (reuse parsing from install.sh concepts)
declare -a MANIFEST_SOURCES
declare -a MANIFEST_TARGETS
declare -a MANIFEST_MODES

# Logging functions (same as install.sh)
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_dry() { echo "[DRY-RUN] $*"; }
log_skip() { echo "[SKIP] $*"; }
log_ok() { echo "[OK] $*"; }

show_help() {
    sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --home)
                [[ -z "${2:-}" ]] && { log_error "--home requires a directory"; exit 1; }
                TARGET_HOME="$2"; shift 2 ;;
            --restore) RESTORE_BACKUP=true; shift ;;
            --help|-h) show_help ;;
            *) log_error "Unknown option: $1"; show_help ;;
        esac
    done
}

expand_tilde() {
    local path="$1"
    echo "${path/#\~/$TARGET_HOME}"
}

is_real_home() {
    [[ "$TARGET_HOME" == "$HOME" ]]
}

increment_changes() {
    ((CHANGES_MADE++)) || true
}

# Parse manifest.toml (simplified version - just need targets)
parse_manifest() {
    local manifest_file="$REPO_DIR/manifest.toml"
    [[ ! -f "$manifest_file" ]] && { log_error "manifest.toml not found"; exit 1; }
    
    local current_source="" current_target="" current_mode="symlink"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        if [[ "$line" =~ ^\[\[ ]]; then
            if [[ -n "$current_source" && -n "$current_target" ]]; then
                MANIFEST_SOURCES+=("$current_source")
                MANIFEST_TARGETS+=("$current_target")
                MANIFEST_MODES+=("$current_mode")
            fi
            current_source="" current_target="" current_mode="symlink"
        elif [[ "$line" =~ ^[[:space:]]*source[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            current_source="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*target[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            current_target="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*mode[[:space:]]*=[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
            current_mode="${BASH_REMATCH[1]}"
        fi
    done < "$manifest_file"
    
    # Don't forget the last entry
    if [[ -n "$current_source" && -n "$current_target" ]]; then
        MANIFEST_SOURCES+=("$current_source")
        MANIFEST_TARGETS+=("$current_target")
        MANIFEST_MODES+=("$current_mode")
    fi
    
    log_info "Parsed ${#MANIFEST_SOURCES[@]} entries from manifest"
}

# Find most recent backup directory
find_latest_backup() {
    local backup_base="${TARGET_HOME}/.dotlocal-backup"
    [[ ! -d "$backup_base" ]] && return 1
    
    # Find most recent backup by directory name (timestamp-based)
    local latest
    latest=$(ls -1d "$backup_base"/*/ 2>/dev/null | sort -r | head -1)
    [[ -z "$latest" ]] && return 1
    
    echo "$latest"
}

# Remove symlinks
remove_symlinks() {
    log_info "Removing symlinks..."
    local removed=0 skipped=0
    
    for i in "${!MANIFEST_TARGETS[@]}"; do
        local target
        target=$(expand_tilde "${MANIFEST_TARGETS[$i]}")
        local source="${REPO_DIR}/${MANIFEST_SOURCES[$i]}"
        
        if [[ -L "$target" ]]; then
            # Verify it points to our repo before removing
            local link_target
            link_target=$(readlink "$target")
            if [[ "$link_target" == "$source" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log_dry "rm $target"
                else
                    rm "$target"
                    log_ok "Removed: $target"
                    increment_changes
                fi
                ((removed++))
            else
                log_skip "$target (symlink points elsewhere: $link_target)"
                ((skipped++))
            fi
        elif [[ -e "$target" ]]; then
            log_skip "$target (not a symlink, leaving untouched)"
            ((skipped++))
        else
            log_skip "$target (does not exist)"
            ((skipped++))
        fi
    done
    
    log_info "Symlinks: $removed removed, $skipped skipped"
}

# Restore from backup
restore_backups() {
    if [[ "$RESTORE_BACKUP" != true ]]; then
        return
    fi
    
    log_info "Looking for backups to restore..."
    
    local backup_dir
    if ! backup_dir=$(find_latest_backup); then
        log_warn "No backup directory found at ${TARGET_HOME}/.dotlocal-backup/"
        return
    fi
    
    log_info "Found backup: $backup_dir"
    
    local restored=0
    for i in "${!MANIFEST_TARGETS[@]}"; do
        local target
        target=$(expand_tilde "${MANIFEST_TARGETS[$i]}")
        local relative_path="${target#$TARGET_HOME/}"
        local backup_file="${backup_dir}${relative_path}"
        
        if [[ -f "$backup_file" || -d "$backup_file" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "mv $backup_file -> $target"
            else
                # Ensure parent directory exists
                mkdir -p "$(dirname "$target")"
                mv "$backup_file" "$target"
                log_ok "Restored: $target"
                increment_changes
            fi
            ((restored++))
        fi
    done
    
    log_info "Restored $restored files from backup"
}

# Unregister launchd job
unregister_launchd() {
    if ! is_real_home; then
        log_skip "launchd unregistration (not on real \$HOME)"
        return
    fi
    
    local plist_path="${TARGET_HOME}/Library/LaunchAgents/com.dotlocal.sync.plist"
    
    if [[ ! -f "$plist_path" ]]; then
        log_skip "launchd job (plist not found)"
        return
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "launchctl unload $plist_path"
        log_dry "rm $plist_path"
    else
        launchctl unload "$plist_path" 2>/dev/null || true
        rm "$plist_path"
        log_ok "Unregistered launchd job"
        increment_changes
    fi
}

main() {
    parse_args "$@"
    
    log_info "dotlocal uninstall script"
    log_info "Repository: $REPO_DIR"
    log_info "Target home: $TARGET_HOME"
    [[ "$DRY_RUN" == true ]] && log_info "Mode: DRY RUN"
    [[ "$RESTORE_BACKUP" == true ]] && log_info "Restore backups: YES"
    
    parse_manifest
    remove_symlinks
    restore_backups
    unregister_launchd
    
    echo ""
    log_info "Uninstall complete."
    log_info "Changes made: $CHANGES_MADE"
}

main "$@"
