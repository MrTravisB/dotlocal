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
            # Check if target exists and is identical
            if [[ -e "$target" ]]; then
                # For directories, always back up and re-copy to ensure freshness
                # For files, could compare with diff but simpler to just back up
                backup_file "$target"
            fi
            
            # Copy file or directory
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "cp -r $abs_source $target"
            else
                cp -r "$abs_source" "$target"
                log_info "Copied: $abs_source -> $target"
                increment_changes
            fi
            ((created++)) || true
            
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

validate_secrets() {
    log_info "Validating secrets..."
    
    local secrets_file="${REPO_DIR}/.secrets"
    local secrets_example="${REPO_DIR}/.secrets.example"
    
    # Check if .secrets file exists
    if [[ ! -f "$secrets_file" ]]; then
        log_warn ".secrets file not found"
        if [[ -f "$secrets_example" ]]; then
            log_warn "Copy .secrets.example to .secrets and fill in your values:"
            log_warn "  cp $secrets_example $secrets_file"
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
    install_homebrew
    parse_manifest
    create_symlinks
    process_brewfile
    install_cli_tools
    clone_repos
    validate_secrets
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
    
    echo "=========================================="
    
    # Determine exit code
    # 0 = success, 2 = partial success (if there were warnings)
    # Since we currently continue on warnings, check if any warnings were logged
    # For now, we'll use exit code 0 on success
    # In the future, we could track warnings in a WARNINGS_COUNT variable
    exit 0
}

main "$@"
