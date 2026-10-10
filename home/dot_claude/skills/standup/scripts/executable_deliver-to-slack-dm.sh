#!/usr/bin/env bash
# Deliver a standup draft to the user's own Slack DM, headlessly.
#
# Why this exists: the scheduled `claude -p "/standup --unattended"` run cannot
# reach Slack. The claude.ai account *connectors* (Slack/Linear) only load in the
# interactive client — never in a headless/cron session — so the model has no
# Slack tool at all. Instead the skill writes the finished standup body to a plain
# file and THIS script — deterministic bash — posts it to the user's own Slack DM
# via the Web API. The model never sees the token and the destination is hardcoded
# to the user's self-DM (`conversations.open` on their own id), so there is no path
# by which an imperfect draft lands in a public channel. The user reviews/edits in
# the DM and posts into #phantom themselves.
#
# Usage:  deliver-to-slack-dm.sh <draft-file>
# Config: ~/.config/standup/slack-dm.env  (chmod 600) — see slack-dm.env.example:
#           SLACK_TOKEN=xoxb-...           # bot token (chat:write, im:write) or user token (chat:write)
#           SLACK_DM_USER_ID=U09PRSV657S   # whose DM to post into
# Exit:   0 = delivered (or already delivered today); non-zero = not delivered
#         (draft is always preserved on disk regardless).
set -uo pipefail

DRAFT="${1:?usage: deliver-to-slack-dm.sh <draft-file>}"
CONFIG="${STANDUP_SLACK_CONFIG:-${HOME}/.config/standup/slack-dm.env}"
LOG="${STANDUP_LOG:-${HOME}/Library/Logs/standup-draft.log}"
API="https://slack.com/api"

log() { echo "[deliver $(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

[ -s "$DRAFT" ]   || { log "no draft (or empty) at $DRAFT — nothing to deliver"; exit 1; }
[ -f "$CONFIG" ]  || { log "no Slack config at $CONFIG — skipping delivery; draft preserved at $DRAFT"; exit 1; }

# shellcheck disable=SC1090
set -a; . "$CONFIG"; set +a
: "${SLACK_TOKEN:?SLACK_TOKEN missing in $CONFIG}"
: "${SLACK_DM_USER_ID:?SLACK_DM_USER_ID missing in $CONFIG}"

command -v curl    >/dev/null 2>&1 || { log "missing dependency: curl";    exit 1; }
command -v python3 >/dev/null 2>&1 || { log "missing dependency: python3"; exit 1; }

# Idempotency: one DM per draft file. Re-running the job the same day (e.g. manual
# kickstart after the scheduled run) won't double-post.
MARKER="${DRAFT}.delivered"
[ -f "$MARKER" ] && { log "already delivered ($MARKER) — skipping"; exit 0; }

# Open (or fetch the existing) DM channel with the user. Works for the self-DM.
CHAN=$(curl -sS -X POST "$API/conversations.open" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H 'Content-type: application/json; charset=utf-8' \
  --data "{\"users\":\"${SLACK_DM_USER_ID}\"}" \
  | python3 -c 'import sys,json
d=json.load(sys.stdin); print(d["channel"]["id"] if d.get("ok") else "ERR:"+str(d.get("error")))' 2>/dev/null)
case "${CHAN:-}" in
  ERR:*|"") log "conversations.open failed: ${CHAN:-empty/invalid response}"; exit 1 ;;
esac

TODAY=$(date '+%Y-%m-%d')
HEADER="📝 Standup draft for ${TODAY} — edit, then post into today's #phantom thread:"
BODY=$(printf '%s\n\n%s' "$HEADER" "$(cat "$DRAFT")")

RESP=$(curl -sS -X POST "$API/chat.postMessage" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H 'Content-type: application/json; charset=utf-8' \
  --data "$(python3 -c 'import sys,json
print(json.dumps({"channel":sys.argv[1],"text":sys.argv[2],"unfurl_links":False,"unfurl_media":False}))' "$CHAN" "$BODY")")
OK=$(printf '%s' "$RESP" | python3 -c 'import sys,json
d=json.load(sys.stdin); print("ok" if d.get("ok") else "ERR:"+str(d.get("error")))' 2>/dev/null)

case "${OK:-}" in
  ok) : > "$MARKER"; log "delivered standup draft to self-DM ($CHAN)"; exit 0 ;;
  *)  log "chat.postMessage failed: ${OK:-unparseable response}"; exit 1 ;;
esac
