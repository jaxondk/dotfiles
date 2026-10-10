## Beads Issue Tracking (Firecrew Only)

**BD tracking is OFF by default.** Use `/bd-on` to enable, `/bd-off` to disable, `/bd-status` to check.

### Checking if BD Tracking is Enabled

Before using any `bd` commands, check if tracking is enabled:
```bash
test -f ~/.config/opencode/.bd-enabled && echo "ENABLED" || echo "DISABLED"
```

**Only use `bd` commands if BOTH conditions are met:**
1. The flag file `~/.config/opencode/.bd-enabled` exists
2. You are working in the **firecrew** repository (remote URL is `git@github.com:Twenty-IO/firecrew.git` or `https://github.com/Twenty-IO/firecrew.git`)

If BD tracking is DISABLED or you're not in firecrew, **do not use any `bd` commands**.

---

### When BD Tracking is ENABLED

Use these commands to manage issues:

| Command | Description |
|---------|-------------|
| `bd ready` | Show issues ready to work on |
| `bd list` | List all issues |
| `bd create "title" -t <type> -p <priority>` | Create new issue |
| `bd update <id> --status in_progress` | Update issue status |
| `bd close <id>` | Close completed issue |
| `bd prime` | Get workflow context and instructions |
| `bd sync` | Sync issues before pushing (use in Landing the Plane) |

### Issue Types
- `task` - General work item
- `bug` - Bug fix
- `feature` - New feature
- `epic` - Large feature with sub-issues

### Priority Levels
- `0` - Critical
- `1` - High
- `2` - Medium (default)
- `3` - Low
- `4` - Backlog

### Issue Prefix
Firecrew issues use the `fc-` prefix (e.g., `fc-a1b2`)
