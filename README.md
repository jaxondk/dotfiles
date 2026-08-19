# Dotfiles

Managed with [chezmoi](https://chezmoi.io). One command sets up a new machine:
identity prompts, package installs, configs, and editor/AI tooling all land in place.

## New machine

```bash
gh repo clone jaxondk/dotfiles ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` installs chezmoi if needed, then runs `chezmoi init --apply` against this
repo. On first run it asks a few questions (name, git email, work email, optional
personal git identity), installs packages, writes all configs, and runs `bun install`
for the opencode plugins. Re-running is safe.

Then drop secrets in place (see [Secrets](#secrets)) and restart your shell: `exec zsh`.

## How it works (chezmoi in 30 seconds)

chezmoi keeps a **source** (this repo, specifically the `home/` subdirectory) and
writes **real files** into `$HOME` when you run `chezmoi apply`. Source filenames use
prefixes that encode attributes:

| Source name (under `home/`)        | Becomes                         |
| ---------------------------------- | ------------------------------- |
| `dot_zshrc`                        | `~/.zshrc`                      |
| `dot_config/nvim/init.lua`         | `~/.config/nvim/init.lua`      |
| `dot_gitconfig.tmpl`               | `~/.gitconfig` (templated)      |
| `executable_foo.sh`                | `~/foo.sh` with `+x`            |
| `symlink_bar.tmpl`                 | a symlink whose target is the rendered file contents |
| `run_once_*.sh.tmpl`               | a script run once per machine   |

`.tmpl` files are Go templates filled from the answers you gave at init (stored in
`~/.config/chezmoi/chezmoi.toml`). That's how the same repo produces the right
identity and `$HOME` paths on any machine.

`.chezmoiroot` points chezmoi at `home/`, so everything outside `home/` (this README,
`install.sh`, `agentic/`) is plain repo content that chezmoi ignores.

This repo **is** the chezmoi source: `install.sh` runs `chezmoi init --source=~/dotfiles`,
so the source stays at `~/dotfiles` (not chezmoi's default `~/.local/share/chezmoi`).
`chezmoi` commands work from any directory.

## Daily use

You no longer edit `~/.zshrc` directly (it's a real file, not a symlink). Instead:

```bash
chezmoi edit ~/.zshrc        # edit the source, auto-applies on save
chezmoi cd                   # jump into the source dir (~/dotfiles/home)
chezmoi apply                # apply pending source changes to $HOME
chezmoi diff                 # preview what apply would change
chezmoi status               # short list of what's out of sync
chezmoi re-add               # pull edits you made directly in $HOME back into source
chezmoi update               # git pull + apply (sync another machine)
chezmoi data                 # dump the template variables (debug .tmpl files)
```

`chezmoi edit` on a templated target (e.g. `chezmoi edit ~/.gitconfig`) opens the
**template** — you'll see `{{ ... }}` syntax; keep it intact. After editing in
`chezmoi cd`, commit and push like any repo.

### The one thing to internalize

There are now **two** gaps, and `git status` only sees one of them:

```
source (home/)  ←── chezmoi status ──→  $HOME
      └── git status ──→ commits
```

Editing `~/.zshrc` directly changes **nothing** in this repo — `git status` stays empty;
only `chezmoi status` sees it. (Under the old stow setup this gap didn't exist, because
the file in `$HOME` *was* the file in the repo.) And `chezmoi apply` closes that gap by
overwriting `$HOME` from the source — so an in-place edit you forgot about is destroyed
silently, with no git history to recover it from.

**Habit: run `chezmoi status` before `chezmoi apply`.** In its two-letter output the
first column is drift since chezmoi last wrote the file, the second is what `apply` will
do. Full picture in one shot:

```bash
chezmoi status && git status --short
```

Edited something in `$HOME` and want to keep it? `chezmoi re-add <file>`, then commit.
Want to discard it? `chezmoi apply`. Both are avoided entirely by using `chezmoi edit`
in the first place.

Three things behave differently:

- **Templates** (`.tmpl`) — `chezmoi re-add` refuses to overwrite them and says nothing,
  so an in-place edit to e.g. `~/.gitconfig` is silently orphaned and dies at the next
  apply. Always `chezmoi edit` these.
- **`~/.claude/settings.json`** — the output of a `modify_` script, not a stored file.
  Hand edits survive *except* the few keys the script enforces; change those in
  `home/dot_claude/modify_settings.json.tmpl`.
- **Tool-owned files** — never show up in `chezmoi status` at all. See
  [Deliberately not managed](#deliberately-not-managed).

### Add a new config file

```bash
chezmoi add ~/.config/foo/config.toml      # imports it into the source tree
chezmoi cd && git add . && git commit       # then commit
```

### Remove / stop managing a file

```bash
chezmoi forget ~/.config/foo/config.toml   # stop managing it; leaves the file in $HOME
chezmoi destroy ~/.config/foo/config.toml  # remove it from BOTH source and $HOME
```

### Change your init answers (name, emails, personal identity)

Answers live in `~/.config/chezmoi/chezmoi.toml` under `[data]`. To change them, either
edit that file directly, or force the prompts to run again (a plain `chezmoi init` skips
them once they're set):

```bash
chezmoi init --prompt    # re-ask every question (current values are the defaults)
chezmoi apply            # re-render templated files with the new values
```

## What's managed

- **zsh** — `.zshrc`, plugins (antidote), `~/.zsh/functions.zsh`
- **git** — `.gitconfig` (templated identity) + global ignore; optional personal identity
- **ghostty / starship / nvim (LazyVim) / direnv / herdr / worktrunk** — `~/.config/*`
- **opencode** — `~/.config/opencode` (plugins via `bun install`)
- **Claude Code** — `~/.claude/{hooks,commands,agents,skills,scripts}`; `settings.json` is
  merged by a `modify_` script rather than overwritten (see below)
- **skills library** — public skills vendored under `~/.agents/skills`, exposed to Claude
  via symlinks

See [AGENTS.md](AGENTS.md) for the full layout and conventions.

### Deliberately not managed

Files that the tools themselves write and rewrite. Tracking these means every machine
clobbers every other one with a stale snapshot, and chezmoi ends up fighting a running
process for the file:

- `~/.claude/hooks/herdr-agent-state.sh` — generated by `herdr integration install claude`
  (done by `run_once_after_40`). It carries a `HERDR_INTEGRATION_VERSION` that herdr bumps;
  a tracked copy pins every machine to whatever version was committed.
- `~/.claude/plugins/{installed_plugins,known_marketplaces}.json` — Claude Code rewrites
  these whenever a plugin or marketplace changes.
- `~/.agents/.skill-lock.json` — rewritten on skill install.

The rule of thumb: **if a tool generates it when you install or use it, track the command,
not the output.** Two useful tests — would you be unhappy if this were regenerated from
scratch on a new machine, and does the tool write to it behind your back while you work?

Lockfiles are the deliberate exception: `lazy-lock.json` and `package-lock.json` are
generated too, but pinning exact versions *is* the point, so they stay tracked.

`settings.json` is the mixed case — herdr owns its `hooks` entries, Claude Code owns
`enabledPlugins`, and we own a handful of preferences. A static managed file would make
every `apply` revert the other two owners, so `modify_settings.json.tmpl` enforces only
our keys and passes everything else through untouched.

## Secrets

Secrets are **not** managed by chezmoi. Recreate these per machine:

- `~/.zsh_secrets` and `~/.zshrc.local` — sourced by `.zshrc` if present. `~/.zshrc.local`
  is also the right home for anything machine-local but non-secret (a PATH entry for a
  tool installed outside Homebrew, a one-off function) — it keeps the tracked `.zshrc`
  identical across machines.
- `~/.config/opencode/kdco-notify.json` — Slack webhook (copy from `kdco-notify.example.json`)

## Claude Code skills

- **Authored skills** (e.g. `activity-digest`, `standup`, `friday-story`) live as real
  files in the repo and deploy directly.
- **Public skills** (mattpocock/skills, playwriter, …) are vendored under
  `home/dot_agents/skills/` and surfaced as symlinks in `~/.claude/skills`. The set is
  pinned in `~/.agents/.skill-lock.json`.
- **Work skills** (`shadow-*`, `mission*`) are symlinks into the private
  `Twenty-IO/shadow-factory` repo. They're only deployed when that repo is cloned at
  `~/src/xx-internal-ai/shadow-factory` — otherwise chezmoi skips them, so a fresh or
  personal box never gets dangling links.

## The `agentic/` directory

`agentic/` is the canonical, harness-agnostic source for some agent definitions, synced
into each tool by the `sync-agentic` skill. It is **not** a chezmoi-managed target — it
stays as plain repo content.
