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
  for tool in kwriteconfig6 plasma-apply-lookandfeel qdbus6 kpackagetool6; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %q "$*" >>%q\n' "$tool" "$calls" >"$mock_bin/$tool"
  done
  # busctl answers NameHasOwner from FCITX5_RUNNING and logs every other call
  cat >"$mock_bin/busctl" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *NameHasOwner* ]]; then
  echo "b \${FCITX5_RUNNING:-false}"
  exit 0
fi
printf 'busctl %s\n' "\$*" >>'$calls'
EOF
  chmod +x "$mock_bin"/*
}

# Make chezmoi report this hostname, as kde.machines is keyed by it
set_hostname() {
  mkdir -p "$XDG_CONFIG_HOME/chezmoi"
  printf '[data.chezmoi]\nhostname = "%s"\n' "$1" >"$XDG_CONFIG_HOME/chezmoi/chezmoi.toml"
}

# Install a copy of every Plasma package from kde/, as kpackagetool6 would
install_packages() {
  mkdir -p "$XDG_DATA_HOME/plasma/look-and-feel"
  cp -r "$PROJECT_ROOT/kde/plasma/look-and-feel/a2n.kuro" "$XDG_DATA_HOME/plasma/look-and-feel/"
}

# Store every value from kde.yaml, so nothing differs
store_all_current() {
  install_packages
  chezmoi --source "$PROJECT_ROOT" execute-template <"$PROJECT_ROOT/scripts/kde-settings.tmpl" \
    | awk -F'\t' '{ gsub("\037", "/", $2); print $1 "|" $2 "|" $3 "=" $4 }' >"$store"
  printf 'kdeglobals|KDE|LookAndFeelPackage=%s\n' \
    "$(chezmoi --source "$PROJECT_ROOT/home" execute-template '{{ .kde.lookAndFeel }}')" >>"$store"
  # shellcheck disable=SC2016 # $i and $im are template variables, not shell ones
  chezmoi --source "$PROJECT_ROOT/home" execute-template '{{ with .kde.fcitx5 -}}
fcitx5/profile|Groups/0|Default Layout={{ .layout }}
fcitx5/profile|Groups/0|DefaultIM={{ .default }}
{{ range $i, $im := .inputMethods }}fcitx5/profile|Groups/0/Items/{{ $i }}|Name={{ $im }}
{{ end }}{{ end }}' >>"$store"
}

# Replace the stored fcitx5 profile with a stock one: keyboard-us and pinyin, two extra items
store_stock_fcitx5() {
  sed -i '/^fcitx5\/profile|/d' "$store"
  printf '%s\n' 'fcitx5/profile|Groups/0|Default Layout=us' 'fcitx5/profile|Groups/0|DefaultIM=pinyin' \
    'fcitx5/profile|Groups/0/Items/0|Name=keyboard-us' 'fcitx5/profile|Groups/0/Items/1|Name=pinyin' \
    'fcitx5/profile|Groups/0/Items/2|Name=mozc' 'fcitx5/profile|Groups/0/Items/3|Name=hangul' \
    'fcitx5/profile|Groups/0/Items/4|Name=rime' >>"$store"
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

@test "desktop step applies a machine's device keys on that machine" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  set_hostname HwngPC
  store_all_current
  grep -q '^kcminputrc|Libinput/1267/12410/ELAN1203:00 04F3:307A Touchpad|NaturalScroll=true$' "$store"
  sed -i '/^kcminputrc|/d' "$store"

  run env PATH="$mock_bin:$PATH" "$DESKTOP" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'5 KDE setting(s) differ'* ]]
  [[ "$output" == *'kcminputrc [Libinput][1267][12410][ELAN1203:00 04F3:307A Touchpad] NaturalScroll: <unset> -> true'* ]]
  [[ "$output" == *'kcminputrc [Libinput][14139][4569][Compx Wireless mouse 8k dongle-L] PointerAccelerationProfile: <unset> -> 1'* ]]
  [ ! -e "$calls" ]
}

@test "desktop step leaves another machine's device keys alone" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  set_hostname OtherPC
  store_all_current

  run grep -c '^kcminputrc|' "$store"
  [ "$output" = '0' ]
  run grep -c '^kwinrc|NightColor|Active=true$' "$store"
  [ "$output" = '1' ]

  run env PATH="$mock_bin:$PATH" "$DESKTOP" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'already match kde.yaml'* ]]
  [[ "$output" != *kcminputrc* ]]
}

@test "kde settings: a machine entry replaces the shared entry with the same key" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  set_hostname TestPC
  data='{"kde": {"settings": [
      {"file": "powerdevilrc", "group": ["AC", "Display"], "key": "TurnOffDisplayWhenIdle", "value": "false"},
      {"file": "kwinrc", "group": ["NightColor"], "key": "Active", "value": "true"}],
    "machines": {
      "TestPC": {"settings": [
        {"file": "powerdevilrc", "group": ["AC", "Display"], "key": "TurnOffDisplayWhenIdle", "value": "true"},
        {"file": "kcminputrc", "group": ["Mouse"], "key": "X11LibInputXAccelProfileFlat", "value": "true"}]},
      "OtherPC": {"settings": [
        {"file": "kwinrc", "group": ["NightColor"], "key": "Active", "value": "false"}]}}}}'

  run chezmoi --source "$PROJECT_ROOT" --override-data "$data" execute-template <"$PROJECT_ROOT/scripts/kde-settings.tmpl"

  [ "$status" -eq 0 ]
  expected="$(printf '%s\t%s\t%s\t%s\n' kwinrc NightColor Active true \
    powerdevilrc $'AC\x1fDisplay' TurnOffDisplayWhenIdle true kcminputrc Mouse X11LibInputXAccelProfileFlat true)"
  [ "$output" = "$expected" ]
}

@test "desktop step skips machines without KDE Plasma" {
  empty_bin="$BATS_TEST_TMPDIR/empty-bin"
  mkdir -p "$empty_bin"
  for tool in dirname cat; do ln -s "$(command -v "$tool")" "$empty_bin/$tool"; done

  run env PATH="$empty_bin" "$BASH" "$DESKTOP" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'KDE Plasma 6 is not installed'* ]]
}

@test "desktop step removes dangling *rc links into the chezmoi source" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  store_all_current
  mkdir -p "$XDG_CONFIG_HOME"
  ln -s "$PROJECT_ROOT/home/dot_config/kwinrc" "$XDG_CONFIG_HOME/kwinrc"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/kdeglobals" "$XDG_CONFIG_HOME/kdeglobals"
  ln -s "$PROJECT_ROOT/home/.chezmoidata/kde.yaml" "$XDG_CONFIG_HOME/kde.yaml"

  run env PATH="$mock_bin:$PATH" "$DESKTOP" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'kwinrc: dangling link into the chezmoi source, removing it'* ]]
  [[ "$output" == *"+ rm -- $XDG_CONFIG_HOME/kwinrc"* ]]
  [ -L "$XDG_CONFIG_HOME/kwinrc" ]

  run env PATH="$mock_bin:$PATH" "$DESKTOP"

  [ "$status" -eq 0 ]
  [ ! -L "$XDG_CONFIG_HOME/kwinrc" ]
  [ -L "$XDG_CONFIG_HOME/kdeglobals" ]
  [ -L "$XDG_CONFIG_HOME/kde.yaml" ]
  [[ "$output" != *'kdeglobals: dangling'* ]]
}

@test "desktop step sends the fcitx5 input methods over D-Bus to a running fcitx5" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  store_all_current
  store_stock_fcitx5

  run env PATH="$mock_bin:$PATH" FCITX5_RUNNING=true "$DESKTOP"

  [ "$status" -eq 0 ]
  [[ "$output" == *'fcitx5 input methods: us: keyboard-us pinyin mozc hangul rime (default pinyin) -> us: keyboard-us bamboo lotus unikey (default lotus)'* ]]
  grep -qxF 'busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 SetInputMethodGroupInfo ssa(ss) Default us 4 keyboard-us  bamboo  lotus  unikey ' "$calls"
  grep -qxF 'busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 SetCurrentIM s lotus' "$calls"
  run grep -c '^kwriteconfig6' "$calls"
  [ "$output" = '0' ]
}

@test "desktop step writes the fcitx5 profile when fcitx5 is not running" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  store_all_current
  store_stock_fcitx5

  run env PATH="$mock_bin:$PATH" "$DESKTOP"

  [ "$status" -eq 0 ]
  run grep -c '^busctl' "$calls"
  [ "$output" = '0' ]
  grep -qx 'kwriteconfig6 --file fcitx5/profile --group Groups/0 --key DefaultIM lotus' "$calls"
  grep -qx 'kwriteconfig6 --file fcitx5/profile --group Groups/0/Items/1 --key Name bamboo' "$calls"
  grep -qx 'kwriteconfig6 --file fcitx5/profile --group Groups/0/Items/3 --key Name unikey' "$calls"
  grep -qx 'kwriteconfig6 --file fcitx5/profile --group Groups/0/Items/4 --key Name --delete' "$calls"
}

@test "desktop dry-run previews the fcitx5 change and calls nothing" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  store_all_current
  store_stock_fcitx5

  run env PATH="$mock_bin:$PATH" FCITX5_RUNNING=true "$DESKTOP" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'+ busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 SetInputMethodGroupInfo ssa\(ss\) Default us 4 keyboard-us'* ]]
  [ ! -e "$calls" ]
}

@test "desktop step installs a missing Plasma package and upgrades a changed one" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  store_all_current
  rm -rf "$XDG_DATA_HOME/plasma/look-and-feel/a2n.kuro"

  run env PATH="$mock_bin:$PATH" "$DESKTOP"
  [ "$status" -eq 0 ]
  [[ "$output" == *'package a2n.kuro: <not installed> -> kde/plasma/look-and-feel/a2n.kuro'* ]]
  grep -qx "kpackagetool6 --type Plasma/LookAndFeel --install $PROJECT_ROOT/kde/plasma/look-and-feel/a2n.kuro" "$calls"

  install_packages
  printf 'changed\n' >>"$XDG_DATA_HOME/plasma/look-and-feel/a2n.kuro/metadata.json"
  rm -f "$calls"
  run env PATH="$mock_bin:$PATH" "$DESKTOP"
  [ "$status" -eq 0 ]
  [[ "$output" == *'installed copy differs'* ]]
  grep -qx "kpackagetool6 --type Plasma/LookAndFeel --upgrade $PROJECT_ROOT/kde/plasma/look-and-feel/a2n.kuro" "$calls"
}
