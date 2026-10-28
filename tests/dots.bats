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
    --skip packages --skip git --skip accounts --skip fonts --skip shell --skip apply --skip wallpaper

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
    --skip-fonts --skip-shell --skip-apply --skip-wallpaper

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
