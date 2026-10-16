# AGENTS.md — global agent instructions

Global conventions for AI agents working anywhere on this machine. Repo-local `AGENTS.md` / `CLAUDE.md` files take precedence over this one.

## Always reproduce before fixing

Before starting any fix (bug, limitation, broken ticket — including Linear
tickets), always reproduce the issue first and show the repro. Treat a
confirmed repro as the entry gate to fix work: it grounds the fix in observed
behavior, not assumptions. Only move to analysis + fix once the repro is shown.

- If reproducing needs setup only the user can do, ask them to repro it
  ("let me know if you need me to repro it") rather than skipping the step.
- If a repro needs local scaffolding (test harness, stub target, temp flag),
  it's fine to add that scaffolding to enable the repro.
- Scaffolding stays local by default: don't check in repro/test scaffolding
  (a Dockerfile, a helper recipe, a stub target) unless explicitly asked.
  Keep it in the working tree but out of git (e.g. via `.git/info/exclude`),
  or in a scratch dir — don't edit tracked build files (justfiles, etc.) just
  to wire up a throwaway repro.

## Markdown style

- Do not hard-wrap prose to a fixed column width. Write each paragraph as a single physical line and let whatever renders the Markdown handle wrapping — line width is the renderer's job, not the writer's.
- Normal structure still applies: one line per list item, heading, and table row; blank lines between blocks; fenced code blocks left exactly as written.
- If a formatter is wanted, the equivalent setting is Prettier's `proseWrap: "never"`.
