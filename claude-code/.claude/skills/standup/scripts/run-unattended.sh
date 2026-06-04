#!/usr/bin/env bash
# Unattended daily standup draft (user-agnostic).
#
# Invoked by the per-user launchd agent installed via install-launchd.sh, weekday
# mornings ~09:55 local (just after the #phantom stand-up bot posts at 09:50).
# Runs Claude headless to gather the day's activity-digest and draft the standup,
# then DMs that draft to the user for review. Two-stage by necessity: the claude.ai
# Slack connector only loads in the interactive client, never in a headless/cron
# session, so the model can't reach Slack at all. Stage 1 (model) writes the
# standup body to $STANDUP_DRAFT_FILE; stage 2 (deterministic bash below) posts it
# to the user's own Slack DM. Safe by construction: the model never sees the Slack
# token, and the deliverer only ever targets the user's self-DM, never a channel.
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

# Where the (Slack-less) headless run drops the finished standup body. The skill,
# in --unattended mode, writes ONLY the y:/t:/b: markdown here — no prose, no
# fences — so the deliverer can post it verbatim. Exported so the child `claude`
# process and the skill running inside it can read the path.
export STANDUP_DRAFT_FILE="${TMPDIR:-/tmp}/standup-draft-$(date '+%F').md"
rm -f "$STANDUP_DRAFT_FILE" "$STANDUP_DRAFT_FILE.delivered"   # fresh each run

mkdir -p "$(dirname "$LOG")"
echo "===== $(date '+%Y-%m-%d %H:%M:%S %Z') : standup-draft starting =====" >> "$LOG"

cd "$WORKDIR" 2>/dev/null || cd "$HOME"

# Headless run. Default permission mode + the scoped settings file: allowed tools
# run, the Slack send tool is denied, and any un-allowlisted tool is auto-denied
# (print mode can't prompt) — so the worst case is an incomplete draft, never a
# hang and never a send. --add-dir grants read/write outside cwd (repos, transcripts).
claude -p "/standup --unattended" \
  --settings "$SETTINGS" \
  --add-dir "${HOME}/src" "${HOME}/.claude" "$(dirname "$STANDUP_DRAFT_FILE")" \
  --permission-mode default \
  >> "$LOG" 2>&1
RC=$?

# Stage 2 — deliver. The skill wrote the standup body to $STANDUP_DRAFT_FILE (it
# can't reach Slack itself). Hand it to the deterministic Slack-DM deliverer, which
# reads the token from ~/.config/standup/slack-dm.env and posts to the self-DM only.
# A missing config or a Slack error is logged but never fails the job — the draft
# is preserved on disk either way.
if [ -s "$STANDUP_DRAFT_FILE" ]; then
  bash "${SCRIPT_DIR}/deliver-to-slack-dm.sh" "$STANDUP_DRAFT_FILE" >> "$LOG" 2>&1 \
    || echo "delivery step did not complete; draft preserved at $STANDUP_DRAFT_FILE" >> "$LOG"
else
  echo "no draft at $STANDUP_DRAFT_FILE — skill produced nothing to deliver (see log above)" >> "$LOG"
fi

echo "----- $(date '+%Y-%m-%d %H:%M:%S %Z') : finished (exit $RC) -----" >> "$LOG"
exit "$RC"
