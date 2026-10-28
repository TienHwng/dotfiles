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
    --prompt)
      PROMPT=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

export DRY_RUN
if ! has git; then
  if [[ "$DRY_RUN" == '1' ]]; then
    log_warn 'git is unavailable; dry-run can only validate chezmoi data ownership.'
  else
    die 'git is not installed.'
  fi
fi

if [[ "$PROMPT" == '1' && "$NON_INTERACTIVE" == '1' ]]; then
  die '--prompt cannot be used with --non-interactive.'
fi

configured_name="$(chezmoi_value '.gitName')"
configured_email="$(chezmoi_value '.gitEmail')"

if [[ "$PROMPT" == '1' || ("$NON_INTERACTIVE" != '1' && (-z "$configured_name" || -z "$configured_email")) ]]; then
  if [[ "$DRY_RUN" == '1' ]]; then
    print_command chezmoi init --prompt
    log_warn 'Git identity prompts were not executed during dry-run.'
  else
    require_command chezmoi 'chezmoi is required to store machine-specific Git data.'
    chezmoi init --prompt
    configured_name="$(chezmoi_value '.gitName')"
    configured_email="$(chezmoi_value '.gitEmail')"
  fi
fi

if [[ -n "$GIT_NAME" && "$GIT_NAME" != "$configured_name" ]] \
  || [[ -n "$GIT_EMAIL" && "$GIT_EMAIL" != "$configured_email" ]] \
  || [[ "$FORCE" == '1' ]]; then
  log_warn 'Direct Git writes are disabled. Re-run chezmoi init --prompt to change machine data.'
fi

if [[ -z "$configured_name" || -z "$configured_email" ]]; then
  if [[ "$DRY_RUN" == '1' ]]; then
    log_warn 'Git identity is incomplete; a real non-interactive bootstrap would stop before apply.'
  else
    die 'Git identity is incomplete. Run chezmoi init --prompt or populate data.gitName and data.gitEmail.'
  fi
fi

log_success 'Git configuration is owned by home/dot_gitconfig.tmpl'
