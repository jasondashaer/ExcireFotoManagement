#!/usr/bin/env bash
# setup.sh — One-time installer for osxphotos automation
#
# What it does:
#   1. Verifies dependencies (osxphotos, exiftool, curl)
#   2. Creates log directory
#   3. Makes scripts executable
#   4. Installs launchd plists (nightly sync + hourly progress)
#
# Usage:
#   bash setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCH_AGENTS="${HOME}/Library/LaunchAgents"

SYNC_PLIST="com.jackson.osxphotos.sync.plist"
PROGRESS_PLIST="com.jackson.osxphotos.progress.plist"

echo "=== osxphotos Automation Setup ==="
echo ""

# Check dependencies
echo "Checking dependencies..."
for cmd in osxphotos exiftool curl; do
    if command -v "$cmd" &>/dev/null; then
        echo "  ✓ $cmd found: $(command -v "$cmd")"
    else
        echo "  ✗ $cmd NOT FOUND — install it before running the sync"
        echo "    brew install $cmd"
        exit 1
    fi
done
echo ""

# Create log directory
mkdir -p "${SCRIPT_DIR}/logs"
echo "Created logs directory"

# Make scripts executable
chmod +x "${SCRIPT_DIR}/osxphotos_sync.sh"
chmod +x "${SCRIPT_DIR}/osxphotos_progress.sh"
echo "Made scripts executable"
echo ""

install_plist() {
    local name="$1"
    local load="$2"   # "load" or "pause"
    local src="${SCRIPT_DIR}/${name}"
    local dest="${LAUNCH_AGENTS}/${name}"

    # Unload if already running
    if launchctl list | grep -q "${name%.plist}" 2>/dev/null; then
        echo "Unloading existing: ${name}"
        launchctl unload "$dest" 2>/dev/null || true
    fi

    cp "$src" "$dest"

    if [[ "$load" == "load" ]]; then
        launchctl load "$dest"
        echo "  ✓ Installed and ENABLED: ${name}"
    else
        echo "  ✓ Installed (paused): ${name}"
    fi
}

echo "Installing launchd plists..."
install_plist "$SYNC_PLIST" "pause"       # enable manually when ready
install_plist "$PROGRESS_PLIST" "load"    # start hourly progress checks now

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Nightly sync (3 AM):   PAUSED — enable when ready:"
echo "  launchctl load ${LAUNCH_AGENTS}/${SYNC_PLIST}"
echo ""
echo "Hourly progress:       ACTIVE — disable when iCloud downloads finish:"
echo "  launchctl unload ${LAUNCH_AGENTS}/${PROGRESS_PLIST}"
echo ""
echo "To run sync manually:  bash ${SCRIPT_DIR}/osxphotos_sync.sh"
echo "To check jobs:         launchctl list | grep osxphotos"
echo ""
echo "Export destination: /Volumes/PhotosX9/Photos/Export/iCloud"
echo "ntfy topic:         jackson-photosx9-4829"
