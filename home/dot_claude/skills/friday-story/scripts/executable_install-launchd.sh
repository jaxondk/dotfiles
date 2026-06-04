#!/usr/bin/env bash
# Install (or reinstall) the per-user "friday-story" launchd agent.
#
# User-agnostic: derives this user's $HOME, uid, and the wrapper path automatically,
# generates a per-user plist, and loads it. Idempotent. Each teammate just runs:
#   bash install-launchd.sh
#
# Schedule defaults to Thursday 11:00 local; override with
# FRIDAY_STORY_WEEKDAY (1=Mon..5=Fri), FRIDAY_STORY_HOUR, FRIDAY_STORY_MIN.
set -euo pipefail

LABEL="com.firecrew.friday-story"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="${SCRIPT_DIR}/run-unattended.sh"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOGDIR="${HOME}/Library/Logs"
UID_NUM="$(id -u)"
WEEKDAY="${FRIDAY_STORY_WEEKDAY:-4}"   # 4 = Thursday
HOUR="${FRIDAY_STORY_HOUR:-11}"
MIN="${FRIDAY_STORY_MIN:-0}"

[ -f "$WRAPPER" ] || { echo "wrapper not found: $WRAPPER" >&2; exit 1; }
chmod +x "$WRAPPER"
mkdir -p "${HOME}/Library/LaunchAgents" "$LOGDIR"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${WRAPPER}</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>${WEEKDAY}</integer>
    <key>Hour</key><integer>${HOUR}</integer>
    <key>Minute</key><integer>${MIN}</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>${LOGDIR}/friday-story.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOGDIR}/friday-story.err.log</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
PLIST

plutil -lint "$PLIST"
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$PLIST"
printf 'installed + loaded %s (weekday %d at %d:%02d local)\n' "$LABEL" "$WEEKDAY" "$HOUR" "$MIN"
launchctl print "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 && echo "verified registered" || echo "WARNING: not found in launchctl after bootstrap"
