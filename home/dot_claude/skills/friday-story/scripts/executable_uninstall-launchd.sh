#!/usr/bin/env bash
# Remove the per-user "friday-story" launchd agent. Leaves skill files + logs.
set -uo pipefail
LABEL="com.firecrew.friday-story"
UID_NUM="$(id -u)"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
rm -f "$PLIST"
echo "removed ${LABEL} (logs kept at ~/Library/Logs/friday-story*.log)"
