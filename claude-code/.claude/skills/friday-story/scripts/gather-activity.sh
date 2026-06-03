#!/usr/bin/env bash
# Gather this week's activity for the Friday-story reframe.
#
# Two data sources, glued together:
#   1. GitHub (PRs merged/opened/reviewed, issues closed, commits direct-to-main,
#      and non-default-branch work) — via `gh search` + per-repo compare API.
#   2. Claude Code conversation history (~/.claude/projects/*.jsonl) — the
#      human-authored prompts you actually wrote, grouped by project/session.
#      This catches work that never made it to a PR: debugging, design,
#      exploration, pairing, anything you only ever talked to Claude about.
#
# Usage:
#   gather-activity.sh                 # since last Friday
#   gather-activity.sh 2026-05-15      # since explicit YYYY-MM-DD
#   gather-activity.sh --days 7        # since N days ago
#
# Env:
#   GH_USER             override the resolved login (default: gh api user)
#   ORG_FILTER          optional org/user prefix — limits gh search to that org
#   GH_INCLUDE_COMMITS  set to 0 to skip direct-to-main + non-default-branch walk
#   CC_INCLUDE          set to 0 to skip Claude Code conversation history
#   CC_MAX_CHARS        truncate each cc prompt to N chars (default 600)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SINCE=""
if [ "${1:-}" = "--days" ] && [ -n "${2:-}" ]; then
  SINCE=$(python3 -c "import datetime; print((datetime.date.today()-datetime.timedelta(days=$2)).isoformat())")
elif [ -n "${1:-}" ]; then
  SINCE="$1"
else
  # Most-recent past Friday (if today IS Friday, use last Friday — one week back).
  SINCE=$(python3 -c "
import datetime
t = datetime.date.today()
d = (t.weekday() - 4) % 7
if d == 0:
    d = 7
print((t - datetime.timedelta(days=d)).isoformat())
")
fi

USER="${GH_USER:-$(gh api user --jq .login)}"

OWNER_ARGS=()
if [ -n "${ORG_FILTER:-}" ]; then
  OWNER_ARGS=(--owner "${ORG_FILTER}")
fi

echo "=== Activity for @${USER} since ${SINCE} ==="
echo

echo "--- Merged PRs (authored by ${USER}) ---"
gh search prs \
  --author "${USER}" \
  --merged-at ">=${SINCE}" \
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
echo "--- Open PRs (authored, updated since ${SINCE}) ---"
gh search prs \
  --author "${USER}" \
  --state open \
  --updated ">=${SINCE}" \
  "${OWNER_ARGS[@]}" \
  --json repository,number,title,url,isDraft \
  --limit 50 \
  --jq '.[] | "OPEN\(if .isDraft then "/draft" else "" end)  \(.repository.nameWithOwner)#\(.number)  \(.title)\n    \(.url)"' || true

echo
echo "--- Closed issues (authored by ${USER}) ---"
gh search issues \
  --author "${USER}" \
  --state closed \
  --closed ">=${SINCE}" \
  "${OWNER_ARGS[@]}" \
  --json repository,number,title,url \
  --limit 50 \
  --jq '.[] | "ISSUE \(.repository.nameWithOwner)#\(.number)  \(.title)\n    \(.url)"' || true

echo
echo "--- PRs you reviewed (updated since ${SINCE}) ---"
gh search prs \
  --reviewed-by "${USER}" \
  --updated ">=${SINCE}" \
  "${OWNER_ARGS[@]}" \
  --json repository,number,title,url,state,author \
  --limit 50 \
  --jq '.[] | select(.author.login != "'"${USER}"'") | "REVIEW \(.state)  \(.repository.nameWithOwner)#\(.number)  \(.title)\n    \(.url)"' || true

# --- Commits-on-default-branch + non-default-branch walk ---
# (See the upstream friday-story SKILL.md for the rationale on each query.)
if [ "${GH_INCLUDE_COMMITS:-1}" != "0" ]; then
  echo
  echo "--- Commits on default branches (across all repos) ---"
  gh search commits \
    --author "${USER}" \
    --author-date ">=${SINCE}" \
    "${OWNER_ARGS[@]}" \
    --json sha,repository,commit,url \
    --limit 500 \
    --jq '
      group_by(.repository.fullName) | .[] |
        "\n  \(.[0].repository.fullName)   (\(length) commits)",
        (sort_by(.commit.author.date) | reverse | .[] |
          "    \(.sha[0:8])  \(.commit.author.date | sub("T.*"; ""))  \(.commit.message | split("\n")[0])")
    ' || echo "(gh search commits unavailable)"

  echo
  echo "--- Active non-default branches with your commits (since ${SINCE}) ---"
  OWNERS_TO_SCAN=()
  if [ -n "${ORG_FILTER:-}" ]; then
    OWNERS_TO_SCAN+=("${ORG_FILTER}")
  else
    while IFS= read -r O; do
      [ -n "$O" ] && OWNERS_TO_SCAN+=("$O")
    done < <(gh api user/orgs --jq '.[].login' 2>/dev/null || true)
  fi

  SINCE_ISO="${SINCE}T00:00:00Z"
  SEEN=$(mktemp -t friday-seen.XXXXXX)
  trap 'rm -f "${SEEN}"' EXIT
  : > "${SEEN}"

  for OWNER in "${OWNERS_TO_SCAN[@]}"; do
    REPOS=$(gh repo list "${OWNER}" --limit 300 \
      --json nameWithOwner,pushedAt,isArchived,defaultBranchRef \
      2>/dev/null | jq -r --arg since "${SINCE_ISO}" '
        .[] | select(.isArchived | not) | select(.pushedAt >= $since) |
        "\(.nameWithOwner)|\(.defaultBranchRef.name // "main")"' || true)
    while IFS='|' read -r REPO DEFAULT_BRANCH; do
      [ -z "$REPO" ] && continue
      BRANCHES=$(gh api "repos/${REPO}/branches?per_page=100" --jq '.[].name' 2>/dev/null || true)
      for B in ${BRANCHES}; do
        [ "${B}" = "${DEFAULT_BRANCH}" ] && continue
        case "${B}" in gh-readonly-queue/*) continue ;; esac
        CANDIDATES=$(gh api "repos/${REPO}/compare/${DEFAULT_BRANCH}...${B}" 2>/dev/null \
          | jq -r --arg u "${USER}" --arg s "${SINCE_ISO}" '
              .commits // [] |
              map(select(.author.login == $u)) |
              map(select(.commit.author.date >= $s)) |
              sort_by(.commit.author.date) | reverse | .[] |
              "\(.sha[0:8])|\(.commit.author.date | sub("T.*"; ""))|\(.commit.message | split("\n")[0])"' \
          2>/dev/null || true)
        [ -z "${CANDIDATES}" ] && continue
        NEW=""
        while IFS='|' read -r SHA DATE MSG; do
          [ -z "${SHA}" ] && continue
          if ! grep -qFx "${SHA}" "${SEEN}"; then
            NEW="${NEW}    ${SHA}  ${DATE}  ${MSG}"$'\n'
            echo "${SHA}" >> "${SEEN}"
          fi
        done <<< "${CANDIDATES}"
        if [ -n "${NEW}" ]; then
          N=$(printf '%s' "${NEW}" | grep -c .)
          echo
          echo "  ${REPO}  ${B}  (${N} new commits)"
          printf '%s' "${NEW}"
        fi
      done
    done <<< "${REPOS}"
  done
fi

# --- Claude Code conversation history (~/.claude/projects/*.jsonl) ---
#
# Catches everything that never showed up in git: debugging sessions, design
# conversations, investigations that dead-ended, prompts that became commits
# later via other branches, anything you only ever talked to Claude about.
# The agent uses these to reconstruct *what you were thinking about* this
# week, not just what landed.
if [ "${CC_INCLUDE:-1}" != "0" ]; then
  echo
  echo "--- Claude Code conversations (your prompts, by project) ---"
  python3 "${SCRIPT_DIR}/pull-cc-history.py" \
    --since "${SINCE}" \
    --max-chars "${CC_MAX_CHARS:-600}" \
    || echo "(cc history walk failed)"
fi

# --- Slack handoff ---
#
# Slack lives behind the MCP server, not a CLI, so this script can't pull it
# directly. The agent fills this section in by calling the Slack MCP tools
# itself — see the SKILL.md "Pulling Slack" section for the exact queries.
echo
echo "--- Slack (agent must fill this in via MCP) ---"
echo "  Use slack_search_public_and_private with 'from:@${USER} after:${SINCE}'"
echo "  and slack_search_users to resolve the user's Slack handle first if needed."

echo
echo "=== End ==="
