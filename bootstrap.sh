#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Bootstrapping dotfiles..."

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
  OS="macos"
elif [[ -f /etc/debian_version ]]; then
  OS="debian"
elif [[ -f /etc/redhat-release ]]; then
  OS="redhat"
else
  OS="unknown"
fi

echo "==> Detected OS: $OS"

# Install packages based on OS
install_packages() {
  case "$OS" in
    macos)
      if ! command -v brew &>/dev/null; then
        echo "==> Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
      echo "==> Installing packages via Homebrew..."
      brew install stow zsh zsh-autosuggestions antidote starship neovim direnv
      ;;
    debian)
      echo "==> Installing packages via apt..."
      sudo apt update
      sudo apt install -y stow zsh zsh-autosuggestions git curl
      
      # Install starship
      if ! command -v starship &>/dev/null; then
        echo "==> Installing Starship..."
        curl -sS https://starship.rs/install.sh | sudo sh -s -- -y
      fi
      
      # Install neovim (apt version is often outdated, use appimage or snap)
      if ! command -v nvim &>/dev/null; then
        echo "==> Installing Neovim..."
        sudo snap install nvim --classic || sudo apt install -y neovim
      fi
      
      # Install direnv
      if ! command -v direnv &>/dev/null; then
        sudo apt install -y direnv
      fi
      ;;
    redhat)
      echo "==> Installing packages via dnf..."
      sudo dnf install -y stow zsh git curl neovim direnv
      
      # Install starship
      if ! command -v starship &>/dev/null; then
        curl -sS https://starship.rs/install.sh | sh -s -- -y
      fi
      ;;
    *)
      echo "Unknown OS. Please install manually: stow, zsh, zsh-autosuggestions, starship, neovim, direnv"
      ;;
  esac
}

# Stow all dotfiles
stow_dotfiles() {
  echo "==> Stowing dotfiles..."
  cd "$SCRIPT_DIR"
  ./stow-all.sh
}

# Set zsh as default shell
set_default_shell() {
  if [[ "$SHELL" != *"zsh"* ]]; then
    echo "==> Setting zsh as default shell..."
    sudo chsh -s "$(which zsh)" "$USER"
  fi
}

# Main
install_packages
stow_dotfiles
set_default_shell

echo ""
echo "==> Bootstrap complete!"
echo "    Restart your terminal or run: exec zsh"
