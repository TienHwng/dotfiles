#!/usr/bin/env bats
# shellcheck disable=SC2016

load test_helper

setup() {
  setup_isolated_home
  export DOTS_NO_GUM=1
  DOTS="$PROJECT_ROOT/scripts/unix/dots"
}

# Mock pacman and paru; paru records that it really ran
mock_package_tools() {
  mock_bin="$BATS_TEST_TMPDIR/package-bin"
  paru_marker="$BATS_TEST_TMPDIR/paru-executed"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$mock_bin/pacman"
  printf '#!/usr/bin/env bash\ntouch %q\n' "$paru_marker" >"$mock_bin/paru"
  chmod +x "$mock_bin/pacman" "$mock_bin/paru"
}

@test "dots help lists every command and unknown commands fail" {
  run "$DOTS" help
  [ "$status" -eq 0 ]
  local command_name
  for command_name in bootstrap packages doctor update backup cleanup; do
    if [[ "$output" != *"$command_name"* ]]; then
      echo "help does not mention $command_name"
      return 1
    fi
  done

  run "$DOTS" no-such-command
  [ "$status" -ne 0 ]
  [[ "$output" == *'Unknown command: no-such-command'* ]]

  run "$DOTS" bootstrap --skip no-such-step
  [ "$status" -ne 0 ]
  [[ "$output" == *'Unknown step: no-such-step'* ]]
}

@test "dots works through a symlink on PATH" {
  ln -s "$DOTS" "$BATS_TEST_TMPDIR/dots"

  run "$BATS_TEST_TMPDIR/dots" help
  [ "$status" -eq 0 ]
  [[ "$output" == *'Usage: dots'* ]]
}

@test "dots bootstrap dry-run with every step skipped changes nothing" {
  before="$(find "$HOME" -mindepth 1 -print | sort)"

  run "$DOTS" bootstrap --dry-run --non-interactive \
    --skip packages --skip git --skip accounts --skip fonts --skip shell --skip apply --skip desktop --skip wallpaper --skip sync --skip system

  [ "$status" -eq 0 ]
  [ "$before" = "$(find "$HOME" -mindepth 1 -print | sort)" ]
  [[ "$output" == *'Skipping packages'* ]]
  [[ "$output" == *'Skipping apply'* ]]
  [[ "$output" == *'Bootstrap complete'* ]]
}

@test "interactive bootstrap previews each step and honours skip and quit" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  mock_package_tools

  run env PATH="$mock_bin:$PATH" DOTFILES_PLATFORM=arch bash -c \
    'printf "s\nq\n" | "$1" bootstrap --skip git --skip accounts' _ "$DOTS"

  [ "$status" -eq 0 ]
  [ ! -e "$paru_marker" ]
  [[ "$output" == *'paru -S --needed --noconfirm'* ]]
  [[ "$output" == *'Skipped packages'* ]]
  [[ "$output" == *'install Nerd Font JetBrainsMono'* ]]
  [[ "$output" == *'Stopped before fonts'* ]]
  [[ "$output" != *'Bootstrap complete'* ]]
}

@test "interactive bootstrap runs a step after yes" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  mock_package_tools

  run env PATH="$mock_bin:$PATH" DOTFILES_PLATFORM=arch bash -c \
    'printf "y\nq\n" | "$1" bootstrap --skip git --skip accounts' _ "$DOTS"

  [ "$status" -eq 0 ]
  [ -e "$paru_marker" ]
  [[ "$output" == *'Stopped before fonts'* ]]
}

@test "bootstrap.sh hands its steps to dots bootstrap" {
  run env DOTFILES_PLATFORM=arch "$PROJECT_ROOT/scripts/unix/bootstrap.sh" \
    --dry-run --non-interactive --skip-packages --skip-git --skip-accounts \
    --skip-fonts --skip-shell --skip-apply --skip-desktop --skip-wallpaper --skip-sync --skip-system

  [ "$status" -eq 0 ]
  [[ "$output" == *'[packages]'* ]]
  [[ "$output" == *'Skipping packages'* ]]
  [[ "$output" == *'Unix bootstrap complete'* ]]
}

@test "dots backup dry-run warns when the destination is on the OS disk" {
  destination="$HOME/backups"
  disk_of() { df -P "$1" | awk 'NR == 2 { print $1 }'; }

  run "$DOTS" backup --dry-run --destination "$destination"

  [ "$status" -eq 0 ]
  [ ! -e "$destination" ]
  [[ "$output" == *'+ tar -czf'* ]]
  if [[ "$(disk_of "$HOME")" == "$(disk_of /)" ]]; then
    [[ "$output" == *'same disk as the running OS'* ]]
  else
    [[ "$output" != *'same disk as the running OS'* ]]
  fi
}

@test "dots runs a single step by name and rejects options it does not know" {
  run env DOTS_NO_GUM=1 "$DOTS" fonts --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *'Unknown fonts option'* ]]

  run env DOTS_NO_GUM=1 DOTFILES_PLATFORM=arch "$DOTS" fonts --dry-run --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *'[fonts]'* ]]
}

@test "doctor warns about Plasma packages with symlinks and a splash that is not installed" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  mock_bin="$BATS_TEST_TMPDIR/plasma-bin"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\necho Missing.theme\n' >"$mock_bin/kreadconfig6"
  printf '#!/usr/bin/env bash\necho "Path traversal attempt detected: x is not inside y"\n' >"$mock_bin/journalctl"
  chmod +x "$mock_bin"/*
  installed="$XDG_DATA_HOME/plasma/look-and-feel/a2n.kuro"
  mkdir -p "$(dirname "$installed")"
  cp -r "$PROJECT_ROOT/kde/plasma/look-and-feel/a2n.kuro" "$installed"
  ln -sf "$PROJECT_ROOT/kde/plasma/look-and-feel/a2n.kuro/metadata.json" "$installed/metadata.json"

  run env PATH="$mock_bin:$PATH" bash -c 'source "$1"; doctor_plasma_packages' _ "$DOTS"

  [ "$status" -eq 0 ]
  [[ "$output" == *'a2n.kuro contains symlinks, which Plasma refuses; run: dots desktop'* ]]
  [[ "$output" == *'The splash screen Missing.theme is not installed anywhere'* ]]
  [[ "$output" == *'Plasma refused 1 package file(s)'* ]]
}

@test "dots update lists upgrades, asks, and never pulls the repository" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  mock_bin="$BATS_TEST_TMPDIR/update-bin"
  calls="$BATS_TEST_TMPDIR/update-calls"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\necho "lvm2 2.03.43-2 -> 2.03.44-1"\n' >"$mock_bin/checkupdates"
  printf '#!/usr/bin/env bash\nprintf "paru %%s\\n" "$*" >>%q\n[[ "$1" == -Qua ]] && echo "zsh-auto-notify 0.11.0 -> 0.11.1"\nexit 0\n' "$calls" >"$mock_bin/paru"
  chmod +x "$mock_bin"/*

  run env PATH="$mock_bin:$PATH" DOTFILES_PLATFORM=arch "$DOTS" update --packages --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'lvm2 2.03.43-2 -> 2.03.44-1'* ]]
  [[ "$output" == *'zsh-auto-notify'* ]]
  [[ "$output" == *'+ paru -Syu'* ]]
  [[ "$output" != *'chezmoi update'* ]]
  run grep -c '^paru -Syu' "$calls"
  [ "$output" = '0' ]

  run env PATH="$mock_bin:$PATH" DOTFILES_PLATFORM=arch DOTS_NO_GUM=1 bash -c 'printf "n\nn\n" | "$1" update --packages' _ "$DOTS"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Packages left as they are'* ]]
  run grep -c '^paru -Syu' "$calls"
  [ "$output" = '0' ]
}
