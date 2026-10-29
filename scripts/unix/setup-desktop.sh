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
(plasma-apply-lookandfeel), each listed key (kwriteconfig6) and the fcitx5 input method list
(over D-Bus when fcitx5 runs, else its profile). Prints current -> new
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
# layout<TAB>input methods (space-separated)<TAB>default; empty when kde.yaml has no fcitx5
fcitx5_wanted="$(chezmoi --source "$ROOT_DIR/home" execute-template \
  '{{ with .kde.fcitx5 }}{{ .layout }}{{ "\t" }}{{ join " " .inputMethods }}{{ "\t" }}{{ .default }}{{ end }}')"

changes=0
kwin_changed=0
login_needed=0

# Before P5a chezmoi symlinked whole *rc files into the source; those files left it, so on an
# older machine the links dangle. kwriteconfig6 then writes nothing yet exits 0, and KWin loses
# keys such as the fcitx5 input method. Remove the links so the writes below create real files.
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
for link in "$config_dir"/*; do
  [[ -L "$link" && ! -e "$link" ]] || continue
  [[ "$(readlink -- "$link")" == "$ROOT_DIR/home/"* ]] || continue
  printf '  %s: dangling link into the chezmoi source, removing it\n' "${link##*/}"
  run_or_print rm -- "$link"
done

current_theme="$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)"
theme_changed=0
if [[ -n "$look_and_feel" && "$current_theme" != "$look_and_feel" ]]; then
  printf '  global theme: %s -> %s\n' "${current_theme:-<unset>}" "$look_and_feel"
  theme_changed=1
  changes=$((changes + 1))
fi

# fcitx5 input methods, read from its profile (fcitx5 saves it every few minutes and on exit)
fcitx5_changed=0
profile=(--file fcitx5/profile --group Groups/0)
current_ims=()
if [[ -n "$fcitx5_wanted" ]]; then
  IFS=$'\t' read -r im_layout im_list im_default <<<"$fcitx5_wanted"
  for ((i = 0; ; i++)); do
    im="$(kreadconfig6 --file fcitx5/profile --group "Groups/0/Items/$i" --key Name)"
    [[ -n "$im" ]] || break
    current_ims+=("$im")
  done
  current_im="$(kreadconfig6 "${profile[@]}" --key 'Default Layout'): ${current_ims[*]} (default $(kreadconfig6 "${profile[@]}" --key DefaultIM))"
  wanted_im="$im_layout: $im_list (default $im_default)"
  if [[ "$current_im" != "$wanted_im" ]]; then
    printf '  fcitx5 input methods: %s -> %s\n' "$current_im" "$wanted_im"
    fcitx5_changed=1
    changes=$((changes + 1))
  fi
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
  [[ "$file" =~ ^(kglobalshortcutsrc|kcminputrc|powerdevilrc)$ ]] && login_needed=1
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

# A running fcitx5 keeps the list in memory and saves it over the profile, so it gets the list
# over D-Bus like fcitx5-configtool does; otherwise the profile is written for its next start.
if ((fcitx5_changed)); then
  read -r -a ims <<<"$im_list"
  fcitx5_owner="$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus NameHasOwner s org.fcitx.Fcitx5 2>/dev/null || true)"
  if [[ "$fcitx5_owner" == 'b true' ]]; then
    entries=()
    for im in "${ims[@]}"; do
      entries+=("$im" '')
    done
    run_or_print busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 \
      SetInputMethodGroupInfo 'ssa(ss)' Default "$im_layout" "${#ims[@]}" "${entries[@]}"
    run_or_print busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 \
      SetCurrentIM s "$im_default"
  else
    run_or_print kwriteconfig6 --file fcitx5/profile --group GroupOrder --key 0 Default
    run_or_print kwriteconfig6 "${profile[@]}" --key Name Default
    run_or_print kwriteconfig6 "${profile[@]}" --key 'Default Layout' "$im_layout"
    run_or_print kwriteconfig6 "${profile[@]}" --key DefaultIM "$im_default"
    for i in "${!ims[@]}"; do
      run_or_print kwriteconfig6 --file fcitx5/profile --group "Groups/0/Items/$i" --key Name "${ims[$i]}"
    done
    for ((i = ${#ims[@]}; i < ${#current_ims[@]}; i++)); do
      run_or_print kwriteconfig6 --file fcitx5/profile --group "Groups/0/Items/$i" --key Name --delete
    done
  fi
fi

if ((kwin_changed)) && has qdbus6 && qdbus6 org.kde.KWin >/dev/null 2>&1; then
  run_or_print qdbus6 org.kde.KWin /KWin reconfigure
fi
if ((login_needed)); then
  log_warn 'Global shortcuts, input devices and power settings take effect after the next login.'
fi

log_success 'KDE settings step complete'
