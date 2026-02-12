#!/usr/bin/env bash
set -euo pipefail

# macOS System Defaults
# Applies Finder, Dock, and Trackpad preferences

DRY_RUN=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
  esac
done

log() {
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] $1"
  else
    echo "[INFO] $1"
  fi
}

apply_setting() {
  local domain="$1"
  local key="$2"
  local type="$3"
  local value="$4"
  
  log "Setting $domain.$key to $value"
  
  if [ "$DRY_RUN" = false ]; then
    defaults write "$domain" "$key" "$type" "$value"
  fi
}

log "Applying macOS system defaults..."

# ============================================================================
# Finder Settings
# ============================================================================

log "Configuring Finder..."

# List view as default
apply_setting "com.apple.finder" "FXPreferredViewStyle" "-string" "Nlsv"

# Search current folder by default
apply_setting "com.apple.finder" "FXDefaultSearchScope" "-string" "SCcf"

# Show path bar
apply_setting "com.apple.finder" "ShowPathbar" "-bool" "true"

# Hide recent tags in sidebar
apply_setting "com.apple.finder" "ShowRecentTags" "-bool" "false"

# Hide desktop icons
apply_setting "com.apple.finder" "ShowExternalHardDrivesOnDesktop" "-bool" "false"
apply_setting "com.apple.finder" "ShowHardDrivesOnDesktop" "-bool" "false"
apply_setting "com.apple.finder" "ShowRemovableMediaOnDesktop" "-bool" "false"

# New windows open to Home folder
apply_setting "com.apple.finder" "NewWindowTarget" "-string" "PfHm"

# Collapse tags section in sidebar
apply_setting "com.apple.finder" "SidebarTagsSctionDisclosedState" "-bool" "false"

# Disable iCloud Drive Desktop/Documents sync
apply_setting "com.apple.finder" "FXICloudDriveDesktop" "-bool" "false"
apply_setting "com.apple.finder" "FXICloudDriveDocuments" "-bool" "false"

# ============================================================================
# Dock Settings
# ============================================================================

log "Configuring Dock..."

# No autohide
apply_setting "com.apple.dock" "autohide" "-bool" "false"

# Autohide animation time (slower)
apply_setting "com.apple.dock" "autohide-time-modifier" "-float" "2"

# Dock tile size
apply_setting "com.apple.dock" "tilesize" "-int" "41"

# Magnification size
apply_setting "com.apple.dock" "largesize" "-int" "128"

# Hide recent apps
apply_setting "com.apple.dock" "show-recents" "-bool" "false"

# Hide process indicators
apply_setting "com.apple.dock" "show-process-indicators" "-bool" "false"

# Don't reorder Spaces by recent use
apply_setting "com.apple.dock" "mru-spaces" "-bool" "false"

# Bottom-right hot corner = Quick Note (14)
apply_setting "com.apple.dock" "wvous-br-corner" "-int" "14"

# ============================================================================
# Trackpad Settings
# ============================================================================

log "Configuring Trackpad..."

# Disable tap to click
apply_setting "com.apple.AppleMultitouchTrackpad" "Clicking" "-bool" "false"

# Disable Force Touch
apply_setting "com.apple.AppleMultitouchTrackpad" "ForceSuppressed" "-bool" "true"

# Disable three-finger drag
apply_setting "com.apple.AppleMultitouchTrackpad" "TrackpadThreeFingerDrag" "-bool" "false"

# Enable two-finger right click
apply_setting "com.apple.AppleMultitouchTrackpad" "TrackpadRightClick" "-bool" "true"

# Enable pinch to zoom
apply_setting "com.apple.AppleMultitouchTrackpad" "TrackpadPinch" "-bool" "true"

# Enable rotate gesture
apply_setting "com.apple.AppleMultitouchTrackpad" "TrackpadRotate" "-bool" "true"

# ============================================================================
# Screenshots
# ============================================================================

log "Configuring Screenshots..."

# Create screenshots directory
SCREENSHOT_DIR="$HOME/Downloads/screenshots"
if [ "$DRY_RUN" = false ]; then
  mkdir -p "$SCREENSHOT_DIR"
  log "Created screenshot directory: $SCREENSHOT_DIR"
else
  log "Would create directory: $SCREENSHOT_DIR"
fi

# Set screenshot location
apply_setting "com.apple.screencapture" "location" "-string" "$SCREENSHOT_DIR"

# ============================================================================
# Global Settings
# ============================================================================

log "Configuring global settings..."

# Double-click title bar does not minimize
apply_setting "NSGlobalDomain" "AppleMiniaturizeOnDoubleClick" "-bool" "false"

# Enable force click globally
apply_setting "NSGlobalDomain" "com.apple.trackpad.forceClick" "-bool" "true"

# ============================================================================
# Restart Services
# ============================================================================

if [ "$DRY_RUN" = false ]; then
  log "Restarting Finder and Dock..."
  killall Finder
  killall Dock
else
  log "Would restart Finder and Dock (skipped in dry-run mode)"
fi

log "macOS defaults applied successfully!"
