---
name: friday-story
description: Weekly sync / Friday-meeting summary of what the current user shipped — framed as capability gains ("what can the product do today that it couldn't last Friday") rather than ticket counts. A PROJECTION on top of the activity-digest skill: it gets the week's raw activity from activity-digest (code / Claude Code / Slack / Linear) and reframes it into impact bullets ready to paste into Slack. User-agnostic — identity is resolved at runtime, so anyone on the team can run it. Triggers on "friday story", "weekly summary", "what did I do this week", "pre-friday sync", or any prep for a Thursday/Friday standup. Use this (not a raw PR list) when the framing is the point.
---

# Friday story (capability-gain weekly summary)

A **projection** on top of `activity-digest`. The raw understanding — what actually
happened across code / Claude Code / Slack / Linear over the week — comes from
`activity-digest`. This skill's only job is to **reframe** that into the story a
manager wants: the capability delta, not a changelog.

```
activity-digest (week, raw) → friday-story (capability-gain framing)
```

User-agnostic: it works for whoever runs it; `activity-digest` resolves identity at
runtime (GitHub via `gh`, Slack/Linear via the `userEmail` context). Nothing here is
tied to a person.

## The framing problem (the whole point of this skill)

Default summaries read like a changelog:

> Bad: "We fixed 6 bugs and shipped 2 features."

The manager wants the *capability delta* — what the product can now do that it
couldn't last Friday, and who that helps:

> Good: "Fixed 3 bugs reported via Dan that now let FICR properly use Spectre to run
> commands on a remote device. Two perf bugs that make FICR meaningfully faster on
> long sessions. One bug that lets us track how FICR chose a tool."

Editorial rules that produce "good" framing:

1. **Lead with the capability gained, not the work done.** "Product X can now Y" beats "we fixed Z." Tickets are inputs; capabilities are outputs.
2. **Cluster by theme, not by repo or PR count.** Three PRs that all unblock the same workflow are one bullet, not three.
3. **Name the stakeholder when known** ("reported via Dan", "for the eval team", "asked by Patrick"). The digest's Slack and Linear sections are where these names live — mine them.
4. **Name specific subsystems by name** — not "the backend." Specificity is what makes the story real.
5. **Quantify only when it's not noise.** "30% faster on long sessions" yes. "Fixed 6 bugs" no.
6. **Don't omit work that doesn't fit the frame.** Surface it in a "doesn't yet show up as a capability" bucket so the user can decide whether to drop it or invest in telling that story.

If you can't write a bullet in capability-gain form because the source is opaque,
**say so and ask the user** — that alignment is the whole point of the Thursday
pre-meeting. Don't invent motivation you don't have.

## Running it

### 1. Resolve the week window

Default: **since last Friday** (if today is Friday, since the previous Friday — a
full week back). Honor explicit asks ("since the last sync", "this week", a date).
Express it as a `SINCE` (open-ended) or a closed range for `activity-digest`.

### 2. Get the raw material via activity-digest

Run the **`activity-digest`** skill for that window — don't re-implement gathering.
It produces a factual, source-attributed digest across all four sources (and writes
it to the data repo). If a digest already covers the window, read it; otherwise let
activity-digest gather and write it. Everything you need is in there:

- **Code** — merged/opened PRs (with bodies — motivation), closed issues, reviews, commits.
- **Claude Code** — the week's sessions: design, debugging, investigations that never hit git. Great for in-flight/"shipping next" bullets and for *why* work happened.
- **Slack** — what the user posted/triaged; the source of stakeholder names ("reported via Dan in #foo").
- **Linear** — issues created/closed and comments — another stakeholder + motivation source.

### 3. Reframe into the story

1. **Read PR bodies and the digest's themes carefully** — linked issues, "fixes:" lines, and the Slack/Linear threads are where the *why* and *who* live.
2. **Cluster** into 3–6 capability themes. More than 6 → you're too granular; merge.
3. **For each theme, write one bullet** in capability-gain form. Plumbing/cleanup with no user-visible capability → frame as "unblocks X" or put it in the "doesn't yet show up as a capability" bucket.
4. **Flag uncertainty inline** — "I think this enables X but the source doesn't say; the Tuesday session suggests Y — which is closer?" Questions beat invented narrative.

### 4. Output

Default shape (plain text, **markdown bullets** so it renders right — see formatting note):

```
*What <product> can do this week that it couldn't last Friday*

- <capability 1>. <which PRs / who asked, in plain prose>.
- <capability 2>. …
- <capability 3>. …

*Also shipped, but doesn't yet show up as a user-facing capability*
- <plumbing / cleanup / infra>

*In-flight (visible in Claude sessions / open PRs, not yet merged)*
- <investigation / WIP>

*Questions for the sync*
- <thing you weren't sure how to frame>
```

Offer to tweak tone (drier / more enthusiastic / shorter) before the user posts.

### Formatting note (so bullets render as a real Slack list)

Slack builds native bullet lists from **markdown** (`- item`, indent to nest), which
it renders as `•`/`◦`. **Do not emit literal `•`/`◦` glyphs** — pasted in they're
inert text with broken indentation. If the user wants it *in Slack*, deliver via
`slack_send_message_draft` (the MCP tool converts the markdown to a native list);
for pasting into a doc/message by hand, markdown `-` is fine. Keep section labels
(`*What … *`) as `*bold*` lines, not headers.

## Unattended mode (`--unattended`)

A per-user launchd job runs `claude -p "/friday-story --unattended"` **Thursdays ~11:00 local**, so a draft of the week's story is waiting before the Friday sync. No human is in the loop:

- **Never call `AskUserQuestion`** / never block on input.
- **Window:** the **last 7 days** (`SINCE = today − 7`, through now).
- **Gather via activity-digest, inline (no subagents)** — the headless permission set excludes the `Agent` tool. Run it for the 7-day window and read/write the digest as usual.
- **Reframe** per the editorial rules into the default output shape. Since no one is here to answer them, **keep the "Questions for the sync" bullets in the draft** — they're exactly what the user should resolve before posting.
- **Deliver to the user's personal DM as a draft.** Resolve the current user's Slack `user_id` (via `slack_search_users` on the `userEmail`); call `slack_send_message_draft` with `channel_id = <that user_id>` (a self-DM) and **no `thread_ts`**. It's a scratch space to review/edit, then paste wherever the Friday sync lives.
- **Formatting:** the draft tool takes **standard markdown** — use `**bold**` for the section labels and `- ` bullets (4-space-indented to nest); the MCP converts them to native Slack formatting. Never literal `•`/`◦`.
- **Only ever a draft — never `slack_send_message`.**
- **Idempotency:** if `slack_send_message_draft` returns `draft_already_exists` (the self-DM already has a draft), log and stop — don't clobber.
- Everything goes to the run log; no conversational output.

## When it won't work / what to flag

- **Empty week.** Don't pad. `activity-digest` will report the zeros; say "nothing merged since {date}" — but the CC/Slack/Linear sections often still have a story (investigations, design, triage) so check before giving up.
- **Opaque PR descriptions.** Common. Fall back to titles + linked issues + the digest's CC/Slack/Linear context; tell the user which bullets are guesses.
- **Work outside the core four** (incidents over Zoom, design docs in Notion, pairing in someone else's editor). Ask the user to dump anything they want included.
- This skill is framing only. For the raw, unframed record, that's `activity-digest`; for a daily y:/t:/b: post, that's `standup`.
