# ==============================
# ZSH Configuration File
# ==============================


# ==============================
# Prompt Engine
# ==============================

# Available prompt engines:
#
#   omp  = Oh My Posh
#   p10k = Powerlevel10k
#
# Temporarily switch:
#
#   PROMPT_ENGINE=omp exec zsh
#   PROMPT_ENGINE=p10k exec zsh
PROMPT_ENGINE="${PROMPT_ENGINE:-omp}"

case "$PROMPT_ENGINE" in
  omp|p10k)
    ;;
  *)
    print -P "%F{yellow}Unknown PROMPT_ENGINE=$PROMPT_ENGINE; falling back to omp%f"
    PROMPT_ENGINE="omp"
    ;;
esac


# ==============================
# Fastfetch on Kitty Startup
# ==============================

# Fastfetch appearance is configured in:
#
#   ~/.config/fastfetch/config.jsonc
#
# This block only controls when Fastfetch runs.
#
# It runs:
#   - in interactive Zsh
#   - inside Kitty
#   - outside SSH
#   - outside tmux
#   - once per Kitty window
#
# It does not run again after:
#   reloadzsh
#   useomp
#   usep10k
if [[ -o interactive \
      && -n "${KITTY_WINDOW_ID:-}" \
      && -z "${SSH_CONNECTION:-}" \
      && -z "${TMUX:-}" \
      && "${FASTFETCH_SHOWN_FOR:-}" != "$KITTY_WINDOW_ID" ]] \
   && (( $+commands[fastfetch] )); then

  export FASTFETCH_SHOWN_FOR="$KITTY_WINDOW_ID"
  command fastfetch
fi


# ==============================
# Powerlevel10k Instant Prompt
# ==============================

# Keep this section near the top.
#
# Commands that may write to the terminal or request input should be
# placed above this section.
if [[ "$PROMPT_ENGINE" == "p10k" ]]; then
  P10K_INSTANT_PROMPT="${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"

  if [[ -r "$P10K_INSTANT_PROMPT" ]]; then
    source "$P10K_INSTANT_PROMPT"
  fi

  unset P10K_INSTANT_PROMPT
fi


# ==============================
# XDG Directories
# ==============================

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"


# ==============================
# PATH
# ==============================

# Use Zsh's path array and automatically remove duplicates.
typeset -U path PATH

path=(
  "$HOME/bin"
  "$HOME/.local/bin"
  "/usr/local/bin"
  $path
)


# ==============================
# Prompt Theme Helpers
# ==============================

# Default Oh My Posh theme.
OMP_THEME_NAME="${OMP_THEME_NAME:-montys}"


# Find an Oh My Posh theme file.
#
# Accepted input:
#
#   montys
#   montys.omp.json
_omp_find_theme() {
  local theme_name="${1:-$OMP_THEME_NAME}"
  theme_name="${theme_name%.omp.json}"

  local theme_dirs=(
    "$XDG_CONFIG_HOME/oh-my-posh/themes"
    "$XDG_CACHE_HOME/oh-my-posh/themes"
    "$XDG_CACHE_HOME/paru/clone/oh-my-posh-git/src/oh-my-posh/themes"
    "/usr/share/oh-my-posh/themes"
    "/usr/local/share/oh-my-posh/themes"
  )

  local dir
  local candidate

  for dir in "${theme_dirs[@]}"; do
    candidate="$dir/${theme_name}.omp.json"

    if [[ -r "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done

  return 1
}


# Find the installed Powerlevel10k theme engine.
_p10k_find_theme() {
  local candidates=(
    "/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme"
    "/usr/share/powerlevel10k/powerlevel10k.zsh-theme"
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k/powerlevel10k.zsh-theme"
  )

  local candidate

  for candidate in "${candidates[@]}"; do
    if [[ -r "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done

  return 1
}


# ==============================
# Zsh Completion
# ==============================

autoload -Uz compinit

# Store the completion cache in XDG_CACHE_HOME.
if [[ ! -d "$XDG_CACHE_HOME/zsh" ]]; then
  mkdir -p "$XDG_CACHE_HOME/zsh"
fi

compinit -d "$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"


# ==============================
# Editor
# ==============================

if (( $+commands[nvim] )); then
  export EDITOR="nvim"
  export VISUAL="nvim"
elif (( $+commands[vim] )); then
  export EDITOR="vim"
  export VISUAL="vim"
fi


# ==============================
# General Aliases
# ==============================

# Open this configuration file.
zshconfig() {
  "${EDITOR:-nvim}" "$HOME/.zshrc"
}

# Restart Zsh without nesting another shell.
alias reloadzsh='exec zsh'

# Switch prompt engines.
alias useomp='PROMPT_ENGINE=omp exec zsh'
alias usep10k='PROMPT_ENGINE=p10k exec zsh'

# Use Python 3 when typing python.
alias python='python3'


# ==============================
# Eza
# ==============================

if (( $+commands[eza] )); then
  unalias ls ll la lt 2>/dev/null

  alias ls='eza --icons=auto --group-directories-first'
  alias ll='eza -lah --icons=auto --group-directories-first --git'
  alias la='eza -a --icons=auto --group-directories-first'
  alias lt='eza --tree --icons=auto --group-directories-first'
fi


# ==============================
# Oh My Posh Theme Switcher
# ==============================

# Examples:
#
#   useomp_theme montys
#   useomp_theme atomic
#   useomp_theme catppuccin_mocha
#   useomp_theme jandedobbeleer
useomp_theme() {
  local theme_name="${1:-$OMP_THEME_NAME}"
  theme_name="${theme_name%.omp.json}"

  local theme_file
  theme_file="$(_omp_find_theme "$theme_name")"

  if [[ -n "$theme_file" && -r "$theme_file" ]]; then
    OMP_THEME_NAME="$theme_name" \
    OMP_THEME="$theme_file" \
    PROMPT_ENGINE="omp" \
    exec zsh
  else
    print -P "%F{red}Oh My Posh theme not found: ${theme_name}.omp.json%f"

    print
    print "Theme directories checked:"
    print "  $XDG_CONFIG_HOME/oh-my-posh/themes"
    print "  $XDG_CACHE_HOME/oh-my-posh/themes"
    print "  $XDG_CACHE_HOME/paru/clone/oh-my-posh-git/src/oh-my-posh/themes"
    print "  /usr/share/oh-my-posh/themes"
    print "  /usr/local/share/oh-my-posh/themes"

    return 1
  fi
}


# ==============================
# Bat
# ==============================

# View installed themes:
#
#   bat --list-themes
#
# Check this specific theme:
#
#   bat --list-themes | grep -Fx "Catppuccin Mocha"
export BAT_THEME="Catppuccin Mocha"


# ==============================
# FZF + fd
# ==============================

# fd creates candidate lists.
# fzf displays the interactive fuzzy finder.
#
# These variables must be defined before loading `fzf --zsh`.
if (( $+commands[fd] )); then
  export FZF_DEFAULT_COMMAND='fd --hidden --strip-cwd-prefix --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --strip-cwd-prefix --exclude .git'
else
  # Fallback when fd is unavailable.
  export FZF_DEFAULT_COMMAND="find . -path '*/.git' -prune -o -print"
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="find . -path '*/.git' -prune -o -type d -print"
fi


# Preview either a file or directory.
#
# Directory:
#   eza, with find as fallback
#
# File:
#   bat, with sed as fallback
show_file_or_dir_preview='
  if [ -d {} ]; then
    if command -v eza >/dev/null 2>&1; then
      eza --tree --color=always {} | head -n 200
    else
      find {} -maxdepth 2 -print 2>/dev/null | head -n 200
    fi
  else
    if command -v bat >/dev/null 2>&1; then
      bat --number --color=always --line-range :500 {}
    else
      sed -n "1,500p" {}
    fi
  fi
'


# Preview directories only.
show_dir_preview='
  if command -v eza >/dev/null 2>&1; then
    eza --tree --color=always {} | head -n 200
  else
    find {} -maxdepth 2 -print 2>/dev/null | head -n 200
  fi
'


# Ctrl + T:
# Select a path and insert it into the current command.
export FZF_CTRL_T_OPTS="
  --preview '$show_file_or_dir_preview'
  --preview-window=right:60%
"


# Alt + C:
# Select a directory and cd into it.
export FZF_ALT_C_OPTS="
  --preview '$show_dir_preview'
  --preview-window=right:60%
"


# Load FZF key bindings and fuzzy completion.
if (( $+commands[fzf] )); then
  source <(fzf --zsh)
fi


# Candidate generator for file and path completion.
#
# Example:
#
#   nvim **<Tab>
_fzf_compgen_path() {
  if (( $+commands[fd] )); then
    fd --hidden --exclude .git . "$1"
  else
    command find "$1" -path '*/.git' -prune -o -print
  fi
}


# Candidate generator for directory completion.
#
# Example:
#
#   cd **<Tab>
_fzf_compgen_dir() {
  if (( $+commands[fd] )); then
    fd --type d --hidden --exclude .git . "$1"
  else
    command find "$1" -path '*/.git' -prune -o -type d -print
  fi
}


# Customize FZF completion previews based on the command.
_fzf_comprun() {
  local command_name="$1"
  shift

  case "$command_name" in
    cd)
      fzf --preview "$show_dir_preview" "$@"
      ;;

    export|unset)
      fzf --preview "eval 'echo \$'{}" "$@"
      ;;

    ssh)
      if (( $+commands[dig] )); then
        fzf --preview 'dig {}' "$@"
      else
        fzf "$@"
      fi
      ;;

    *)
      fzf --preview "$show_file_or_dir_preview" "$@"
      ;;
  esac
}


# ==============================
# fzf-git.sh
# ==============================

# Optional FZF integration for Git.
#
# Expected location:
#
#   ~/fzf-git.sh/fzf-git.sh
if [[ -r "$HOME/fzf-git.sh/fzf-git.sh" ]]; then
  source "$HOME/fzf-git.sh/fzf-git.sh"
fi


# ==============================
# TheFuck
# ==============================

# Correct the previous command using:
#
#   fk
if (( $+commands[thefuck] )); then
  eval "$(thefuck --alias fk)"
fi


# ==============================
# Zoxide
# ==============================

# Replace cd with Zoxide's smart directory navigation.
#
# Examples:
#
#   cd ~/.config
#   cd nvim
#   cd dotfiles
#   cd -
#
# Interactive directory selection:
#
#   cdi
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh --cmd cd)"
fi


# ==============================
# Prompt
# ==============================

case "$PROMPT_ENGINE" in
  p10k)
    P10K_THEME="$(_p10k_find_theme)"

    if [[ -n "$P10K_THEME" && -r "$P10K_THEME" ]]; then
      # Load the Powerlevel10k engine.
      source "$P10K_THEME"

      # Load the personal Powerlevel10k configuration.
      if [[ -r "$HOME/.p10k.zsh" ]]; then
        source "$HOME/.p10k.zsh"
      else
        print -P "%F{yellow}Powerlevel10k config not found: $HOME/.p10k.zsh%f"
        print "Run: p10k configure"
      fi
    else
      print -P "%F{red}Powerlevel10k theme engine not found.%f"

      print
      print "Check the installed package with:"
      print "  pacman -Ql zsh-theme-powerlevel10k 2>/dev/null | grep powerlevel10k.zsh-theme"
      print "  pacman -Ql zsh-theme-powerlevel10k-git 2>/dev/null | grep powerlevel10k.zsh-theme"
    fi

    unset P10K_THEME
    ;;

  omp)
    # Use OMP_THEME when already set.
    # Otherwise, locate the theme using OMP_THEME_NAME.
    OMP_THEME="${OMP_THEME:-$(_omp_find_theme "$OMP_THEME_NAME")}"

    if (( $+commands[oh-my-posh] )) \
       && [[ -n "$OMP_THEME" && -r "$OMP_THEME" ]]; then

      eval "$(oh-my-posh init zsh --config "$OMP_THEME")"
    else
      print -P "%F{red}Oh My Posh is not installed or its theme was not found.%f"

      print
      print "Theme name: $OMP_THEME_NAME"
      print "Theme path: ${OMP_THEME:-<not found>}"

      print
      print "Check:"
      print "  command -v oh-my-posh"
      print "  ls -l \"$OMP_THEME\""
    fi
    ;;
esac


# ==============================
# Zsh Autosuggestions
# ==============================

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

if [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
else
  print -P "%F{yellow}zsh-autosuggestions not found%f"
fi


# ==============================
# Zsh Syntax Highlighting
# ==============================

# Keep this plugin at the end of ~/.zshrc.
if [[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
else
  print -P "%F{yellow}zsh-syntax-highlighting not found%f"
fi