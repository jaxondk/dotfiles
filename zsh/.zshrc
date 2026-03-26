# . "$HOME/.local/bin/env"

# Fix for Ghostty terminal on systems without its terminfo
if [[ "$TERM" == "xterm-ghostty" ]] && ! infocmp xterm-ghostty &>/dev/null; then
  export TERM=xterm-256color
fi

# Performance-optimized completion system
autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# zsh autosuggest (platform-specific)
if [[ "$OSTYPE" == "darwin"* ]]; then
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
elif [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# History configuration
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt HIST_IGNORE_DUPS SHARE_HISTORY

# MISE let's let the mise tools win

# Antidote plugin management (platform-specific)
if [[ "$OSTYPE" == "darwin"* ]]; then
  source $(brew --prefix)/share/antidote/antidote.zsh
  antidote load ~/.zsh_plugins.txt
elif [[ -f /usr/share/zsh-antidote/antidote.zsh ]]; then
  source /usr/share/zsh-antidote/antidote.zsh
  antidote load ~/.zsh_plugins.txt
fi

# Applies vim keys when you  hit escape on command line
# set -o vi

######## ALIASES
alias hg="history -n 1000 | grep"
alias zshrc='vim ~/.zshrc'
alias sz='source ~/.zshrc'
alias ghostconf='vim ~/.config/ghostty/config'
alias promptconf='vim ~/.config/starship.toml'
alias kittyconf='vim ~/.config/kitty/kitty.conf'

alias vim=nvim
alias nvimrc='nvim ~/.config/nvim/init.lua'

alias tmuxconf='vim ~/.tmux.conf'
alias ccusage='npx ccusage@latest'
alias awsd="source _awsd"
alias awsconf='vim ~/.aws/config'
alias cclip='pbpaste | pbcopy'
ocb() { opencode run --agent bash-cmd-only "$*" | pbcopy; }

alias ghcrlogin='gh auth token | docker login ghcr.io -u $(gh api user --jq .login) --password-stdin'

alias nload='TERM=xterm-256color nload'
alias o='opencode'


#############
### Make LS colorful
#############
export CLICOLOR=1
export LSCOLORS="GxFxCxDxBxegedabagaced"

#############
# Custom modular configs (add this at the very end)
############
for file in ~/.zsh/{aliases,functions,work}.zsh; do
  [ -r "$file" ] && source "$file"
done

# Source local secrets (gitignored)
[ -f ~/.zsh_secrets ] && source ~/.zsh_secrets

# Add custom scripts to PATH
export PATH="$HOME/bin:$PATH"
export PATH="/opt/homebrew/bin/:$PATH"
### Go
export PATH=$PATH:/usr/local/go/bin
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:/Users/jaxon.keeler/go/bin

### Bun
export PATH="$HOME/.bun/bin:$PATH"


#############
# Stuff that's supposed to be at the end?
#############

# eval $(thefuck --alias)

# Only activate mise if we're in or under a directory with a .mise.toml or .tool-versions
if mise direnv activate >/dev/null 2>&1; then
  eval "$(mise activate zsh)"  # or zsh/fish depending on your shell
fi

# add cargo installed packages to PATH
export PATH="$HOME/.cargo/bin:$PATH"

# direnv hook for per-directory environment variables
eval "$(direnv hook zsh)"

# Starship prompt (must be last)
eval "$(starship init zsh)"
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"

# AWS Session Manager Plugin
export PATH="/usr/local/sessionmanagerplugin/bin:$PATH"

if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi
