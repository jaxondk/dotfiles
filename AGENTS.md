# AGENTS.md — working in this dotfiles repo

This repo is managed with **chezmoi**. Read this before changing anything so you don't
break the source/target contract.

## Mental model

- **Source** = `home/` in this repo (`.chezmoiroot` points here).
- **Target** = the user's `$HOME`.
- `chezmoi apply` renders source → writes **real files** into `$HOME`.
- Editing a file in `$HOME` directly does NOT update the repo. Either edit under
  `home/` and `chezmoi apply`, or run `chezmoi re-add` to pull `$HOME` edits back.
- Everything **outside** `home/` (this file, `README.md`, `install.sh`, `agentic/`) is
  plain repo content chezmoi never touches.

## Filename conventions (source attributes)

Encode attributes in the filename, not the filesystem bits:

- `dot_X` → `.X`  (e.g. `dot_zshrc` → `~/.zshrc`, `dot_config/` → `~/.config/`)
- `executable_X` → file with `+x`. **Required** for any script that must stay
  executable — chezmoi sets mode 0644 by default and ignores the source file's `+x` bit.
- `symlink_X.tmpl` → a symlink; the rendered file contents are the link target.
- `*.tmpl` → Go-template; rendered with data from `~/.config/chezmoi/chezmoi.toml`.
- `run_once_*` / `run_onchange_*` → scripts run during `apply` (once per content hash).
- Prefixes combine in order: `executable_dot_foo.sh.tmpl`.

When adding an executable script, name it `executable_…`. When adding a leading-dot file
inside an already-`dot_` directory (e.g. nvim's `.neoconf.json`), name it `dot_neoconf.json`.

## Templating data

Defined in `home/.chezmoi.toml.tmpl`, prompted at `chezmoi init`:

- `.name`, `.email` — git identity
- `.workEmail` — used by the Claude account-guard hook
- `.personalGitEmail`, `.personalGitName` — optional; blank ⇒ no personal git identity
- `.chezmoi.homeDir`, `.chezmoi.os` — built-ins; use these instead of hardcoding
  `/Users/<name>` or branching on OS.

**Never hardcode** the user's home path or identity in a managed file. Either use `$HOME`
at runtime (shell) or `{{ .chezmoi.homeDir }}` (template), and rename the file to `.tmpl`.

## Conditional deployment

`home/.chezmoiignore` is itself a template. Use it to skip targets per-machine, e.g. the
work-only `shadow-*` skills are ignored unless `~/src/xx-internal-ai/shadow-factory`
exists. Add new machine-specific exclusions there.

## Claude Code skills (three tiers)

1. **Authored** — real files under `home/dot_claude/skills/<name>/`. Edit freely.
2. **Public/vendored** — real files under `home/dot_agents/skills/<name>/`, exposed via
   `home/dot_claude/skills/symlink_<name>.tmpl` → `{{ .chezmoi.homeDir }}/.agents/skills/<name>`.
   Pinned by `home/dot_agents/dot_skill-lock.json`. To refresh: update the real files (or
   re-run the upstream skills installer into `~/.agents`, then `chezmoi re-add ~/.agents`).
3. **Work** — `symlink_shadow-*.tmpl` / `symlink_mission*.tmpl` point into the
   shadow-factory repo and are conditionally ignored (see above). Do not vendor work code
   into this repo.

## Secrets — do NOT commit

Not managed by chezmoi; recreated per machine: `~/.zsh_secrets`, `~/.zshrc.local`,
`~/.config/opencode/kdco-notify.json`. The root `.gitignore` and `home/.chezmoiignore`
both guard against accidental adds. opencode `node_modules` and `bun.lock` are generated
by `bun install` and intentionally unmanaged.

## Safe workflow for changes

```bash
chezmoi cd                       # work inside home/
# edit / git mv files using the conventions above
chezmoi diff                     # preview target changes (does NOT run scripts)
chezmoi status                   # A=create, M=modify, R=script-will-run
chezmoi apply --exclude=scripts  # apply files without re-running install scripts
```

Verify a template renders before applying: `chezmoi cat ~/.gitconfig`.
Inspect available template variables: `chezmoi data`.
Validate the whole tree: `chezmoi status` should be empty when in sync.
Stop managing a file without deleting it: `chezmoi forget <target>` (use `destroy` to
remove from both source and `$HOME`). Change init answers: `chezmoi init --prompt`
(a plain re-init won't re-ask, since prompts use `promptStringOnce`).

## `agentic/`

Canonical harness-agnostic agent definitions, synced into each tool by the
`sync-agentic` skill. Plain repo content — not a chezmoi target.
