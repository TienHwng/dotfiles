#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SHELL_NAME="${DOTFILES_SHELL:-zsh}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/setup-shell.sh [bash|zsh|fish] [--non-interactive] [--dry-run]
EOF
}

while (($#)); do
  case "$1" in
    bash|zsh|fish) SHELL_NAME="$1"; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unsupported option or shell: $1" ;;
  esac
done

export DRY_RUN
has "$SHELL_NAME" || die "$SHELL_NAME is not installed."
shell_path="$(command -v "$SHELL_NAME")"
current_shell="${SHELL:-}"

if [[ "$current_shell" == "$shell_path" ]]; then
  log_success "$SHELL_NAME is already the current login shell"
  exit 0
fi

if [[ -f /etc/shells ]] && ! grep -Fxq "$shell_path" /etc/shells; then
  log_step "Adding $shell_path to /etc/shells..."
  if [[ "$DRY_RUN" == '1' ]]; then
    print_command sh -c "printf '%s\\n' '$shell_path' >> /etc/shells"
  else
    printf '%s\n' "$shell_path" | run_root tee -a /etc/shells >/dev/null
  fi
fi

if ! has chsh; then
  log_warn "chsh is unavailable. Set the login shell manually to: $shell_path"
  exit 0
fi

log_step "Changing login shell to $shell_path..."
if [[ "$DRY_RUN" == '1' ]]; then
  print_command chsh -s "$shell_path"
  exit 0
fi

if ! chsh -s "$shell_path"; then
  log_warn 'Could not change the login shell automatically.'
  log_warn "Run manually: chsh -s $shell_path"
  exit 0
fi

log_success "Login shell set to $SHELL_NAME; restart the session to use it"
