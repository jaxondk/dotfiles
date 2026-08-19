#!/usr/bin/env bash
# Install (or reinstall) the per-user "standup draft" launchd agent.
#
# User-agnostic: derives this user's $HOME, uid, and the wrapper path automatically,
# generates a per-user plist, and loads it. Idempotent — safe to re-run (it boots
# out any existing copy first). Each teammate just runs:  bash install-launchd.sh
#
# Schedule defaults to weekdays 09:55 local; override with STANDUP_HOUR / STANDUP_MIN.
set -euo pipefail

LABEL="com.firecrew.standup-draft"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="${SCRIPT_DIR}/run-unattended.sh"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOGDIR="${HOME}/Library/Logs"
UID_NUM="$(id -u)"
HOUR="${STANDUP_HOUR:-9}"
MIN="${STANDUP_MIN:-55}"

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
  <array>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MIN}</integer></dict>
    <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MIN}</integer></dict>
    <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MIN}</integer></dict>
    <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MIN}</integer></dict>
    <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>${HOUR}</integer><key>Minute</key><integer>${MIN}</integer></dict>
  </array>
  <key>StandardOutPath</key>
  <string>${LOGDIR}/standup-draft.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOGDIR}/standup-draft.err.log</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
PLIST

plutil -lint "$PLIST"
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$PLIST"
printf 'installed + loaded %s (weekdays %d:%02d local)\n' "$LABEL" "$HOUR" "$MIN"
launchctl print "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1 && echo "verified registered" || echo "WARNING: not found in launchctl after bootstrap"
