---
name: bd-on
type: command
description: Enable BD issue tracking for this session
---

Enable BD (Beads) issue tracking. Run these steps:

1. First, verify this is a firecrew repository:
   ```bash
   git remote get-url origin 2>/dev/null
   ```
   Only proceed if the output is `git@github.com:Twenty-IO/firecrew.git` or `https://github.com/Twenty-IO/firecrew.git`

2. Create the flag file to enable BD tracking:
   ```bash
   touch ~/.config/opencode/.bd-enabled
   ```

3. Run `bd onboard` to get current workflow context and understand active issues

4. Confirm BD tracking is now enabled

From now on, you should:
- Use `bd create "title" -t <type> -p <priority>` to track new issues
- Use `bd update <id> --status in_progress` when starting work
- Use `bd close <id>` when completing issues
- Use `bd ready` to see issues ready to work on
- Use `bd sync` before pushing code (in "Landing the Plane" workflow)
