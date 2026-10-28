#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/setup-desktop.sh [--dry-run]

Applies the KDE Plasma settings from home/.chezmoidata/kde.yaml: the global theme
(plasma-apply-lookandfeel) and each listed key (kwriteconfig6). Prints current -> new
for every key that differs; with --dry-run it changes nothing.
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

if ! has kwriteconfig6 || ! has kreadconfig6; then
  log_warn 'KDE Plasma 6 is not installed (kwriteconfig6/kreadconfig6 missing); nothing to do.'
  exit 0
fi
if ! has chezmoi; then
  [[ "$DRY_RUN" == '1' ]] || die 'chezmoi is required to read home/.chezmoidata/kde.yaml.'
  log_warn 'chezmoi is unavailable; the desktop step cannot be previewed in this dry-run.'
  exit 0
fi

# Read from this checkout: on a fresh machine's dry-run chezmoi has no source directory yet
settings="$(chezmoi --source "$ROOT_DIR" execute-template <"$ROOT_DIR/scripts/kde-settings.tmpl")"
look_and_feel="$(chezmoi --source "$ROOT_DIR/home" execute-template '{{ .kde.lookAndFeel }}')"

changes=0
kwin_changed=0
shortcuts_changed=0

current_theme="$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)"
theme_changed=0
if [[ -n "$look_and_feel" && "$current_theme" != "$look_and_feel" ]]; then
  printf '  global theme: %s -> %s\n' "${current_theme:-<unset>}" "$look_and_feel"
  theme_changed=1
  changes=$((changes + 1))
fi

# Collect the keys that differ: file, groups, key, value per entry
pending=()
while IFS=$'\t' read -r file groups key value; do
  [[ -n "$file" ]] || continue
  group_args=()
  IFS=$'\x1f' read -r -a group_list <<<"$groups"
  for group in "${group_list[@]}"; do
    group_args+=(--group "$group")
  done

  current="$(kreadconfig6 --file "$file" "${group_args[@]}" --key "$key")"
  [[ "$current" == "$value" ]] && continue

  printf '  %s [%s] %s: %s -> %s\n' "$file" "${groups//$'\x1f'/][}" "$key" "${current:-<unset>}" "$value"
  pending+=("$file"$'\t'"$groups"$'\t'"$key"$'\t'"$value")
  changes=$((changes + 1))
  [[ "$file" == 'kwinrc' ]] && kwin_changed=1
  [[ "$file" == 'kglobalshortcutsrc' ]] && shortcuts_changed=1
done <<<"$settings"

if ((changes == 0)); then
  log_success 'KDE settings already match kde.yaml'
  exit 0
fi
log_step "$changes KDE setting(s) differ from kde.yaml"

# The global theme rewrites colors in kdeglobals, so it goes first
if ((theme_changed)); then
  if has plasma-apply-lookandfeel; then
    run_or_print plasma-apply-lookandfeel --apply "$look_and_feel"
  else
    log_warn "plasma-apply-lookandfeel not found; pick $look_and_feel in System Settings."
  fi
fi

for entry in "${pending[@]}"; do
  IFS=$'\t' read -r file groups key value <<<"$entry"
  group_args=()
  IFS=$'\x1f' read -r -a group_list <<<"$groups"
  for group in "${group_list[@]}"; do
    group_args+=(--group "$group")
  done
  run_or_print kwriteconfig6 --notify --file "$file" "${group_args[@]}" --key "$key" "$value"
done

if ((kwin_changed)) && has qdbus6 && qdbus6 org.kde.KWin >/dev/null 2>&1; then
  run_or_print qdbus6 org.kde.KWin /KWin reconfigure
fi
if ((shortcuts_changed)); then
  log_warn 'Global shortcuts take effect after the next login.'
fi

log_success 'KDE settings step complete'
