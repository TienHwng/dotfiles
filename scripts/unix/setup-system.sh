#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=0
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
ROOT_CACHE=/var/cache/chezmoi-root

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/setup-system.sh [--dry-run] [--non-interactive]

The Linux system step (L5, sudo), run by `dots system`:
  1. Boot theme packages from pkgbuilds/boot-themes (makepkg as you, pacman -U with sudo)
     when one is missing or older than the PKGBUILD.
  2. The system chezmoi instance (source root/, target /): status and diff, then apply
     after you confirm. Its hooks regenerate grub.cfg and the initramfs when needed.

--dry-run previews both without sudo (a throwaway chezmoi state, so every hook shows as
pending). A real run never happens non-interactively or in CI.
EOF
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
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

ROOT_DIR="$(repo_root)"
SYSTEM_SOURCE="$ROOT_DIR/root"
THEMES_DIR="$ROOT_DIR/pkgbuilds/boot-themes"
SYSTEM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi-root/chezmoi.toml"

# Policy (docs/design.md, L5): / changes only with a person at the keyboard
if [[ "$DRY_RUN" == '0' ]]; then
  [[ "$NON_INTERACTIVE" == '1' ]] && die 'The system step changes / and never runs non-interactively; use --dry-run to preview.'
  [[ -n "${CI:-}" ]] && die 'The system step never runs in CI; use --dry-run to preview.'
fi

# Prints "version" from the PKGBUILD, then one package name per line
theme_packages() {
  # shellcheck disable=SC2154 # pkgver, pkgrel and pkgname come from the PKGBUILD
  (
    # shellcheck source=/dev/null
    source "$THEMES_DIR/PKGBUILD"
    printf '%s-%s\n' "$pkgver" "$pkgrel"
    printf '%s\n' "${pkgname[@]}"
  )
}

install_theme_packages() {
  local wanted current name package
  local -a lines names outdated=() overwrite=()

  if ! has pacman || ! has makepkg; then
    log_warn 'pacman/makepkg not found; the boot theme packages are Arch-only.'
    return 0
  fi

  mapfile -t lines < <(theme_packages)
  wanted="${lines[0]}"
  names=("${lines[@]:1}")
  for name in "${names[@]}"; do
    current="$(pacman -Q "$name" 2>/dev/null | awk '{print $2}' || true)"
    [[ "$current" == "$wanted" ]] && continue
    printf '  %s: %s -> %s\n' "$name" "${current:-<not installed>}" "$wanted"
    outdated+=("$name")
  done

  if ((${#outdated[@]} == 0)); then
    log_success "Boot theme packages are up to date ($wanted)"
    return 0
  fi

  # Before P6 the system instance wrote these themes into /usr; let the packages take them over
  while read -r dir; do
    overwrite+=(--overwrite "/$dir/*")
  done < <(awk '$1 == "_install_theme" { print $3 }' "$THEMES_DIR/PKGBUILD")

  if [[ "$DRY_RUN" == '1' ]]; then
    print_command makepkg --nodeps --clean --cleanbuild
    print_command sudo pacman -U --needed "${overwrite[@]}" "${names[@]/%/-$wanted-any.pkg.tar.zst}"
    return 0
  fi

  local work
  work="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'; trap - RETURN" RETURN
  log_step "Building $wanted boot theme packages"
  (cd "$THEMES_DIR" && BUILDDIR="$work/build" PKGDEST="$work/pkg" makepkg --nodeps --clean --cleanbuild --noconfirm)
  local -a files=()
  for package in "$work"/pkg/*.pkg.tar.*; do
    files+=("$package")
  done
  run_root pacman -U --needed "${overwrite[@]}" "${files[@]}"
  log_success "Installed the boot theme packages ($wanted)"
}

# Preview as this user: the real state file is root's, so a throwaway one stands in
preview_system_instance() {
  local state
  state="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$state'; trap - RETURN" RETURN
  chezmoi --config="$SYSTEM_CONFIG" --source="$SYSTEM_SOURCE" --destination=/ \
    --persistent-state="$state/state.boltdb" --cache="$state/cache" diff --no-pager
  log_warn 'Preview with an empty chezmoi state: hooks show as pending even when they ran before.'
}

apply_system_instance() {
  local chezmoi_bin changes
  local -a root_chezmoi

  [[ -f "$SYSTEM_CONFIG" ]] || die "System instance config missing: $SYSTEM_CONFIG (run the apply step first)."
  chezmoi_bin="$(command -v chezmoi)"
  # Plain sudo: root keeps its own HOME, and its cache lives outside this user's home
  root_chezmoi=("$chezmoi_bin" --config="$SYSTEM_CONFIG" --cache="$ROOT_CACHE" --source="$SYSTEM_SOURCE" --destination=/)

  changes="$(run_root "${root_chezmoi[@]}" status)"
  if [[ -z "$changes" ]]; then
    log_success "/ already matches $SYSTEM_SOURCE"
    return 0
  fi
  printf '%s\n' "$changes"
  run_root "${root_chezmoi[@]}" diff --no-pager
  if confirm 'Apply these changes to / ?' no; then
    run_root "${root_chezmoi[@]}" apply --verbose
    log_success 'System instance applied'
  else
    log_warn 'Nothing applied to /'
  fi

  # Commands run as root can leave root-owned files in the source; hand them back
  if [[ -n "$(find "$SYSTEM_SOURCE" ! -user "$(id -un)" -print -quit 2>/dev/null)" ]]; then
    run_root chown -R "$(id -un):$(id -gn)" "$SYSTEM_SOURCE"
  fi
}

if [[ "$(detect_platform)" == 'windows' || "$(uname -s)" != 'Linux' ]]; then
  log_warn 'The Linux system step only runs on Linux.'
  exit 0
fi

log_step 'Boot theme packages (pkgbuilds/boot-themes)'
install_theme_packages

log_step "System instance ($SYSTEM_SOURCE -> /)"
if ! has chezmoi; then
  [[ "$DRY_RUN" == '1' ]] || die 'chezmoi is required for the system instance.'
  log_warn 'chezmoi is unavailable; the system instance cannot be previewed in this dry-run.'
elif [[ "$DRY_RUN" == '1' ]]; then
  preview_system_instance
else
  apply_system_instance
fi

log_success 'System step complete'
