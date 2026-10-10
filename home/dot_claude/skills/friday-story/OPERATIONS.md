# friday-story automation — operations / teardown

Context for editing/removing the **unattended weekly friday-story** automation. Skill
logic is in `SKILL.md` (incl. `## Unattended mode`); this records the out-of-repo
machine state and the commands to manage it. User-agnostic: paths use `$HOME`, the
launchd domain uses `$(id -u)`, the label is the neutral `com.firecrew.friday-story`.

## What it does (one line)

A per-user macOS launchd agent runs `claude -p "/friday-story --unattended"` every
**Thursday at 11:00 local**, which builds the **last-7-days** `activity-digest` and
creates — never sends — a capability-gain "friday story" **draft in the user's
personal Slack DM**, ready to review before the Friday sync.

## Install / uninstall (each teammate runs for themselves)

```bash
SK=~/dotfiles/claude-code/.claude/skills/friday-story/scripts

bash "$SK/install-launchd.sh"        # Thursday 11:00 local by default
# override schedule: FRIDAY_STORY_WEEKDAY (1=Mon..5=Fri) / FRIDAY_STORY_HOUR / FRIDAY_STORY_MIN
FRIDAY_STORY_HOUR=10 bash "$SK/install-launchd.sh"

bash "$SK/uninstall-launchd.sh"      # remove (leaves skill files + logs)
```

The installer generates `~/Library/LaunchAgents/com.firecrew.friday-story.plist`
from the current user's `$HOME`/uid and bootstraps it. No static plist is checked in.

## Files

### In the repo (version-controlled; stowed into `~/.claude/skills/`)
- `friday-story/SKILL.md` — the projection skill (capability-gain framing), incl. `## Unattended mode`.
- `friday-story/scripts/run-unattended.sh` — wrapper launchd executes.
- `friday-story/scripts/unattended.settings.json` — scoped perms: read + `slack_send_message_draft`, **denies `slack_send_message`**.
- `friday-story/scripts/install-launchd.sh` / `uninstall-launchd.sh`.
- (Gathering is delegated to the `activity-digest` skill — friday-story has no gather scripts of its own.)

### Outside the repo (machine state)
- **`~/Library/LaunchAgents/com.firecrew.friday-story.plist`** — live agent (generated).
- **`~/Library/Logs/friday-story.log`** — per-run log; plus `.out.log` / `.err.log`.
- Draft output lands in the user's **self-DM** in Slack (not a channel) — review/edit there, then paste into the Friday sync.

## Manage the schedule (`gui/$(id -u)`)

```bash
launchctl list | grep friday-story                                  # status
launchctl kickstart -k gui/$(id -u)/com.firecrew.friday-story       # run now
launchctl print     gui/$(id -u)/com.firecrew.friday-story          # inspect
launchctl bootout   gui/$(id -u)/com.firecrew.friday-story          # disable
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.firecrew.friday-story.plist
```

## Common edits
- **Time / day:** re-run `install-launchd.sh` with the `FRIDAY_STORY_*` env vars (regenerates + reloads). Times are **system-local**.
- **Window / behavior / delivery target:** edit the `## Unattended mode` section of `SKILL.md` (it specifies 7-day window + self-DM draft). No reload needed.
- **Permissions:** edit `unattended.settings.json` — keep the `slack_send_message` deny.

## FULL REMOVAL
```bash
SK=~/dotfiles/claude-code/.claude/skills/friday-story/scripts
bash "$SK/uninstall-launchd.sh"
rm -f ~/Library/Logs/friday-story.log ~/Library/Logs/friday-story.out.log ~/Library/Logs/friday-story.err.log
```
To drop the automation but keep the skill: also delete the four `scripts/` files and the `## Unattended mode` section of `SKILL.md`.

## Safety invariant
Only ever a **draft**, never a send — enforced by SKILL.md, the settings deny, and the harness. Keep the deny entry. (See the standup skill's `OPERATIONS.md` for the same pattern; this is its weekly sibling.)
