---
name: pr-digest
type: command
description: Summarize all PRs merged since a given date
---

# PR Digest

Generate a BLUF (Bottom Line Up Front) summary of all PRs merged since a given date.

**User arguments:** $ARGUMENTS

If no arguments are provided, default to 7 days ago. The argument should be a date in YYYY-MM-DD format (e.g., `2026-02-27`).

## Phase 0: Detect the Repository

Determine the GitHub owner/repo from the current working directory:

```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

Store this as `REPO` (e.g., `Twenty-IO/firecrew`). Use `REPO` in all `gh` commands below.

Also detect the default branch:

```bash
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
```

Store this as `DEFAULT_BRANCH` (e.g., `main`, `develop`, `master`).

## Phase 1: Collect the Complete PR List

Some repos use **Graphite merge queue**, which complicates PR discovery. Graphite MQ closes PRs *without* setting GitHub's `mergedAt` field — they show as state `CLOSED` with `mergedAt: null`. You **must** combine two queries to get the full picture.

### Query 1: Standard merged PRs (mergedAt is set)

```bash
gh pr list --repo $REPO --state merged --limit 200 \
  --search "merged:>YYYY-MM-DD" \
  --json number,title,mergedAt,author,additions,deletions \
  --jq 'sort_by(.mergedAt) | .[] | "\(.number)\t\(.mergedAt)\t\(.author.login)\t+\(.additions)/-\(.deletions)\t\(.title)"'
```

### Query 2: Graphite MQ PRs (mergedAt is null, state is CLOSED)

```bash
gh pr list --repo $REPO --state closed --limit 300 \
  --json number,title,mergedAt,closedAt,state,baseRefName,author,additions,deletions \
  --jq '.[] |
    select(.mergedAt == null and .closedAt >= "YYYY-MM-DDT00:00:00Z" and .baseRefName == "$DEFAULT_BRANCH") |
    select(.title | startswith("[Graphite MQ]") | not) |
    select(.title | startswith("ci: bump") | not) |
    "\(.number)\t\(.closedAt)\t\(.author.login)\t+\(.additions)/-\(.deletions)\t\(.title)"
  ' | sort -t$'\t' -k2
```

**Important filtering rules:**
- Exclude `[Graphite MQ] Draft PR GROUP:...` entries — these are Graphite's internal merge queue PRs, not real feature PRs
- Exclude `ci: bump the actions group...` — these are dependabot auto-bumps
- For Graphite PRs, use `closedAt` as the merge timestamp (since `mergedAt` is null)
- Some PRs have very old PR numbers but were merged recently (e.g., PR #239 opened months ago). **Do not filter by PR number** — only filter by date
- If Query 2 returns zero results, the repo likely doesn't use Graphite MQ — that's fine, just use Query 1 results

### Query 3: Catch stragglers with very old PR numbers

The `--limit 300` on Query 2 may not reach PRs with very old numbers. If Query 2 references Graphite MQ groups containing PR numbers you haven't seen (look for `(PRs NNN)` in titles), fetch those directly:

```bash
gh pr view <NUMBER> --repo $REPO \
  --json number,title,closedAt,mergedAt,state,baseRefName,author,additions,deletions
```

### Combine and deduplicate

Merge both lists, deduplicate by PR number, and sort by merge/close date ascending. This is your canonical PR list.

## Phase 2: Analyze PRs Using Subagents

Group PRs by theme using your judgment based on the actual PR titles and content. Common groupings might include things like Features, Bug Fixes, Refactoring, Infrastructure, CI/Testing, Documentation, etc. — but adapt the categories to whatever makes sense for this specific repo and batch of PRs.

**Fan out one subagent per group**. For very large groups (>10 PRs or >5K total lines changed), split into multiple subagents.

Each subagent should:
1. Run `gh pr diff <number> --repo $REPO` and `gh pr view <number> --repo $REPO` for each PR in its group
2. Summarize each PR: what changed, why, key files, implications
3. Synthesize a group-level summary: overall theme, new capabilities, bug fixes, architectural changes, breaking changes

## Phase 3: Compile the BLUF Report

Structure the output as an **information pyramid** — most important first, drill deeper as you go:

### Level 1: BLUF (3-5 bullets)
- Total PR count, primary contributors, net line delta
- The 2-4 biggest shifts/themes in plain English
- Anything that changes how developers work day-to-day

### Level 2: Area-by-Area Summary
For each thematic group:
- 2-3 sentence summary of the group
- Bullet list of key changes (new features, bug fixes, refactors)
- Notable PRs called out by number

### Level 3: Breaking Changes & Migration Notes
A table of anything that requires action:
| Change | Impact | Action Needed |
|--------|--------|---------------|

## Guidelines

- **Be opinionated.** Don't just list PRs — synthesize what matters. Call out architectural shifts, not just line counts.
- **BLUF means BLUF.** The first 5 lines should let someone decide if they need to read more.
- **Group, don't enumerate.** Nobody wants to read 40 individual PR summaries. Themes and patterns matter more than individual PRs.
- **Call out breaking changes prominently.** Anything that changes APIs, wire formats, CLI interfaces, or DB schemas.
- **Skip trivial PRs.** A `.gitignore` addition or single-line config change doesn't need its own section — mention in passing or skip.
- **Use markdown formatting.** Headers, tables, bold for emphasis. This will be read in a terminal.
