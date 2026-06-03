---
name: activity-digest
description: Gather ALL of the user's activity across the core four sources — local Claude Code conversations (excluding ~/src/personal), code (GitHub PRs/issues/reviews/commits), Slack, and Linear — for an arbitrary time window, and synthesize it into a canonical, factual raw digest. This is the source-of-truth layer: it captures what actually happened, source-attributed, without reframing for any audience. Projections (daily standup, friday-story) are built on top of it and should call this first. Triggers on "what did I do (today/yesterday/this week/since X)", "summarize my activity", "my activity for <period>", "what have I been working on", "pull my activity", or any request to understand work done over a period. NOT for impact/audience framing — that's a projection's job.
---

# Activity digest (Jaxon's canonical work record)

## What this is

The **raw-understanding layer**. One job: for a given time window, faithfully reconstruct everything the user did across the **core four** sources, attribute each item to its source, cluster lightly by theme, and write it to a durable file. No editorializing, no impact spin, no audience. That faithful record is the point — projections read *from* it.

```
sources → activity-digest (raw, canonical) → projections (standup, friday-story, …)
```

If the user asks for a standup or a friday story, run the relevant projection skill — but those skills lean on this one to do the gathering. If the user just asks "what did I do", produce the digest and stop.

## The core four sources

1. **Claude Code** — local session transcripts (`~/.claude/projects/*.jsonl`). Catches work that never hit git: design, debugging, investigations, reviews, pairing. **Always exclude `~/src/personal/`** (private).
2. **Code** — GitHub via `gh`: PRs opened (`--created`, any state) / merged / reviewed, issues closed, and commits on default branches.
3. **Slack** — messages the *user wrote* (MCP-only; no CLI).
4. **Linear** — issues created/updated/closed, comments authored, status updates (MCP-only; no CLI).

## Where the digest goes

Canonical digests live in the **`activity-digest` data repo**, default `~/src/activity-digest` (override with `$ACTIVITY_DIGEST_REPO`). See that repo's `AGENTS.md` for the file format and naming. One file per window:

- single day → `digests/YYYY-MM-DD.md`
- range → `digests/YYYY-MM-DD_YYYY-MM-DD.md`

If a digest for the window already exists, read it and offer to refresh rather than silently overwriting — the user may have hand-edited it.

## Running it

### 1. Resolve the window → `SINCE` (and optional `UNTIL`), both `YYYY-MM-DD`

Use the `currentDate` from context. Interpret natural language in the user's local timezone:

- "today" → `SINCE=UNTIL=<today>`
- "yesterday" → `SINCE=UNTIL=<today-1>`
- "this week" / "since Monday" → `SINCE=<this Monday>`, open-ended (no `UNTIL`)
- "since Friday" / "this sprint" → `SINCE=<that date>`, open-ended
- "last week" → the full Mon–Sun range (set both)
- explicit dates / ranges → use them verbatim

A window with no `UNTIL` runs up to *now*. A closed window (both set) is inclusive of both days.

### 2. Gather the deterministic half (code + CC) via the script

```bash
scripts/gather-code-and-cc.sh <SINCE> [UNTIL]
scripts/gather-code-and-cc.sh --days 7
ORG_FILTER=Twenty-IO scripts/gather-code-and-cc.sh <SINCE>   # scope GitHub to one org
```

Needs `gh` authenticated (`gh auth status`) and `python3`. It prints code activity, then the CC prompt history (already excluding `src/personal`), then Slack+Linear stubs you fill in next. Env knobs: `GH_INCLUDE_COMMITS=0`, `CC_INCLUDE=0`, `CC_MAX_CHARS=N`, `CC_EXCLUDE="src/personal src/other"`.

### 3. Gather the MCP half (Slack + Linear) — in parallel

Slack and Linear have no CLI. Dispatch **two subagents in parallel** (one per source) so they run concurrently and keep their raw dumps out of the main context. Give each the resolved window and the user's identity (email from `userEmail` context; Slack `user_id` if known). Tell each to load its MCP tool schemas via `ToolSearch` first, then:

- **Slack agent**: resolve the user's handle/id, `slack_search_public_and_private` with `from:@<handle> after:<SINCE-1>` (and `before:<UNTIL+1>` for closed windows), read notable threads, return what the user *posted/decided/asked* grouped by channel/thread. Ignore one-line acks/emoji.
- **Linear agent**: `list_issues` has **no `creator` filter** — only `assignee`. So an assignee-only query MISSES issues the user created or closed. Use this recipe (verified against the workspace):
  1. Resolve the user (`list_users` by email) to get their Linear user id + name.
  - **Keep responses small — this is mandatory, not optional.** A broad `updatedAt`/`createdAt` pull on a busy team day returns full issue descriptions and *will overflow the MCP response* (~tens of thousands of chars, spilled to a file you then have to slice). Always: scope with **`team:`** (e.g. `Firecrew`), set a modest **`limit`** (e.g. 40–50), `orderBy` the date you're filtering on, and **paginate with the `cursor`** until you pass the window's far edge rather than asking for one giant page. Narrow the window if you can.
  2. **Created:** `list_issues` with `createdAt: <SINCE>` (this is a *created-after* bound; ISO date or `-P{N}D` duration), `orderBy: createdAt`, `team:`, a `limit`, **no assignee**. `createdBy` / `createdById` are **on the list payload** — keep the rows where that's the user. (Bound the top end client-side against `UNTIL` if it's a closed window.)
  3. **Closed / touched:** `list_issues` with `updatedAt: <SINCE>`, `orderBy: updatedAt`, `team:`, a `limit`, no assignee. There is **no `completedBy` field** — Linear records *when* an issue was completed (`completedAt`, `status`/`statusType: completed`, and `stateHistory` via `get_issue`) but **not who closed it**. So attribute a *close* only when it's the user's own issue (`createdById == user` or `assigneeId == user`) with `completedAt` inside the window. Don't claim the user closed an issue you can't tie to them.
  4. **Comments:** for in-window candidate issues, `list_comments` and keep comments whose author is the user.
  5. **Assigned:** also surface issues currently `assignee: me` updated in-window — received assignments are real activity worth noting (but label them as "assigned", not authored).
  6. Report with `TEAM-NNN` identifiers + titles, classified as created / closed / commented / assigned.
  - **`gitBranchName` (e.g. `jaxonkeeler/fire-838-…`) is auto-derived from the querying token and is NOT evidence of authorship** — verified: June-1 issues created by larry.rivera / ying-ke / dlruddell all carried `jaxonkeeler/…` branch names. Never infer involvement from it.

(For a single short window you may pull Slack/Linear inline instead of via subagents — but parallel subagents are the proven shape and scale to wide windows.)

### 4. Synthesize → write the digest file

Combine all four raw streams into one file following the data repo's `AGENTS.md` format. Discipline for this layer:

- **Factual and source-attributed.** Every claim traces to a PR/issue/commit, a CC session, a Slack thread, or a Linear ticket. No invented motivation, no impact framing.
- **Cluster by theme across sources** when a through-line is obvious (e.g. one design thread that shows up in a PR + a Slack thread + a CC session = one theme), but keep the per-source raw sections beneath so nothing is lost.
- **Call out the negatives.** "No commits today", "no Linear writes", "Slack auth failed" are findings — record them, don't omit.
- **Note unresolved/open threads** — in-flight work, undecided questions, dependencies. Projections need these.
- **Stamp `generated_at`** with the real timestamp (read it from the environment / `date`; do not invent one).

### 5. Report

Give the user a tight prose summary in-conversation (themes first, then notable specifics, then negatives/open threads), and the path to the written digest. Offer the obvious next step ("want a standup or friday-story projection off this?").

## Notes / failure modes

- **Empty window.** Don't pad. State plainly what each source returned, including the zeros. The CC history alone often still has something (investigations, reviews) even when git is empty.
- **MCP not authenticated.** Mention once and move on; record the gap in the digest rather than looping on auth.
- **Don't re-summarize a reporting session.** If the CC history includes a prior activity-digest / standup / friday-story session, note it as "activity-reporting session" — don't recurse into describing the act of summarizing.
- **gh covers *pushed* code only.** Unpushed local work surfaces via the CC history instead; that's expected, not a gap to chase.
- This skill never reframes for an audience. If the user wants impact bullets, that's `friday-story`; if they want a y:/t:/b: post, that's `standup`.
