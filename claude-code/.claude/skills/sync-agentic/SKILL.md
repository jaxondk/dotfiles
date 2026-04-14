---
name: sync-agentic
description: Sync canonical agentic definitions from ~/dotfiles/agentic/ to a target harness format
argument-hint: "<harness: claude-code | opencode>"
---

# Sync Agentic Definitions

Sync all canonical agentic definitions from `~/dotfiles/agentic/` to the target harness specified by: $ARGUMENTS

If no harness is specified, default to `claude-code`.

## Step 1: Read all canonical definitions

Read every file in these directories:
- `~/dotfiles/agentic/commands/*.md`
- `~/dotfiles/agentic/skills/*/SKILL.md`
- `~/dotfiles/agentic/agents/*.md`

For each file, parse the YAML frontmatter to get `name`, `type`, `description`, `model`, and `argument-hint`.

## Step 2: Translate to target harness format

### Target: `claude-code`

Output directory: `~/dotfiles/claude-code/.claude/`

**Commands** (`agentic/commands/*.md`) become **Skills**:
- Write to `skills/<name>/SKILL.md`
- Frontmatter: keep `name`, `description`, `argument-hint`. Drop `type`.
- Body: keep as-is, BUT shift positional arg references: `$1` → `$0`, `$2` → `$1`, `${2:-...}` → `${1:-...}`, etc.
- `$ARGUMENTS` stays the same (it's universal).
- Shell injection syntax `!`backtick`` is supported in Claude Code skills — keep as-is.

**Skills** (`agentic/skills/*/SKILL.md`) become **Skills**:
- Write to `skills/<name>/SKILL.md`
- Frontmatter: keep `name`, `description`. Drop `type`.
- Body: keep as-is (skills are mostly reference docs, no arg substitution needed).

**Agents** (`agentic/agents/*.md`) become **Agents**:
- Write to `agents/<name>/AGENT.md`
- Frontmatter: keep `name`, `description`. Drop `type`.
- If canonical `model` is set, translate: `haiku` → `haiku`, `sonnet` → `sonnet`, `opus` → `opus` (Claude Code uses short names).
- Body: keep as-is.

### Target: `opencode`

Output directory: `~/dotfiles/opencode/.config/opencode/`

**Commands** (`agentic/commands/*.md`) become **Commands**:
- Write to `commands/<name>.md`
- Frontmatter: keep `description`. Drop `name`, `type`, `argument-hint`.
- Body: keep as-is (OpenCode uses `$1`, `$2` natively — no translation needed since canonical uses the same convention).

**Skills** (`agentic/skills/*/SKILL.md`) become **Skills**:
- Write to `skills/<name>/SKILL.md`
- Frontmatter: drop `type`. Keep everything else.
- Body: keep as-is.

**Agents** (`agentic/agents/*.md`) become **Agents**:
- Write to `agent/<name>.md` (note: `agent/` singular in OpenCode)
- Frontmatter: keep `description`. Add `mode: all`. Drop `type`, `name`.
- If canonical `model` is set, translate: `haiku` → `anthropic/claude-haiku-4-5`, `sonnet` → `anthropic/claude-sonnet-4-6`, `opus` → `anthropic/claude-opus-4-6`.
- For `bash-cmd-only` agent specifically, add the tools disable block from the canonical description.
- Body: keep as-is.

## Step 3: Report

After writing all files, report:
- How many commands/skills/agents were synced
- Any files that were skipped and why
- Any translation issues encountered

## Important notes

- Do NOT touch the `build.md` primary agent in OpenCode — that's harness-specific and not managed by sync.
- Do NOT delete files in the target that don't have a canonical source — they may be harness-specific.
- Do NOT sync `sync-agentic` itself — it lives independently in each harness.
- Overwrite existing files in the target — the canonical source is the authority.
