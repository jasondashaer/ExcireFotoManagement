#!/usr/bin/env bash
# osxphotos_progress.sh — Periodic iCloud download progress notifications
#
# Sends a push notification showing how many photos are still downloading
# from iCloud. Intended to run during the initial library sync.
# Disable this launchd job once iCloud downloads are complete.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHOTOS_LIBRARY="/Volumes/PhotosX9/Photos Library.photoslibrary"
VOLUME_NAME="PhotosX9"
NTFY_TOPIC="jackson-photosx9-4829"
STATE_FILE="/tmp/osxphotos_progress_last.txt"
LOCK_FILE="/tmp/osxphotos_progress.lock"
QUERY_TIMEOUT=120  # seconds before giving up on a query

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

cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Lock file — prevent overlapping runs
if [[ -f "$LOCK_FILE" ]]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$LOCK_PID" ]] && kill -0 "$LOCK_PID" 2>/dev/null; then
        exit 0  # already running, skip silently
    else
        rm -f "$LOCK_FILE"
    fi
fi
echo $$ > "$LOCK_FILE"

# Check volume is mounted
if [[ ! -d "/Volumes/${VOLUME_NAME}" ]]; then
    ntfy_push "📷 Progress Check Failed" "PhotosX9 not mounted" "high"
    exit 1
fi

# Run a query with a hard timeout via perl alarm (macOS-native, no extra deps)
run_query() {
    perl -e 'alarm(shift); exec @ARGV' -- "$QUERY_TIMEOUT" \
        osxphotos query \
        --library "$PHOTOS_LIBRARY" \
        "$1" --missing --count 2>/dev/null | tail -1 || echo "?"
}

MISSING=$(run_query "--only-photos")
MISSING_VIDEOS=$(run_query "--only-movies")

# Calculate delta since last run
LAST_MISSING=""
if [[ -f "$STATE_FILE" ]]; then
    LAST_MISSING=$(cat "$STATE_FILE" 2>/dev/null || echo "")
fi

if [[ -n "$LAST_MISSING" && "$MISSING" =~ ^[0-9]+$ && "$LAST_MISSING" =~ ^[0-9]+$ ]]; then
    DELTA=$(( LAST_MISSING - MISSING ))
    DELTA_STR="↓ ${DELTA} downloaded"
else
    DELTA_STR="first check"
fi

# Save current count for next run
echo "$MISSING" > "$STATE_FILE"

# Build and send message
if [[ "$MISSING" == "0" ]]; then
    ntfy_push "📷 iCloud Download Complete!" "All photos are local — disable the hourly check" "high"
else
    MSG="Still downloading: ${MISSING} photos, ${MISSING_VIDEOS} videos (${DELTA_STR})"
    ntfy_push "📷 iCloud Progress" "$MSG" "default"
fi
