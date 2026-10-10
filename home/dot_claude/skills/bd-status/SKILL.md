---
name: bd-status
description: Check if BD issue tracking is enabled
---

Check the current BD tracking status:

```bash
test -f ~/.config/opencode/.bd-enabled && echo "BD tracking: ENABLED" || echo "BD tracking: DISABLED"
```

Report the status to the user.
