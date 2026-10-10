#!/usr/bin/env bash
# Unattended weekly friday-story draft (user-agnostic).
#
# Invoked by the per-user launchd agent installed via install-launchd.sh, Thursday
# ~11:00 local. Runs Claude headless to build the last-7-days activity-digest and
# create — never send — a capability-gain "friday story" draft in the user's
# personal Slack DM, ready to review before the Friday sync. Safe by construction:
# the settings file denies the Slack send tool; the skill's unattended mode only
# drafts.
#
# Portable: resolves its own location and $HOME. Logs to ~/Library/Logs.
# Manual test:  bash run-unattended.sh
set -uo pipefail

export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${SCRIPT_DIR}/unattended.settings.json"
WORKDIR="${ACTIVITY_DIGEST_REPO:-${HOME}/src/activity-digest}"
LOG="${HOME}/Library/Logs/friday-story.log"

mkdir -p "$(dirname "$LOG")"
echo "===== $(date '+%Y-%m-%d %H:%M:%S %Z') : friday-story starting =====" >> "$LOG"

cd "$WORKDIR" 2>/dev/null || cd "$HOME"

# Headless. Default permission mode + scoped settings: allowed tools run, the Slack
# send tool is denied, un-allowlisted tools auto-deny (print mode can't prompt) —
# worst case an incomplete draft, never a hang and never a send.
claude -p "/friday-story --unattended" \
  --settings "$SETTINGS" \
  --add-dir "${HOME}/src" "${HOME}/.claude" \
  --permission-mode default \
  >> "$LOG" 2>&1
RC=$?

echo "----- $(date '+%Y-%m-%d %H:%M:%S %Z') : finished (exit $RC) -----" >> "$LOG"
exit "$RC"
