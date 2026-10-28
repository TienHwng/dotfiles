#!/usr/bin/env bats

load test_helper

setup() {
  setup_isolated_home
}

managed_for_os() {
  chezmoi --source "$PROJECT_ROOT" --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" \
    managed --include=files,symlinks
}

@test "Linux-only targets are never managed on Windows" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run managed_for_os windows
  [ "$status" -eq 0 ]
  [[ "$output" == *'.config/nvim/init.lua'* ]]
  [[ "$output" == *'.gitconfig'* ]]

  local linux_only
  for linux_only in .zshrc .oh-my-zsh .config/kitty .config/hypr .config/kwinrc \
    .config/kdeglobals .config/chezmoi-root .local/share/plasma .local/bin/dots; do
    if [[ "$output" == *"$linux_only"* ]]; then
      echo "Linux-only target managed on Windows: $linux_only"
      return 1
    fi
  done
}

@test "Linux keeps its shell, desktop, and system instance targets" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run managed_for_os linux
  [ "$status" -eq 0 ]
  [[ "$output" == *'.zshrc'* ]]
  [[ "$output" == *'.config/kwinrc'* ]]
  [[ "$output" == *'.config/chezmoi-root/chezmoi.toml'* ]]
  [[ "$output" == *'.config/nvim/init.lua'* ]]
  [[ "$output" == *'.local/bin/dots'* ]]
}
