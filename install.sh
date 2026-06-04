#!/usr/bin/env bash
# One-shot setup for a fresh machine.
#
#   gh repo clone jaxondk/dotfiles ~/dotfiles
#   cd ~/dotfiles
#   ./install.sh
#
# Installs chezmoi if needed, then initializes from this repo and applies
# everything: prompts for identity, installs packages, links configs, installs
# opencode deps. Safe to re-run.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v chezmoi >/dev/null 2>&1; then
  echo "==> Installing chezmoi..."
  if command -v brew >/dev/null 2>&1; then
    brew install chezmoi
  else
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

echo "==> chezmoi init --apply (source: $REPO_DIR)"
chezmoi init --apply --source="$REPO_DIR"

cat <<'EOF'

==> Done.
    - Restart your shell:  exec zsh
    - Edit a config later: chezmoi edit ~/.zshrc   (then it auto-applies)
    - See pending changes: chezmoi diff
    - Secrets are NOT managed by chezmoi. Recreate as needed:
        ~/.zsh_secrets, ~/.zshrc.local, ~/.config/opencode/kdco-notify.json
EOF
