#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

FORCE=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/install-fonts.sh [--force] [--dry-run]

Fonts come from the nerdFonts list in home/.chezmoidata/packages.yaml.
Each entry is a Nerd Fonts release archive name, for example JetBrainsMono
or FiraCode.
EOF
}

while (($#)); do
  case "$1" in
    --force)
      FORCE=1
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

export DRY_RUN

if ! has chezmoi; then
  if [[ "$DRY_RUN" == '1' ]]; then
    log_warn 'chezmoi is unavailable; the font list cannot be read in this dry-run.'
    exit 0
  fi
  die 'chezmoi is required to read the font list (home/.chezmoidata/packages.yaml).'
fi
FONTS="$(manifest_list nerdFonts)" || die 'Could not read the nerdFonts list from the package manifest.'
[[ -n "$FONTS" ]] || {
  log_warn 'No Nerd Fonts are configured.'
  exit 0
}

case "$(uname -s)" in
  Darwin) FONT_HOME="$HOME/Library/Fonts/NerdFonts" ;;
  Linux) FONT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/NerdFonts" ;;
  *) die 'This script supports Linux and macOS only.' ;;
esac

download_file() {
  local url="$1" output="$2"
  if has curl; then
    curl -fL --retry 3 --connect-timeout 15 -o "$output" "$url"
  elif has wget; then
    wget -O "$output" "$url"
  else
    die 'curl or wget is required to download fonts.'
  fi
}

if [[ "$DRY_RUN" == '0' ]]; then
  has unzip || die 'unzip is required to install fonts.'
  mkdir -p "$FONT_HOME"
fi

while IFS= read -r font; do
  target_dir="$FONT_HOME/$font"

  if [[ -d "$target_dir" && "$FORCE" == '0' ]]; then
    log_success "$font is already installed"
    continue
  fi

  if [[ "$DRY_RUN" == '1' ]]; then
    printf '+ install Nerd Font %q into %q\n' "$font" "$target_dir"
    continue
  fi

  log_step "Installing $font Nerd Font..."
  tmp_dir="$(mktemp -d)"
  archive="$tmp_dir/$font.zip"
  extracted="$tmp_dir/extracted"
  trap 'rm -rf "${tmp_dir:-}"' EXIT

  download_file \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip" \
    "$archive"

  mkdir -p "$extracted"
  unzip -q "$archive" -d "$extracted"

  font_files=()
  while IFS= read -r font_file; do
    font_files+=("$font_file")
  done < <(find "$extracted" -type f \( -iname '*.ttf' -o -iname '*.otf' \))
  ((${#font_files[@]})) || die "No font files found in the $font archive."

  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  cp "${font_files[@]}" "$target_dir/"

  rm -rf "$tmp_dir"
  trap - EXIT
  log_success "Installed $font"
done <<<"$FONTS"

if [[ "$DRY_RUN" == '0' ]] && has fc-cache; then
  log_step 'Refreshing font cache...'
  fc-cache -f "$FONT_HOME" >/dev/null
fi

log_success 'Font installation complete'
