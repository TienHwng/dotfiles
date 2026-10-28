#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SSH_AGENT="${SSH_AGENT:-}"
SSH_KEY_EMAIL="${SSH_KEY_EMAIL:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-}"
BITWARDEN_SSH_AUTH_SOCK="${BITWARDEN_SSH_AUTH_SOCK:-$HOME/.bitwarden-ssh-agent.sock}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
PROMPT=0
FORCE=0
DRY_RUN=0
ALLOW_UNENCRYPTED_KEY=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/setup-accounts.sh [options]

Logs in to GitHub with gh (HTTPS; the git template already makes gh the
credential helper), then checks the SSH key:
  bitwarden  the Bitwarden desktop SSH agent holds a key that GitHub accepts
  file       a passphrase-protected key file exists (created if missing)
The mode comes from .accounts.ssh.agent in chezmoi data.

Options:
  --ssh-agent bitwarden|file
  --ssh-email EMAIL          (file mode)
  --ssh-key-path PATH        (file mode)
  --ssh-key-type TYPE        (file mode)
  --prompt
  --force                    (file mode: replace the key, keeping a backup)
  --allow-unencrypted-key    (file mode: allow a key without passphrase when non-interactive)
  --non-interactive
  --dry-run
EOF
}

while (($#)); do
  case "$1" in
    --ssh-agent)
      [[ $# -ge 2 ]] || die '--ssh-agent requires a value'
      SSH_AGENT="$2"
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

[[ -n "$SSH_AGENT" ]] || SSH_AGENT="$(chezmoi_value '.accounts.ssh.agent' 'bitwarden')"
case "$SSH_AGENT" in
  bitwarden | file) ;;
  *) die "Unknown SSH agent mode: $SSH_AGENT (expected bitwarden or file)" ;;
esac

# GitHub over HTTPS through gh. The git template renders gh as the credential
# helper, so gh auth login does not offer to edit ~/.gitconfig (never run gh auth setup-git).
github_login() {
  if ! has gh; then
    log_warn 'GitHub CLI (gh) not found; install it with the packages step.'
    return 0
  fi
  if [[ "$DRY_RUN" == '1' ]]; then
    log_step 'Would check gh auth status and, if logged out, run:'
    print_command gh auth login --hostname github.com --git-protocol https --web
    return 0
  fi
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    log_success 'GitHub CLI is logged in'
    return 0
  fi
  if [[ "$NON_INTERACTIVE" == '1' ]]; then
    log_warn 'GitHub CLI is not logged in. Run: gh auth login --hostname github.com --git-protocol https --web'
    return 0
  fi

  if ! git config --get-all 'credential.https://github.com.helper' 2>/dev/null | grep -q 'auth git-credential'; then
    log_warn "If gh asks 'Authenticate Git with your GitHub credentials?', answer No: home/dot_gitconfig.tmpl owns ~/.gitconfig. Run the apply step first to avoid the question."
  fi
  gh auth login --hostname github.com --git-protocol https --web
}

print_bitwarden_agent_help() {
  log_step 'Set up the Bitwarden SSH agent:'
  printf '  %s\n' \
    'Open Bitwarden desktop (native package, not Flatpak) and unlock the vault' \
    'Settings > Enable SSH agent' \
    'Create the key in the vault: New > SSH key (generate ed25519), then save'
}

# Prints the agent's public keys; returns 1 when the agent is not reachable
bitwarden_agent_keys() {
  local status=0 keys=''

  keys="$(SSH_AUTH_SOCK="$BITWARDEN_SSH_AUTH_SOCK" ssh-add -L 2>/dev/null)" || status=$?
  # ssh-add -L: 0 = keys listed, 1 = agent has no identities, 2 = no agent
  ((status == 2)) && return 1
  ((status == 0)) && printf '%s\n' "$keys"
  return 0
}

# Waits for the person to fix the agent (interactive) or fails (non-interactive)
retry_or_die() {
  local message="$1"

  [[ "$NON_INTERACTIVE" == '1' ]] && die "$message"
  confirm "$message Retry now?" yes || die "$message"
}

github_accepts_ssh() {
  local output=''

  output="$(SSH_AUTH_SOCK="$BITWARDEN_SSH_AUTH_SOCK" ssh -T -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new -o IdentityAgent="$BITWARDEN_SSH_AUTH_SOCK" \
    git@github.com 2>&1 || true)"
  [[ "$output" == *'successfully authenticated'* ]]
}

upload_ssh_key() {
  local public_key="$1" key_file=''

  if ! has gh || [[ "$NON_INTERACTIVE" == '1' ]]; then
    log_warn 'Add this public key at https://github.com/settings/ssh/new:'
    printf '%s\n' "$public_key"
    return 0
  fi
  confirm 'Add this key to your GitHub account with gh?' yes || {
    printf '%s\n' "$public_key"
    return 0
  }

  key_file="$(mktemp "${TMPDIR:-/tmp}/dotfiles-ssh-key.XXXXXX")"
  printf '%s\n' "$public_key" >"$key_file"
  if ! gh ssh-key add "$key_file" --title "$(uname -n) (Bitwarden)"; then
    log_warn 'gh needs the admin:public_key scope: gh auth refresh -h github.com -s admin:public_key'
  fi
  rm -f -- "$key_file"
}

setup_bitwarden_ssh() {
  local keys='' count=0

  if ! has ssh-add; then
    [[ "$DRY_RUN" == '1' ]] || die 'ssh-add is required (package openssh).'
    log_warn 'ssh-add is unavailable; the Bitwarden agent check was not executed.'
    return 0
  fi

  if [[ "$DRY_RUN" == '1' ]]; then
    if keys="$(bitwarden_agent_keys)"; then
      count="$(grep -c . <<<"$keys" || true)"
      log_success "Bitwarden SSH agent at $BITWARDEN_SSH_AUTH_SOCK holds $count key(s)"
    else
      log_warn "Bitwarden SSH agent is not reachable at $BITWARDEN_SSH_AUTH_SOCK; a real run would stop here."
    fi
    log_step 'Would check that GitHub accepts the key: ssh -T git@github.com'
    return 0
  fi

  until keys="$(bitwarden_agent_keys)"; do
    print_bitwarden_agent_help
    retry_or_die "The Bitwarden SSH agent is not reachable at $BITWARDEN_SSH_AUTH_SOCK."
  done
  while [[ -z "$keys" ]]; do
    print_bitwarden_agent_help
    retry_or_die 'The Bitwarden SSH agent holds no keys (is the vault unlocked?).'
    keys="$(bitwarden_agent_keys || true)"
  done
  count="$(grep -c . <<<"$keys")"
  log_success "Bitwarden SSH agent holds $count key(s)"

  if github_accepts_ssh; then
    log_success 'GitHub accepts the SSH key (ssh -T git@github.com)'
    return 0
  fi
  if ((count == 1)); then
    log_warn 'GitHub does not know this key yet.'
    upload_ssh_key "$keys"
  else
    log_warn 'GitHub accepts none of the agent keys. Add one at https://github.com/settings/ssh/new:'
    printf '%s\n' "$keys"
  fi
}

# Headless machines without Bitwarden: a passphrase-protected key file
setup_key_file() {
  local platform ssh_dir backup_path
  local -a ssh_keygen_args

  platform="$(detect_platform)"

  if [[ "$PROMPT" != '1' ]]; then
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
      die 'Refusing to create an unencrypted SSH key non-interactively. Pre-create a protected key, use --skip accounts, or explicitly pass --allow-unencrypted-key.'
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

  if [[ -f "$SSH_KEY_PATH.pub" && "$DRY_RUN" == '0' ]]; then
    log_step 'Add this SSH public key to GitHub > Settings > SSH and GPG keys:'
    cat "$SSH_KEY_PATH.pub"
  fi
}

# Templates do not read Bitwarden secrets yet; report the CLI state for when they do
bitwarden_cli_status() {
  local status=''

  if ! has bw; then
    log_warn 'Bitwarden CLI (bw) not found; templates cannot read Bitwarden secrets on this machine.'
    return 0
  fi
  status="$(bw status 2>/dev/null | grep -o '"status":"[a-z]*"' | cut -d'"' -f4 || true)"
  case "$status" in
    locked | unlocked) log_success "Bitwarden CLI is logged in ($status)" ;;
    unauthenticated) log_warn 'Bitwarden CLI is not logged in. Run bw login before templates use Bitwarden secrets.' ;;
    *) log_warn 'Could not read the Bitwarden CLI status (bw status).' ;;
  esac
}

github_login
case "$SSH_AGENT" in
  bitwarden) setup_bitwarden_ssh ;;
  file) setup_key_file ;;
esac
bitwarden_cli_status

log_success 'SSH host configuration is owned by home/dot_ssh/private_config.tmpl'
log_success 'Account onboarding complete'
