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
