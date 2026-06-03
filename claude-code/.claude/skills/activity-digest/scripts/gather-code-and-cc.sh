#!/usr/bin/env bash
# Gather the deterministic half of an activity digest: CODE (GitHub) + Claude Code.
#
# This script covers the two sources that have a CLI / local-file representation:
#   1. GitHub — PRs opened/merged/reviewed, issues closed, and commits on default
#      branches — via `gh search`. (Authored PRs are found by `--created`, so they
#      surface regardless of current state; no per-branch compare walk needed.)
#   2. Claude Code conversation history (~/.claude/projects/*.jsonl) — the
#      human-authored prompts you actually wrote, grouped by project/session.
#
# The OTHER two sources of the "core four" — Slack and Linear — live behind MCP
# servers, not CLIs. The activity-digest SKILL.md drives those via subagents.
# This script prints handoff stubs for them so the digest has placeholders.
#
# Window is a closed or open interval [SINCE, UNTIL]:
#   gather-code-and-cc.sh 2026-06-01                 # since date, open-ended (until now)
#   gather-code-and-cc.sh 2026-06-01 2026-06-01      # just that day
#   gather-code-and-cc.sh --days 7                   # last N days, open-ended
#
# Env:
#   GH_USER             override the resolved login (default: gh api user)
#   ORG_FILTER          optional org/user prefix — limits gh search to that org
#   GH_INCLUDE_COMMITS  set to 0 to skip the (fast) commits-on-default-branch search
#   CC_INCLUDE          set to 0 to skip Claude Code conversation history
#   CC_MAX_CHARS        truncate each cc prompt to N chars (default 600)
#   CC_EXCLUDE          space-separated cwd substrings to skip (default "src/personal")
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SINCE=""
UNTIL=""
if [ "${1:-}" = "--days" ] && [ -n "${2:-}" ]; then
  SINCE=$(python3 -c "import datetime; print((datetime.date.today()-datetime.timedelta(days=$2)).isoformat())")
else
  SINCE="${1:-}"
  UNTIL="${2:-}"
fi

if [ -z "${SINCE}" ]; then
  echo "usage: gather-code-and-cc.sh <SINCE-YYYY-MM-DD> [UNTIL-YYYY-MM-DD]" >&2
  echo "       gather-code-and-cc.sh --days N" >&2
  exit 2
fi

USER="${GH_USER:-$(gh api user --jq .login)}"

OWNER_ARGS=()
if [ -n "${ORG_FILTER:-}" ]; then
  OWNER_ARGS=(--owner "${ORG_FILTER}")
fi

# Build a gh-search date qualifier. CRITICAL: bare dates ("2026-06-01..") are
# interpreted by GitHub in UTC, which drops evening-local activity into the next
# UTC day. We pin the qualifier to the user's LOCAL timezone with explicit
# datetimes so a "single day" really is that local day.
#   gh search understands "A..B" (inclusive) and ">=A", and accepts ISO8601
#   datetimes with a timezone offset.
TZOFF=$(python3 -c "import datetime;print(datetime.datetime.now().astimezone().strftime('%z'))")
TZOFF="${TZOFF:0:3}:${TZOFF:3:2}"   # -0400 -> -04:00
if [ -n "${UNTIL}" ]; then
  DATEQ="${SINCE}T00:00:00${TZOFF}..${UNTIL}T23:59:59${TZOFF}"
  WINDOW="${SINCE}..${UNTIL} (local ${TZOFF})"
else
  DATEQ=">=${SINCE}T00:00:00${TZOFF}"
  WINDOW="${SINCE} → now (local ${TZOFF})"
fi

echo "=== Code + Claude Code activity for @${USER}  (${WINDOW}) ==="
echo

echo "--- Merged PRs (authored by ${USER}) ---"
gh search prs \
  --author "${USER}" \
  --merged-at "${DATEQ}" \
  "${OWNER_ARGS[@]}" \
  --json repository,number,title,url,body \
  --limit 100 \
  --jq '.[] | "
PR  \(.repository.nameWithOwner)#\(.number)  \(.title)
    \(.url)
    body:
\(.body // "(no description)" | gsub("\r"; "") | split("\n") | map("      " + .) | join("\n"))
"' || echo "(none or gh search unavailable)"

echo
# Use --created (the authoring event), NOT --updated. A PR you opened in the
# window but that has since been merged/closed/touched would fall out of an
# --updated window — exactly the failure that dropped same-day PRs before.
# Any state, so authored work that already merged still shows.
echo "--- PRs you opened in window (any current state) ---"
gh search prs \
  --author "${USER}" \
  --created "${DATEQ}" \
  "${OWNER_ARGS[@]}" \
  --json repository,number,title,url,state,isDraft \
  --limit 50 \
  --jq '.[] | "\(.state | ascii_upcase)\(if .isDraft then "/draft" else "" end)  \(.repository.nameWithOwner)#\(.number)  \(.title)\n    \(.url)"' || true

echo
echo "--- Closed issues (authored by ${USER}) ---"
gh search issues \
  --author "${USER}" \
  --state closed \
  --closed "${DATEQ}" \
  "${OWNER_ARGS[@]}" \
  --json repository,number,title,url \
  --limit 50 \
  --jq '.[] | "ISSUE \(.repository.nameWithOwner)#\(.number)  \(.title)\n    \(.url)"' || true

echo
echo "--- PRs you reviewed (updated in window) ---"
gh search prs \
  --reviewed-by "${USER}" \
  --updated "${DATEQ}" \
  "${OWNER_ARGS[@]}" \
  --json repository,number,title,url,state,author \
  --limit 50 \
  --jq '.[] | select(.author.login != "'"${USER}"'") | "REVIEW \(.state)  \(.repository.nameWithOwner)#\(.number)  \(.title)\n    \(.url)"' || true

if [ "${GH_INCLUDE_COMMITS:-1}" != "0" ]; then
  echo
  echo "--- Commits on default branches (across all repos) ---"
  gh search commits \
    --author "${USER}" \
    --author-date "${DATEQ}" \
    "${OWNER_ARGS[@]}" \
    --json sha,repository,commit,url \
    --limit 500 \
    --jq '
      group_by(.repository.fullName) | .[] |
        "\n  \(.[0].repository.fullName)   (\(length) commits)",
        (sort_by(.commit.author.date) | reverse | .[] |
          "    \(.sha[0:8])  \(.commit.author.date | sub("T.*"; ""))  \(.commit.message | split("\n")[0])")
    ' || echo "(gh search commits unavailable)"
fi

if [ "${CC_INCLUDE:-1}" != "0" ]; then
  echo
  echo "--- Claude Code conversations (your prompts, by project; src/personal excluded) ---"
  EXC_ARGS=()
  for x in ${CC_EXCLUDE:-src/personal}; do EXC_ARGS+=(--exclude "$x"); done
  UNTIL_ARGS=()
  [ -n "${UNTIL}" ] && UNTIL_ARGS=(--until "${UNTIL}")
  python3 "${SCRIPT_DIR}/pull-cc-history.py" \
    --since "${SINCE}" \
    "${UNTIL_ARGS[@]}" \
    "${EXC_ARGS[@]}" \
    --max-chars "${CC_MAX_CHARS:-600}" \
    || echo "(cc history walk failed)"
fi

echo
echo "--- Slack + Linear (agent fills these via MCP — see SKILL.md) ---"
echo "  Slack:  resolve the user's Slack handle (slack_search_users by email), then"
echo "          slack_search_public_and_private  'from:@<handle> after:${SINCE} before:<UNTIL+1d>'"
echo "          (pad bounds by a day to stay tz-safe and inclusive)."
echo "  Linear: list_issues has NO creator filter. Pull createdAt:>=${SINCE} AND updatedAt:>=${SINCE}"
echo "          (no assignee), then attribute by creator / completedAt / comment author client-side."

echo
echo "=== End ==="
