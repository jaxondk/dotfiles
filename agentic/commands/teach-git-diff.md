---
name: teach-git-diff
type: command
description: Learn about changes in a commit, branch, or PR
argument-hint: "<ref> [base]"
---

Teach me about the changes in: $1 (compared against: ${2:-auto-detected base})

First, gather context:

**Detect default branch:**
!`git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"`

**If this looks like a PR number:**
!`gh pr view $1 --json title,body,baseRefName,headRefName,commits,files 2>/dev/null || echo "Not a PR or gh CLI not configured"`

**PR diff (if applicable):**
!`gh pr diff $1 2>/dev/null`

**Git ref info:**
!`git log -1 --format="Commit: %H%nAuthor: %an%nDate: %ad%nMessage: %s%n%n%b" $1 2>/dev/null || echo "Not a git ref"`

**Git diff:**
!`ref="$1"; base="$2"; default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"); if [ -n "$base" ]; then git diff "$base..$ref"; elif git rev-parse --verify "$ref^" >/dev/null 2>&1 && [ "$(git cat-file -t "$ref" 2>/dev/null)" = "commit" ]; then git diff "$ref^..$ref"; elif git rev-parse --verify "$ref" >/dev/null 2>&1; then merge_base=$(git merge-base "$default_branch" "$ref" 2>/dev/null) && git diff "$merge_base..$ref"; fi 2>/dev/null`

**Commit log (for branches, shows all commits since base):**
!`ref="$1"; base="$2"; default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"); if [ -n "$base" ]; then git log --oneline "$base..$ref" 2>/dev/null; elif git rev-parse --verify "$ref" >/dev/null 2>&1; then merge_base=$(git merge-base "$default_branch" "$ref" 2>/dev/null) && git log --oneline "$merge_base..$ref" 2>/dev/null; fi`

---

The context above contains all the information you need - do not run additional git commands to gather more context.

Now teach me about these changes. Help me understand why these design choices were likely made.

Most often, it's best to start from first principles and ELI5 - what are the fundamental problems represented here and how do the changes (and any frameworks involved) help address them?

If the change is relatively simple, this deep discussion may not be necessary - adjust your teaching depth to match the complexity of the change.

Focus on:
1. What problem is being solved?
2. Why was this approach chosen over alternatives?
3. What patterns or concepts should I understand to appreciate this change?
4. Are there any trade-offs or gotchas I should be aware of?
