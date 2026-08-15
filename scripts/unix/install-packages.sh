#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ROOT_DIR="$(repo_root)"
DRY_RUN=0
AUR_HELPER="${AUR_HELPER:-paru}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/install-packages.sh [--dry-run]

Package files:
  packages/arch.txt
  packages/apt.txt
  packages/fedora.txt
  packages/brew.txt

Homebrew GUI packages use the prefix: cask:
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

export DRY_RUN
PLATFORM="$(detect_platform)"
[[ "$PLATFORM" != 'unknown' ]] || die 'Unsupported Unix package manager.'
PACKAGE_FILE="$ROOT_DIR/packages/$PLATFORM.txt"
[[ -f "$PACKAGE_FILE" ]] || die "Package list does not exist: $PACKAGE_FILE"

declare -a PACKAGES=()
declare -a FORMULAE=()
declare -a CASKS=()

after_contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

install_paru() {
  local build_dir

  if [[ "$DRY_RUN" == '0' && "$(id -u)" -eq 0 ]]; then
    die 'Run this script as a regular user; paru does not support running as root.'
  fi

  if has paru; then
    log_step "Using paru: $(command -v paru)"
    return
  fi

  log_step 'Installing paru...'

  if pacman -Si paru >/dev/null 2>&1; then
    run_root_or_print pacman -S --needed --noconfirm paru
    return
  fi

  if [[ "$DRY_RUN" == '1' ]]; then
    run_root_or_print pacman -S --needed --noconfirm base-devel git
    printf '%s\n' '+ git clone https://aur.archlinux.org/paru-bin.git <temporary-directory>/paru-bin'
    printf '%s\n' '+ cd <temporary-directory>/paru-bin && makepkg -si --needed --noconfirm'
    return
  fi

  run_root pacman -S --needed --noconfirm base-devel git

  build_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-paru.XXXXXX")"
  git clone https://aur.archlinux.org/paru-bin.git "$build_dir/paru-bin" || {
    rm -rf -- "$build_dir"
    die 'Could not clone paru-bin from the AUR.'
  }

  (
    cd "$build_dir/paru-bin"
    makepkg -si --needed --noconfirm
  ) || {
    rm -rf -- "$build_dir"
    die 'Could not build and install paru-bin.'
  }

  rm -rf -- "$build_dir"
  has paru || die 'paru was installed but is not available in PATH.'
}

while IFS= read -r package; do
  if [[ "$PLATFORM" == 'brew' && "$package" == cask:* ]]; then
    package="${package#cask:}"
    after_contains "$package" "${CASKS[@]:-}" || CASKS+=("$package")
  elif [[ "$PLATFORM" == 'brew' ]]; then
    after_contains "$package" "${FORMULAE[@]:-}" || FORMULAE+=("$package")
  else
    after_contains "$package" "${PACKAGES[@]:-}" || PACKAGES+=("$package")
  fi
done < <(read_list_file "$PACKAGE_FILE")

case "$PLATFORM" in
  arch)
    ((${#PACKAGES[@]})) || { log_warn 'No Arch packages configured'; exit 0; }
    [[ "$AUR_HELPER" == 'paru' ]] || die "Unsupported AUR helper: $AUR_HELPER (expected: paru)"
    install_paru
    log_step "Installing ${#PACKAGES[@]} package(s) with $AUR_HELPER..."
    run_or_print "$AUR_HELPER" -S --needed --noconfirm "${PACKAGES[@]}"
    ;;
  apt)
    ((${#PACKAGES[@]})) || { log_warn 'No APT packages configured'; exit 0; }
    log_step 'Refreshing APT package metadata...'
    run_root_or_print apt-get update
    log_step "Installing ${#PACKAGES[@]} package(s) with APT..."
    run_root_or_print apt-get install -y "${PACKAGES[@]}"
    ;;
  fedora)
    ((${#PACKAGES[@]})) || { log_warn 'No Fedora packages configured'; exit 0; }
    log_step "Installing ${#PACKAGES[@]} package(s) with DNF..."
    run_root_or_print dnf install -y "${PACKAGES[@]}"
    ;;
  brew)
    if ! has brew; then
      log_step 'Installing Homebrew...'
      if [[ "$DRY_RUN" == '1' ]]; then
        printf '%s\n' '+ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      else
        has curl || die 'curl is required to install Homebrew.'
        NONINTERACTIVE="${NON_INTERACTIVE:-0}" \
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        if [[ -x /opt/homebrew/bin/brew ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
          eval "$(/usr/local/bin/brew shellenv)"
        fi
      fi
    fi

    if ((${#FORMULAE[@]})); then
      log_step "Installing ${#FORMULAE[@]} Homebrew formula(e)..."
      run_or_print brew install "${FORMULAE[@]}"
    fi
    if ((${#CASKS[@]})); then
      log_step "Installing ${#CASKS[@]} Homebrew cask(s)..."
      run_or_print brew install --cask "${CASKS[@]}"
    fi
    ;;
esac

log_success 'Package installation complete'
