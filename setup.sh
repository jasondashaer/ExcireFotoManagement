#!/usr/bin/env bash
# setup.sh — One-time installer for osxphotos automation
#
# What it does:
#   1. Verifies dependencies (osxphotos, exiftool)
#   2. Creates log directory
#   3. Makes the sync script executable
#   4. Installs the launchd plist for daily 3 AM runs
#
# Usage:
#   bash setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.jackson.osxphotos.sync.plist"
PLIST_SRC="${SCRIPT_DIR}/${PLIST_NAME}"
PLIST_DEST="${HOME}/Library/LaunchAgents/${PLIST_NAME}"

echo "=== osxphotos Automation Setup ==="
echo ""

# Check dependencies
echo "Checking dependencies..."
for cmd in osxphotos exiftool; do
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

# Make sync script executable
chmod +x "${SCRIPT_DIR}/osxphotos_sync.sh"
echo "Made osxphotos_sync.sh executable"

# Unload existing plist if present
if launchctl list | grep -q "$PLIST_NAME" 2>/dev/null; then
    echo "Unloading existing launchd job..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

# Install plist
cp "$PLIST_SRC" "$PLIST_DEST"
echo "Installed plist to ${PLIST_DEST}"

# Install plist but do NOT load it yet
echo "Plist installed but NOT loaded (paused)"
echo ""
echo "=== Setup Complete ==="
echo ""
echo "To test manually:  bash ${SCRIPT_DIR}/osxphotos_sync.sh"
echo "To enable nightly:  launchctl load ${PLIST_DEST}"
echo "To check status:    launchctl list | grep osxphotos"
echo "To disable:         launchctl unload ${PLIST_DEST}"
echo ""
echo "Export destination: /Volumes/PhotosX9/Photos/Export/iCloud"
