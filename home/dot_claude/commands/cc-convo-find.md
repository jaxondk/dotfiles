---
description: Find a past Claude Code conversation by description and print the command to resume it (optionally answer a question about its contents)
---

# Find a past Claude Code conversation

The user's query: **$ARGUMENTS**

Your job: locate the Claude Code conversation that best matches the query, then print the command to resume it. If the query also asks a question about what happened in that conversation ("what was decided", "what did we end up doing", "what files did we touch", etc.), answer that question from the transcript.

## How conversations are stored

- Transcripts live in `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`
- Each line is a JSON message. The first 1–2 lines may lack metadata; subsequent lines carry `cwd`, `timestamp`, and `message.content`
- The filename (without `.jsonl`) is the **session id**
- The directory mtime / file mtime is a reliable recency signal
- To resume: `cd <cwd> && claude --resume <session-id>` (run from the original cwd)

## Procedure

Delegate the search to a subagent so the heavy I/O stays out of this context. Use `subagent_type: general-purpose` with `model: haiku` for pure find-the-convo queries, or `model: sonnet` if the query also asks a substantive question about the conversation's contents.

Spawn the subagent with a self-contained prompt that includes:

1. **The user's query, verbatim** — so the agent can detect whether a question needs answering.
2. **The search strategy:**
   - Parse any time hints in the query ("yesterday", "last week", "this morning", "a few days ago"). Today is available via `date`. Map to a date range and filter with `find ~/.claude/projects -name '*.jsonl' -newermt <start> ! -newermt <end>`. With no time hint, sort all `.jsonl` files by mtime descending and consider the top ~50.
   - Extract topic keywords from the query (drop stopwords like "convo", "conversation", "i had", "yesterday", "the one about"). Grep candidate files case-insensitively for those keywords; count matches per file to rank.
   - For the top 3–5 candidates, read the **first user message** (find the first line where `type == "user"` and `message.content` is non-empty — content may be a string OR a list of parts; for lists, concatenate the `text` fields) to confirm topical fit.
   - Also pull `cwd` from any message that has it (usually line 2+), and the file's mtime for the displayed timestamp.
3. **What to return** — the subagent should report a single best match (or top 2 if ambiguous), each with:
   - Session id
   - Project cwd
   - File path
   - Human-readable timestamp (file mtime)
   - One-line summary of the opening user message (truncate to ~200 chars)
   - The exact resume command: `cd <cwd> && claude --resume <session-id>`
   - If the query asks a question: a focused answer (under 200 words) grounded in the transcript, with brief evidence. The agent should read enough of the transcript to answer well — not the whole file if it's huge; skim for assistant decisions, code changes, conclusions.

## Output to the user

After the subagent returns, relay its findings concisely:

- Lead with the resume command in a code block so it's easy to copy.
- Then one short line of context: timestamp + opening prompt snippet.
- If a question was answered, include the answer next, kept tight.
- If the match is uncertain, show the top 2 and ask the user which.

Do not narrate the search process. The user wants the answer, not the methodology.
