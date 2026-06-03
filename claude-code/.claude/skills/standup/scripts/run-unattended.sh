#!/usr/bin/env bash
# Unattended daily standup draft (user-agnostic).
#
# Invoked by the per-user launchd agent installed via install-launchd.sh, weekday
# mornings ~09:55 local (just after the #phantom stand-up bot posts at 09:50).
# Runs Claude headless to gather the day's activity-digest and create — never send
# — a Slack standup draft in that day's #phantom thread. Safe by construction: the
# settings file denies the Slack send tool, and the skill's unattended mode only
# drafts.
#
# Portable: resolves its own location and $HOME, so it works for any teammate who
# has this skill stowed and `claude`/`gh` on PATH. Logs to ~/Library/Logs.
# Manual test:  bash run-unattended.sh
set -uo pipefail

# launchd starts jobs with a minimal env — prepend the usual user/Homebrew bins.
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${SCRIPT_DIR}/unattended.settings.json"
WORKDIR="${ACTIVITY_DIGEST_REPO:-${HOME}/src/activity-digest}"
LOG="${HOME}/Library/Logs/standup-draft.log"

mkdir -p "$(dirname "$LOG")"
echo "===== $(date '+%Y-%m-%d %H:%M:%S %Z') : standup-draft starting =====" >> "$LOG"

cd "$WORKDIR" 2>/dev/null || cd "$HOME"

# Headless run. Default permission mode + the scoped settings file: allowed tools
# run, the Slack send tool is denied, and any un-allowlisted tool is auto-denied
# (print mode can't prompt) — so the worst case is an incomplete draft, never a
# hang and never a send. --add-dir grants read/write outside cwd (repos, transcripts).
claude -p "/standup --unattended" \
  --settings "$SETTINGS" \
  --add-dir "${HOME}/src" "${HOME}/.claude" \
  --permission-mode default \
  >> "$LOG" 2>&1
RC=$?

echo "----- $(date '+%Y-%m-%d %H:%M:%S %Z') : finished (exit $RC) -----" >> "$LOG"
exit "$RC"
