#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
PROMPT=0
FORCE=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/setup-git.sh [options]

Options:
  --name NAME
  --email EMAIL
  --prompt
  --force
  --non-interactive
  --dry-run
EOF
}

while (($#)); do
  case "$1" in
    --name)
      [[ $# -ge 2 ]] || die '--name requires a value'
      GIT_NAME="$2"
      shift 2
      ;;
    --email)
      [[ $# -ge 2 ]] || die '--email requires a value'
      GIT_EMAIL="$2"
      shift 2
      ;;
    --prompt) PROMPT=1; shift ;;
    --force) FORCE=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

export DRY_RUN
has git || die 'git is not installed.'

if [[ "$PROMPT" == '1' && "$NON_INTERACTIVE" == '1' ]]; then
  die '--prompt cannot be used with --non-interactive.'
fi

if [[ "$PROMPT" != '1' ]]; then
  [[ -n "$GIT_NAME" ]] || GIT_NAME="$(chezmoi_value '.git.name')"
  [[ -n "$GIT_EMAIL" ]] || GIT_EMAIL="$(chezmoi_value '.git.email')"
fi

if [[ -z "$GIT_NAME" && "$NON_INTERACTIVE" != '1' ]]; then
  read -r -p 'Git user name: ' GIT_NAME
fi
if [[ -z "$GIT_EMAIL" && "$NON_INTERACTIVE" != '1' ]]; then
  read -r -p 'Git email: ' GIT_EMAIL
fi

existing_name="$(git config --global --get user.name || true)"
existing_email="$(git config --global --get user.email || true)"

if [[ -n "$GIT_NAME" && ( -z "$existing_name" || "$FORCE" == '1' ) ]]; then
  run_or_print git config --global user.name "$GIT_NAME"
elif [[ -n "$existing_name" ]]; then
  log_success "Keeping existing Git user.name: $existing_name"
else
  log_warn 'Git user.name is not configured'
fi

if [[ -n "$GIT_EMAIL" && ( -z "$existing_email" || "$FORCE" == '1' ) ]]; then
  run_or_print git config --global user.email "$GIT_EMAIL"
elif [[ -n "$existing_email" ]]; then
  log_success "Keeping existing Git user.email: $existing_email"
else
  log_warn 'Git user.email is not configured'
fi

run_or_print git config --global init.defaultBranch main
run_or_print git config --global fetch.prune true
run_or_print git config --global rerere.enabled true
run_or_print git config --global push.autoSetupRemote true

if has nvim && ! git config --global --get core.editor >/dev/null; then
  run_or_print git config --global core.editor nvim
fi

log_success 'Git configuration complete'
