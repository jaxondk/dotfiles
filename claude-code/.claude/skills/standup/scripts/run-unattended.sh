#!/usr/bin/env bash
# Unattended daily standup draft.
#
# Invoked by the launchd agent `com.jaxonkeeler.standup-draft` at ~09:55 ET,
# Mon–Fri (just after the #phantom stand-up bot posts at 09:50). Runs Claude
# headless to gather the day's activity-digest and create — never send — a Slack
# standup draft in that day's #phantom thread. Safe by construction: the settings
# file denies the Slack send tool, and the skill's unattended mode only drafts.
#
# Logs to ~/Library/Logs/standup-draft.log. Manual test:  bash run-unattended.sh
set -uo pipefail

# launchd starts jobs with a minimal env — set an explicit PATH for claude/gh/etc.
export PATH="/Users/jaxon.keeler/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SKILL_DIR="/Users/jaxon.keeler/dotfiles/claude-code/.claude/skills/standup"
SETTINGS="${SKILL_DIR}/scripts/unattended.settings.json"
WORKDIR="/Users/jaxon.keeler/src/activity-digest"
LOG="/Users/jaxon.keeler/Library/Logs/standup-draft.log"

mkdir -p "$(dirname "$LOG")"
{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S %Z') : standup-draft starting ====="
} >> "$LOG"

cd "$WORKDIR" 2>/dev/null || cd "$HOME"

# Headless run. Default permission mode + the scoped settings file: allowed tools
# run, the send tool is denied, and any un-allowlisted tool is auto-denied (print
# mode can't prompt) — so the worst case is an incomplete draft, never a hang and
# never a send. --add-dir grants read/write outside the cwd (repos, transcripts).
claude -p "/standup --unattended" \
  --settings "$SETTINGS" \
  --add-dir "$HOME/src" "$HOME/.claude" \
  --permission-mode default \
  >> "$LOG" 2>&1
RC=$?

echo "----- $(date '+%Y-%m-%d %H:%M:%S %Z') : finished (exit $RC) -----" >> "$LOG"
exit "$RC"
