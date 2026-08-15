#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=0
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
ASSUME_YES=0
CHEZMOI_BIN_DIR="${CHEZMOI_BIN_DIR:-$HOME/.local/bin}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/cleanup.sh [--dry-run] [--yes]

Cleans package-manager caches, chezmoi's cache, and the chezmoi binary installed
in CHEZMOI_BIN_DIR (default: ~/.local/bin). It does not remove the source
repository or the chezmoi configuration file.
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

export DRY_RUN NON_INTERACTIVE
if [[ "$ASSUME_YES" != '1' ]]; then
  confirm 'Clean caches and remove the locally installed chezmoi binary?' no || {
    log_warn 'Cleanup cancelled'
    exit 0
  }
fi

case "$(detect_platform)" in
  arch)
    run_root_or_print pacman -Sc --noconfirm
    ;;
  apt)
    run_root_or_print apt-get autoremove -y
    run_root_or_print apt-get autoclean
    ;;
  fedora)
    run_root_or_print dnf autoremove -y
    run_root_or_print dnf clean all
    ;;
  brew)
    has brew && run_or_print brew cleanup
    ;;
  *)
    log_warn 'No package cache cleanup is configured for this platform'
    ;;
esac

cache_dir="$(chezmoi_value '.chezmoi.cacheDir' "${XDG_CACHE_HOME:-$HOME/.cache}/chezmoi")"
if [[ -d "$cache_dir" ]]; then
  run_or_print rm -rf "$cache_dir"
fi

chezmoi_binary="$CHEZMOI_BIN_DIR/chezmoi"
if [[ -f "$chezmoi_binary" || -L "$chezmoi_binary" ]]; then
  log_step "Removing locally installed chezmoi binary: $chezmoi_binary"
  run_or_print rm -f -- "$chezmoi_binary"
else
  log_warn "No locally installed chezmoi binary found at: $chezmoi_binary"
fi

log_success 'Cleanup complete'
