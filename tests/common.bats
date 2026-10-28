#!/usr/bin/env bats
# shellcheck disable=SC2016

load test_helper

@test "platform detection accepts a controlled Arch override" {
  run env DOTFILES_PLATFORM=arch bash -c 'source "$1"; detect_platform' _ \
    "$PROJECT_ROOT/scripts/unix/lib/common.sh"

  [ "$status" -eq 0 ]
  [ "$output" = 'arch' ]
}

@test "platform detection rejects an invalid override" {
  run env DOTFILES_PLATFORM=invalid bash -c 'source "$1"; detect_platform' _ \
    "$PROJECT_ROOT/scripts/unix/lib/common.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *'Invalid DOTFILES_PLATFORM override'* ]]
}

@test "run_or_print never executes its command in dry-run" {
  marker="$BATS_TEST_TMPDIR/executed"

  run env MARKER="$marker" bash -c '
    source "$1"
    DRY_RUN=1
    run_or_print sh -c '\''touch "$MARKER"'\''
  ' _ "$PROJECT_ROOT/scripts/unix/lib/common.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  [[ "$output" == '+ sh -c '* ]]
}

@test "run_or_print propagates command failures" {
  run bash -c '
    source "$1"
    DRY_RUN=0
    run_or_print sh -c "exit 23"
  ' _ "$PROJECT_ROOT/scripts/unix/lib/common.sh"

  [ "$status" -eq 23 ]
}

@test "run_root_or_print performs no privilege escalation in dry-run" {
  marker="$BATS_TEST_TMPDIR/escalated"
  mock_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\ntouch %q\n' "$marker" >"$mock_bin/sudo"
  chmod +x "$mock_bin/sudo"

  run env PATH="$mock_bin:$PATH" bash -c '
    source "$1"
    DRY_RUN=1
    run_root_or_print true
  ' _ "$PROJECT_ROOT/scripts/unix/lib/common.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
}

@test "non-interactive privilege escalation disables password prompts" {
  args_file="$BATS_TEST_TMPDIR/sudo-args"
  mock_bin="$BATS_TEST_TMPDIR/noninteractive-bin"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\nprintf "1000\\n"\n' >"$mock_bin/id"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >%q\n' "$args_file" >"$mock_bin/sudo"
  chmod +x "$mock_bin/id" "$mock_bin/sudo"

  run env PATH="$mock_bin:$PATH" NON_INTERACTIVE=1 bash -c '
    source "$1"
    run_root true
  ' _ "$PROJECT_ROOT/scripts/unix/lib/common.sh"

  [ "$status" -eq 0 ]
  [ "$(cat "$args_file")" = '-n true' ]
}
