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

  local -a args=()
  local use_cloud=false
  for arg in "$@"; do
    if [[ "$arg" == "--cloud" ]]; then
      use_cloud=true
    else
      args+=("$arg")
    fi
  done

  if $use_cloud; then
    CRITIQUE_WORKER_URL="https://open-inspect-web-twenty.xx-agents.workers.dev/" command critique "${args[@]}"
  else
    command critique "${args[@]}"
  fi
}
