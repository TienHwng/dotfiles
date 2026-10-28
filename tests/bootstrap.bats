#!/usr/bin/env bats

load test_helper

setup() {
  setup_isolated_home
}

@test "repository shorthand resolves deterministically" {
  run bash -c 'source "$1"; normalize_repo TienHwng' _ \
    "$PROJECT_ROOT/scripts/unix/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ "$output" = 'https://github.com/TienHwng/dotfiles.git' ]

  run bash -c 'source "$1"; normalize_repo owner/repository' _ \
    "$PROJECT_ROOT/scripts/unix/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ "$output" = 'https://github.com/owner/repository.git' ]
}

@test "unsupported platform fails before provisioning" {
  run env DOTFILES_PLATFORM=unknown "$PROJECT_ROOT/scripts/unix/bootstrap.sh" \
    --dry-run --non-interactive

  [ "$status" -ne 0 ]
  [[ "$output" == *'Unsupported platform'* ]]
  [ -z "$(find "$HOME" -mindepth 1 -print -quit)" ]
}

@test "Arch prerequisite dry-run reports every missing bootstrap tool" {
  run bash -c '
    source "$1"
    DRY_RUN=1
    NON_INTERACTIVE=1
    has() { return 1; }
    ensure_bootstrap_prerequisites arch
  ' _ "$PROJECT_ROOT/scripts/unix/bootstrap.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'pacman is unavailable'* ]]
  [[ "$output" == *'pacman -S --needed --noconfirm git curl unzip'* ]]
}

@test "bootstrap dry-run does not initialize a repository or modify isolated HOME" {
  before="$(find "$HOME" -mindepth 1 -print | sort)"

  run env DOTFILES_PLATFORM=arch "$PROJECT_ROOT/scripts/unix/bootstrap.sh" \
    --dry-run --non-interactive --skip-packages --skip-git --skip-accounts \
    --skip-fonts --skip-shell

  [ "$status" -eq 0 ]
  after="$(find "$HOME" -mindepth 1 -print | sort)"
  [ "$before" = "$after" ]
  [[ "$output" == *'+ chezmoi init --promptDefaults'* ]]
  [[ "$output" == *'Repository initialization was not executed'* ]]
}

@test "package dry-run never invokes pacman or the AUR helper" {
  marker="$BATS_TEST_TMPDIR/package-command-executed"
  mock_bin="$BATS_TEST_TMPDIR/package-bin"
  mkdir -p "$mock_bin"
  for command_name in pacman paru; do
    printf '#!/usr/bin/env bash\ntouch %q\n' "$marker" >"$mock_bin/$command_name"
    chmod +x "$mock_bin/$command_name"
  done

  run env PATH="$mock_bin:$PATH" DOTFILES_PLATFORM=arch \
    "$PROJECT_ROOT/scripts/unix/install-packages.sh" --dry-run

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  [[ "$output" == *'paru -S --needed --noconfirm'* ]]
}

@test "non-interactive shell setup never invokes chsh" {
  marker="$BATS_TEST_TMPDIR/chsh-executed"
  mock_bin="$BATS_TEST_TMPDIR/shell-bin"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$mock_bin/zsh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$mock_bin/grep"
  printf '#!/usr/bin/env bash\ntouch %q\n' "$marker" >"$mock_bin/chsh"
  chmod +x "$mock_bin/chsh" "$mock_bin/grep" "$mock_bin/zsh"

  run env PATH="$mock_bin:$PATH" SHELL=/bin/false \
    "$PROJECT_ROOT/scripts/unix/setup-shell.sh" zsh --non-interactive

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  [[ "$output" == *'will not invoke chsh'* ]]
}

@test "non-interactive Git setup fails explicitly when machine data is missing" {
  run "$PROJECT_ROOT/scripts/unix/setup-git.sh" --non-interactive

  [ "$status" -ne 0 ]
  [[ "$output" == *'Git identity is incomplete'* ]]
  [ ! -e "$HOME/.gitconfig" ]
}

@test "non-interactive account setup refuses implicit unencrypted key creation" {
  key_path="$HOME/.ssh/id_test"

  run "$PROJECT_ROOT/scripts/unix/setup-accounts.sh" --non-interactive \
    --ssh-email user@example.test --ssh-key-path "$key_path"

  [ "$status" -ne 0 ]
  [[ "$output" == *'Refusing to create an unencrypted SSH key'* ]]
  [ ! -e "$key_path" ]
  [ ! -e "$HOME/.ssh" ]
}

@test "forced non-interactive key replacement also requires explicit opt-in" {
  key_path="$HOME/.ssh/id_test"
  mkdir -p "$(dirname "$key_path")"
  printf '%s\n' 'existing-private-key-placeholder' >"$key_path"

  run "$PROJECT_ROOT/scripts/unix/setup-accounts.sh" --force --non-interactive \
    --ssh-email user@example.test --ssh-key-path "$key_path"

  [ "$status" -ne 0 ]
  [[ "$output" == *'Refusing to create an unencrypted SSH key'* ]]
  [ "$(cat "$key_path")" = 'existing-private-key-placeholder' ]
  [ -z "$(find "$HOME/.ssh" -name 'id_test.bak.*' -print -quit)" ]
}

@test "account dry-run with explicit opt-in does not create files" {
  key_path="$HOME/.ssh/id_test"
  marker="$BATS_TEST_TMPDIR/gh-executed"
  mock_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\ntouch %q\n' "$marker" >"$mock_bin/gh"
  chmod +x "$mock_bin/gh"

  run env PATH="$mock_bin:$PATH" "$PROJECT_ROOT/scripts/unix/setup-accounts.sh" \
    --dry-run --non-interactive --allow-unencrypted-key \
    --ssh-email user@example.test --ssh-key-path "$key_path"

  [ "$status" -eq 0 ]
  [ ! -e "$key_path" ]
  [ ! -e "$HOME/.ssh" ]
  [ ! -e "$marker" ]
  [[ "$output" == *'ssh-keygen'* ]]
}

@test "account onboarding keeps an existing key unchanged across repeated runs" {
  key_path="$HOME/.ssh/id_test"
  mkdir -p "$(dirname "$key_path")"
  printf '%s\n' 'existing-private-key-placeholder' >"$key_path"
  before="$(sha256sum "$key_path")"

  run "$PROJECT_ROOT/scripts/unix/setup-accounts.sh" --non-interactive \
    --ssh-email user@example.test --ssh-key-path "$key_path"
  [ "$status" -eq 0 ]

  run "$PROJECT_ROOT/scripts/unix/setup-accounts.sh" --non-interactive \
    --ssh-email user@example.test --ssh-key-path "$key_path"
  [ "$status" -eq 0 ]

  [ "$before" = "$(sha256sum "$key_path")" ]
  [ ! -e "$HOME/.ssh/config" ]
}

@test "bootstrap.sh downloaded on its own runs until the clone" {
  standalone="$BATS_TEST_TMPDIR/dots-bootstrap.sh"
  cp "$PROJECT_ROOT/scripts/unix/bootstrap.sh" "$standalone"

  run env DOTFILES_PLATFORM=arch bash "$standalone" --dry-run --non-interactive --repo TienHwng

  [ "$status" -ne 0 ]
  [[ "$output" != *'No such file'* ]]
  [[ "$output" == *'+ chezmoi init --promptDefaults https://github.com/TienHwng/dotfiles.git'* ]]
  [[ "$output" == *'Dry-run requires an existing local repository checkout'* ]]
}
