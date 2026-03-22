#!/usr/bin/env bash
# osxphotos_progress.sh — Hourly iCloud download progress notifications
#
# Sends a push notification showing how many photos are still downloading
# from iCloud. Intended to run hourly during the initial library sync.
# Disable this launchd job once iCloud downloads are complete.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHOTOS_LIBRARY="/Volumes/PhotosX9/Photos Library.photoslibrary"
VOLUME_NAME="PhotosX9"
NTFY_TOPIC="jackson-photosx9-4829"
STATE_FILE="/tmp/osxphotos_progress_last.txt"

ntfy_push() {
    local title="$1"
    local message="$2"
    local priority="${3:-default}"
    curl -s --max-time 10 \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -d "$message" \
        "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null 2>&1 || true
}

# Check volume is mounted
if [[ ! -d "/Volumes/${VOLUME_NAME}" ]]; then
    ntfy_push "📷 Progress Check Failed" "PhotosX9 not mounted" "high"
    exit 1
fi

# Count photos still missing from iCloud
MISSING=$(osxphotos query \
    --library "$PHOTOS_LIBRARY" \
    --only-photos \
    --missing \
    --count 2>/dev/null | tail -1 || echo "?")

# Count videos still missing
MISSING_VIDEOS=$(osxphotos query \
    --library "$PHOTOS_LIBRARY" \
    --only-movies \
    --missing \
    --count 2>/dev/null | tail -1 || echo "?")

# Calculate delta since last run
LAST_MISSING=""
if [[ -f "$STATE_FILE" ]]; then
    LAST_MISSING=$(cat "$STATE_FILE" 2>/dev/null || echo "")
fi

if [[ -n "$LAST_MISSING" && "$MISSING" =~ ^[0-9]+$ && "$LAST_MISSING" =~ ^[0-9]+$ ]]; then
    DELTA=$(( LAST_MISSING - MISSING ))
    DELTA_STR="↓ ${DELTA} since last hour"
else
    DELTA_STR="first check"
fi

# Save current count for next run
echo "$MISSING" > "$STATE_FILE"

# Build and send message
if [[ "$MISSING" == "0" ]]; then
    ntfy_push "📷 iCloud Download Complete!" "All photos are local — you can disable the hourly check" "high"
else
    MSG="Still downloading: ${MISSING} photos, ${MISSING_VIDEOS} videos (${DELTA_STR})"
    ntfy_push "📷 iCloud Progress" "$MSG" "default"
fi
