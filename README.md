# Dotfiles

My dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## How It Works

This repo uses stow to create symlinks from your home directory into this repo. Each top-level directory is a "package" that maps to files in `~`.

For example:
```
dotfiles/zsh/.zshrc  -->  ~/.zshrc (symlink)
dotfiles/nvim/.config/nvim/  -->  ~/.config/nvim (symlink)
```

When you edit `~/.zshrc`, you're actually editing the file in this repo.

## Setup (New Machine)

```bash
# Install stow
brew install stow   # macOS
# apt install stow  # Debian/Ubuntu

# Clone repo
git clone git@github.com:YOUR_USERNAME/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Create symlinks for all packages
./stow-all.sh
```

If stow reports conflicts, you have existing files where it wants to create symlinks. Back them up and remove them, then re-run stow.

## Usage

**Stow all packages:**
```bash
./stow-all.sh
```

**Stow a single package:**
```bash
cd ~/dotfiles
stow zsh
```

**Unstow (remove symlinks):**
```bash
stow -D zsh        # single package
stow -D */         # all packages
```

**Restow (refresh symlinks after changes):**
```bash
stow -R zsh
```

## Adding New Configs

1. Create a new directory for the package
2. Mirror the path structure from `~`
3. Move your config file(s) into that structure
4. Run `stow <package>`

Example for adding `~/.config/foo/config.toml`:
```bash
mkdir -p ~/dotfiles/foo/.config/foo
mv ~/.config/foo/config.toml ~/dotfiles/foo/.config/foo/
cd ~/dotfiles && stow foo
```

## Packages

- `ghostty` - terminal emulator
- `git` - git config and global ignore
- `nvim` - Neovim (LazyVim)
- `opencode` - OpenCode AI assistant
- `starship` - shell prompt
- `worktrunk` - git worktree manager
- `zsh` - shell config
