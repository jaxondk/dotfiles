---
description: Copy text to the macOS clipboard via a tmp file (write → cat | pbcopy), preserving formatting exactly
---

# Copy to clipboard

Copy content to the user's macOS clipboard using the write-to-tmp-then-pbcopy pattern, so the text lands on the clipboard byte-for-byte with no shell-escaping or quoting mangling.

The user's instruction: **$ARGUMENTS**

## What to copy

- If `$ARGUMENTS` names or describes a specific artifact from this conversation (e.g. "the slack draft", "that commit message", "the last code block", "the review summary"), copy **that exact content** — the full thing, verbatim, with its original formatting/markup.
- If `$ARGUMENTS` is itself the literal text to copy, copy that.
- If it's ambiguous which artifact is meant, ask one quick clarifying question before copying.

## Procedure

1. Write the content to a tmp file with the Write tool (e.g. `/tmp/clip-<short-slug>.md` or `.txt`). Do **not** try to inline the text into an `echo`/`printf` — writing the file avoids escaping issues and keeps newlines, quotes, backticks, and markup intact.
2. Run: `cat <tmpfile> | pbcopy && echo "copied to clipboard ($(wc -c < <tmpfile>) bytes)"`
3. Report that it's copied, the byte count, and the tmp file path. If the content uses a platform-specific markup convention (e.g. Slack `*bold*`), note that so the user knows it'll render correctly where they paste.

Keep it terse — this is a utility action, not a task that needs narration.
