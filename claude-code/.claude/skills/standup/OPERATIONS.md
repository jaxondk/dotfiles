# standup automation — operations / teardown

Context a future agent needs to **edit or remove** the unattended daily-standup
automation. The skill logic is in `SKILL.md`; this file records the parts that
live **outside** the repo (machine state, scheduler, logs, side artifacts) and
the exact commands to manage them. Set up 2026-06-03. User uid is `503` (the
`gui/$(id -u)` commands below resolve to `gui/503`).

## What it does (one line)

A macOS launchd agent runs `claude -p "/standup --unattended"` every weekday at
**09:55 ET** (5 min after the #phantom stand-up bot posts), which builds the day's
`activity-digest` and creates — never sends — a Slack standup **draft** in that
day's #phantom thread for the user to review and send.

## Files

### In the repo (version-controlled; edit here, normal git/stow workflow)
`~/dotfiles/claude-code/.claude/skills/` (stowed into `~/.claude/skills/` via symlink)
- `standup/SKILL.md` — the projection skill, incl. the `## Unattended mode` section.
- `standup/scripts/run-unattended.sh` — wrapper launchd executes (sets PATH, runs claude, logs).
- `standup/scripts/unattended.settings.json` — scoped permissions: allows read + `slack_send_message_draft`, **denies `slack_send_message`**.
- `standup/scripts/com.jaxonkeeler.standup-draft.plist` — **reference copy** of the LaunchAgent (the live one is installed elsewhere, see below).
- `activity-digest/SKILL.md` + `activity-digest/scripts/{gather-code-and-cc.sh,pull-cc-history.py}` — the gather layer the standup projects from.

### Outside the repo (NOT version-controlled — the actual machine state)
- **`~/Library/LaunchAgents/com.jaxonkeeler.standup-draft.plist`** — the LIVE LaunchAgent (a copy of the reference plist). This is what's loaded into launchd.
- **`~/Library/Logs/standup-draft.log`** — per-run human-readable log (wrapper appends start/finish + claude output).
- **`~/Library/Logs/standup-draft.out.log`** / **`.err.log`** — launchd stdout/stderr.
- **`~/src/activity-digest/`** — the digest data repo (git-init'd; `digests/YYYY-MM-DD.md` + `AGENTS.md`). Created for this system; shared with the `activity-digest` skill generally, so only delete if tearing the whole system down.

### Stray side artifact to clean up manually
- A **self-DM test message** in the user's Slack (DM channel `D09NXJCV8G2`, ts `1780500064.782119`, text "formatting test — safe to delete"). There's no delete-message MCP tool, so the user must delete it by hand in Slack. Harmless if left.

## Manage the schedule (launchd, user domain `gui/$(id -u)`)

```bash
# status (shows label if loaded)
launchctl list | grep standup-draft

# run it right now (exact path launchd uses)
launchctl kickstart -k gui/$(id -u)/com.jaxonkeeler.standup-draft

# inspect resolved schedule / last exit
launchctl print gui/$(id -u)/com.jaxonkeeler.standup-draft

# DISABLE (unload) — stops it firing; leaves files in place
launchctl bootout gui/$(id -u)/com.jaxonkeeler.standup-draft

# RE-ENABLE (load)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jaxonkeeler.standup-draft.plist
```

## Common edits

- **Change the time / weekdays:** edit `StartCalendarInterval` in BOTH the repo
  reference plist and `~/Library/LaunchAgents/...plist` (or edit repo copy then
  `cp` it over), then reload: `bootout` then `bootstrap` (a plist change needs a reload).
  Weekday: 1=Mon … 5=Fri. Times are **system-local** (so they track ET only while
  the Mac is on ET).
- **Change what it runs / permissions / behavior:** edit `run-unattended.sh`,
  `unattended.settings.json`, or the SKILL.md files. **No launchd reload needed** —
  launchd just re-execs the wrapper each fire.
- **Change model/flags:** edit the `claude -p …` invocation in `run-unattended.sh`.

## FULL REMOVAL checklist

```bash
# 1. unload + delete the live LaunchAgent
launchctl bootout gui/$(id -u)/com.jaxonkeeler.standup-draft 2>/dev/null
rm -f ~/Library/LaunchAgents/com.jaxonkeeler.standup-draft.plist

# 2. logs
rm -f ~/Library/Logs/standup-draft.log ~/Library/Logs/standup-draft.out.log ~/Library/Logs/standup-draft.err.log
```
Then, depending on how much you're removing:
- **Just the automation, keep the skills:** delete only `run-unattended.sh`,
  `unattended.settings.json`, `com.jaxonkeeler.standup-draft.plist`, this file, and
  the `## Unattended mode` section of `standup/SKILL.md`.
- **The whole standup/activity-digest system:** also remove the `standup/` and
  `activity-digest/` skill dirs from `~/dotfiles/.../skills/` (re-stow / drop symlinks),
  `rm -rf ~/src/activity-digest`, and delete the memory files
  `project_activity_digest_skill.md` (+ its line in `MEMORY.md`) under
  `~/.claude/projects/-Users-jaxon-keeler-src-firecrew-ecosystem/memory/`.
- Manually delete the Slack self-DM test message (above).

## Safety invariants (don't regress these when editing)
- The job must **only ever create a draft**, never send. Enforced 3 ways: SKILL.md
  says don't; `unattended.settings.json` denies `slack_send_message`; and the harness
  would prompt anyway. Keep the deny entry.
- Headless runs can't answer permission prompts — keep the allowlist complete enough
  that needed tools run, but note an over-tight list yields an *incomplete draft*,
  never a hang or a send.
