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

You'll need to install any tools that are being used / managed that you haven't already installed. For example:

```bash
brew install starship antidote nvim worktrunk opencode
```

Additionally, you need to install stow, which is used for symlinking all of these dotfiles.


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

**Stow** = create symlinks (activate a package)

**Unstow** = remove symlinks (deactivate a package)

**Restow** = remove then recreate symlinks (useful after renaming/moving files)

```bash
# Stow all packages
./stow-all.sh

# Stow a single package
cd ~/dotfiles
stow zsh

# Unstow (remove symlinks)
stow -D zsh        # single package
stow -D */         # all packages

# Restow (refresh symlinks)
stow -R zsh
```

### When to use each

**Stow**: Setting up a new machine, or adding a new package to the repo.

**Unstow**: Removing a package from the repo, or temporarily disabling a config.

**Restow**: After renaming or moving files within a package.

In practice, you'll mostly just run `./stow-all.sh` once on a new machine, then edit configs directly (symlinks mean edits go straight to the repo) and commit/push. You rarely need to re-run stow unless adding a new package or restructuring files.

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
- `herdr` - agent multiplexer; prefix is `cmd+a` (rewritten to ctrl+a by ghostty)
- `nvim` - Neovim (LazyVim)
- `opencode` - OpenCode AI assistant
- `starship` - shell prompt
- `worktrunk` - git worktree manager
- `zsh` - shell config

### opencode

After stowing, install plugin dependencies:

```bash
cd ~/.config/opencode && bun install
```

#### Notifications (Slack)

The opencode package includes the [opencode-notify](https://github.com/kdcokenny/opencode-notify) plugin with Slack webhook support. Native macOS notifications are disabled by default in favor of Slack (which covers both desktop and mobile).

To set up Slack notifications:

1. Go to https://api.slack.com/apps and click "Create New App" > "From scratch"
2. Name it something like "OpenCode Notify" and pick your workspace
3. Go to "Incoming Webhooks" in the sidebar and toggle it on
4. Click "Add New Webhook to Workspace" and pick the channel or DM you want notifications in
5. Copy the webhook URL (looks like `https://hooks.slack.com/services/T.../B.../xxx`)
6. Create your config from the example:
   ```bash
   cp ~/.config/opencode/kdco-notify.example.json ~/.config/opencode/kdco-notify.json
   ```
7. Edit `~/.config/opencode/kdco-notify.json` and replace the placeholder with your webhook URL
8. Restart OpenCode

The real config is gitignored since it contains the webhook secret. To re-enable native macOS notifications alongside Slack, set `"native": true` in the config.
