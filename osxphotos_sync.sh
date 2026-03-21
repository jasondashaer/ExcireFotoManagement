#!/usr/bin/env bash
# osxphotos_sync.sh — Wrapper for automated osxphotos exports
#
# Features:
#   - Pre-flight check that destination volume is mounted
#   - caffeinate to prevent sleep during export
#   - 4-hour timeout watchdog
#   - Lock file to prevent overlapping runs
#   - macOS notifications on completion/failure
#   - Rotating log files (14-day retention)

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/osxphotos_export.toml"

# Destination and library paths
EXPORT_DEST="/Volumes/PhotosX9/Photos/Export/iCloud"
PHOTOS_LIBRARY="/Volumes/PhotosX9/Photos Library.photoslibrary"

# Volume name to check
VOLUME_NAME="PhotosX9"

# Timeout in seconds (4 hours)
TIMEOUT=14400

# Log and lock paths
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/osxphotos_sync_$(date +%Y%m%d_%H%M%S).log"
LOCK_FILE="/tmp/osxphotos_sync.lock"

# Log retention in days
LOG_RETENTION_DAYS=14

# ─── Functions ───────────────────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

notify() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
}

cleanup() {
    # Kill caffeinate if running
    if [[ -n "${CAFFEINATE_PID:-}" ]]; then
        kill "$CAFFEINATE_PID" 2>/dev/null || true
    fi
    # Kill osxphotos if running (timeout case)
    if [[ -n "${EXPORT_PID:-}" ]]; then
        kill "$EXPORT_PID" 2>/dev/null || true
    fi
    # Remove lock file
    rm -f "$LOCK_FILE"
}

trap cleanup EXIT

# ─── Pre-flight checks ──────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

log "Starting osxphotos sync"

# Check lock file
if [[ -f "$LOCK_FILE" ]]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$LOCK_PID" ]] && kill -0 "$LOCK_PID" 2>/dev/null; then
        log "ERROR: Another sync is already running (PID $LOCK_PID)"
        exit 1
    else
        log "WARNING: Stale lock file found, removing"
        rm -f "$LOCK_FILE"
    fi
fi
echo $$ > "$LOCK_FILE"

# Check volume is mounted
if [[ ! -d "/Volumes/${VOLUME_NAME}" ]]; then
    log "ERROR: Volume '${VOLUME_NAME}' is not mounted. Aborting."
    notify "osxphotos Sync Failed" "Volume '${VOLUME_NAME}' is not mounted"
    exit 1
fi

# Check config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR: Config file not found at ${CONFIG_FILE}"
    notify "osxphotos Sync Failed" "Config file not found"
    exit 1
fi

# Check osxphotos is installed
if ! command -v osxphotos &>/dev/null; then
    log "ERROR: osxphotos not found in PATH"
    notify "osxphotos Sync Failed" "osxphotos not installed"
    exit 1
fi

# Clean old logs
find "$LOG_DIR" -name "osxphotos_sync_*.log" -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true

# ─── Run export ──────────────────────────────────────────────────────────────
log "Destination: ${EXPORT_DEST}"
log "Config: ${CONFIG_FILE}"
log "Timeout: ${TIMEOUT}s"

# Prevent sleep
caffeinate -s &
CAFFEINATE_PID=$!

# Run osxphotos in background so we can monitor with timeout
osxphotos export "$EXPORT_DEST" \
    --load-config "$CONFIG_FILE" \
    --library "$PHOTOS_LIBRARY" \
    --report "${EXPORT_DEST}/export_report.csv" \
    >> "$LOG_FILE" 2>&1 &
EXPORT_PID=$!

log "osxphotos started (PID $EXPORT_PID)"

# Watchdog: wait for export to finish or timeout
SECONDS=0
while kill -0 "$EXPORT_PID" 2>/dev/null; do
    if [[ $SECONDS -ge $TIMEOUT ]]; then
        log "ERROR: Export timed out after ${TIMEOUT}s. Killing PID $EXPORT_PID."
        kill "$EXPORT_PID" 2>/dev/null || true
        wait "$EXPORT_PID" 2>/dev/null || true
        notify "osxphotos Sync Failed" "Export timed out after $(( TIMEOUT / 3600 )) hours"
        exit 1
    fi
    sleep 30
done

# Get exit code
wait "$EXPORT_PID"
EXIT_CODE=$?
unset EXPORT_PID

if [[ $EXIT_CODE -eq 0 ]]; then
    log "Export completed successfully in ${SECONDS}s"
    notify "osxphotos Sync Complete" "Export finished in $(( SECONDS / 60 )) minutes"
else
    log "ERROR: Export failed with exit code ${EXIT_CODE}"
    notify "osxphotos Sync Failed" "Export failed (exit code ${EXIT_CODE})"
    exit $EXIT_CODE
fi

log "Sync finished"
