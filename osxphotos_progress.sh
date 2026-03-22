#!/usr/bin/env bash
# osxphotos_progress.sh — Periodic iCloud download progress notifications
#
# Sends a push notification showing how many photos are still downloading
# from iCloud. Intended to run during the initial library sync.
# Disable this launchd job once iCloud downloads are complete.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHOTOS_LIBRARY="/Volumes/PhotosX9/Photos Library.photoslibrary"
PHOTOS_DB="${PHOTOS_LIBRARY}/database/Photos.sqlite"
VOLUME_NAME="PhotosX9"
NTFY_TOPIC="jackson-photosx9-4829"
STATE_FILE="/tmp/osxphotos_progress_last.txt"
LOCK_FILE="/tmp/osxphotos_progress.lock"
TMP_DB="/tmp/osxphotos_progress_db.sqlite"

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
    rm -f "$LOCK_FILE" "$TMP_DB" "${TMP_DB}-wal" "${TMP_DB}-shm"
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

# Copy DB to /tmp to bypass lock contention from active iCloud downloads
cp "$PHOTOS_DB" "$TMP_DB" 2>/dev/null || true
cp "${PHOTOS_DB}-wal" "${TMP_DB}-wal" 2>/dev/null || true
cp "${PHOTOS_DB}-shm" "${TMP_DB}-shm" 2>/dev/null || true

# Query the copy directly — fast and lock-free
# ZASSET: ZTRASHEDSTATE=0 (not trashed), ZKIND=0 (photo) or 1 (video)
# ZCLOUDLOCALSTATE=0 means not yet downloaded from iCloud
MISSING=$(sqlite3 "$TMP_DB" \
    "SELECT COUNT(*) FROM ZASSET WHERE ZTRASHEDSTATE=0 AND ZKIND=0 AND ZCLOUDLOCALSTATE=0;" \
    2>/dev/null || echo "?")

MISSING_VIDEOS=$(sqlite3 "$TMP_DB" \
    "SELECT COUNT(*) FROM ZASSET WHERE ZTRASHEDSTATE=0 AND ZKIND=1 AND ZCLOUDLOCALSTATE=0;" \
    2>/dev/null || echo "?")

# Load previous counts
LAST_MISSING=""
LAST_MISSING_VIDEOS=""
if [[ -f "$STATE_FILE" ]]; then
    LAST_MISSING=$(awk 'NR==1' "$STATE_FILE" 2>/dev/null || echo "")
    LAST_MISSING_VIDEOS=$(awk 'NR==2' "$STATE_FILE" 2>/dev/null || echo "")
fi

# Only save state when we have real numbers
if [[ "$MISSING" =~ ^[0-9]+$ ]]; then
    printf '%s\n%s\n' "$MISSING" "$MISSING_VIDEOS" > "$STATE_FILE"
fi

# Calculate deltas
if [[ "$MISSING" =~ ^[0-9]+$ && "$LAST_MISSING" =~ ^[0-9]+$ ]]; then
    PHOTO_DELTA=$(( LAST_MISSING - MISSING ))
    PHOTO_DELTA_STR="↓ ${PHOTO_DELTA} downloaded since last check"
else
    PHOTO_DELTA_STR="first check"
fi

if [[ "$MISSING_VIDEOS" =~ ^[0-9]+$ && "$LAST_MISSING_VIDEOS" =~ ^[0-9]+$ ]]; then
    VIDEO_DELTA=$(( LAST_MISSING_VIDEOS - MISSING_VIDEOS ))
    VIDEO_DELTA_STR="↓ ${VIDEO_DELTA} downloaded since last check"
else
    VIDEO_DELTA_STR="first check"
fi

# Build and send message
if [[ "$MISSING" == "0" && "$MISSING_VIDEOS" == "0" ]]; then
    ntfy_push "📷 iCloud Download Complete!" "All photos and videos are local — disable the progress check" "high"
else
    MSG="Photos remaining: ${MISSING} (${PHOTO_DELTA_STR})
Videos remaining: ${MISSING_VIDEOS} (${VIDEO_DELTA_STR})"
    ntfy_push "📷 iCloud Progress" "$MSG" "default"
fi
