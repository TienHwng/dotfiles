#!/usr/bin/env bats
# shellcheck disable=SC2016 # mock scripts and bash -c bodies expand when they run

load test_helper

# A throwaway clone of scripts/unix with a bare upstream. chezmoi is mocked to fail, so only
# repository files are offered; the YAML editors are tested on copies.
setup() {
  setup_isolated_home
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  git config --global user.name Test
  git config --global user.email test@example.test
  git config --global init.defaultBranch main

  upstream="$BATS_TEST_TMPDIR/upstream.git"
  work="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$upstream"
  git init -q "$work"
  mkdir -p "$work/scripts" "$work/docs"
  cp -r "$PROJECT_ROOT/scripts/unix" "$work/scripts/unix"
  printf 'old\n' >"$work/docs/note.md"
  git -C "$work" add -A
  git -C "$work" commit -qm initial
  git -C "$work" remote add origin "$upstream"
  git -C "$work" push -q -u origin main

  mock_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\n[[ "$*" == *chezmoi.hostname* ]] && { echo "${MOCK_HOST:-HwngPC}"; exit 0; }\nexit 1\n' >"$mock_bin/chezmoi"
  chmod +x "$mock_bin/chezmoi"
  answers="$BATS_TEST_TMPDIR/answers"
}

capture() {
  run env PATH="$mock_bin:$PATH" DOTS_NO_GUM=1 DOTS_TTY="$answers" "$work/scripts/unix/capture.sh" "$@" </dev/null
}

@test "capture --dry-run lists repository changes and changes nothing" {
  printf 'new\n' >"$work/docs/note.md"
  printf 'x\n' >"$work/docs/added.md"

  capture --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'file       M docs/note.md'* ]]
  [[ "$output" == *'file      ?? docs/added.md'* ]]
  [ "$(git -C "$work" status --porcelain | wc -l)" -eq 2 ]
}

@test "capture commits only the chosen items to main and pushes" {
  printf 'new\n' >"$work/docs/note.md"
  printf 'x\n' >"$work/docs/added.md"
  printf '1\n\ny\n' >"$answers"

  capture

  [ "$status" -eq 0 ]
  [[ "$output" == *'Committed and pushed to origin/main'* ]]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "Capture local changes from $(uname -n)" ]
  git -C "$upstream" show --name-only --format= main | grep -qx docs/note.md
  [ "$(git -C "$work" status --porcelain)" = '?? docs/added.md' ]
}

@test "capture answered no unstages everything and pushes nothing" {
  printf 'new\n' >"$work/docs/note.md"
  printf '1\nmy message\nn\n' >"$answers"
  before="$(git -C "$upstream" rev-parse main)"

  capture

  [ "$status" -eq 0 ]
  [[ "$output" == *'Unstaged everything'* ]]
  [ "$(git -C "$upstream" rev-parse main)" = "$before" ]
  [ "$(git -C "$work" status --porcelain)" = ' M docs/note.md' ]
}

@test "capture refuses non-interactive runs and branches other than main" {
  printf 'new\n' >"$work/docs/note.md"

  run env PATH="$mock_bin:$PATH" NON_INTERACTIVE=1 "$work/scripts/unix/capture.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *'never runs non-interactively'* ]]

  git -C "$work" switch -q -c topic
  capture
  [ "$status" -ne 0 ]
  [[ "$output" == *'Captures commit to main'* ]]
}

@test "a captured KDE value lands in the machine entry for this host, else the shared one" {
  yaml="$BATS_TEST_TMPDIR/kde.yaml"
  cat >"$yaml" <<'EOF'
kde:
  settings:
    - { file: kwinrc, group: [NightColor], key: Active, value: "true" }
    - { file: kcminputrc, group: [Mouse], key: X, value: "1" }
  machines:
    HwngPC:
      settings:
        - { file: kcminputrc, group: [Libinput, "1267", "ELAN Touchpad"], key: NaturalScroll, value: "true" }
        - { file: kcminputrc, group: [Mouse], key: X, value: "2" }
    Other:
      settings:
        - { file: kcminputrc, group: [Mouse], key: X, value: "3" }
EOF
  run env PATH="$mock_bin:$PATH" bash -c '
    source "$1/scripts/unix/capture.sh"
    KDE_YAML="$2"
    set_kde_value kwinrc NightColor Active false
    set_kde_value kcminputrc "Libinput${SEP}1267${SEP}ELAN Touchpad" NaturalScroll "say \"hi\""
    set_kde_value kcminputrc Mouse X 9
  ' _ "$PROJECT_ROOT" "$yaml"

  [ "$status" -eq 0 ]
  grep -qxF '    - { file: kwinrc, group: [NightColor], key: Active, value: "false" }' "$yaml"
  grep -qxF '        - { file: kcminputrc, group: [Libinput, "1267", "ELAN Touchpad"], key: NaturalScroll, value: "say \"hi\"" }' "$yaml"
  grep -qxF '        - { file: kcminputrc, group: [Mouse], key: X, value: "9" }' "$yaml"
  grep -qxF '    - { file: kcminputrc, group: [Mouse], key: X, value: "1" }' "$yaml"
  grep -qxF '        - { file: kcminputrc, group: [Mouse], key: X, value: "3" }' "$yaml"
}

@test "captured packages are appended to the platform list" {
  yaml="$BATS_TEST_TMPDIR/packages.yaml"
  cat >"$yaml" <<'EOF'
packages:
  arch:
    # Base
    - grub
    - paru

  apt:
    - build-essential
EOF
  run env DOTFILES_PLATFORM=arch bash -c '
    source "$1/scripts/unix/capture.sh"
    PACKAGES_YAML="$2"
    add_packages htop btop
  ' _ "$PROJECT_ROOT" "$yaml"

  [ "$status" -eq 0 ]
  [ "$(sed -n 5,7p "$yaml")" = $'    - paru\n    - htop\n    - btop' ]
  [ "$(tail -2 "$yaml")" = $'  apt:\n    - build-essential' ]
}

@test "picked packages are added to the manifest or uninstalled" {
  printf '#!/usr/bin/env bash\nprintf "paru %%s\\n" "$*" >>%q\n' "$BATS_TEST_TMPDIR/calls" >"$mock_bin/paru"
  chmod +x "$mock_bin/paru"
  printf 'u\na\nnope\n' >"$answers"

  run env PATH="$mock_bin:$PATH" DOTS_NO_GUM=1 DOTFILES_PLATFORM=arch bash -c '
    source "$1/scripts/unix/capture.sh"
    exec 3<"$2"
    for n in 2 1 1; do choose_package_action "$n"; done
    uninstall_packages htop btop
  ' _ "$PROJECT_ROOT" "$answers"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = uninstall ]
  [ "${lines[1]}" = add ]
  [ "${lines[2]}" = skip ]
  grep -qx 'paru -Rns htop btop' "$BATS_TEST_TMPDIR/calls"
}

@test "kde_snapshot flattens KDE config files and skips ignored ones" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  config="$HOME/.config"
  mkdir -p "$config"
  printf '[Plugins]\nblurEnabled=true\n\n[Effect-Blur][Sub]\nStrength=5\nName[vi]=x\n' >"$config/kwinrc"
  printf '[Containments][1]\nplugin=x\n' >"$config/plasma-org.kde.plasma.desktop-appletsrc"
  printf '[State]\nwidth=1\n' >"$config/dolphinstaterc"

  run bash -c 'source "$1/scripts/unix/capture.sh"; kde_snapshot' _ "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'kwinrc\tEffect-Blur\x1fSub\tStrength\t5' ]
  [ "${lines[1]}" = $'kwinrc\tPlugins\tblurEnabled\ttrue' ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "discovered KDE keys are formatted and appended to the shared or the host list" {
  yaml="$BATS_TEST_TMPDIR/kde.yaml"
  cat >"$yaml" <<'EOF2'
kde:
  settings:
    - { file: kwinrc, group: [NightColor], key: Active, value: "true" }
  machines:
    HwngPC:
      settings:
        - { file: kcminputrc, group: [Mouse], key: X, value: "2" }
EOF2
  run bash -c '
    source "$1/scripts/unix/capture.sh"
    KDE_YAML="$2"
    append_kde_entry "" "$(kde_entry kwinrc Plugins blurEnabled true)"
    append_kde_entry HwngPC "$(kde_entry kcminputrc "Libinput${SEP}1267${SEP}ELAN:Touchpad" Natural "a \"b\"")"
    append_kde_entry Laptop "$(kde_entry kdeglobals KDE "Shut Down" x)"
  ' _ "$PROJECT_ROOT" "$yaml"

  [ "$status" -eq 0 ]
  expected='kde:
  settings:
    - { file: kwinrc, group: [NightColor], key: Active, value: "true" }
    - { file: kwinrc, group: [Plugins], key: blurEnabled, value: "true" }
  machines:
    HwngPC:
      settings:
        - { file: kcminputrc, group: [Mouse], key: X, value: "2" }
        - { file: kcminputrc, group: [Libinput, "1267", "ELAN:Touchpad"], key: Natural, value: "a \"b\"" }
    Laptop:
      settings:
        - { file: kdeglobals, group: [KDE], key: Shut Down, value: "x" }'
  [ "$(cat "$yaml")" = "$expected" ]

  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  run chezmoi --source "$BATS_TEST_TMPDIR" execute-template '{{ (index (fromYaml (include "kde.yaml")).kde.machines.HwngPC.settings 1).value }}'
  [ "$output" = 'a "b"' ]
}

@test "capture offers a changed Plasma package and copies it into kde/" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo"
  cp -r "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/home" "$PROJECT_ROOT/kde" "$repo/"
  installed="$XDG_DATA_HOME/plasma/look-and-feel/a2n.kuro"
  mkdir -p "$(dirname "$installed")"
  cp -r "$repo/kde/plasma/look-and-feel/a2n.kuro" "$installed"

  run bash -c 'source "$1/scripts/unix/capture.sh"; collect_kde_packages; printf "%s\n" "${items[@]}"' _ "$repo"
  [ -z "$output" ]

  printf 'new frame\n' >"$installed/contents/splash/images/extra.txt"
  run bash -c 'source "$1/scripts/unix/capture.sh"; collect_kde_packages; printf "%s\n" "${items[@]}"' _ "$repo"
  [[ "$output" == *'kde-pkg   plasma/look-and-feel/a2n.kuro: keep the installed copy'* ]]

  git -C "$repo" init -q
  run bash -c 'source "$1/scripts/unix/capture.sh"; capture_item kde-pkg plasma/look-and-feel/a2n.kuro' _ "$repo"
  [ "$status" -eq 0 ]
  [ "$(cat "$repo/kde/plasma/look-and-feel/a2n.kuro/contents/splash/images/extra.txt")" = 'new frame' ]
  git -C "$repo" diff --cached --name-only | grep -qx 'kde/plasma/look-and-feel/a2n.kuro/contents/splash/images/extra.txt'
}
