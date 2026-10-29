#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

UPDATE_PACKAGES=0
UPDATE_FONTS=0
DRY_RUN=0
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/update.sh [--packages] [--fonts] [--dry-run]

Upgrades what is installed; with neither option, both:
  --packages  every package (paru -Syu; IgnorePkg holds still apply), then the manifest
              packages that are missing
  --fonts     reinstall the Nerd Fonts from their latest release

Each part lists what it would do and asks first; --dry-run only lists. Repository changes
are not pulled here: that is dots sync, which shows and asks.
EOF
}

while (($#)); do
  case "$1" in
    --packages)
      UPDATE_PACKAGES=1
      shift
      ;;
    --fonts)
      UPDATE_FONTS=1
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

if [[ "$UPDATE_PACKAGES" == '0' && "$UPDATE_FONTS" == '0' ]]; then
  UPDATE_PACKAGES=1
  UPDATE_FONTS=1
fi
export DRY_RUN NON_INTERACTIVE

# Lists pending upgrades without touching the system databases (checkupdates syncs a copy)
list_upgrades() {
  if has checkupdates; then
    checkupdates || true
  else
    log_warn 'checkupdates (pacman-contrib) is missing; the list below may be out of date.'
    pacman -Qu || true
  fi
  if has paru; then
    paru -Qua || true
  fi
}

update_packages() {
  local upgrades
  case "$(detect_platform)" in
    arch) ;;
    *)
      log_warn 'Upgrading every package is implemented for Arch-based systems only; use your package manager.'
      return 0
      ;;
  esac

  log_step 'Package upgrades'
  upgrades="$(list_upgrades)"
  if [[ -z "$upgrades" ]]; then
    log_success 'Every package is up to date'
  else
    printf '%s\n' "$upgrades" | sed 's/^/  /'
    if [[ "$DRY_RUN" == '1' ]]; then
      print_command paru -Syu
    elif confirm "Upgrade these $(grep -c . <<<"$upgrades") package(s)?" no; then
      has paru || die 'paru is required to upgrade packages.'
      paru -Syu
    else
      log_warn 'Packages left as they are'
    fi
  fi

  log_step 'Manifest packages (--needed skips the installed ones)'
  "$SCRIPT_DIR/install-packages.sh" --dry-run
  [[ "$DRY_RUN" == '1' ]] && return 0
  if confirm 'Install the manifest packages that are missing?' no; then
    "$SCRIPT_DIR/install-packages.sh"
  fi
}

update_fonts() {
  log_step 'Nerd Fonts'
  "$SCRIPT_DIR/install-fonts.sh" --force --dry-run
  [[ "$DRY_RUN" == '1' ]] && return 0
  if confirm 'Reinstall these fonts from their latest release?' no; then
    "$SCRIPT_DIR/install-fonts.sh" --force
  fi
}

if [[ "$UPDATE_PACKAGES" == '1' ]]; then
  update_packages
fi
if [[ "$UPDATE_FONTS" == '1' ]]; then
  update_fonts
fi
log_success 'Update complete'
