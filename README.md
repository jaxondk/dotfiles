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
- **Claude Code** — `~/.claude/{settings.json,hooks,commands,agents,skills,scripts,plugins}`
- **skills library** — public skills vendored under `~/.agents/skills` + pinned by
  `~/.agents/.skill-lock.json`; exposed to Claude via symlinks

See [AGENTS.md](AGENTS.md) for the full layout and conventions.

## Secrets

Secrets are **not** managed by chezmoi. Recreate these per machine:

- `~/.zsh_secrets` and `~/.zshrc.local` — sourced by `.zshrc` if present
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
