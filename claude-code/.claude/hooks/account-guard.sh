#!/usr/bin/env bash
# Block Claude Code session start if the active account doesn't match the cwd.
# Personal dir (~/src/personal/**) must NOT be the work account.
# Anywhere else must be the work account.
# Escape hatch: CLAUDE_SKIP_ACCOUNT_CHECK=1

set -u

WORK_EMAIL="jaxon.keeler@twenty.io"
PERSONAL_DIR="$HOME/src/personal"

if [ "${CLAUDE_SKIP_ACCOUNT_CHECK:-0}" = "1" ]; then
  exit 0
fi

input="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | /usr/bin/python3 -c 'import json,sys,os
try:
  d=json.loads(sys.stdin.read() or "{}")
  print(d.get("cwd") or d.get("workspace",{}).get("current_dir") or os.environ.get("PWD",""))
except Exception:
  print(os.environ.get("PWD",""))' 2>/dev/null)"
cwd="${cwd:-$PWD}"

# Resolve to absolute path
cwd_abs="$(cd "$cwd" 2>/dev/null && pwd -P || printf '%s' "$cwd")"
personal_abs="$(cd "$PERSONAL_DIR" 2>/dev/null && pwd -P || printf '%s' "$PERSONAL_DIR")"

active_email="$(/usr/bin/python3 -c 'import json
try: print(json.load(open("/Users/jaxon.keeler/.claude.json")).get("oauthAccount",{}).get("emailAddress",""))
except Exception: print("")' 2>/dev/null)"

if [ -z "$active_email" ]; then
  # Not logged in — let Claude Code handle login flow itself.
  exit 0
fi

case "$cwd_abs/" in
  "$personal_abs"/*)
    in_personal=1 ;;
  *)
    in_personal=0 ;;
esac

if [ "$in_personal" = "1" ] && [ "$active_email" = "$WORK_EMAIL" ]; then
  echo "" >&2
  echo "✋ Account guard: you are in $cwd_abs (personal dir) but logged in as $active_email (work)." >&2
  echo "   Run /login inside Claude Code to switch to your personal account, or set CLAUDE_SKIP_ACCOUNT_CHECK=1 to override." >&2
  echo "" >&2
  exit 2
fi

if [ "$in_personal" = "0" ] && [ "$active_email" != "$WORK_EMAIL" ]; then
  echo "" >&2
  echo "✋ Account guard: you are in $cwd_abs (work area) but logged in as $active_email (personal)." >&2
  echo "   Run /login inside Claude Code to switch back to $WORK_EMAIL, or set CLAUDE_SKIP_ACCOUNT_CHECK=1 to override." >&2
  echo "" >&2
  exit 2
fi

exit 0
