#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

UPDATE_PACKAGES=0
UPDATE_FONTS=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/update.sh [--packages] [--fonts] [--dry-run]
EOF
}

while (($#)); do
  case "$1" in
    --packages) UPDATE_PACKAGES=1; shift ;;
    --fonts) UPDATE_FONTS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

export DRY_RUN
has chezmoi || die 'chezmoi is required.'

log_step 'Updating dotfiles repository and target state...'
if [[ "$DRY_RUN" == '1' ]]; then
  print_command chezmoi update --verbose
  chezmoi apply --dry-run --verbose
else
  chezmoi update --verbose
fi
log_success 'Dotfiles update complete'

if [[ "$UPDATE_PACKAGES" == '1' ]]; then
  package_args=()
  [[ "$DRY_RUN" == '1' ]] && package_args+=(--dry-run)
  "$SCRIPT_DIR/install-packages.sh" "${package_args[@]}"
fi

if [[ "$UPDATE_FONTS" == '1' ]]; then
  font_args=(--force)
  [[ "$DRY_RUN" == '1' ]] && font_args+=(--dry-run)
  "$SCRIPT_DIR/install-fonts.sh" "${font_args[@]}"
fi

if [[ "$DRY_RUN" == '0' ]]; then
  chezmoi doctor || log_warn 'chezmoi doctor reported warnings'
fi
