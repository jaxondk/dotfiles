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
  local -a candidate_branches
  local -a candidate_dirs
  local -a skipped
  local wt_dir wt_status branch_tree landed_commit

  # Identify the primary worktree (first entry in porcelain output)
  # and the current worktree we're running from -- never delete either
  local primary_wt current_root
  primary_wt=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
  current_root=$(git rev-parse --show-toplevel 2>/dev/null)

  # Build a map of tree SHA -> trunk commit SHA using first-parent trunk
  # history. This lets us detect branches whose exact content has already
  # landed on trunk even if Graphite rebased, squashed, or rewrote commits.
  local trunk_ref
  trunk_ref=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  if [[ -z "$trunk_ref" ]]; then
    if git show-ref --verify --quiet refs/remotes/origin/develop; then
      trunk_ref="origin/develop"
    elif git show-ref --verify --quiet refs/remotes/origin/main; then
      trunk_ref="origin/main"
    fi
  fi

  local -A trunk_tree_to_commit
  local trunk_commit trunk_tree
  if [[ -n "$trunk_ref" ]]; then
    while IFS=' ' read -r trunk_commit trunk_tree; do
      [[ -n "$trunk_tree" ]] || continue
      trunk_tree_to_commit[$trunk_tree]="$trunk_commit"
    done < <(git log --first-parent --format='%H %T' "$trunk_ref")
  fi

  for branch in "${branches[@]}"; do
    wt_dir="${worktree_paths[$branch]}"
    if [[ -z "$wt_dir" ]]; then
      echo "  $branch: no worktree found (already removed?), skipping"
      continue
    fi

    # Never delete the primary or current worktree
    if [[ "$wt_dir" == "$primary_wt" ]] || \
       [[ -n "$current_root" && "$wt_dir" == "$current_root" ]] || \
       [[ -d "$wt_dir/.git" ]]; then
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

    # Check whether this branch's exact content already exists on trunk.
    # Tree equality is the right safety check for Graphite merge queues,
    # where landed commits may have different SHAs due to rebases/squashes.
    if [[ -z "$trunk_ref" || ${#trunk_tree_to_commit[@]} -eq 0 ]]; then
      echo "  $branch: could not determine trunk history, skipping"
      echo "    (expected origin/HEAD, origin/develop, or origin/main)"
      skipped+=("$branch")
      continue
    fi

    branch_tree=$(git rev-parse "${branch}^{tree}" 2>/dev/null)
    landed_commit="${trunk_tree_to_commit[$branch_tree]:-}"
    if [[ -z "$branch_tree" || -z "$landed_commit" ]]; then
      echo "  $branch: branch content not found on $trunk_ref, skipping"
      echo "    ($wt_dir)"
      skipped+=("$branch")
      continue
    fi

    echo "  $branch: landed on $trunk_ref at $landed_commit, queued for removal"
    candidate_branches+=("$branch")
    candidate_dirs+=("$wt_dir")
  done

  if [[ ${#candidate_dirs[@]} -gt 0 ]]; then
    echo ""
    echo "Ready to remove ${#candidate_dirs[@]} worktree(s):"
    local i
    for i in {1..${#candidate_dirs[@]}}; do
      echo "  ${candidate_branches[$i]} -> ${candidate_dirs[$i]}"
    done
    echo ""
    printf "Delete these worktrees now? [y/N] "
    local reply
    read -r reply
    if [[ "$reply" == "y" || "$reply" == "Y" ]]; then
      for i in {1..${#candidate_dirs[@]}}; do
        # Sync docs/scratch before removal
        _gt_sync_scratch "${candidate_dirs[$i]}" "${candidate_branches[$i]}" "$primary_wt"
        /bin/rm -rf "${candidate_dirs[$i]}"
        removed_dirs+=("${candidate_dirs[$i]}")
      done
    else
      echo "Skipped removal."
    fi
  fi

  if [[ ${#removed_dirs[@]} -gt 0 ]]; then
    git worktree prune
    echo ""
    echo "Pruned worktrees. Removed ${#removed_dirs[@]} worktree(s)."

    # Delete branches after prune (worktree ref locks are gone now).
    # We already verified the branch head tree exists on trunk, so -D is safe
    # as fallback for Graphite/squash-rewritten history that git doesn't
    # recognize as a normal merged branch topology.
    for i in {1..${#candidate_branches[@]}}; do
      [[ " ${removed_dirs[*]} " == *" ${candidate_dirs[$i]} "* ]] || continue
      git branch -d "${candidate_branches[$i]}" 2>/dev/null || \
        git branch -D "${candidate_branches[$i]}" 2>/dev/null
      echo "  deleted branch ${candidate_branches[$i]}"
    done
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

# Sync docs/scratch files from a worktree to the primary worktree before removal.
# Files whose content does not already exist anywhere under primary docs/scratch/
# get copied into docs/scratch/<worktree_bucket>/.
# Usage: _gt_sync_scratch <worktree_dir> <branch_name> <primary_worktree_dir>
_gt_sync_scratch() {
  local src_wt="$1" branch="$2" primary="$3"
  local wt_name="${src_wt:t}"
  local wt_bucket="$wt_name"
  if [[ "$wt_name" == *.* ]]; then
    wt_bucket="${wt_name#*.}"
  fi
  local src_scratch="$src_wt/docs/scratch"
  local dst_scratch="$primary/docs/scratch"

  # Nothing to sync if the worktree has no docs/scratch
  [[ -d "$src_scratch" ]] || return 0

  local -A existing_paths_by_hash
  local existing_file existing_hash

  # Index all existing scratch file content in the primary worktree so we can
  # skip re-copying notes that were already preserved elsewhere.
  while IFS= read -r existing_file; do
    [[ "${existing_file:t}" == ".DS_Store" ]] && continue
    existing_hash=$(git hash-object "$existing_file" 2>/dev/null)
    [[ -n "$existing_hash" ]] || continue
    existing_paths_by_hash[$existing_hash]="$existing_file"
  done < <(find "$dst_scratch" -type f 2>/dev/null)

  local -a to_sync
  local rel_file src_file src_hash existing_path

  # Find all files in the worktree's docs/scratch
  while IFS= read -r src_file; do
    [[ "${src_file:t}" == ".DS_Store" ]] && continue
    rel_file="${src_file#$src_scratch/}"
    src_hash=$(git hash-object "$src_file" 2>/dev/null)
    existing_path="${existing_paths_by_hash[$src_hash]:-}"

    if [[ -z "$src_hash" ]]; then
      to_sync+=("$rel_file")
    elif [[ -z "$existing_path" ]]; then
      # This file's content does not exist anywhere in primary docs/scratch.
      to_sync+=("$rel_file")
    fi
  done < <(find "$src_scratch" -type f 2>/dev/null)

  [[ ${#to_sync[@]} -gt 0 ]] || return 0

  echo ""
  echo "  docs/scratch files in $wt_name whose content is not yet in primary:"
  for rel_file in "${to_sync[@]}"; do
    echo "    $rel_file"
  done
  printf "  Copy these to docs/scratch/%s/ in primary worktree? [Y/n] " "$wt_bucket"
  local scratch_reply
  read -r scratch_reply
  if [[ "$scratch_reply" == "n" || "$scratch_reply" == "N" ]]; then
    echo "  Skipped scratch sync for $branch."
    return 0
  fi

  local dest_dir="$dst_scratch/$wt_bucket"
  for rel_file in "${to_sync[@]}"; do
    /bin/mkdir -p "$dest_dir/${rel_file:h}"
    /bin/cp "$src_scratch/$rel_file" "$dest_dir/$rel_file"
  done
  echo "  Copied ${#to_sync[@]} file(s) to $dest_dir/"
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
