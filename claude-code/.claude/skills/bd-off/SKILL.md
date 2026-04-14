---
name: bd-off
description: Disable BD issue tracking
---

Disable BD (Beads) issue tracking by removing the flag file:

```bash
rm -f ~/.config/opencode/.bd-enabled
```

Confirm that BD tracking is now disabled. You should no longer use `bd` commands for issue tracking until `/bd-on` is run again.
