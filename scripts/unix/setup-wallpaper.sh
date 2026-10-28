#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/setup-wallpaper.sh [--dry-run]

Fetches the wallpaper repository (chezmoi external, private Git LFS repository from
.wallpapers.repo) into ~/.wallpapers.dir, then sets .wallpapers.current as the KDE
Plasma desktop wallpaper.
EOF
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --non-interactive) shift ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

export DRY_RUN

ROOT_DIR="$(repo_root)"
if ! has chezmoi; then
  [[ "$DRY_RUN" == '1' ]] || die 'chezmoi is required to fetch the wallpapers.'
  log_warn 'chezmoi is unavailable; the wallpaper step cannot be previewed in this dry-run.'
  exit 0
fi

# Read from this checkout: on a fresh machine's dry-run chezmoi has no source directory yet
data_value() {
  chezmoi --source "$ROOT_DIR/home" execute-template "{{ $1 }}"
}

repo="$(data_value '.wallpapers.repo')"
dir="$HOME/$(data_value '.wallpapers.dir')"
image="$dir/$(data_value '.wallpapers.current')"

[[ -n "$repo" ]] || die 'No wallpaper repository is set (.wallpapers.repo).'

if ! has git-lfs; then
  [[ "$DRY_RUN" == '1' ]] || die 'git-lfs is required to fetch the wallpapers; run the packages step first.'
  log_warn 'git-lfs is unavailable; a real run would stop here.'
fi

# chezmoi pulls whatever repository already sits there, so never adopt a foreign clone
if [[ -e "$dir" ]]; then
  origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  if [[ "${origin%.git}" != "${repo%.git}" ]]; then
    die "$dir is not a clone of $repo (origin: ${origin:-none}). Move it away, then run this step again."
  fi
  log_step "Updating wallpapers in $dir"
else
  log_step "Cloning wallpapers from $repo into $dir"
fi
run_or_print chezmoi --source "$ROOT_DIR/home" apply --verbose "$dir"

if [[ "$DRY_RUN" == '0' && ! -f "$image" ]]; then
  die "Wallpaper not found: $image (check .wallpapers.current)"
fi

if has plasma-apply-wallpaperimage; then
  run_or_print plasma-apply-wallpaperimage "$image"
else
  log_warn "plasma-apply-wallpaperimage not found; set the wallpaper by hand: $image"
fi

log_success 'Wallpaper step complete'
