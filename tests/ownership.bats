#!/usr/bin/env bats

load test_helper

setup() {
  # promptStringOnce prefers values already in the real local chezmoi config
  setup_isolated_home
}

@test "chezmoi templates are the only Git and SSH configuration writers" {
  run grep -nE 'run_or_print git config|ssh_config=|sshConfigPath|FilePath .git.*ArgumentList.*config' \
    "$PROJECT_ROOT/scripts/unix/setup-git.sh" \
    "$PROJECT_ROOT/scripts/unix/setup-accounts.sh" \
    "$PROJECT_ROOT/scripts/windows/setup-git.ps1" \
    "$PROJECT_ROOT/scripts/windows/setup-accounts.ps1"

  [ "$status" -eq 1 ]
  [ -f "$PROJECT_ROOT/home/dot_gitconfig.tmpl" ]
  [ -f "$PROJECT_ROOT/home/dot_ssh/private_config.tmpl" ]
}

@test "bootstrap automation does not apply protected root source state" {
  # Scripts may name the system config file (backup copies it, doctor checks it exists)
  # but must never run chezmoi against the system instance or the root/ source.
  run grep -rnE 'root\.toml|sourceDir.*root|--(config|source)[= ][^[:space:]]*(chezmoi-root|/root([^[:alnum:]_]|$))|(^|[^[:alnum:]_-])cmr([^[:alnum:]_]|$)' \
    "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/.github/workflows"

  [ "$status" -eq 1 ]
}

@test "chezmoi config template records machine-specific identity data" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run chezmoi --source "$PROJECT_ROOT" execute-template --init \
    --promptString 'Git user name=Test User,Git email=test@example.test,GitHub username (optional)=tester,SSH key email=test@example.test' \
    <"$PROJECT_ROOT/home/.chezmoi.toml.tmpl"

  [ "$status" -eq 0 ]
  [[ "$output" == *'gitName = "Test User"'* ]]
  [[ "$output" == *'gitEmail = "test@example.test"'* ]]
  [[ "$output" == *'githubUsername = "tester"'* ]]
  [[ "$output" == *'sshEmail = "test@example.test"'* ]]
}

@test "Git and SSH templates render from machine data" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  data='{"gitName":"Test User","gitEmail":"test@example.test","githubUsername":"tester","sshEmail":"test@example.test"}'

  run chezmoi --source "$PROJECT_ROOT" --override-data "$data" execute-template <"$PROJECT_ROOT/home/dot_gitconfig.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'name = Test User'* ]]
  [[ "$output" == *'email = test@example.test'* ]]

  # Bitwarden agent (default): no key file, Linux points ssh at the agent socket
  run chezmoi --source "$PROJECT_ROOT" --override-data "$data" execute-template <"$PROJECT_ROOT/home/dot_ssh/private_config.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Host github.com'* ]]
  [[ "$output" == *'IdentityAgent ~/.bitwarden-ssh-agent.sock'* ]]
  [[ "$output" != *'IdentityFile'* ]]

  # Windows: Bitwarden answers on the default OpenSSH agent pipe
  run chezmoi --source "$PROJECT_ROOT" --override-data '{"chezmoi":{"os":"windows"}}' \
    execute-template <"$PROJECT_ROOT/home/dot_ssh/private_config.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" != *'IdentityAgent'* ]]
  [[ "$output" != *'IdentityFile'* ]]

  # Key file mode for headless machines
  run chezmoi --source "$PROJECT_ROOT" --override-data '{"accounts":{"ssh":{"agent":"file"}}}' \
    execute-template <"$PROJECT_ROOT/home/dot_ssh/private_config.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'IdentityFile ~/.ssh/id_ed25519'* ]]
  [[ "$output" != *'IdentityAgent'* ]]
}
