---
name: friday-story
description: When the user wants a weekly sync / Friday-meeting summary of what they shipped — framed as capability gains ("what can the product do today that it couldn't last Friday") rather than ticket counts. Triggers on "friday story", "weekly summary", "what did I do this week", "pre-friday sync", or any prep for a Thursday/Friday standup. Pulls merged PRs, closed issues, reviews, commits, AND the user's own Claude Code conversation history for the window, then reframes raw activity into impact bullets ready to paste into Slack. Use this instead of just listing PRs — the framing is the whole point.
---

# Friday story (Jaxon's version)

## When this fires

Any time the user is preparing for a weekly sync and wants to talk about *impact*, not activity. Common triggers:

- "Friday story", "friday summary", "weekly impact", "pre-friday sync"
- "What did I do this week / since Friday / since last sync"
- "Help me write my Slack update for tomorrow"
- Thursday afternoon ambient prep, when they're staring at GitHub

If the user just asks "what PRs did I merge" — that's a different (smaller) ask; answer it directly and offer to run the full Friday-story reframe. Don't force this skill on simple lookups.

## The framing problem (the whole point of this skill)

Default GitHub summaries read like a changelog:

> Bad: "We fixed 6 bugs and shipped 2 features."

The user's manager wants the *capability delta* — what the product can now do that it couldn't last Friday, and who that helps:

> Good: "Fixed 3 bugs reported via Dan that now let FICR properly use Spectre to run commands on a remote device. Two perf bugs that make FICR meaningfully faster on long sessions. One bug that lets us track how FICR chose a tool."

Editorial rules that produce "good" framing:

1. **Lead with the capability gained, not the work done.** "Product X can now Y" beats "we fixed Z." Tickets are inputs; capabilities are outputs.
2. **Cluster by theme, not by repo or PR count.** Three PRs that all unblock the same workflow are one bullet, not three.
3. **Name the stakeholder when known** ("reported via Dan", "for the eval team", "asked by Patrick"). PR titles rarely say this; the PR body / linked issue / Claude conversation usually does.
4. **Name specific subsystems by name** — not "the backend." Specificity is what makes the story real.
5. **Quantify only when it's not noise.** "30% faster on long sessions" yes. "Fixed 6 bugs" no.
6. **Don't omit work that doesn't fit the frame.** Surface it in a "doesn't yet show up as a capability" bucket so the user can decide whether to drop it or invest in telling that story.

If you can't write a bullet in capability-gain form because the PR title is opaque, **say so and ask the user** — that's the whole "align on the story" step the manager described. Don't invent motivation you don't have.

## Running it

```bash
scripts/gather-activity.sh                 # since last Friday (default)
scripts/gather-activity.sh 2026-05-15      # since an explicit date
scripts/gather-activity.sh --days 7        # last N days

ORG_FILTER=twentyhq  scripts/gather-activity.sh   # scope GitHub queries to one org
GH_INCLUDE_COMMITS=0 scripts/gather-activity.sh   # skip the commit/branch walks
CC_INCLUDE=0         scripts/gather-activity.sh   # skip Claude Code history
CC_MAX_CHARS=400     scripts/gather-activity.sh   # tighten prompt snippets
```

The script needs `gh` authenticated (`gh auth status` to check) and `python3` on PATH. Output is plain text, grouped into:

- **Merged PRs** (with full body — this is where motivation lives)
- **Open PRs** (mention only if user wants a "shipping next" section)
- **Closed issues**
- **PRs reviewed** (collaborator credit — usually a separate bullet group)
- **Commits on default branches** + **active non-default branches** (catches direct-to-main + integration-branch work that never had its own PR)
- **Claude Code conversations** (the user's prompts, grouped by project then session — this is the section that captures debugging, design, investigations, and anything that never showed up in git)
- **Slack** — *the script can't reach Slack* (it's behind the MCP server, not a CLI). The script prints a stub reminding you to pull Slack yourself; see "Pulling Slack" below.

## Why the Claude Code history matters

PRs and commits only see the work that *landed*. A lot of the user's week happens in conversation: design exploration, debugging a flaky test for two hours, helping a teammate over a screenshare, investigating a customer report that turned out to be a non-issue. That work is real and worth surfacing — but only the user's own prompts (in `~/.claude/projects/*.jsonl`) can recover it.

When reading the CC history section:

- The user's prompts are the signal. Skim them by project (cwd) — the first prompt of a session usually announces the topic; later prompts in the same session show how it evolved.
- A long string of related sessions in one repo is *one* theme, not N themes. Cluster them.
- Don't quote prompts back at the user verbatim in the final story. Use them to ask "looks like you spent Tuesday on tool-selection latency — did that ship?" and then frame the answer as a capability.
- If a session's prompts strongly suggest a capability that *didn't* land yet, that's a great "shipping next" or "in-flight investigation" bullet.

## Pulling Slack (agent-driven, since Slack is MCP-only)

Slack messages the user *wrote* (not received) round out the picture: customer reports they triaged in-thread, design discussions, "hey can you look at X" pings they answered, status updates they posted. Often this is the only record of work that never produced a PR or a Claude session.

When the gather script finishes, do this **before** drafting the story:

1. Resolve the user's Slack handle if you don't already have it. Use `slack_search_users` with their email (available in the `userEmail` context block) to get the canonical `@handle`. Remember it for the rest of the session.
2. Pull the user's messages in the window:
   - `slack_search_public_and_private` with `from:@<handle> after:YYYY-MM-DD` (use the same `SINCE` the script used).
   - If the user is in private channels you want covered, that's why the `_and_private` variant matters.
3. Skim and cluster:
   - Long threads where the user wrote multiple substantive replies → likely a real work theme, fold into the matching capability bullet.
   - One-line acks, emoji, "thanks!", "lgtm" → ignore.
   - Status posts the user already wrote (e.g. in a `#standup` or team channel) → these are *gold*; quote them or build the bullet around the phrasing they already chose.
4. If Slack reveals a stakeholder name that isn't in the PR body, pull it into the bullet ("reported via Dan in #foo").

Don't dump raw Slack messages into the final story. Use them like you use CC history: as context for *why* the work happened, and as a source of stakeholder names.

If the Slack MCP server isn't authenticated or returns no results, mention it once and move on — don't loop on auth.

## Producing the story

After running the script:

1. **Read the PR bodies carefully** — not just the titles. Linked issues, "fixes:" lines, and stakeholder mentions are where the *why* lives.
2. **Cross-reference with CC history and Slack.** If a PR title is opaque, the user's own prompts from that week (and Slack threads they wrote in) often explain what they were actually trying to do, and who asked.
3. **Cluster** into 3–6 themes. If you have more than 6, you're being too granular; merge.
4. **For each theme, draft one bullet** in capability-gain form. If the underlying work is plumbing/cleanup with no user-visible capability, draft it as "unblocks X" or put it in the "doesn't yet show up as a capability" bucket.
5. **Flag uncertainty inline** — "I think this enables X but the PR doesn't say; the Tuesday Claude session suggests Y — which is closer?" The point of the Thursday pre-meeting is alignment, so questions beat invented narrative.
6. **Output as a Slack-pastable block** — plain text, hyphen bullets, no markdown headers (Slack mangles them). Stakeholder names in plain text, not @mentions, unless the user asks.

Default output shape:

```
*What <product> can do this week that it couldn't last Friday*

- <capability 1>. <which PRs / who asked, in plain prose>.
- <capability 2>. ...
- <capability 3>. ...

*Also shipped, but doesn't yet show up as a user-facing capability*
- <plumbing / cleanup / infra>

*In-flight (visible in Claude sessions but not yet merged)*
- <investigation / WIP>

*Questions for the sync*
- <thing where you weren't sure how to frame it>
```

Offer to tweak tone (drier / more enthusiastic / shorter) before the user pastes.

## When it won't work / what to flag

- **No PRs in the window.** Don't pad. Tell the user "nothing merged since {date}" — the CC history may still give you something to talk about (investigations, design work) so check that before giving up.
- **Private PR descriptions are empty.** Common. Fall back to PR title + linked issues + the user's CC prompts from the same week; explicitly tell the user which bullets are guesses.
- **Work happened outside GitHub *and* outside Claude Code** (incidents over Zoom, design docs in Notion, Slack threads, pairing in someone else's editor). Ask the user to dump anything they want included.
- **CC history is noisy.** The user's own prompts include throwaway one-liners and `/clear`s. Don't surface every session — only the ones that look like sustained work on a topic. When in doubt, ask the user "looks like you had a long session on X on Tuesday — was that real work or me-poking-at-something?"
