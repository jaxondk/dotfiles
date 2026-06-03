---
name: standup
description: Draft the user's daily standup post for the #phantom thread in their own y:/t:/b: style, projected from a canonical activity-digest. Use when the user asks for a "standup", "daily standup", "phantom update", "y/t/b", "what do I write for standup", or prep for the daily stand-up bot. This is a PROJECTION on top of the activity-digest skill: it gathers yesterday's raw activity via activity-digest, drafts the "yesterday" (y:) section from it, then ASKS the user how to handle "today" (t:) and "blockers" (b:) before finalizing. Produces the post in the user's exact #phantom formatting using markdown bullets (`-`), and delivers it as a reviewable Slack draft that renders as a native bullet list — never literal `•`/`◦` glyphs, which paste in as inert text.
---

# Standup (projection of activity-digest)

A thin transform: **yesterday's digest → a #phantom standup post**, in the user's own voice. The raw understanding comes from `activity-digest`; this skill only reframes it into the standup shape and fills in the forward-looking parts *with the user*, never by guessing.

**User-agnostic.** Anyone on the team can run this for themselves. Resolve the current user's identity at runtime — their email from the `userEmail` context → Slack `@handle` / `user_id` via `slack_search_users` (`activity-digest` resolves GitHub/Linear). The only baked-in values are **workspace constants** shared by the whole team: the #phantom channel (`C09HD90PR1C`) and its "Daily Stand-up" bot (`B0AELNL5HFY`) — those hold for everyone in this Slack workspace. If the skill is ever reused in a *different* workspace, resolve #phantom and its stand-up bot by name instead.

## The #phantom standup house style (match it exactly)

Observed from the team's real #phantom standup replies — the whole channel uses this shape, so it's a channel convention, not one person's. Reproduce faithfully:

- Three lowercase sections: `y:` (yesterday), `t:` (today), `b:` (blockers). Sometimes `b:` is omitted or just `none`.
- All lowercase, casual. Shorthand: `w/`, `g2g`, `tix`, `smh`, `pr`/`prs`.
- Bare refs: PR numbers as `1848`, Linear tickets as `FIRE-852` (not linked unless asked).
- Cluster related work into one bullet with sub-bullets, don't enumerate every PR.
- Optional trailing `:information_source:` note for availability (e.g. travel, half-day).
- No markdown headers/bold (Slack mangles those here).

### Bullets: emit markdown lists, NOT literal `•`/`◦` glyphs

Easy to get wrong, and the reason a previous draft looked off. Real #phantom posts are **native Slack rich-text lists** (proper nesting + hanging indent). In Slack those come from **markdown** — `- item`, nested by indenting — which Slack *renders* as `•` / `◦`. The bullet glyphs are Slack's rendering, not what you type. **Verified empirically:** sending `- a` / `    - b` via the Slack MCP tools comes back serialized as `•` / `    ◦` — a real list, identical to how real #phantom standups serialize. Literal `•`/`◦` characters pasted in stay inert text (no nesting, no hanging indent — the "indentation is off" bug).

So:
- **Draft in markdown:** `- ` for top-level items; indent nested items 4 spaces (or a tab): `    - subitem`. Keep the bare `y:` / `t:` / `b:` label lines above their lists.
- **Never emit literal `•` / `◦`** in the thing the user will post.
- Deliver through the Slack MCP tool (next-to-last step), which converts the markdown into a native list. See "Deliver it".

## Procedure

### 1. Get the raw material via activity-digest

The standup's `y:` reports **yesterday's** work (the day since the last standup). Run the `activity-digest` skill for that window (default: yesterday; if the user says "since Friday" or it's Monday, widen accordingly). If a digest file for the window already exists in the data repo, read it instead of re-gathering. Don't duplicate activity-digest's gathering logic here — delegate to it.

### 2. Pull the last 1–3 prior standups for continuity (#phantom)

The daily stand-up bot posts a parent message in **#phantom** (channel `C09HD90PR1C`): "Daily Stand-up time! …". The user replies in-thread with their `y:/t:/b:`. Before drafting, pull the user's own most recent standup replies (e.g. `slack_search_public_and_private` `from:@<handle> in:#phantom` sorted by time, or read the recent #phantom standup threads). Use them as **context, not ground truth** — the digest is authoritative:

- The **prior day's `t:`** is what they *planned*. It's the best prior for what today's `y:` should report progress on. Expect partial overlap, not a match — plans slip and priorities shift. Reconcile each planned item against the digest: did it land, slip, or get dropped?
- The **prior `y:`** is what they already reported. Don't re-report the same item as if new; where the digest confirms continuation, phrase it as "finished X" / "continued Y".
- Carry forward any still-open blocker or in-flight thread worth a status line.

If no recent standups are found, skip this silently.

### 3. Draft `y:` from the digest (reconciled with the prior `t:`)

Reframe the digest's themes into standup bullets in the house style above. Cluster; lead with the coordination/design/code groupings the digest already found. Keep bare PR/ticket refs. This section is fully derivable from the digest — draft it without bothering the user. Where the prior day's `t:` named a plan, reflect the actual outcome (shipped / progressed / slipped) rather than restating the intention.

### 4. ASK the user about `t:` and `b:` — do not invent them

Today's plan and blockers are **not** in yesterday's activity and must not be fabricated. Before finalizing, ask the user (one `AskUserQuestion` with a couple of questions, or a short inline prompt):

- **today (`t:`)** — how should we handle it? Options to offer: (a) skip `t:` entirely and post only `y:`; (b) the user dictates today's plan; (c) let the skill *propose* a `t:` from open/in-flight threads in the digest (unmerged PRs, undecided design questions, "shipping next") **plus any items from the prior day's `t:` that the digest shows didn't land yet** — for the user to edit. Make clear any proposed `t:` is a draft to correct.
- **blockers (`b:`)** — ask if there are any; default to a single `- none` only if the user confirms or declines to add. If the digest surfaced an unresolved dependency (e.g. a blocked PR, a pending approval), mention it as a *candidate* blocker for the user to accept or drop.

Respect the answer literally — if they say "just y:", produce only `y:`.

### 5. Deliver it (as a real Slack list, not pasteable plain text)

Assemble the final block in **markdown** per the Bullets rule: bare `y:` / `t:` / `b:` label lines, each followed by `- ` items with 4-space-indented `- ` sub-items. Show it to the user in-conversation first (the markdown source is fine to show).

**Resolve the thread first — it is not a fixed value.** `channel_id` is always `C09HD90PR1C` (#phantom), but `thread_ts` changes every day: the post is a reply under the *current day's* stand-up prompt, a new message the "Daily Stand-up" bot (bot id `B0AELNL5HFY`) posts each morning. Resolve it fresh on every run — find the most recent "Daily Stand-up time!" message from that bot in #phantom and use its `ts` as `thread_ts`. (Today's `y:` reports yesterday's work, but it still goes under *today's* prompt.) Never hardcode or reuse a previous day's ts. If today's prompt isn't up yet, don't fall back to an old thread — tell the user and ask whether to wait or post elsewhere.

Then deliver. **This skill only ever creates a draft — it never sends:**

- **`slack_send_message_draft`** into that thread (`channel_id` `C09HD90PR1C`, `thread_ts` = the resolved parent). The MCP tool converts the markdown into a real Slack rich-text list, so a ready-to-review draft appears in the thread's compose box and **the user reviews and sends it themselves in Slack**. Do **not** call `slack_send_message` — sending is the user's action in Slack, never the skill's.
- **Clipboard / local file is a fallback only.** If the user wants to paste by hand, give them the markdown (`-`) form and warn that whether Slack auto-converts a paste into a list depends on their client — the draft tool is the reliable route. Do **not** hand them literal `•`/`◦` text expecting a native list (that's the original bug).

## Unattended mode (`--unattended`)

When invoked with `--unattended` (the scheduled launchd job runs `claude -p "/standup --unattended"` weekday mornings ~9:55 ET, just after the stand-up bot posts), there is **no human in the loop**. Override the interactive steps as follows:

- **Never call `AskUserQuestion`** and never block on input. Step 4 is replaced by the auto-policy below.
- **Window:** same rule as normal — yesterday, widened to "since the last working day" on a Monday (Fri–Sun).
- **Gather inline, no subagents.** Do the Slack + Linear pulls inline (the headless permission set does not include the `Agent` tool); a single-day window is small enough. Run `gather-code-and-cc.sh` for the code+CC half as usual and write the digest file.
- **Resolve today's thread, and if it's not there yet, STOP.** Find today's "Daily Stand-up" bot parent (`B0AELNL5HFY`) in `C09HD90PR1C`. If today's prompt doesn't exist yet, **log it and exit without drafting** — never fall back to an old thread.
- **`y:`** — draft from the digest exactly as in step 3 (reconciled against the prior day's `t:`).
- **`t:` (auto-proposed):** build it from the digest's in-flight threads (unmerged PRs, undecided design questions, "shipping next") **plus carried-over items from the prior day's `t:` that the digest shows didn't land**. Make it visibly provisional — first sub-item `- (proposed — edit before sending)`.
- **`b:`** — `- none`, unless the digest surfaced a concrete unresolved dependency (blocked PR, pending approval), in which case list it and append `(proposed)`.
- **Deliver as a draft only:** `slack_send_message_draft` into the resolved thread. **Never `slack_send_message`.** The whole point is that a ready-to-review draft is waiting in the user's compose box; they edit `t:`/`b:` and send it themselves.
- **Idempotency (check before drafting):** after resolving today's thread, look at whether the **current user** (the Slack `user_id` you resolved from their email) has **already replied** in it — if so, they've posted their own standup; log and stop, don't drop a duplicate draft. Likewise, if `slack_send_message_draft` returns `draft_already_exists`, a draft is already there — log and stop.
- Everything goes to the run log; there's no conversational output to a human.

## Notes

- In interactive use this skill is **forward-looking-input-required by design**: `y:` is mechanical, `t:`/`b:` are a conversation. That asymmetry is the point — don't shortcut it by inventing a plan. (Unattended mode is the deliberate exception: it *proposes* `t:`/`b:` but leaves them clearly marked for the user to fix in the draft.)
- If `activity-digest` found nothing for the window, say so; a standup with an empty `y:` is a real (if rare) outcome — confirm with the user rather than padding (in unattended mode, draft the empty-`y:` note rather than asking).
- Keep refs bare and lowercase to match the channel; only linkify if the user asks.
