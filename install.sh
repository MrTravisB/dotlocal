#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# dotlocal install script
# ==============================================================================
# Usage: ./install.sh [OPTIONS]
#
# Options:
#   --dry-run       Show what would be done without making changes
#   --home <dir>    Use <dir> instead of $HOME (for testing)
#   --help          Show this help message
#
# Examples:
#   ./install.sh --dry-run                    # Preview changes
#   ./install.sh --home ~/dotlocal-test       # Test against alternate directory
#   ./install.sh                              # Real install
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${HOME}"
DRY_RUN=false
CHANGES_MADE=0
BACKUP_DIR=""
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SECRETS_NEED_ATTENTION=false

# Manifest data structures
declare -a MANIFEST_SOURCES
declare -a MANIFEST_TARGETS
declare -a MANIFEST_MODES
declare -a SKIP_SOURCES
declare -a SKIP_APPS

# ------------------------------------------------------------------------------
# Logging functions
# ------------------------------------------------------------------------------
log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_dry() {
    echo "[DRY-RUN] $*"
}

log_skip() {
    echo "[SKIP] $*"
}

log_ok() {
    echo "[OK] $*"
}

# ------------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------------
show_help() {
    sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --home)
                if [[ -z "${2:-}" ]]; then
                    log_error "--home requires a directory argument"
                    exit 1
                fi
                TARGET_HOME="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Utility functions
# ------------------------------------------------------------------------------
expand_tilde() {
    local path="$1"
    echo "${path/#\~/$TARGET_HOME}"
}

is_real_home() {
    [[ "$TARGET_HOME" == "$HOME" ]]
}

run_or_dry() {
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "$*"
    else
        "$@"
    fi
}

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "mkdir -p $dir"
        else
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    fi
}

increment_changes() {
    ((CHANGES_MADE++)) || true
}

is_skipped() {
    local source="$1"
    # Safe array iteration: handle empty arrays
    for skip_src in ${SKIP_SOURCES[@]+"${SKIP_SOURCES[@]}"}; do
        if [[ "$source" == "$skip_src" ]]; then
            return 0
        fi
    done
    return 1
}

is_app_skipped() {
    local app="$1"
    # Safe array iteration: handle empty arrays
    for skip_app in ${SKIP_APPS[@]+"${SKIP_APPS[@]}"}; do
        if [[ "$app" == "$skip_app" ]]; then
            return 0
        fi
    done
    return 1
}

backup_file() {
    local target="$1"
    
    # Ensure backup directory exists
    ensure_dir "$BACKUP_DIR"
    
    # Compute relative path from TARGET_HOME
    # This preserves directory structure in the backup
    local rel_path="${target#$TARGET_HOME/}"
    local backup_path="${BACKUP_DIR}/${rel_path}"
    local backup_parent="$(dirname "$backup_path")"
    
    # Ensure parent directory exists in backup location
    ensure_dir "$backup_parent"
    
    # Move the file
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would backup $target to $backup_path"
    else
        mv "$target" "$backup_path"
        log_info "Backed up: $target -> $backup_path"
        increment_changes
    fi
}

# ------------------------------------------------------------------------------
# Main installation functions (to be implemented)
# ------------------------------------------------------------------------------
install_homebrew() {
    log_info "Checking Homebrew..."
    
    # Check if brew command exists
    if command -v brew &> /dev/null; then
        log_ok "Homebrew already installed: $(brew --version | head -n1)"
        return 0
    fi
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "Homebrew installation (not on real \$HOME)"
        return 0
    fi
    
    # Dry-run mode: just log what would happen
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would install Homebrew using official install script"
        return 0
    fi
    
    # Install Homebrew using official script
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Ensure brew is in PATH for current session
    # The install script adds to shell rc files, but we need it now
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        # Apple Silicon
        eval "$(/opt/homebrew/bin/brew shellenv)"
        log_ok "Homebrew installed and added to PATH (Apple Silicon)"
    elif [[ -x "/usr/local/bin/brew" ]]; then
        # Intel
        eval "$(/usr/local/bin/brew shellenv)"
        log_ok "Homebrew installed and added to PATH (Intel)"
    else
        log_error "Homebrew installation completed but brew command not found"
        return 1
    fi
    
    increment_changes
}

install_oh_my_zsh() {
    log_info "Checking oh-my-zsh..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "oh-my-zsh installation (not on real \$HOME)"
        return 0
    fi
    
    local oh_my_zsh_dir="${TARGET_HOME}/.oh-my-zsh"
    local zsh_custom="${ZSH_CUSTOM:-${oh_my_zsh_dir}/custom}"
    
    # Check if oh-my-zsh is already installed
    if [[ -d "$oh_my_zsh_dir" ]]; then
        log_ok "oh-my-zsh already installed at $oh_my_zsh_dir"
    else
        # Install oh-my-zsh
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would install oh-my-zsh to $oh_my_zsh_dir"
        else
            log_info "Installing oh-my-zsh..."
            if sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
                log_ok "oh-my-zsh installed successfully"
                increment_changes
            else
                log_error "Failed to install oh-my-zsh"
                return 1
            fi
        fi
    fi
    
    # Install custom plugins
    log_info "Checking oh-my-zsh custom plugins..."
    
    local plugins_dir="${zsh_custom}/plugins"
    local plugins_updated=0
    local plugins_cloned=0
    
    # Ensure plugins directory exists
    if [[ "$DRY_RUN" == false && -d "$oh_my_zsh_dir" ]]; then
        ensure_dir "$plugins_dir"
    fi
    
    # -------------------------------------------------------------------------
    # zsh-syntax-highlighting
    # -------------------------------------------------------------------------
    local plugin_name="zsh-syntax-highlighting"
    local plugin_dir="${plugins_dir}/${plugin_name}"
    log_info "Checking ${plugin_name}..."
    
    if [[ -d "$plugin_dir" ]]; then
        # Directory exists, update it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would update $plugin_dir (git pull)"
        else
            log_info "Updating ${plugin_name}..."
            if git -C "$plugin_dir" pull; then
                log_ok "Updated ${plugin_name}"
                increment_changes
                ((plugins_updated++)) || true
            else
                log_warn "Failed to update ${plugin_name}"
            fi
        fi
    else
        # Directory does not exist, clone it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would clone https://github.com/zsh-users/${plugin_name}.git to $plugin_dir"
        else
            log_info "Cloning ${plugin_name}..."
            if git clone https://github.com/zsh-users/${plugin_name}.git "$plugin_dir"; then
                log_ok "Cloned ${plugin_name}"
                increment_changes
                ((plugins_cloned++)) || true
            else
                log_error "Failed to clone ${plugin_name}"
            fi
        fi
    fi
    
    # -------------------------------------------------------------------------
    # zsh-autosuggestions
    # -------------------------------------------------------------------------
    plugin_name="zsh-autosuggestions"
    plugin_dir="${plugins_dir}/${plugin_name}"
    log_info "Checking ${plugin_name}..."
    
    if [[ -d "$plugin_dir" ]]; then
        # Directory exists, update it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would update $plugin_dir (git pull)"
        else
            log_info "Updating ${plugin_name}..."
            if git -C "$plugin_dir" pull; then
                log_ok "Updated ${plugin_name}"
                increment_changes
                ((plugins_updated++)) || true
            else
                log_warn "Failed to update ${plugin_name}"
            fi
        fi
    else
        # Directory does not exist, clone it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would clone https://github.com/zsh-users/${plugin_name}.git to $plugin_dir"
        else
            log_info "Cloning ${plugin_name}..."
            if git clone https://github.com/zsh-users/${plugin_name}.git "$plugin_dir"; then
                log_ok "Cloned ${plugin_name}"
                increment_changes
                ((plugins_cloned++)) || true
            else
                log_error "Failed to clone ${plugin_name}"
            fi
        fi
    fi
    
    # -------------------------------------------------------------------------
    # zsh-completions
    # -------------------------------------------------------------------------
    plugin_name="zsh-completions"
    plugin_dir="${plugins_dir}/${plugin_name}"
    log_info "Checking ${plugin_name}..."
    
    if [[ -d "$plugin_dir" ]]; then
        # Directory exists, update it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would update $plugin_dir (git pull)"
        else
            log_info "Updating ${plugin_name}..."
            if git -C "$plugin_dir" pull; then
                log_ok "Updated ${plugin_name}"
                increment_changes
                ((plugins_updated++)) || true
            else
                log_warn "Failed to update ${plugin_name}"
            fi
        fi
    else
        # Directory does not exist, clone it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would clone https://github.com/zsh-users/${plugin_name}.git to $plugin_dir"
        else
            log_info "Cloning ${plugin_name}..."
            if git clone https://github.com/zsh-users/${plugin_name}.git "$plugin_dir"; then
                log_ok "Cloned ${plugin_name}"
                increment_changes
                ((plugins_cloned++)) || true
            else
                log_error "Failed to clone ${plugin_name}"
            fi
        fi
    fi
    
    # Summary
    if [[ "$DRY_RUN" == false ]]; then
        if [[ $((plugins_cloned + plugins_updated)) -gt 0 ]]; then
            log_ok "Plugins: $plugins_cloned cloned, $plugins_updated updated"
        else
            log_ok "All plugins up to date"
        fi
    fi
    
    return 0
}

parse_manifest() {
    log_info "Parsing manifest..."
    
    local manifest_file="${REPO_DIR}/manifest.toml"
    local local_file="${REPO_DIR}/local.toml"
    
    # Ensure manifest.toml exists
    if [[ ! -f "$manifest_file" ]]; then
        log_error "manifest.toml not found in $REPO_DIR"
        exit 1
    fi
    
    # Parse manifest.toml
    parse_toml_file "$manifest_file"
    
    # Parse local.toml if it exists
    if [[ -f "$local_file" ]]; then
        log_info "Found local.toml, processing overrides..."
        parse_local_toml "$local_file"
    fi
    
    log_ok "Parsed ${#MANIFEST_SOURCES[@]} manifest entries"
    if [[ ${#SKIP_SOURCES[@]:-0} -gt 0 ]]; then
        log_info "Skipping ${#SKIP_SOURCES[@]} entries from manifest"
    fi
    if [[ ${#SKIP_APPS[@]:-0} -gt 0 ]]; then
        log_info "Skipping ${#SKIP_APPS[@]} apps from installation"
    fi
}

# Parse a TOML file and add entries to manifest arrays
parse_toml_file() {
    local file="$1"
    local current_source=""
    local current_target=""
    local current_mode="symlink"
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi
        
        # Detect start of new entry: [[category]]
        if [[ "$line" =~ ^\[\[.*\]\][[:space:]]*$ ]]; then
            # Save previous entry if we have one
            if [[ -n "$current_source" && -n "$current_target" ]]; then
                MANIFEST_SOURCES+=("$current_source")
                MANIFEST_TARGETS+=("$current_target")
                MANIFEST_MODES+=("$current_mode")
            fi
            
            # Reset for new entry
            current_source=""
            current_target=""
            current_mode="symlink"
            continue
        fi
        
        # Parse source field
        if [[ "$line" =~ ^[[:space:]]*source[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            current_source="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Parse target field
        if [[ "$line" =~ ^[[:space:]]*target[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            current_target="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Parse mode field (optional)
        if [[ "$line" =~ ^[[:space:]]*mode[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            current_mode="${BASH_REMATCH[1]}"
            continue
        fi
    done < "$file"
    
    # Save last entry if exists
    if [[ -n "$current_source" && -n "$current_target" ]]; then
        MANIFEST_SOURCES+=("$current_source")
        MANIFEST_TARGETS+=("$current_target")
        MANIFEST_MODES+=("$current_mode")
    fi
}

# Parse local.toml for additions, skips, and app skips
parse_local_toml() {
    local file="$1"
    local current_source=""
    local current_target=""
    local current_mode="symlink"
    local in_skip_section=false
    local in_apps_section=false
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi
        
        # Detect [[skip]] section
        if [[ "$line" =~ ^\[\[skip\]\][[:space:]]*$ ]]; then
            # Save previous non-skip entry if exists
            if [[ "$in_skip_section" == false && -n "$current_source" && -n "$current_target" ]]; then
                MANIFEST_SOURCES+=("$current_source")
                MANIFEST_TARGETS+=("$current_target")
                MANIFEST_MODES+=("$current_mode")
            fi
            
            in_skip_section=true
            in_apps_section=false
            current_source=""
            current_target=""
            current_mode="symlink"
            continue
        fi
        
        # Detect [apps] section
        if [[ "$line" =~ ^\[apps\][[:space:]]*$ ]]; then
            # Save previous non-skip entry if exists
            if [[ "$in_skip_section" == false && -n "$current_source" && -n "$current_target" ]]; then
                MANIFEST_SOURCES+=("$current_source")
                MANIFEST_TARGETS+=("$current_target")
                MANIFEST_MODES+=("$current_mode")
            fi
            
            in_apps_section=true
            in_skip_section=false
            current_source=""
            current_target=""
            current_mode="symlink"
            continue
        fi
        
        # Detect start of new addition entry: [[category]]
        if [[ "$line" =~ ^\[\[.*\]\][[:space:]]*$ ]]; then
            # Save previous non-skip entry if exists
            if [[ "$in_skip_section" == false && -n "$current_source" && -n "$current_target" ]]; then
                MANIFEST_SOURCES+=("$current_source")
                MANIFEST_TARGETS+=("$current_target")
                MANIFEST_MODES+=("$current_mode")
            fi
            
            in_skip_section=false
            in_apps_section=false
            current_source=""
            current_target=""
            current_mode="symlink"
            continue
        fi
        
        # Parse source field
        if [[ "$line" =~ ^[[:space:]]*source[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            current_source="${BASH_REMATCH[1]}"
            
            # If in skip section, add to skip list immediately
            if [[ "$in_skip_section" == true ]]; then
                SKIP_SOURCES+=("$current_source")
                current_source=""
            fi
            continue
        fi
        
        # Parse target field
        if [[ "$line" =~ ^[[:space:]]*target[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            current_target="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Parse mode field (optional)
        if [[ "$line" =~ ^[[:space:]]*mode[[:space:]]*=[[:space:]]*=\"(.*)\"[[:space:]]*$ ]]; then
            current_mode="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Parse apps skip array
        # Format: skip = ["app1", "app2", "app3"]
        if [[ "$in_apps_section" == true && "$line" =~ ^[[:space:]]*skip[[:space:]]*=[[:space:]]*\[(.*)\][[:space:]]*$ ]]; then
            local apps_str="${BASH_REMATCH[1]}"
            # Extract quoted app names
            while [[ "$apps_str" =~ \"([^\"]+)\" ]]; do
                SKIP_APPS+=("${BASH_REMATCH[1]}")
                apps_str="${apps_str#*\"${BASH_REMATCH[1]}\"}"
            done
            continue
        fi
    done < "$file"
    
    # Save last entry if exists and not in skip section
    if [[ "$in_skip_section" == false && -n "$current_source" && -n "$current_target" ]]; then
        MANIFEST_SOURCES+=("$current_source")
        MANIFEST_TARGETS+=("$current_target")
        MANIFEST_MODES+=("$current_mode")
    fi
}

create_symlinks() {
    log_info "Creating symlinks..."
    
    local created=0
    local skipped=0
    
    # Iterate over all manifest entries
    for i in "${!MANIFEST_SOURCES[@]}"; do
        local source="${MANIFEST_SOURCES[$i]}"
        local target="${MANIFEST_TARGETS[$i]}"
        local mode="${MANIFEST_MODES[$i]}"
        
        # Skip if source is in skip list
        if is_skipped "$source"; then
            log_skip "$source (in skip list)"
            ((skipped++)) || true
            continue
        fi
        
        # Expand tilde in target path
        target="$(expand_tilde "$target")"
        
        # Resolve source to absolute path
        local abs_source="${REPO_DIR}/${source}"
        
        # Check if source exists
        if [[ ! -e "$abs_source" ]]; then
            log_warn "Source not found: $abs_source (skipping)"
            ((skipped++)) || true
            continue
        fi
        
        # Ensure parent directory of target exists
        local target_parent="$(dirname "$target")"
        ensure_dir "$target_parent"
        
        # Handle symlink mode
        if [[ "$mode" == "symlink" ]]; then
            # Check if target exists
            if [[ -e "$target" || -L "$target" ]]; then
                # Check if it's already the correct symlink
                if [[ -L "$target" ]]; then
                    local current_link="$(readlink "$target")"
                    if [[ "$current_link" == "$abs_source" ]]; then
                        log_ok "Already linked: $target -> $abs_source"
                        continue
                    fi
                fi
                
                # Target exists but is not the correct symlink, back it up
                backup_file "$target"
            fi
            
            # Create symlink
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "ln -s $abs_source $target"
            else
                ln -s "$abs_source" "$target"
                log_info "Symlinked: $target -> $abs_source"
                increment_changes
            fi
            ((created++)) || true
            
        # Handle copy mode
        elif [[ "$mode" == "copy" ]]; then
            # If source is a directory, copy all font files (*.ttf, *.otf) flat into target
            if [[ -d "$abs_source" ]]; then
                ensure_dir "$target"
                local font_count=0
                while IFS= read -r -d '' font_file; do
                    local font_name
                    font_name="$(basename "$font_file")"
                    local font_target="${target}/${font_name}"
                    if [[ -f "$font_target" ]] && cmp -s "$font_file" "$font_target"; then
                        ((skipped++)) || true
                        continue
                    fi
                    if [[ "$DRY_RUN" == true ]]; then
                        log_dry "cp $font_file -> $font_target"
                    else
                        cp "$font_file" "$font_target"
                        increment_changes
                    fi
                    ((font_count++)) || true
                done < <(find "$abs_source" -type f \( -name "*.ttf" -o -name "*.otf" \) -print0)
                if [[ $font_count -gt 0 ]]; then
                    log_info "Copied $font_count font(s) to $target"
                    ((created++)) || true
                else
                    log_skip "No font files found in $abs_source"
                    ((skipped++)) || true
                fi
            else
                # Single file copy
                if [[ -f "$target" ]] && cmp -s "$abs_source" "$target"; then
                    log_skip "$target (unchanged)"
                    ((skipped++)) || true
                else
                    if [[ "$DRY_RUN" == true ]]; then
                        log_dry "cp $abs_source -> $target"
                    else
                        ensure_dir "$(dirname "$target")"
                        cp "$abs_source" "$target"
                        log_info "Copied: $abs_source -> $target"
                        increment_changes
                    fi
                    ((created++)) || true
                fi
            fi
            
        else
            log_warn "Unknown mode '$mode' for $source (skipping)"
            ((skipped++)) || true
        fi
    done
    
    log_ok "Processed $((created + skipped)) entries: $created created/updated, $skipped skipped"
}

process_brewfile() {
    log_info "Processing Brewfile..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "Brewfile processing (not on real \$HOME)"
        return 0
    fi
    
    # Check if Brewfile exists
    local brewfile="${REPO_DIR}/brew/Brewfile"
    if [[ ! -f "$brewfile" ]]; then
        log_warn "Brewfile not found at $brewfile (skipping)"
        return 0
    fi
    
    # Determine which Brewfile to use
    local target_brewfile="$brewfile"
    local temp_brewfile=""
    
    # If we have apps to skip, create a temporary Brewfile
    if [[ ${#SKIP_APPS[@]:-0} -gt 0 ]]; then
        log_info "Creating temporary Brewfile with ${#SKIP_APPS[@]} apps skipped"
        temp_brewfile="${REPO_DIR}/.brewfile.tmp"
        
        # Create temporary Brewfile with skipped apps commented out
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would create temporary Brewfile at $temp_brewfile"
        else
            # Process the Brewfile line by line
            while IFS= read -r line; do
                local should_skip=false
                
                # Check if this line defines a brew or cask
                if [[ "$line" =~ ^[[:space:]]*(brew|cask)[[:space:]]+\"([^\"]+)\" ]]; then
                    local app_name="${BASH_REMATCH[2]}"
                    
                    # Check if this app should be skipped
                    if is_app_skipped "$app_name"; then
                        echo "# [SKIPPED by local.toml] $line" >> "$temp_brewfile"
                        should_skip=true
                    fi
                fi
                
                # Write the line as-is if not skipped
                if [[ "$should_skip" == false ]]; then
                    echo "$line" >> "$temp_brewfile"
                fi
            done < "$brewfile"
            
            log_info "Temporary Brewfile created"
        fi
        
        target_brewfile="$temp_brewfile"
    fi
    
    # Run brew bundle
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would run: brew bundle --file=$target_brewfile --no-lock"
        if [[ -n "$temp_brewfile" ]]; then
            log_dry "Would remove temporary Brewfile: $temp_brewfile"
        fi
    else
        log_info "Running brew bundle..."
        
        # Run brew bundle and capture exit code
        # brew bundle returns 0 if successful, including when packages are installed
        if brew bundle --file="$target_brewfile" --no-lock; then
            log_ok "Brew bundle completed successfully"
            # Track that we made changes (brew bundle was run)
            # Note: We can't easily detect if packages were actually installed,
            # so we track that the operation ran successfully
            increment_changes
        else
            log_error "Brew bundle failed"
            # Clean up temp file before returning
            if [[ -n "$temp_brewfile" && -f "$temp_brewfile" ]]; then
                rm -f "$temp_brewfile"
            fi
            return 1
        fi
        
        # Clean up temporary Brewfile
        if [[ -n "$temp_brewfile" && -f "$temp_brewfile" ]]; then
            rm -f "$temp_brewfile"
            log_info "Removed temporary Brewfile"
        fi
    fi
    
    return 0
}

install_cli_tools() {
    log_info "Installing CLI tools..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "CLI tools installation (not on real \$HOME)"
        return 0
    fi
    
    local tools_installed=0
    
    # -------------------------------------------------------------------------
    # bun
    # -------------------------------------------------------------------------
    log_info "Checking bun..."
    if command -v bun &> /dev/null; then
        log_ok "bun already installed: $(bun --version)"
    else
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would install bun using official installer"
        else
            log_info "Installing bun..."
            if curl -fsSL https://bun.sh/install | bash; then
                log_ok "bun installed successfully"
                increment_changes
                ((tools_installed++)) || true
            else
                log_error "Failed to install bun"
            fi
        fi
    fi
    
    # -------------------------------------------------------------------------
    # google-cloud-sdk (gcloud)
    # -------------------------------------------------------------------------
    log_info "Checking google-cloud-sdk..."
    if command -v gcloud &> /dev/null; then
        log_ok "google-cloud-sdk already installed: $(gcloud version --format='value(core)' 2>/dev/null || echo 'unknown')"
    else
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would install google-cloud-sdk using official installer"
        else
            log_info "Installing google-cloud-sdk..."
            if curl https://sdk.cloud.google.com | bash -s -- --disable-prompts; then
                log_ok "google-cloud-sdk installed successfully"
                increment_changes
                ((tools_installed++)) || true
            else
                log_error "Failed to install google-cloud-sdk"
            fi
        fi
    fi
    
    # -------------------------------------------------------------------------
    # opencode
    # -------------------------------------------------------------------------
    log_info "Checking opencode..."
    if command -v opencode &> /dev/null; then
        log_ok "opencode already installed: $(opencode --version 2>/dev/null || echo 'version unknown')"
    else
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would install opencode using npm"
        else
            # Check if npm is available
            if ! command -v npm &> /dev/null; then
                log_warn "npm not found, cannot install opencode (install Node.js first)"
            else
                log_info "Installing opencode..."
                if npm install -g opencode; then
                    log_ok "opencode installed successfully"
                    increment_changes
                    ((tools_installed++)) || true
                else
                    log_error "Failed to install opencode"
                fi
            fi
        fi
    fi
    
    # Summary
    if [[ "$DRY_RUN" == false && "$tools_installed" -gt 0 ]]; then
        log_ok "Installed $tools_installed CLI tool(s)"
    fi
    
    return 0
}

clone_repos() {
    log_info "Cloning external repos..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "External repos cloning (not on real \$HOME)"
        return 0
    fi
    
    # Ensure workspace directory exists
    local workspace_dir="${TARGET_HOME}/workspace"
    ensure_dir "$workspace_dir"
    
    local repos_cloned=0
    local repos_updated=0
    
    # -------------------------------------------------------------------------
    # amix/vimrc
    # -------------------------------------------------------------------------
    local vim_target="${TARGET_HOME}/.vim_runtime"
    log_info "Checking amix/vimrc..."
    
    if [[ -d "$vim_target" ]]; then
        # Directory exists, update it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would update $vim_target (git pull)"
        else
            log_info "Updating amix/vimrc..."
            if git -C "$vim_target" pull; then
                log_ok "Updated amix/vimrc"
                increment_changes
                ((repos_updated++)) || true
            else
                log_warn "Failed to update amix/vimrc"
            fi
        fi
    else
        # Directory does not exist, clone it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would clone https://github.com/amix/vimrc.git to $vim_target"
            log_dry "Would run $vim_target/install_awesome_vimrc.sh"
        else
            log_info "Cloning amix/vimrc..."
            if git clone --depth=1 https://github.com/amix/vimrc.git "$vim_target"; then
                log_ok "Cloned amix/vimrc"
                
                # Run installation script
                if [[ -f "$vim_target/install_awesome_vimrc.sh" ]]; then
                    log_info "Running install_awesome_vimrc.sh..."
                    if bash "$vim_target/install_awesome_vimrc.sh"; then
                        log_ok "Installed awesome vimrc"
                    else
                        log_warn "Failed to run install_awesome_vimrc.sh"
                    fi
                fi
                
                increment_changes
                ((repos_cloned++)) || true
            else
                log_error "Failed to clone amix/vimrc"
            fi
        fi
    fi
    
    # -------------------------------------------------------------------------
    # mrtravisb/dotagent
    # -------------------------------------------------------------------------
    local dotagent_target="${workspace_dir}/dotagent"
    log_info "Checking mrtravisb/dotagent..."
    
    if [[ -d "$dotagent_target" ]]; then
        # Directory exists, update it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would update $dotagent_target (git pull)"
        else
            log_info "Updating mrtravisb/dotagent..."
            if git -C "$dotagent_target" pull; then
                log_ok "Updated mrtravisb/dotagent"
                increment_changes
                ((repos_updated++)) || true
            else
                log_warn "Failed to update mrtravisb/dotagent"
            fi
        fi
    else
        # Directory does not exist, clone it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would clone https://github.com/mrtravisb/dotagent.git to $dotagent_target"
        else
            log_info "Cloning mrtravisb/dotagent..."
            if git clone https://github.com/mrtravisb/dotagent.git "$dotagent_target"; then
                log_ok "Cloned mrtravisb/dotagent"
                increment_changes
                ((repos_cloned++)) || true
            else
                log_error "Failed to clone mrtravisb/dotagent"
            fi
        fi
    fi
    
    # Summary
    if [[ "$DRY_RUN" == false ]]; then
        if [[ $((repos_cloned + repos_updated)) -gt 0 ]]; then
            log_ok "Repos: $repos_cloned cloned, $repos_updated updated"
        else
            log_ok "All repos up to date"
        fi
    fi
    
    return 0
}

install_powerline_fonts() {
    log_info "Installing powerline fonts..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "Powerline fonts installation (not on real \$HOME)"
        return 0
    fi
    
    # Define target directory
    local fonts_dir="${TARGET_HOME}/.local/share/fonts"
    local powerline_dir="${fonts_dir}/powerline-fonts"
    
    # Ensure fonts directory exists
    ensure_dir "$fonts_dir"
    
    # Check if powerline fonts repo exists
    if [[ -d "$powerline_dir" ]]; then
        # Directory exists, optionally update
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would update $powerline_dir (git pull)"
        else
            log_info "Updating powerline fonts repo..."
            if git -C "$powerline_dir" pull; then
                log_ok "Updated powerline fonts repo"
                
                # Run install script after update
                if [[ -f "$powerline_dir/install.sh" ]]; then
                    log_info "Running powerline fonts install.sh..."
                    if bash "$powerline_dir/install.sh"; then
                        log_ok "Powerline fonts installed/updated successfully"
                        increment_changes
                    else
                        log_warn "Failed to run powerline fonts install.sh"
                    fi
                fi
            else
                log_warn "Failed to update powerline fonts repo"
            fi
        fi
    else
        # Directory does not exist, clone it
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would clone https://github.com/powerline/fonts.git to $powerline_dir"
            log_dry "Would run $powerline_dir/install.sh"
        else
            log_info "Cloning powerline fonts..."
            if git clone --depth=1 https://github.com/powerline/fonts.git "$powerline_dir"; then
                log_ok "Cloned powerline fonts repo"
                
                # Run installation script
                if [[ -f "$powerline_dir/install.sh" ]]; then
                    log_info "Running powerline fonts install.sh..."
                    if bash "$powerline_dir/install.sh"; then
                        log_ok "Powerline fonts installed successfully"
                        increment_changes
                    else
                        log_warn "Failed to run powerline fonts install.sh"
                    fi
                else
                    log_warn "install.sh not found in powerline fonts repo"
                fi
            else
                log_error "Failed to clone powerline fonts"
            fi
        fi
    fi
    
    return 0
}

validate_secrets() {
    log_info "Validating secrets..."
    
    local secrets_file="${REPO_DIR}/.secrets"
    local secrets_example="${REPO_DIR}/.secrets.example"
    local target_secrets="${TARGET_HOME}/.secrets"
    
    # Check if .secrets file exists
    if [[ ! -f "$secrets_file" ]]; then
        log_warn ".secrets file not found in repository"
        
        # Check if .secrets.example exists
        if [[ -f "$secrets_example" ]]; then
            # Copy .secrets.example to TARGET_HOME/.secrets
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "Would copy $secrets_example to $target_secrets"
            else
                cp "$secrets_example" "$target_secrets"
                log_info "Copied .secrets.example to $target_secrets"
                SECRETS_NEED_ATTENTION=true
                increment_changes
            fi
        else
            log_warn ".secrets.example not found - cannot create .secrets template"
        fi
        return 0
    fi
    
    # .secrets exists, validate required secrets
    log_info "Found .secrets file, checking required secrets..."
    
    # Check if .secrets.example exists to get list of required secrets
    if [[ ! -f "$secrets_example" ]]; then
        log_warn ".secrets.example not found, cannot validate required secrets"
        return 0
    fi
    
    # Parse required secrets from .secrets.example
    # Required secrets are in the section between "REQUIRED SECRETS" and "OPTIONAL SECRETS"
    local required_secrets=()
    local in_required_section=false
    
    while IFS= read -r line; do
        # Detect start of required section
        if [[ "$line" =~ REQUIRED[[:space:]]SECRETS ]]; then
            in_required_section=true
            continue
        fi
        
        # Detect end of required section (start of optional section)
        if [[ "$line" =~ OPTIONAL[[:space:]]SECRETS ]]; then
            in_required_section=false
            break
        fi
        
        # Parse export statements in required section
        if [[ "$in_required_section" == true && "$line" =~ ^[[:space:]]*export[[:space:]]+([A-Z_]+)= ]]; then
            required_secrets+=("${BASH_REMATCH[1]}")
        fi
    done < "$secrets_example"
    
    # If no required secrets found, we're done
    if [[ ${#required_secrets[@]} -eq 0 ]]; then
        log_ok "No required secrets to validate"
        return 0
    fi
    
    # Source .secrets in a subshell to check values
    local missing_secrets=()
    for secret_name in "${required_secrets[@]}"; do
        # Check if the secret is set and non-empty after sourcing .secrets
        # Use a subshell to avoid polluting current environment
        local secret_value
        secret_value=$(bash -c "source '$secrets_file' 2>/dev/null && echo \"\${$secret_name:-}\"")
        
        if [[ -z "$secret_value" ]]; then
            missing_secrets+=("$secret_name")
        fi
    done
    
    # Report results
    if [[ ${#missing_secrets[@]} -eq 0 ]]; then
        log_ok "All ${#required_secrets[@]} required secret(s) are set"
    else
        log_warn "Missing ${#missing_secrets[@]} required secret(s):"
        for secret_name in "${missing_secrets[@]}"; do
            log_warn "  - $secret_name"
        done
        log_warn "Update your .secrets file with the missing values"
    fi
    
    return 0
}

setup_ssh_key() {
    log_info "Setting up SSH key..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "SSH key generation (not on real \$HOME)"
        return 0
    fi
    
    # Define paths
    local ssh_dir="${TARGET_HOME}/.ssh"
    local ssh_key="${ssh_dir}/id_rsa"
    
    # Ensure .ssh directory exists with proper permissions
    if [[ ! -d "$ssh_dir" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "mkdir -p $ssh_dir"
            log_dry "chmod 700 $ssh_dir"
        else
            mkdir -p "$ssh_dir"
            chmod 700 "$ssh_dir"
            log_info "Created .ssh directory with permissions 700"
        fi
    else
        # Verify permissions are correct
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "chmod 700 $ssh_dir"
        else
            chmod 700 "$ssh_dir"
        fi
    fi
    
    # Check if SSH key already exists
    if [[ -f "$ssh_key" ]]; then
        log_ok "SSH key already exists at $ssh_key"
        return 0
    fi
    
    # Key doesn't exist, generate it
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would prompt for email address"
        log_dry "Would generate SSH key: ssh-keygen -t rsa -b 4096 -C <email> -f $ssh_key -N \"\""
        return 0
    fi
    
    # Prompt for email address
    local email=""
    echo ""
    echo "=========================================="
    echo "SSH Key Generation"
    echo "=========================================="
    read -p "Enter your email address for SSH key: " email
    
    # Validate email is not empty
    if [[ -z "$email" ]]; then
        log_warn "No email provided, skipping SSH key generation"
        return 0
    fi
    
    # Generate SSH key
    log_info "Generating SSH key..."
    if ssh-keygen -t rsa -b 4096 -C "$email" -f "$ssh_key" -N ""; then
        log_ok "SSH key generated successfully at $ssh_key"
        log_info "Public key: ${ssh_key}.pub"
        echo ""
        log_info "To add this key to GitHub:"
        log_info "  1. Copy your public key: pbcopy < ${ssh_key}.pub"
        log_info "  2. Go to GitHub Settings > SSH and GPG keys"
        log_info "  3. Click 'New SSH key' and paste your key"
        echo ""
        increment_changes
    else
        log_error "Failed to generate SSH key"
        return 1
    fi
    
    return 0
}

register_launchd() {
    log_info "Registering launchd job..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "launchd registration (not on real \$HOME)"
        return 0
    fi
    
    # Define paths
    local plist_source="${REPO_DIR}/launchd/com.dotlocal.sync.plist"
    local plist_target="${TARGET_HOME}/Library/LaunchAgents/com.dotlocal.sync.plist"
    local log_dir="${TARGET_HOME}/Library/Logs/dotlocal"
    
    # Check if source plist exists
    if [[ ! -f "$plist_source" ]]; then
        log_warn "launchd plist not found at $plist_source"
        log_warn "This is a future backlog item - skipping for now"
        return 0
    fi
    
    # Ensure LaunchAgents directory exists
    ensure_dir "${TARGET_HOME}/Library/LaunchAgents"
    
    # Ensure log directory exists
    ensure_dir "$log_dir"
    
    # Copy plist to LaunchAgents
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "sed 's|__HOME__|$TARGET_HOME|g' $plist_source > $plist_target"
        log_dry "launchctl unload $plist_target 2>/dev/null || true"
        log_dry "launchctl load $plist_target"
    else
        # Copy the plist and replace __HOME__ placeholder with actual home directory
        sed "s|__HOME__|${TARGET_HOME}|g" "$plist_source" > "$plist_target"
        log_info "Copied plist to $plist_target (replaced __HOME__ with ${TARGET_HOME})"
        
        # Unload if already loaded (suppress errors if not loaded)
        launchctl unload "$plist_target" 2>/dev/null || true
        
        # Load the plist
        if launchctl load "$plist_target"; then
            log_ok "launchd job registered and loaded"
            increment_changes
        else
            log_error "Failed to load launchd plist"
            return 1
        fi
    fi
    
    return 0
}

patch_vscode_insiders_product_json() {
    log_info "Patching VS Code Insiders product.json for OpenVSX..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "VS Code Insiders product.json patching (not on real \$HOME)"
        return 0
    fi
    
    # Define path to VS Code Insiders product.json
    local product_json="/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/product.json"
    
    # Check if VS Code Insiders is installed
    if [[ ! -f "$product_json" ]]; then
        log_skip "VS Code Insiders product.json not found (app not installed)"
        return 0
    fi
    
    # Dry-run mode
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would patch $product_json to add OpenVSX configuration"
        return 0
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required to patch product.json but is not installed"
        return 1
    fi
    
    # Create backup of product.json
    local backup_file="${product_json}.backup.$(date +%Y%m%d_%H%M%S)"
    if ! cp "$product_json" "$backup_file"; then
        log_error "Failed to create backup of product.json"
        return 1
    fi
    log_info "Created backup: $backup_file"
    
    # Patch the JSON file with OpenVSX configuration
    local temp_json="${product_json}.tmp"
    if jq '.extensionsGallery = {
        "serviceUrl": "https://open-vsx.org/vscode/gallery",
        "itemUrl": "https://open-vsx.org/vscode/item"
    } | .linkProtectionTrustedDomains = (.linkProtectionTrustedDomains // [] | if (. | index("https://open-vsx.org")) then . else . + ["https://open-vsx.org"] end)' "$product_json" > "$temp_json"; then
        # Replace original file
        if mv "$temp_json" "$product_json"; then
            log_ok "Patched VS Code Insiders product.json for OpenVSX"
            increment_changes
            return 0
        else
            log_error "Failed to replace product.json"
            rm -f "$temp_json"
            return 1
        fi
    else
        log_error "Failed to patch product.json with jq"
        rm -f "$temp_json"
        return 1
    fi
}

install_editor_extensions() {
    log_info "Installing editor extensions..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "Editor extensions installation (not on real \$HOME)"
        return 0
    fi
    
    # Define paths
    local extensions_file="${REPO_DIR}/editor/extensions.txt"
    local antigravity_bin="/Users/t/.antigravity/antigravity/bin/antigravity"
    local vscode_insiders_bin="/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code"
    
    # Check if extensions file exists
    if [[ ! -f "$extensions_file" ]]; then
        log_warn "Extensions file not found at $extensions_file (skipping)"
        return 0
    fi
    
    # Check which editors are installed
    local antigravity_available=false
    local vscode_insiders_available=false
    
    if [[ -x "$antigravity_bin" ]]; then
        antigravity_available=true
        log_info "Antigravity detected"
    else
        log_skip "Antigravity not found at $antigravity_bin"
    fi
    
    if [[ -x "$vscode_insiders_bin" ]]; then
        vscode_insiders_available=true
        log_info "VS Code Insiders detected"
    else
        log_skip "VS Code Insiders not found"
    fi
    
    # If neither editor is available, skip
    if [[ "$antigravity_available" == false && "$vscode_insiders_available" == false ]]; then
        log_skip "No compatible editors found"
        return 0
    fi
    
    # Count extensions
    local total_extensions=0
    while IFS= read -r extension_id; do
        # Skip empty lines and comments
        if [[ -z "$extension_id" || "$extension_id" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        ((total_extensions++)) || true
    done < "$extensions_file"
    
    log_info "Found $total_extensions extensions to install"
    
    # Dry-run mode
    if [[ "$DRY_RUN" == true ]]; then
        while IFS= read -r extension_id; do
            # Skip empty lines and comments
            if [[ -z "$extension_id" || "$extension_id" =~ ^[[:space:]]*# ]]; then
                continue
            fi
            
            if [[ "$antigravity_available" == true ]]; then
                log_dry "Would run: $antigravity_bin --install-extension $extension_id"
            fi
            
            if [[ "$vscode_insiders_available" == true ]]; then
                log_dry "Would run: $vscode_insiders_bin --install-extension $extension_id"
            fi
        done < "$extensions_file"
        return 0
    fi
    
    # Install extensions
    local installed_count=0
    local skipped_count=0
    local current=0
    
    while IFS= read -r extension_id; do
        # Skip empty lines and comments
        if [[ -z "$extension_id" || "$extension_id" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        ((current++)) || true
        log_info "[$current/$total_extensions] Installing $extension_id..."
        
        # Install to Antigravity
        if [[ "$antigravity_available" == true ]]; then
            if "$antigravity_bin" --install-extension "$extension_id" &> /dev/null; then
                log_ok "  → Antigravity: installed"
                ((installed_count++)) || true
            else
                log_warn "  → Antigravity: failed or already installed"
                ((skipped_count++)) || true
            fi
        fi
        
        # Install to VS Code Insiders
        if [[ "$vscode_insiders_available" == true ]]; then
            if "$vscode_insiders_bin" --install-extension "$extension_id" &> /dev/null; then
                log_ok "  → VS Code Insiders: installed"
                ((installed_count++)) || true
            else
                log_warn "  → VS Code Insiders: failed or already installed"
                ((skipped_count++)) || true
            fi
        fi
    done < "$extensions_file"
    
    log_ok "Extensions processed: $installed_count installed, $skipped_count skipped/failed"
    
    if [[ $installed_count -gt 0 ]]; then
        increment_changes
    fi
    
    return 0
}

apply_macos_defaults() {
    log_info "Applying macOS defaults..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "macOS defaults (not on real \$HOME)"
        return 0
    fi
    
    # Define path to defaults script
    local defaults_script="${REPO_DIR}/macos/defaults.sh"
    
    # Check if defaults script exists
    if [[ ! -f "$defaults_script" ]]; then
        log_skip "macOS defaults script not found at $defaults_script"
        return 0
    fi
    
    # Check if script is executable
    if [[ ! -x "$defaults_script" ]]; then
        log_warn "macOS defaults script is not executable, fixing permissions..."
        if [[ "$DRY_RUN" == false ]]; then
            chmod +x "$defaults_script"
        fi
    fi
    
    # Run the defaults script
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "$defaults_script --dry-run"
        # Actually run it in dry-run mode to show what would be done
        "$defaults_script" --dry-run
    else
        log_info "Running macOS defaults script..."
        if "$defaults_script"; then
            log_ok "macOS defaults applied successfully"
            increment_changes
        else
            log_error "Failed to apply macOS defaults"
            return 1
        fi
    fi
    
    return 0
}

setup_1password_and_decrypt_fonts() {
    log_info "Setting up 1Password and decrypting fonts..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "1Password and font decryption (not on real \$HOME)"
        return 0
    fi
    
    # Check if op CLI is installed
    if ! command -v op &> /dev/null; then
        log_skip "1Password CLI not installed, skipping font decryption"
        return 0
    fi
    
    # Check if encrypted fonts archive exists
    local encrypted_fonts="${REPO_DIR}/fonts.tar.gz.age"
    if [[ ! -f "$encrypted_fonts" ]]; then
        log_skip "Encrypted fonts archive not found at $encrypted_fonts"
        return 0
    fi
    
    # Dry-run mode
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would check if signed into 1Password: op account list"
        log_dry "Would prompt: Please sign into 1Password app, then press Enter..."
        log_dry "Would create directory: mkdir -p ${TARGET_HOME}/.dotlocal-secrets"
        log_dry "Would retrieve key: op read \"op://Personal/dotlocal-fonts-key/notes\" > ${TARGET_HOME}/.dotlocal-secrets/fonts.age"
        log_dry "Would decrypt fonts: age -d -i ${TARGET_HOME}/.dotlocal-secrets/fonts.age < $encrypted_fonts | tar xzf - -C ${REPO_DIR}/fonts/"
        return 0
    fi
    
    # Check if already signed in to 1Password
    if ! op account list &> /dev/null; then
        log_info "Not signed into 1Password"
        echo ""
        echo "=========================================="
        echo "1Password Sign-In Required"
        echo "=========================================="
        echo "Please sign into the 1Password app, then press Enter to continue..."
        read -r
        
        # Verify sign-in worked
        if ! op account list &> /dev/null; then
            log_error "Still not signed into 1Password. Skipping font decryption."
            return 0
        fi
    fi
    
    log_ok "Signed into 1Password"
    
    # Ensure .dotlocal-secrets directory exists
    local secrets_dir="${TARGET_HOME}/.dotlocal-secrets"
    ensure_dir "$secrets_dir"
    
    # Set proper permissions on secrets directory
    chmod 700 "$secrets_dir"
    
    # Retrieve age key from 1Password
    local age_key_file="${secrets_dir}/fonts.age"
    log_info "Retrieving age key from 1Password..."
    
    if op read "op://Personal/dotlocal-fonts-key/notes" > "$age_key_file" 2>/dev/null; then
        log_ok "Retrieved age key from 1Password"
        chmod 600 "$age_key_file"
    else
        log_error "Failed to retrieve age key from 1Password"
        log_error "Make sure the item 'dotlocal-fonts-key' exists in your Personal vault"
        return 0
    fi
    
    # Check if age is installed
    if ! command -v age &> /dev/null; then
        log_error "age is not installed, cannot decrypt fonts"
        return 0
    fi
    
    # Ensure fonts directory exists
    local fonts_dir="${REPO_DIR}/fonts"
    ensure_dir "$fonts_dir"
    
    # Decrypt fonts
    log_info "Decrypting fonts..."
    if age -d -i "$age_key_file" < "$encrypted_fonts" | tar xzf - -C "$fonts_dir"; then
        log_ok "Fonts decrypted successfully"
        increment_changes
    else
        log_error "Failed to decrypt fonts"
        return 1
    fi
    
    return 0
}

configure_git_identity() {
    log_info "Configuring git identity..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "Git identity configuration (not on real \$HOME)"
        return 0
    fi
    
    # Check if user.name and user.email are already set
    local current_name
    local current_email
    current_name=$(git config --global user.name 2>/dev/null || echo "")
    current_email=$(git config --global user.email 2>/dev/null || echo "")
    
    if [[ -n "$current_name" && -n "$current_email" ]]; then
        log_ok "Git identity already configured"
        log_info "  Name: $current_name"
        log_info "  Email: $current_email"
        return 0
    fi
    
    # Dry-run mode
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would prompt for Git name and email"
        log_dry "Would run: git config --global user.name <name>"
        log_dry "Would run: git config --global user.email <email>"
        return 0
    fi
    
    # Prompt for git name and email
    local git_name=""
    local git_email=""
    
    echo ""
    echo "=========================================="
    echo "Git Identity Configuration"
    echo "=========================================="
    read -p "Enter your Git name: " git_name
    read -p "Enter your Git email: " git_email
    
    # Validate inputs are not empty
    if [[ -z "$git_name" || -z "$git_email" ]]; then
        log_warn "Git name or email not provided, skipping git identity configuration"
        return 0
    fi
    
    # Set git identity using git config
    log_info "Setting git identity..."
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    
    log_ok "Git identity configured successfully"
    log_info "  Name: $git_name"
    log_info "  Email: $git_email"
    increment_changes
    
    return 0
}

configure_ssh_signing() {
    log_info "Configuring SSH signing for git commits..."
    
    # Skip if not on real $HOME
    if ! is_real_home; then
        log_skip "SSH signing configuration (not on real \$HOME)"
        return 0
    fi
    
    # Check if already configured
    local current_format
    current_format=$(git config --global gpg.format 2>/dev/null || echo "")
    
    if [[ "$current_format" == "ssh" ]]; then
        local current_key
        current_key=$(git config --global user.signingkey 2>/dev/null || echo "")
        log_ok "SSH signing already configured"
        if [[ -n "$current_key" ]]; then
            log_info "  Signing key: $current_key"
        fi
        return 0
    fi
    
    # Dry-run mode
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would prompt: Would you like to enable SSH signing for git commits? (y/n)"
        log_dry "Would check for SSH public keys in ~/.ssh/"
        log_dry "Would run: git config --global gpg.format ssh"
        log_dry "Would run: git config --global user.signingkey <path_to_pub_key>"
        log_dry "Would run: git config --global commit.gpgsign true"
        return 0
    fi
    
    # Prompt user
    echo ""
    echo "=========================================="
    echo "SSH Signing Configuration"
    echo "=========================================="
    read -p "Would you like to enable SSH signing for git commits? (y/n): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_skip "SSH signing configuration (user declined)"
        return 0
    fi
    
    # Look for SSH public keys in order of preference
    local ssh_dir="${TARGET_HOME}/.ssh"
    local -a preferred_keys=("id_ed25519.pub" "id_rsa.pub")
    local -a found_keys=()
    
    # Check preferred keys first
    for key_name in "${preferred_keys[@]}"; do
        local key_path="${ssh_dir}/${key_name}"
        if [[ -f "$key_path" ]]; then
            found_keys+=("$key_path")
        fi
    done
    
    # Find any other .pub files
    if [[ -d "$ssh_dir" ]]; then
        while IFS= read -r -d '' pub_file; do
            local basename_key
            basename_key=$(basename "$pub_file")
            # Skip if already in found_keys
            local already_added=false
            for existing_key in "${found_keys[@]}"; do
                if [[ "$(basename "$existing_key")" == "$basename_key" ]]; then
                    already_added=true
                    break
                fi
            done
            if [[ "$already_added" == false ]]; then
                found_keys+=("$pub_file")
            fi
        done < <(find "$ssh_dir" -maxdepth 1 -name "*.pub" -type f -print0 2>/dev/null)
    fi
    
    # Handle based on number of keys found
    local selected_key=""
    
    if [[ ${#found_keys[@]} -eq 0 ]]; then
        log_warn "No SSH public keys found in $ssh_dir"
        log_info "Please run 'ssh-keygen' to create a new SSH key, or use 1Password SSH agent"
        log_info "Then re-run this installer to configure SSH signing"
        return 0
    elif [[ ${#found_keys[@]} -eq 1 ]]; then
        selected_key="${found_keys[0]}"
        log_info "Found SSH key: $selected_key"
    else
        echo "Found multiple SSH keys:"
        for i in "${!found_keys[@]}"; do
            echo "  $((i+1)). ${found_keys[$i]}"
        done
        echo ""
        read -p "Select key number (1-${#found_keys[@]}): " key_selection
        
        # Validate selection
        if [[ "$key_selection" =~ ^[0-9]+$ ]] && [[ "$key_selection" -ge 1 ]] && [[ "$key_selection" -le ${#found_keys[@]} ]]; then
            selected_key="${found_keys[$((key_selection-1))]}"
            log_info "Selected: $selected_key"
        else
            log_warn "Invalid selection, skipping SSH signing configuration"
            return 0
        fi
    fi
    
    # Configure git
    log_info "Configuring git for SSH signing..."
    git config --global gpg.format ssh
    git config --global user.signingkey "$selected_key"
    git config --global commit.gpgsign true
    
    log_ok "SSH signing configured successfully"
    log_info "  Format: ssh"
    log_info "  Signing key: $selected_key"
    
    # Print reminder
    echo ""
    echo "Don't forget to add your SSH public key to GitHub as a Signing Key:"
    echo "  1. Copy your public key: pbcopy < $selected_key"
    echo "  2. Go to: Settings → SSH and GPG keys → New SSH key"
    echo "  3. Select 'Key type: Signing Key' and paste your key"
    echo ""
    
    increment_changes
    
    return 0
}

print_manual_install_reminder() {
    # Check if terminal supports colors (is a tty)
    local use_color=false
    if [[ -t 1 ]]; then
        use_color=true
    fi
    
    # ANSI color codes
    local YELLOW=""
    local BOLD=""
    local RESET=""
    
    if [[ "$use_color" == true ]]; then
        YELLOW="\033[33m"
        BOLD="\033[1m"
        RESET="\033[0m"
    fi
    
    echo ""
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}${BOLD}║                         MANUAL STEPS REQUIRED                                ║${RESET}"
    echo -e "${YELLOW}${BOLD}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # Print Chrome Apps section
    local chrome_apps_file="${REPO_DIR}/browser/chrome-apps.txt"
    if [[ -f "$chrome_apps_file" ]]; then
        echo -e "${YELLOW}${BOLD}║${RESET} ${BOLD}Chrome Apps${RESET} (open in Chrome, then install as app):                       ${YELLOW}${BOLD}║${RESET}"
        echo -e "${YELLOW}${BOLD}║${RESET}   How to install: Menu (⋮) → Cast, save, and share → Install page as app  ${YELLOW}${BOLD}║${RESET}"
        echo -e "${YELLOW}${BOLD}║${RESET}                                                                              ${YELLOW}${BOLD}║${RESET}"
        
        while IFS='|' read -r app_name app_url; do
            # Format with proper spacing (pad to 78 chars total width)
            local line="   • ${app_name}"
            local padding=$(( 78 - ${#line} ))
            printf "${YELLOW}${BOLD}║${RESET} %-76s ${YELLOW}${BOLD}║${RESET}\n" "$line"
            
            line="     ${app_url}"
            printf "${YELLOW}${BOLD}║${RESET} %-76s ${YELLOW}${BOLD}║${RESET}\n" "$line"
        done < "$chrome_apps_file"
    fi
    
    echo -e "${YELLOW}${BOLD}║${RESET}                                                                              ${YELLOW}${BOLD}║${RESET}"
    echo -e "${YELLOW}${BOLD}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # Print other manual installs
    echo -e "${YELLOW}${BOLD}║${RESET} ${BOLD}Other Manual Installs:${RESET}                                                       ${YELLOW}${BOLD}║${RESET}"
    echo -e "${YELLOW}${BOLD}║${RESET}   • CleanMyMac                                                             ${YELLOW}${BOLD}║${RESET}"
    echo -e "${YELLOW}${BOLD}║${RESET}     https://macpaw.com/cleanmymac                                           ${YELLOW}${BOLD}║${RESET}"
    
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    parse_args "$@"
    
    log_info "dotlocal install script"
    log_info "Repository: $REPO_DIR"
    log_info "Target home: $TARGET_HOME"
    [[ "$DRY_RUN" == true ]] && log_info "Mode: DRY RUN"
    
    BACKUP_DIR="${TARGET_HOME}/.dotlocal-backup/${TIMESTAMP}"
    
    # Ensure target home exists (for --home flag testing)
    ensure_dir "$TARGET_HOME"
    
    # Run installation steps
    # Install Homebrew first
    install_homebrew
    
    # Process Brewfile early to install 1Password, 1Password CLI, and age
    process_brewfile
    
    # Setup 1Password and decrypt fonts (requires 1Password CLI and age from Brewfile)
    setup_1password_and_decrypt_fonts
    
    # Continue with rest of installation
    install_oh_my_zsh
    parse_manifest
    create_symlinks
    configure_git_identity
    configure_ssh_signing
    install_cli_tools
    patch_vscode_insiders_product_json
    install_editor_extensions
    clone_repos
    install_powerline_fonts
    validate_secrets
    setup_ssh_key
    apply_macos_defaults
    register_launchd
    
    # Summary
    echo ""
    echo "=========================================="
    log_info "Installation complete"
    echo "=========================================="
    log_info "Changes made: $CHANGES_MADE"
    
    if [[ -n "${BACKUP_DIR:-}" ]] && [[ -d "$BACKUP_DIR" ]]; then
        log_info "Backups stored in: $BACKUP_DIR"
    fi
    
    # Determine if shell config was modified
    local shell_config_changed=false
    for i in "${!MANIFEST_SOURCES[@]}"; do
        local source="${MANIFEST_SOURCES[$i]}"
        if [[ "$source" =~ ^shell/ ]] && ! is_skipped "$source"; then
            shell_config_changed=true
            break
        fi
    done
    
    # Suggest re-sourcing shell if shell configs were changed
    if [[ "$shell_config_changed" == true && "$DRY_RUN" == false ]]; then
        echo ""
        log_info "Shell configuration files were updated."
        log_info "To apply changes to your current shell, run:"
        log_info "  source ~/.zshrc"
        log_info "Or start a new terminal session."
    fi
    
    # Remind user to fill in secrets if they were created from template
    if [[ "$SECRETS_NEED_ATTENTION" == true ]]; then
        echo ""
        log_warn "ACTION REQUIRED: ~/.secrets was created from template."
        log_warn "Edit ~/.secrets and fill in your API keys and credentials."
    fi
    
    echo "=========================================="
    
    # Print manual install reminder (MUST be last)
    print_manual_install_reminder
    
    # Determine exit code
    # 0 = success, 2 = partial success (if there were warnings)
    # Since we currently continue on warnings, check if any warnings were logged
    # For now, we'll use exit code 0 on success
    # In the future, we could track warnings in a WARNINGS_COUNT variable
    exit 0
}

main "$@"
