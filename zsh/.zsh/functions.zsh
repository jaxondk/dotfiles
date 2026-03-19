# Wrapper around `gt` that intercepts `sync` to automatically clean up
# worktrees for branches whose PRs have been merged/closed. All other
# subcommands pass straight through to the real `gt`.
gt() {
  if [[ "${1:-}" == "prune" ]]; then
    _gt_prune_local
    return
  fi

  if [[ "${1:-}" != "sync" ]]; then
    command gt "$@"
    return
  fi

  # It's `gt sync` -- shift off "sync" and run it.
  # Use `tee` so gt's output goes to the terminal with full colors (via the
  # inherited TTY on stdout) while we also capture a copy for parsing.
  shift
  local logfile
  logfile=$(mktemp)
  command gt sync "$@" 2>&1 | tee "$logfile"
  local gt_exit=${pipestatus[1]}

  # Parse branch names from WARNING lines like:
  # WARNING: PR #919 for terminal-cleanup is merged but cannot be cleaned up while it is checked out in another worktree.
  # Strip ANSI codes first, use -E for extended regex (macOS sed needs it for alternation)
  local -a branches
  branches=("${(@f)$(sed 's/\x1b\[[0-9;]*m//g' "$logfile" | sed -En 's/^WARNING: PR #[0-9]+ for (.+) is (merged|closed) but cannot be cleaned up.*/\1/p')}")
  /bin/rm -f "$logfile"

  # Filter out empty entries
  branches=("${(@)branches:#}")

  if [[ ${#branches[@]} -eq 0 ]]; then
    _gt_list_stale_branches
    return $gt_exit
  fi

  echo ""
  echo "Found ${#branches[@]} branch(es) stuck in worktrees: ${branches[*]}"

  # Get worktree paths from git
  local -A worktree_paths
  local wt_branch wt_path
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.*) ]]; then
      wt_path="${match[1]}"
    elif [[ "$line" =~ ^branch\ refs/heads/(.*) ]]; then
      wt_branch="${match[1]}"
      worktree_paths[$wt_branch]="$wt_path"
    fi
  done < <(git worktree list --porcelain)

  local -a removed_dirs
  local -a skipped
  local wt_dir wt_status
  local current_root
  current_root=$(git rev-parse --show-toplevel 2>/dev/null)

  for branch in "${branches[@]}"; do
    wt_dir="${worktree_paths[$branch]}"
    if [[ -z "$wt_dir" ]]; then
      echo "  $branch: no worktree found (already removed?), skipping"
      continue
    fi

    # Never delete the current or primary worktree
    if [[ -n "$current_root" && "$wt_dir" == "$current_root" ]] || [[ -d "$wt_dir/.git" ]]; then
      echo "  $branch: worktree is primary/current, skipping"
      echo "    ($wt_dir)"
      skipped+=("$branch")
      continue
    fi

    # Check for uncommitted changes (staged, unstaged, or untracked)
    # Note: can't use "status" as a variable name -- it's read-only in zsh
    wt_status=$(git -C "$wt_dir" status --porcelain 2>/dev/null)
    if [[ -n "$wt_status" ]]; then
      echo "  $branch: has uncommitted/untracked files, skipping"
      echo "    ($wt_dir)"
      skipped+=("$branch")
      continue
    fi

    echo "  $branch: clean, removing worktree at $wt_dir"
    /bin/rm -rf "$wt_dir"
    removed_dirs+=("$wt_dir")

    # Also delete the local branch since the PR is merged/closed
    git branch -D "$branch" 2>/dev/null && \
      echo "    deleted branch $branch" || \
      echo "    note: could not delete branch $branch"
  done

  if [[ ${#removed_dirs[@]} -gt 0 ]]; then
    git worktree prune
    echo ""
    echo "Pruned worktrees. Removed ${#removed_dirs[@]} worktree(s)."
  fi

  if [[ ${#skipped[@]} -gt 0 ]]; then
    echo ""
    echo "Skipped ${#skipped[@]} worktree(s): ${skipped[*]}"
    echo "Inspect them manually and re-run gt sync, or remove with:"
    echo "  rm -rf <path> && git worktree prune"
  fi

  # Show stale local branches (upstream gone) as a hint
  _gt_list_stale_branches

  return $gt_exit
}

# List local branches whose remote tracking branch has been deleted.
# Skips branches checked out in worktrees and the trunk branch.
_gt_list_stale_branches() {
  local -a stale_branches
  local line br
  local default_branch current_branch
  default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  default_branch=${default_branch#origin/}
  current_branch=$(git branch --show-current 2>/dev/null)

  # `git branch -vv` marks gone upstreams as "[origin/...: gone]"
  while IFS= read -r line; do
    # skip current branch marker, trim leading whitespace
    br="${line#\* }"
    br="${br#  }"
    # extract branch name (first field)
    br="${br%% *}"
    [[ -z "$br" ]] && continue
    stale_branches+=("$br")
  done < <(git branch -vv | grep ': gone]')

  # Filter out branches checked out in worktrees
  local -A wt_checked_out
  local wt_br
  while IFS= read -r line; do
    if [[ "$line" =~ ^branch\ refs/heads/(.*) ]]; then
      wt_checked_out[${match[1]}]=1
    fi
  done < <(git worktree list --porcelain)

  local -a prunable
  for br in "${stale_branches[@]}"; do
    [[ -n "$default_branch" && "$br" == "$default_branch" ]] && continue
    [[ -n "$current_branch" && "$br" == "$current_branch" ]] && continue
    [[ -n "${wt_checked_out[$br]:-}" ]] && continue
    prunable+=("$br")
  done

  if [[ ${#prunable[@]} -gt 0 ]]; then
    echo ""
    echo "${#prunable[@]} local branch(es) with deleted remote (run 'gt prune' to delete):"
    for br in "${prunable[@]}"; do
      echo "  $br"
    done
  fi
}

# Delete local branches whose remote tracking branch has been deleted.
# Skips branches checked out in worktrees.
_gt_prune_local() {
  local -a stale_branches
  local line br
  local default_branch current_branch
  default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  default_branch=${default_branch#origin/}
  current_branch=$(git branch --show-current 2>/dev/null)

  while IFS= read -r line; do
    br="${line#\* }"
    br="${br#  }"
    br="${br%% *}"
    [[ -z "$br" ]] && continue
    stale_branches+=("$br")
  done < <(git branch -vv | grep ': gone]')

  local -A wt_checked_out
  while IFS= read -r line; do
    if [[ "$line" =~ ^branch\ refs/heads/(.*) ]]; then
      wt_checked_out[${match[1]}]=1
    fi
  done < <(git worktree list --porcelain)

  local -a prunable skipped_wt
  for br in "${stale_branches[@]}"; do
    if [[ -n "$default_branch" && "$br" == "$default_branch" ]]; then
      skipped_wt+=("$br")
      continue
    fi
    if [[ -n "$current_branch" && "$br" == "$current_branch" ]]; then
      skipped_wt+=("$br")
      continue
    fi
    if [[ -n "${wt_checked_out[$br]:-}" ]]; then
      skipped_wt+=("$br")
      continue
    fi
    prunable+=("$br")
  done

  if [[ ${#prunable[@]} -eq 0 ]]; then
    echo "No stale local branches to prune."
    return 0
  fi

  echo "Deleting ${#prunable[@]} local branch(es) with deleted remote:"
  for br in "${prunable[@]}"; do
    git branch -D "$br" 2>/dev/null && \
      echo "  deleted $br" || \
      echo "  failed to delete $br"
  done

  if [[ ${#skipped_wt[@]} -gt 0 ]]; then
    echo ""
    echo "Skipped ${#skipped_wt[@]} branch(es) checked out in worktrees:"
    for br in "${skipped_wt[@]}"; do
      echo "  $br"
    done
  fi
}

critique() {
  if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI not found. Install: brew install gh" >&2
    return 1
  fi

  local token
  token=$(gh auth token 2>/dev/null)
  if [[ -z "$token" ]]; then
    echo "Error: gh CLI not authenticated. Run: gh auth login" >&2
    return 1
  fi

  mkdir -p ~/.critique
  printf '{"key":"%s"}\n' "$token" >~/.critique/license.json

  CRITIQUE_WORKER_URL="https://open-inspect-critique-twenty.xx-agents.workers.dev" \
    command critique "$@"
}

# Wrapper to route opencode --share to our own backend instead of opncd.ai.
# NOTE: OPENCODE_CONFIG_CONTENT merges into the full config. If you need to set
# other config via this env var, merge the JSON objects together rather than
# adding a second OPENCODE_CONFIG_CONTENT assignment.
opencode() {
  local md=1
  local args=()
  for arg in "$@"; do
    case "$arg" in
      --no-md) md=0 ;;
      *) args+=("$arg") ;;
    esac
  done
  OPENCODE_EXPERIMENTAL_MARKDOWN="$md" \
  OPENCODE_CONFIG_CONTENT='{"enterprise":{"url":"https://YOUR_SHARE_BACKEND_URL"}}' \
    command opencode "${args[@]}"
}
