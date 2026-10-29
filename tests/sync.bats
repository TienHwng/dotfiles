#!/usr/bin/env bats
# shellcheck disable=SC2016 # mock scripts and bash -c bodies expand when they run

load test_helper

# A throwaway clone of scripts/unix with a bare upstream, so sync.sh and dots find their
# repository there; "other" pushes new commits to the upstream.
setup() {
  setup_isolated_home
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  git config --global user.name Test
  git config --global user.email test@example.test
  git config --global init.defaultBranch main

  upstream="$BATS_TEST_TMPDIR/upstream.git"
  work="$BATS_TEST_TMPDIR/work"
  other="$BATS_TEST_TMPDIR/other"
  git init -q --bare "$upstream"
  git init -q "$work"
  mkdir -p "$work/scripts"
  cp -r "$PROJECT_ROOT/scripts/unix" "$work/scripts/unix"
  git -C "$work" add -A
  git -C "$work" commit -qm initial
  git -C "$work" remote add origin "$upstream"
  git -C "$work" push -q -u origin main
  git clone -q "$upstream" "$other"

  mock_bin="$BATS_TEST_TMPDIR/bin"
  calls="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$mock_bin"
  for tool in kitty konsole; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %q "$*" >>%q\n' "$tool" "$calls" >"$mock_bin/$tool"
  done
  # notify-send prints the chosen action, like libnotify does after a click
  printf '#!/usr/bin/env bash\nprintf "notify-send %%s\\n" "$*" >>%q\nprintf "%%s\\n" "${NOTIFY_CHOICE:-}"\n' "$calls" >"$mock_bin/notify-send"
  chmod +x "$mock_bin"/*
  unset TERMINAL
}

push_change() {
  mkdir -p "$other/$(dirname "$1")"
  printf '%s\n' "${2:-change}" >"$other/$1"
  git -C "$other" add -A
  git -C "$other" commit -qm "change $1"
  git -C "$other" push -q
}

@test "sync --check reports commits behind without pulling" {
  push_change docs/note.md
  before="$(git -C "$work" rev-parse HEAD)"

  run env PATH="$mock_bin:$PATH" "$work/scripts/unix/sync.sh" --check

  [ "$status" -eq 0 ]
  [ "$output" = 'behind 1, ahead 0' ]
  [ "$(git -C "$work" rev-parse HEAD)" = "$before" ]
  [ ! -e "$calls" ]
}

@test "sync --notify notifies once per upstream commit and opens a terminal on Sync now" {
  push_change docs/note.md

  run env PATH="$mock_bin:$PATH" NOTIFY_CHOICE=sync "$work/scripts/unix/sync.sh" --check --notify
  [ "$status" -eq 0 ]
  grep -q '^notify-send .*--action=sync=Sync now Dotfiles repository changed 1 new commit' "$calls"
  sleep 0.2
  grep -qx "kitty --hold $work/scripts/unix/dots sync" "$calls"

  run env PATH="$mock_bin:$PATH" "$work/scripts/unix/sync.sh" --check --notify
  [ "$(grep -c '^notify-send' "$calls")" -eq 1 ]

  push_change docs/other.md
  run env PATH="$mock_bin:$PATH" "$work/scripts/unix/sync.sh" --check --notify
  [ "$(grep -c '^notify-send' "$calls")" -eq 2 ]
}

@test "sync --notify stays quiet when the machine is up to date" {
  run env PATH="$mock_bin:$PATH" "$work/scripts/unix/sync.sh" --check --notify

  [ "$status" -eq 0 ]
  [ "$output" = 'behind 0, ahead 0' ]
  [ ! -e "$calls" ]
}

@test "dots sync refuses local changes and non-interactive runs" {
  push_change docs/note.md
  printf '# local edit\n' >>"$work/scripts/unix/setup-wallpaper.sh"

  run env DOTS_NO_GUM=1 "$work/scripts/unix/dots" sync </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *'local changes'* ]]

  run env NON_INTERACTIVE=1 "$work/scripts/unix/dots" sync
  [ "$status" -ne 0 ]
  [[ "$output" == *'dots sync --check'* ]]
}

@test "dots sync shows the commits, pulls after yes, and reports when no step is needed" {
  push_change docs/note.md

  run env DOTS_NO_GUM=1 bash -c 'printf "n\n" | "$1" sync' _ "$work/scripts/unix/dots"
  [ "$status" -eq 0 ]
  [[ "$output" == *'change docs/note.md'* ]]
  [[ "$output" == *'Nothing pulled'* ]]
  [ ! -e "$work/docs/note.md" ]

  run env DOTS_NO_GUM=1 bash -c 'printf "y\n" | "$1" sync' _ "$work/scripts/unix/dots"
  [ "$status" -eq 0 ]
  [ -e "$work/docs/note.md" ]
  [[ "$output" == *'No step needs to run for these changes'* ]]

  run env DOTS_NO_GUM=1 "$work/scripts/unix/dots" sync </dev/null
  [[ "$output" == *'Already up to date'* ]]
}

@test "changed paths select the steps that read them" {
  run bash -c 'source "$1"; printf "%s\n" "$2" | steps_for_paths' _ "$PROJECT_ROOT/scripts/unix/dots" \
    $'scripts/unix/dots\nhome/dot_zshrc\nroot/etc/default/grub.tmpl\nhome/.chezmoidata/kde.yaml\nhome/.chezmoidata/packages.yaml\nhome/.chezmoidata/windows.yaml'

  [ "$status" -eq 0 ]
  [ "$output" = $'packages\nfonts\napply\ndesktop\nsystem' ]
}

@test "dots status reports upstream, local edits and the timer" {
  push_change docs/note.md

  run "$work/scripts/unix/dots" status

  [ "$status" -eq 0 ]
  [[ "$output" == *'Upstream     origin/main: 1 behind, 0 ahead'* ]]
  [[ "$output" == *'Local edits  0 file(s)'* ]]
}

@test "the sync timer units are valid and Linux-only" {
  units="$PROJECT_ROOT/home/dot_config/systemd/user"
  grep -qx 'OnUnitActiveSec=6h' "$units/dots-sync.timer"
  grep -qx 'ExecStart=%h/.local/bin/dots sync --check --notify' "$units/dots-sync.service"
  if command -v systemd-analyze >/dev/null; then
    run systemd-analyze --user verify "$units/dots-sync.timer"
    [[ "$output" != *'Unknown'* ]]
  fi
  grep -qx '.config/systemd' "$PROJECT_ROOT/home/.chezmoiignore"
}
