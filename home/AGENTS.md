# AGENTS.md — global agent instructions

Global conventions for AI agents working anywhere on this machine. Repo-local `AGENTS.md` / `CLAUDE.md` files take precedence over this one.

## Markdown style

- Do not hard-wrap prose to a fixed column width. Write each paragraph as a single physical line and let whatever renders the Markdown handle wrapping — line width is the renderer's job, not the writer's.
- Normal structure still applies: one line per list item, heading, and table row; blank lines between blocks; fenced code blocks left exactly as written.
- If a formatter is wanted, the equivalent setting is Prettier's `proseWrap: "never"`.
