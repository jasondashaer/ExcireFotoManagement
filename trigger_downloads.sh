#!/usr/bin/env bash
# trigger_downloads.sh — Steps through Photos.app one photo at a time to
# trigger iCloud original downloads. Viewing a photo full-size forces
# Photos to request the full-resolution file from iCloud.
#
# Usage:
#   bash trigger_downloads.sh [count] [delay_seconds]
#
# Examples:
#   bash trigger_downloads.sh            # step through 2000 photos, 1s each
#   bash trigger_downloads.sh 500 0.5   # 500 photos, 0.5s each
#   bash trigger_downloads.sh 13000 1   # full library pass
#
# Stop at any time with: kill $(cat /tmp/trigger_downloads.pid)

COUNT="${1:-2000}"
DELAY="${2:-1}"
PID_FILE="/tmp/trigger_downloads.pid"

echo "Starting photo scroll: ${COUNT} photos at ${DELAY}s each"
echo "Estimated time: $(echo "scale=1; $COUNT * $DELAY / 60" | bc) minutes"
echo "Stop with: kill \$(cat $PID_FILE)"
echo ""

echo $$ > "$PID_FILE"

# Bring Photos to front and navigate to All Photos view
osascript -e '
tell application "Photos" to activate
delay 1
tell application "System Events"
    tell process "Photos"
        -- Navigate to All Photos view
        click menu item "All Photos" of menu "View" of menu bar 1
        delay 1
        -- Select the first photo (Home key jumps to beginning)
        key code 115  -- Home key
        delay 0.5
        -- Open it full-size (Return key)
        key code 36
        delay 1
    end tell
end tell' 2>&1

echo "Stepping through ${COUNT} photos..."
echo ""

for (( i=1; i<=COUNT; i++ )); do
    # Step to next photo via right arrow
    osascript -e '
    tell application "System Events"
        tell process "Photos"
            key code 124  -- right arrow
        end tell
    end tell' 2>/dev/null

    sleep "$DELAY"

    # Progress every 50 photos
    if (( i % 50 == 0 )); then
        ORIGINALS_SIZE=$(du -sh "/Volumes/PhotosX9/Photos Library.photoslibrary/originals/" 2>/dev/null | cut -f1)
        echo "[$(date '+%H:%M:%S')] Photo ${i}/${COUNT} | Originals: ${ORIGINALS_SIZE}"
    fi
done

# Exit full-size view when done
osascript -e '
tell application "System Events"
    tell process "Photos"
        key code 53  -- Escape
    end tell
end tell' 2>/dev/null

rm -f "$PID_FILE"
echo ""
echo "Done. Viewed ${COUNT} photos."
