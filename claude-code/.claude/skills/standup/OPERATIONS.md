# standup automation — operations / teardown

Context for editing or removing the **unattended daily-standup** automation. The
skill logic is in `SKILL.md`; this file records the parts that live **outside** the
repo (the launchd agent, logs, side artifacts) and the exact commands to manage
them. Everything here is **user-agnostic** — paths use `$HOME`, the launchd domain
uses `$(id -u)`, and the agent label is the neutral `com.firecrew.standup-draft`,
so each teammate installs their own copy with the same commands.

## What it does (one line)

A per-user macOS launchd agent runs `claude -p "/standup --unattended"` every
weekday at **09:55 local** (just after the #phantom stand-up bot posts at 09:50),
which builds the day's `activity-digest`, drafts the standup, and **DMs that draft
to the user** for them to review, edit, and post into #phantom themselves.

## Why delivery is two-stage (the headless-Slack constraint)

The claude.ai **Slack/Linear connectors only load in the interactive client** —
they are *absent* in a headless `claude -p` / cron session (confirmed empirically:
the model finds no `slack_*` tool at all). So the unattended run **cannot** read
Slack, resolve the #phantom thread, or place a native Slack draft. Delivery is
therefore split:

1. **Stage 1 (model):** `claude -p "/standup --unattended"` gathers code+CC, drafts
   the standup, and writes **only the `y:/t:/b:` body** to `$STANDUP_DRAFT_FILE`
   (set by `run-unattended.sh` to `${TMPDIR:-/tmp}/standup-draft-<date>.md`).
2. **Stage 2 (bash):** `run-unattended.sh` calls `deliver-to-slack-dm.sh`, which
   reads a Slack token from `~/.config/standup/slack-dm.env` and posts that file to
   the user's **own Slack DM** via the Web API. The model never sees the token, and
   the deliverer's destination is hardcoded to the self-DM (`conversations.open` on
   the user's own id) — it can never post to a channel.

Consequences vs. the old (never-worked-headlessly) design: there is **no true
unsent Slack "draft"** (only the interactive connector can make one) — the user
gets a real DM message to copy/edit. Slack/Linear are also absent as *gather*
inputs, so the unattended digest is code+CC only (Slack/Linear recorded as gaps).
For the full experience (Slack draft in-thread, Slack/Linear gathering, `t:`/`b:`
conversation) run `/standup` **interactively**, where the connectors are present.

## One-time setup: Slack token for headless delivery

Without this, stage 1 still runs and the draft is saved to disk; stage 2 just logs
"no Slack config" and skips. To enable the DM:

```bash
SK=~/dotfiles/claude-code/.claude/skills/standup/scripts
mkdir -p ~/.config/standup
cp "$SK/slack-dm.env.example" ~/.config/standup/slack-dm.env
chmod 600 ~/.config/standup/slack-dm.env
$EDITOR ~/.config/standup/slack-dm.env     # set SLACK_TOKEN + SLACK_DM_USER_ID

# test (no scheduled run needed):
printf 'y:\n- setup test\nt:\n- (proposed)\nb:\n- none\n' > /tmp/standup-test.md
bash "$SK/deliver-to-slack-dm.sh" /tmp/standup-test.md   # expect a DM; check ~/Library/Logs/standup-draft.log
```

- **`SLACK_TOKEN`** — either a **bot token** (`xoxb-…`, app scopes `chat:write` +
  `im:write`; DM arrives from the app) or a **user token** (`xoxp-…`, scope
  `chat:write`; DM arrives as a message-to-self). Create an app at
  https://api.slack.com/apps if you don't have one. The file must be `chmod 600`
  and is **never committed** (only the `.env.example` template is in the repo).
- **`SLACK_DM_USER_ID`** — your own Slack member id (the interactive
  `slack_search_users` reports the logged-in id; or Slack profile → Copy member ID).

## Install / uninstall (each teammate runs these for themselves)

```bash
SK=~/dotfiles/claude-code/.claude/skills/standup/scripts   # wherever the skill is stowed

# install (or reinstall — idempotent). Schedule defaults to weekdays 09:55 local;
# override with STANDUP_HOUR / STANDUP_MIN.
bash "$SK/install-launchd.sh"
STANDUP_HOUR=9 STANDUP_MIN=50 bash "$SK/install-launchd.sh"   # example: change time

# uninstall (leaves skill files + logs)
bash "$SK/uninstall-launchd.sh"
```

`install-launchd.sh` generates `~/Library/LaunchAgents/com.firecrew.standup-draft.plist`
from the current user's `$HOME`/uid and bootstraps it. There is no static plist
checked into the repo — the installer is the source of truth.

## Files

### In the repo (version-controlled; stowed into `~/.claude/skills/`)
- `standup/SKILL.md` — the projection skill, incl. `## Unattended mode`.
- `standup/scripts/run-unattended.sh` — wrapper launchd executes (self-locating; sets PATH + `$STANDUP_DRAFT_FILE`, runs claude, then runs the deliverer, logs).
- `standup/scripts/deliver-to-slack-dm.sh` — stage 2: posts the drafted file to the user's self-DM via the Slack Web API. Deterministic; reads the token; the model never invokes it.
- `standup/scripts/slack-dm.env.example` — template for the (gitignored) `~/.config/standup/slack-dm.env` token file.
- `standup/scripts/unattended.settings.json` — scoped permissions for stage 1. (The `slack_*` allow/deny entries are now moot headlessly — no Slack tools load — but kept harmless in case connectors ever become available; the **deny `slack_send_message`** stays as defense-in-depth.)
- `standup/scripts/install-launchd.sh` / `uninstall-launchd.sh` — per-user agent install/remove.
- `activity-digest/SKILL.md` + `activity-digest/scripts/{gather-code-and-cc.sh,pull-cc-history.py}` — the gather layer this projects from.

### Outside the repo (machine state, NOT version-controlled)
- **`~/Library/LaunchAgents/com.firecrew.standup-draft.plist`** — the live agent (generated by the installer).
- **`~/Library/Logs/standup-draft.log`** — per-run human-readable log.
- **`~/Library/Logs/standup-draft.out.log`** / **`.err.log`** — launchd stdout/stderr.
- **`~/src/activity-digest/`** — the digest data repo (`digests/YYYY-MM-DD.md` + `AGENTS.md`); override location with `$ACTIVITY_DIGEST_REPO`. Shared with the `activity-digest` skill generally, so only delete if tearing the whole system down.
- **`~/.config/standup/slack-dm.env`** — the Slack token (`chmod 600`, holds a secret). Created by you per the setup section; never version-controlled.
- **`${TMPDIR:-/tmp}/standup-draft-<date>.md`** (+ `.delivered` marker) — per-day draft handoff file from stage 1 → stage 2. `run-unattended.sh` clears it at the start of each run; safe to delete anytime.

### Possible side artifact
- The self-DM messages are real Slack messages from the delivery bot/user token. There's no delete-message step here — clear them in Slack by hand if you want. Harmless if left.

## Manage the schedule (launchd, user domain `gui/$(id -u)`)

```bash
launchctl list | grep standup-draft                                  # status
launchctl kickstart -k gui/$(id -u)/com.firecrew.standup-draft       # run now
launchctl print     gui/$(id -u)/com.firecrew.standup-draft          # inspect schedule / last exit
launchctl bootout   gui/$(id -u)/com.firecrew.standup-draft          # disable (or use uninstall script)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.firecrew.standup-draft.plist   # re-enable
```

## Common edits

- **Time / weekdays:** re-run `install-launchd.sh` with `STANDUP_HOUR`/`STANDUP_MIN`
  (it regenerates the plist and reloads). Weekday in the plist: 1=Mon … 5=Fri.
  Times are **system-local** (track ET only while the Mac is on ET).
- **What it runs / permissions / behavior:** edit `run-unattended.sh`,
  `unattended.settings.json`, or the SKILL.md files. **No reload needed** — launchd
  re-execs the wrapper each fire.
- **Model / flags:** edit the `claude -p …` invocation in `run-unattended.sh`.

## FULL REMOVAL checklist

```bash
SK=~/dotfiles/claude-code/.claude/skills/standup/scripts
bash "$SK/uninstall-launchd.sh"                                       # unload + delete live plist
rm -f ~/Library/Logs/standup-draft.log ~/Library/Logs/standup-draft.out.log ~/Library/Logs/standup-draft.err.log
rm -f ~/.config/standup/slack-dm.env                                  # the Slack token (secret)
```
Then, depending on scope:
- **Just the automation, keep the skills:** also delete `run-unattended.sh`,
  `deliver-to-slack-dm.sh`, `slack-dm.env.example`, `unattended.settings.json`,
  `install-launchd.sh`, `uninstall-launchd.sh`, this file,
  and the `## Unattended mode` section of `standup/SKILL.md`.
- **The whole standup/activity-digest system:** also remove the `standup/` and
  `activity-digest/` skill dirs (re-stow / drop symlinks), `rm -rf ~/src/activity-digest`,
  and delete any activity-digest/standup memory files you created under
  `~/.claude/projects/<encoded-cwd>/memory/` (+ their lines in `MEMORY.md`).
- Manually delete the Slack self-DM test message if one exists.

## Safety invariants (don't regress when editing)
- **The unattended job posts only to the user's own DM, never a channel.** The
  destination in `deliver-to-slack-dm.sh` is hardcoded to `conversations.open` on
  `SLACK_DM_USER_ID` (the user's own id) → `chat.postMessage` to that DM channel.
  Never accept a channel id from the model, the draft file, or the digest, and
  never add a #phantom-posting path to the unattended flow. Public posting stays a
  human action (interactive `/standup` makes the in-thread draft; the user sends).
- **The model never sees the Slack token.** Stage 1 (`claude -p`) only writes a
  file; stage 2 (bash) reads `~/.config/standup/slack-dm.env` and does the send.
  Don't pass the token into the `claude` invocation or expose it via env to the
  model's tools. Keep `slack-dm.env` `chmod 600` and out of git (only the
  `.example` is committed).
- The legacy interactive guarantee still holds: `unattended.settings.json` keeps
  **deny `slack_send_message`** as defense-in-depth (those tools don't load
  headlessly anyway, but keep the deny entry).
- Stage-2 failures (no token, Slack error) are **logged, never fatal** — the draft
  is always preserved at `$STANDUP_DRAFT_FILE`, so a delivery outage degrades to
  "the draft is on disk", never a lost standup or a hang.
