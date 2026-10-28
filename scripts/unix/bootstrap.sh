#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
  # shellcheck source=scripts/unix/lib/common.sh
  source "$SCRIPT_DIR/lib/common.sh"
else
  # Downloaded on its own to a fresh machine: the few helpers needed before the
  # clone. The steps after the clone run from the repository's own scripts.
  log_step() { printf '→ %s\n' "$*"; }
  log_success() { printf '✔ %s\n' "$*"; }
  log_warn() { printf '! %s\n' "$*" >&2; }
  die() {
    printf '✘ %s\n' "$*" >&2
    exit 1
  }
  has() { command -v "$1" >/dev/null 2>&1; }
  require_command() { has "$1" || die "${2:-$1 is required.}"; }
  print_command() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  }
  run_root_or_print() {
    if [[ "${DRY_RUN:-0}" == '1' ]]; then
      print_command sudo "$@"
    elif [[ "$(id -u)" -eq 0 ]]; then
      "$@"
    elif [[ "${NON_INTERACTIVE:-0}" == '1' ]]; then
      sudo -n "$@"
    else
      sudo "$@"
    fi
  }
  detect_platform() {
    if [[ -n "${DOTFILES_PLATFORM:-}" ]]; then
      printf '%s\n' "$DOTFILES_PLATFORM"
    elif [[ "$(uname -s)" == 'Darwin' ]]; then
      printf 'brew\n'
    elif [[ -f /etc/arch-release ]] || has pacman; then
      printf 'arch\n'
    elif has apt-get; then
      printf 'apt\n'
    else
      printf 'unknown\n'
    fi
  }
fi

DOTFILES_REPO="${DOTFILES_REPO:-}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-}"
CHEZMOI_BIN_DIR="${CHEZMOI_BIN_DIR:-$HOME/.local/bin}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
PROMPT_PERSONAL=0
DRY_RUN=0
SKIP_PACKAGES=0
SKIP_FONTS=0
SKIP_GIT=0
SKIP_ACCOUNTS=0
SKIP_SHELL=0
SKIP_APPLY=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/bootstrap.sh [options]

Installs the prerequisites and chezmoi, initializes this repository as the
chezmoi source, then runs `dots bootstrap`, which previews each step and asks
before running it (unless --non-interactive).

Options:
  --repo VALUE
  --branch NAME
  --chezmoi-bin-dir PATH
  --prompt-personal
  --non-interactive
  --dry-run
  --skip-packages
  --skip-fonts
  --skip-git
  --skip-accounts
  --skip-shell
  --skip-apply
EOF
}

normalize_repo() {
  local value="$1"

  case "$value" in
    *://* | git@* | /* | ./* | ../*)
      printf '%s\n' "$value"
      ;;
    */*)
      printf 'https://github.com/%s.git\n' "${value%.git}"
      ;;
    *)
      printf 'https://github.com/%s/dotfiles.git\n' "$value"
      ;;
  esac
}

install_chezmoi() {
  if has chezmoi; then
    log_success "chezmoi is already installed: $(command -v chezmoi)"
    return
  fi

  log_step "Installing chezmoi into $CHEZMOI_BIN_DIR..."

  if [[ "$DRY_RUN" == '1' ]]; then
    print_command mkdir -p "$CHEZMOI_BIN_DIR"
    printf '%s\n' "+ download and run the official chezmoi installer into $CHEZMOI_BIN_DIR"
    log_warn 'chezmoi is unavailable; template rendering and apply cannot be validated in this dry-run.'
    return
  fi

  mkdir -p "$CHEZMOI_BIN_DIR"

  if has curl; then
    sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$CHEZMOI_BIN_DIR"
  elif has wget; then
    sh -c "$(wget -qO- https://get.chezmoi.io)" -- -b "$CHEZMOI_BIN_DIR"
  else
    die 'curl or wget is required to install chezmoi.'
  fi

  export PATH="$CHEZMOI_BIN_DIR:$PATH"
  has chezmoi || die "chezmoi was installed but is not available in PATH: $CHEZMOI_BIN_DIR"
  log_success 'chezmoi installed'
}

ensure_bootstrap_prerequisites() {
  local platform="$1"
  local -a missing=()

  case "$platform" in
    arch)
      if ! has pacman; then
        if [[ "$DRY_RUN" == '1' ]]; then
          log_warn 'pacman is unavailable; Arch prerequisite commands will only be printed.'
        else
          die 'pacman is required on Arch Linux and CachyOS.'
        fi
      fi
      [[ "$DRY_RUN" == '1' || "$(id -u)" -ne 0 ]] \
        || die 'Run bootstrap as a regular user. Privileged package operations use sudo or doas.'

      has git || missing+=(git)
      if ! has curl && ! has wget; then
        missing+=(curl)
      fi
      has unzip || missing+=(unzip)

      if ((${#missing[@]})); then
        log_step "Installing bootstrap prerequisites: ${missing[*]}"
        run_root_or_print pacman -S --needed --noconfirm "${missing[@]}"
      fi
      ;;
    apt | brew)
      require_command git 'git is required before bootstrap on this non-primary platform.'
      if ! has curl && ! has wget; then
        die 'curl or wget is required before bootstrap on this non-primary platform.'
      fi
      ;;
    *)
      die 'Unsupported platform. Phase 1 supports Arch Linux and CachyOS; other detected backends are best-effort.'
      ;;
  esac
}

find_repo_root() {
  local current="$1" depth=0

  while [[ "$current" != '/' && $depth -lt 8 ]]; do
    if [[ -f "$current/scripts/unix/bootstrap.sh" && -f "$current/scripts/windows/bootstrap.ps1" ]]; then
      printf '%s\n' "$current"
      return 0
    fi
    current="$(dirname "$current")"
    depth=$((depth + 1))
  done

  return 1
}

resolve_source_repo_root() {
  local source_path=''

  has chezmoi || return 1
  source_path="$(chezmoi source-path 2>/dev/null || true)"
  [[ -n "$source_path" ]] || return 1

  find_repo_root "$source_path"
}

main() {

  while (($#)); do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || die '--repo requires a value'
        DOTFILES_REPO="$2"
        shift 2
        ;;
      --branch)
        [[ $# -ge 2 ]] || die '--branch requires a value'
        DOTFILES_BRANCH="$2"
        shift 2
        ;;
      --chezmoi-bin-dir)
        [[ $# -ge 2 ]] || die '--chezmoi-bin-dir requires a value'
        CHEZMOI_BIN_DIR="$2"
        shift 2
        ;;
      --prompt-personal)
        PROMPT_PERSONAL=1
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
      --skip-packages)
        SKIP_PACKAGES=1
        shift
        ;;
      --skip-fonts)
        SKIP_FONTS=1
        shift
        ;;
      --skip-git)
        SKIP_GIT=1
        shift
        ;;
      --skip-accounts)
        SKIP_ACCOUNTS=1
        shift
        ;;
      --skip-shell)
        SKIP_SHELL=1
        shift
        ;;
      --skip-apply)
        SKIP_APPLY=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  if [[ "$PROMPT_PERSONAL" == '1' && "$NON_INTERACTIVE" == '1' ]]; then
    die '--prompt-personal cannot be used with --non-interactive.'
  fi

  export NON_INTERACTIVE DRY_RUN

  platform="$(detect_platform)"
  ensure_bootstrap_prerequisites "$platform"
  install_chezmoi

  repo_root="$(resolve_source_repo_root || true)"
  should_init='0'
  [[ -z "$repo_root" ]] && should_init='1'
  [[ -n "$DOTFILES_REPO" || -n "$DOTFILES_BRANCH" ]] && should_init='1'

  if [[ "$should_init" == '1' ]]; then
    if [[ -z "$DOTFILES_REPO" ]]; then
      DOTFILES_REPO='https://github.com/TienHwng/dotfiles.git'
    fi

    DOTFILES_REPO="$(normalize_repo "$DOTFILES_REPO")"

    log_step "Initializing dotfiles from $DOTFILES_REPO..."
    init_args=(init)
    [[ -n "$DOTFILES_BRANCH" ]] && init_args+=(--branch "$DOTFILES_BRANCH")
    [[ "$NON_INTERACTIVE" == '1' ]] && init_args+=(--promptDefaults)
    [[ "$PROMPT_PERSONAL" == '1' ]] && init_args+=(--prompt)
    init_args+=("$DOTFILES_REPO")

    if [[ "$DRY_RUN" == '1' ]]; then
      print_command chezmoi "${init_args[@]}"
      repo_root="$(find_repo_root "$(cd -- "$SCRIPT_DIR/../.." && pwd)" || true)"
      [[ -n "$repo_root" ]] || die 'Dry-run requires an existing local repository checkout.'
      log_warn 'Repository initialization was not executed; continuing against the local checkout.'
    else
      chezmoi "${init_args[@]}"
      log_success 'Dotfiles source initialized'

      repo_root="$(resolve_source_repo_root || true)"
      [[ -n "$repo_root" ]] || die 'Could not locate repository root from chezmoi source path.'
    fi
  else
    log_success "Using existing chezmoi source: $repo_root"

    if [[ "$PROMPT_PERSONAL" == '1' ]]; then
      if [[ "$DRY_RUN" == '1' ]]; then
        print_command chezmoi init --prompt
      else
        chezmoi init --prompt
      fi
    fi
  fi

  active_script_dir="$repo_root/scripts/unix"
  [[ -d "$active_script_dir" ]] || die "Bootstrap script directory not found: $active_script_dir"

  log_step "Platform: $platform"

  # The steps themselves (packages, git, fonts, shell, apply, accounts) live in dots
  dots_args=(bootstrap)
  [[ "$DRY_RUN" == '1' ]] && dots_args+=(--dry-run)
  [[ "$NON_INTERACTIVE" == '1' ]] && dots_args+=(--non-interactive)
  [[ "$SKIP_PACKAGES" == '1' ]] && dots_args+=(--skip packages)
  [[ "$SKIP_GIT" == '1' ]] && dots_args+=(--skip git)
  [[ "$SKIP_ACCOUNTS" == '1' ]] && dots_args+=(--skip accounts)
  [[ "$SKIP_FONTS" == '1' ]] && dots_args+=(--skip fonts)
  [[ "$SKIP_SHELL" == '1' ]] && dots_args+=(--skip shell)
  [[ "$SKIP_APPLY" == '1' ]] && dots_args+=(--skip apply)
  "$active_script_dir/dots" "${dots_args[@]}"

  log_success 'Unix bootstrap complete'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
