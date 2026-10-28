#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=0
SHOW_DIFF=0
AUR_HELPER="${AUR_HELPER:-paru}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/install-packages.sh [--dry-run | --diff]

Packages come from the manifest home/.chezmoidata/packages.yaml:
  arch  -> paru (Arch Linux, CachyOS)
  apt   -> apt-get
  brew  -> brew install; brewCask -> brew install --cask

Options:
  --dry-run  print the install commands without running them
  --diff     list installed packages missing from the manifest, and
             manifest packages that are not installed (changes nothing)

Set DOTFILES_HEADLESS=1 to skip GUI entries (WSL, servers).
EOF
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --diff)
      SHOW_DIFF=1
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
PLATFORM="$(detect_platform)"
[[ "$PLATFORM" != 'unknown' ]] || die 'Unsupported Unix package manager.'

if ! has chezmoi; then
  if [[ "$DRY_RUN" == '1' ]]; then
    log_warn 'chezmoi is unavailable; the package manifest cannot be read in this dry-run.'
    exit 0
  fi
  die 'chezmoi is required to read the package manifest (home/.chezmoidata/packages.yaml).'
fi

declare -a PACKAGES=()
declare -a FORMULAE=()
declare -a CASKS=()

# Fill the array named $1 from the manifest list $2
load_manifest_list() {
  local -n target="$1"
  local output

  output="$(manifest_list "$2")" || die "Could not read the '$2' list from the package manifest."
  # shellcheck disable=SC2034 # written through the nameref
  [[ -z "$output" ]] || mapfile -t target <<<"$output"
}

cleanup_paru_build() {
  if [[ -n "${build_dir:-}" && -d "$build_dir" ]]; then
    rm -rf -- "$build_dir"
  fi
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

  if has pacman && pacman -Si paru >/dev/null 2>&1; then
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
  trap cleanup_paru_build EXIT
  trap 'cleanup_paru_build; exit 130' INT TERM
  git clone https://aur.archlinux.org/paru-bin.git "$build_dir/paru-bin" || {
    die 'Could not clone paru-bin from the AUR.'
  }

  (
    cd "$build_dir/paru-bin"
    makepkg -si --needed --noconfirm
  ) || {
    die 'Could not build and install paru-bin.'
  }

  cleanup_paru_build
  build_dir=''
  trap - EXIT INT TERM
  has paru || die 'paru was installed but is not available in PATH.'
}

# Extra = explicitly installed but not in the manifest; missing = in the manifest
# but not installed at all (dependencies count as installed).
show_package_diff() {
  local explicit all manifest extra missing

  case "$PLATFORM" in
    arch)
      require_command pacman 'pacman is required to list installed packages.'
      explicit="$(pacman -Qqe)"
      all="$(pacman -Qq)"
      ;;
    apt)
      require_command apt-mark 'apt-mark is required to list installed packages.'
      explicit="$(apt-mark showmanual)"
      all="$(dpkg-query -W -f '${Package}\n')"
      ;;
    brew)
      require_command brew 'brew is required to list installed packages.'
      explicit="$(
        brew leaves
        brew list --cask
      )"
      all="$(
        brew list --formula
        brew list --cask
      )"
      ;;
  esac

  manifest="$(printf '%s\n' "${PACKAGES[@]}" "${FORMULAE[@]}" "${CASKS[@]}" | sed '/^$/d' | sort -u)"
  extra="$(comm -13 <(printf '%s\n' "$manifest") <(sort -u <<<"$explicit") | sed '/^$/d')"
  missing="$(comm -23 <(printf '%s\n' "$manifest") <(sort -u <<<"$all") | sed '/^$/d')"

  log_step "Explicitly installed but not in the manifest ($(grep -c . <<<"$extra" || true)):"
  [[ -z "$extra" ]] || awk '{ print "  " $0 }' <<<"$extra"
  log_step "In the manifest but not installed ($(grep -c . <<<"$missing" || true)):"
  [[ -z "$missing" ]] || awk '{ print "  " $0 }' <<<"$missing"
}

case "$PLATFORM" in
  arch | apt) load_manifest_list PACKAGES "$PLATFORM" ;;
  brew)
    load_manifest_list FORMULAE brew
    load_manifest_list CASKS brewCask
    ;;
esac

if [[ "$SHOW_DIFF" == '1' ]]; then
  show_package_diff
  exit 0
fi

case "$PLATFORM" in
  arch)
    ((${#PACKAGES[@]})) || {
      log_warn 'No Arch packages configured'
      exit 0
    }
    if ! has pacman; then
      if [[ "$DRY_RUN" == '1' ]]; then
        log_warn 'pacman is unavailable; package operations will only be printed.'
      else
        die 'pacman is required for the Arch package backend.'
      fi
    fi
    [[ "$AUR_HELPER" == 'paru' ]] || die "Unsupported AUR helper: $AUR_HELPER (expected: paru)"
    install_paru
    log_step "Installing ${#PACKAGES[@]} package(s) with $AUR_HELPER..."
    run_or_print "$AUR_HELPER" -S --needed --noconfirm "${PACKAGES[@]}"
    ;;
  apt)
    ((${#PACKAGES[@]})) || {
      log_warn 'No APT packages configured'
      exit 0
    }
    log_step 'Refreshing APT package metadata...'
    run_root_or_print apt-get update
    log_step "Installing ${#PACKAGES[@]} package(s) with APT..."
    run_root_or_print apt-get install -y "${PACKAGES[@]}"
    ;;
  brew)
    if ! has brew; then
      log_step 'Installing Homebrew...'
      if [[ "$DRY_RUN" == '1' ]]; then
        # shellcheck disable=SC2016
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
