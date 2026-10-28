#!/usr/bin/env bats

load test_helper

# Mock kreadconfig6 answers from a store of "file|group/group|key=value" lines;
# kwriteconfig6, plasma-apply-lookandfeel and qdbus6 log their arguments.
setup() {
  setup_isolated_home
  DESKTOP="$PROJECT_ROOT/scripts/unix/setup-desktop.sh"
  mock_bin="$BATS_TEST_TMPDIR/bin"
  store="$BATS_TEST_TMPDIR/kde-store"
  calls="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$mock_bin"
  : >"$store"
  cat >"$mock_bin/kreadconfig6" <<EOF
#!/usr/bin/env bash
file='' groups='' key=''
while ((\$#)); do
  case "\$1" in
    --file) file="\$2"; shift 2 ;;
    --group) groups="\${groups:+\$groups/}\$2"; shift 2 ;;
    --key) key="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
grep -F -- "\$file|\$groups|\$key=" '$store' | head -1 | cut -d= -f2- || true
EOF
  for tool in kwriteconfig6 plasma-apply-lookandfeel qdbus6; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %q "$*" >>%q\n' "$tool" "$calls" >"$mock_bin/$tool"
  done
  chmod +x "$mock_bin"/*
}

# Store every value from kde.yaml, so nothing differs
store_all_current() {
  chezmoi --source "$PROJECT_ROOT" execute-template <"$PROJECT_ROOT/scripts/kde-settings.tmpl" \
    | awk -F'\t' '{ gsub("\037", "/", $2); print $1 "|" $2 "|" $3 "=" $4 }' >"$store"
  printf 'kdeglobals|KDE|LookAndFeelPackage=%s\n' \
    "$(chezmoi --source "$PROJECT_ROOT/home" execute-template '{{ .kde.lookAndFeel }}')" >>"$store"
}

@test "desktop step reports nothing when KDE already matches kde.yaml" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  store_all_current

  run env PATH="$mock_bin:$PATH" "$DESKTOP"

  [ "$status" -eq 0 ]
  [[ "$output" == *'already match kde.yaml'* ]]
  [ ! -e "$calls" ]
}

@test "desktop dry-run lists differing keys and writes nothing" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  store_all_current
  sed -i 's/^ksplashrc|KSplash|Theme=.*/ksplashrc|KSplash|Theme=org.kde.breeze.desktop/' "$store"
  sed -i '/^kdeglobals|KDE|LookAndFeelPackage=/d' "$store"

  run env PATH="$mock_bin:$PATH" "$DESKTOP" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'ksplashrc [KSplash] Theme: org.kde.breeze.desktop -> a2n.kuro'* ]]
  [[ "$output" == *'global theme: <unset> -> org.kde.breezetwilight.desktop'* ]]
  [[ "$output" == *'+ kwriteconfig6 --notify --file ksplashrc --group KSplash --key Theme a2n.kuro'* ]]
  [ ! -e "$calls" ]
}

@test "desktop step writes only the differing keys, nested groups included" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  store_all_current
  sed -i '/^kglobalshortcutsrc|services\/kitty.desktop|_launch=/d' "$store"
  sed -i 's/^kwinrc|NightColor|Active=.*/kwinrc|NightColor|Active=false/' "$store"

  run env PATH="$mock_bin:$PATH" "$DESKTOP"

  [ "$status" -eq 0 ]
  [[ "$output" == *'take effect after the next login'* ]]
  [ "$(grep -c '^kwriteconfig6 ' "$calls")" -eq 2 ]
  grep -qx 'kwriteconfig6 --notify --file kglobalshortcutsrc --group services --group kitty.desktop --key _launch Meta+T' "$calls"
  grep -qx 'kwriteconfig6 --notify --file kwinrc --group NightColor --key Active true' "$calls"
  run grep -c '^plasma-apply-lookandfeel' "$calls"
  [ "$output" = '0' ]
}

@test "desktop step skips machines without KDE Plasma" {
  empty_bin="$BATS_TEST_TMPDIR/empty-bin"
  mkdir -p "$empty_bin"
  for tool in dirname cat; do ln -s "$(command -v "$tool")" "$empty_bin/$tool"; done

  run env PATH="$empty_bin" "$BASH" "$DESKTOP" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'KDE Plasma 6 is not installed'* ]]
}
