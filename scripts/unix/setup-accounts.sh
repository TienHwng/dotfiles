#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

GITHUB_USERNAME="${GITHUB_USERNAME:-}"
SSH_KEY_EMAIL="${SSH_KEY_EMAIL:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
PROMPT=0
FORCE=0
DRY_RUN=0
ALLOW_UNENCRYPTED_KEY=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/setup-accounts.sh [options]

Options:
  --github-user USERNAME
  --ssh-email EMAIL
  --ssh-key-path PATH
  --ssh-key-type TYPE
  --prompt
  --force
  --allow-unencrypted-key
  --non-interactive
  --dry-run
EOF
}

while (($#)); do
  case "$1" in
    --github-user)
      [[ $# -ge 2 ]] || die '--github-user requires a value'
      GITHUB_USERNAME="$2"
      shift 2
      ;;
    --ssh-email)
      [[ $# -ge 2 ]] || die '--ssh-email requires a value'
      SSH_KEY_EMAIL="$2"
      shift 2
      ;;
    --ssh-key-path)
      [[ $# -ge 2 ]] || die '--ssh-key-path requires a value'
      SSH_KEY_PATH="$2"
      shift 2
      ;;
    --ssh-key-type)
      [[ $# -ge 2 ]] || die '--ssh-key-type requires a value'
      SSH_KEY_TYPE="$2"
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
    --allow-unencrypted-key)
      ALLOW_UNENCRYPTED_KEY=1
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

export DRY_RUN NON_INTERACTIVE

if [[ "$PROMPT" == '1' && "$NON_INTERACTIVE" == '1' ]]; then
  die '--prompt cannot be used with --non-interactive.'
fi

platform="$(detect_platform)"

if [[ "$PROMPT" != '1' ]]; then
  [[ -n "$GITHUB_USERNAME" ]] || GITHUB_USERNAME="$(chezmoi_value '.githubUsername')"
  [[ -n "$SSH_KEY_EMAIL" ]] || SSH_KEY_EMAIL="$(chezmoi_value '.sshEmail')"
fi

if [[ -z "$SSH_KEY_PATH" ]]; then
  if [[ "$platform" == 'arch' ]]; then
    SSH_KEY_PATH="$(chezmoi_value '.accounts.ssh.keyPathArch' "$HOME/.ssh/id_ed25519")"
  else
    SSH_KEY_PATH="$(chezmoi_value '.accounts.ssh.keyPathUnix' "$HOME/.ssh/id_ed25519")"
  fi
fi

[[ -n "$SSH_KEY_TYPE" ]] || SSH_KEY_TYPE="$(chezmoi_value '.accounts.ssh.keyType' 'ed25519')"

if [[ -z "$SSH_KEY_EMAIL" ]] && has git; then
  SSH_KEY_EMAIL="$(git config --global --get user.email 2>/dev/null || true)"
fi

if [[ "$PROMPT" == '1' || (-z "$SSH_KEY_EMAIL" && "$NON_INTERACTIVE" != '1') ]]; then
  if [[ "$DRY_RUN" == '1' ]]; then
    print_command chezmoi init --prompt
    log_warn 'Account prompts were not executed during dry-run.'
  else
    require_command chezmoi 'chezmoi is required to store machine-specific account data.'
    chezmoi init --prompt
    [[ -n "$GITHUB_USERNAME" ]] || GITHUB_USERNAME="$(chezmoi_value '.githubUsername')"
    SSH_KEY_EMAIL="$(chezmoi_value '.sshEmail')"
  fi
fi

if [[ "$SSH_KEY_PATH" == ~* ]]; then
  SSH_KEY_PATH="$HOME${SSH_KEY_PATH#\~}"
fi

[[ -n "$SSH_KEY_PATH" ]] || die 'SSH key path cannot be empty.'
if [[ -z "$SSH_KEY_EMAIL" ]]; then
  if [[ "$DRY_RUN" == '1' ]]; then
    log_warn 'SSH key email is missing; a real run would stop before key generation.'
  else
    die 'SSH key email cannot be empty. Run chezmoi init --prompt or provide --ssh-email.'
  fi
fi

if ! has ssh-keygen; then
  if [[ "$DRY_RUN" == '1' ]]; then
    log_warn 'ssh-keygen is unavailable; printing the intended operation only.'
  else
    die 'ssh-keygen is required to manage SSH keys.'
  fi
fi

if [[ (! -f "$SSH_KEY_PATH" || "$FORCE" == '1') && "$NON_INTERACTIVE" == '1' && "$ALLOW_UNENCRYPTED_KEY" != '1' ]]; then
  if [[ "$DRY_RUN" == '1' ]]; then
    log_warn 'Non-interactive key generation requires --allow-unencrypted-key; no key would be created.'
  else
    die 'Refusing to create an unencrypted SSH key non-interactively. Pre-create a protected key, use --skip-accounts, or explicitly pass --allow-unencrypted-key.'
  fi
fi

ssh_dir="$(dirname "$SSH_KEY_PATH")"
run_or_print mkdir -p "$ssh_dir"
run_or_print chmod 700 "$ssh_dir"

if [[ -f "$SSH_KEY_PATH" && "$FORCE" == '1' ]]; then
  backup_path="$SSH_KEY_PATH.bak.$(date +%Y%m%d%H%M%S)"
  log_warn "Existing SSH key found, backing up to $backup_path"
  run_or_print mv "$SSH_KEY_PATH" "$backup_path"
  [[ -f "$SSH_KEY_PATH.pub" ]] && run_or_print mv "$SSH_KEY_PATH.pub" "$backup_path.pub"
fi

if [[ ! -f "$SSH_KEY_PATH" ]]; then
  log_step "Generating SSH key: $SSH_KEY_PATH"
  ssh_keygen_args=(-t "$SSH_KEY_TYPE" -C "$SSH_KEY_EMAIL" -f "$SSH_KEY_PATH")
  [[ "$ALLOW_UNENCRYPTED_KEY" == '1' ]] && ssh_keygen_args+=(-N '')
  run_or_print ssh-keygen "${ssh_keygen_args[@]}"
else
  log_success "Keeping existing SSH key: $SSH_KEY_PATH"
fi

log_success 'SSH host configuration is owned by home/dot_ssh/private_config.tmpl'

if has gh; then
  if [[ "$DRY_RUN" == '1' ]]; then
    log_step 'Would check GitHub CLI authentication status'
  elif gh auth status >/dev/null 2>&1; then
    log_success 'GitHub CLI authentication already configured'
  else
    log_warn 'GitHub CLI is installed but not authenticated. Run: gh auth login --git-protocol ssh --web'
  fi
else
  log_warn 'GitHub CLI (gh) not found; skipping GitHub authentication check'
fi

if [[ -f "$SSH_KEY_PATH.pub" && "$DRY_RUN" == '0' ]]; then
  log_step 'Add this SSH public key to GitHub > Settings > SSH and GPG keys:'
  cat "$SSH_KEY_PATH.pub"
fi

log_success 'Account onboarding complete'
