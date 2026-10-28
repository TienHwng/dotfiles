#!/usr/bin/env bats
# shellcheck disable=SC2016

load test_helper

setup() {
  setup_isolated_home
}

manifest_list() {
  bash -c 'source "$1"; manifest_list "$2"' _ "$PROJECT_ROOT/scripts/unix/lib/common.sh" "$1"
}

@test "every mapped manifest entry has a unique name and at least one package" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run chezmoi --source "$PROJECT_ROOT" execute-template \
    '{{ range .packages.mapped }}{{ .name }}|{{ len (omit . "name" "gui") }}{{ "\n" }}{{ end }}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  local line
  while IFS= read -r line; do
    if [[ "$line" == '|'* || "$line" == *'|0' ]]; then
      echo "Invalid mapped entry: $line"
      return 1
    fi
  done <<<"$output"

  duplicates="$(cut -d'|' -f1 <<<"$output" | sort | uniq -d)"
  [ -z "$duplicates" ]
}

@test "manifest lists combine mapped entries and per-manager lists without duplicates" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run manifest_list arch
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\ngit\n'* || "$output" == $'git\n'* ]]
  [[ "$output" == *'paru'* ]]
  [ -z "$(sort <<<"$output" | uniq -d)" ]

  run manifest_list winget
  [ "$status" -eq 0 ]
  [[ "$output" == *'Git.Git'* ]]
  [[ "$output" == *'Microsoft.PowerShell'* ]]
  [[ "$output" != *'ripgrep'* ]]

  # Windows CLI tools come from Scoop, not WinGet
  run manifest_list scoop
  [ "$status" -eq 0 ]
  [[ "$output" == *'ripgrep'* ]]
  [[ "$output" == *'oh-my-posh'* ]]

  run manifest_list nerdFonts
  [ "$status" -eq 0 ]
  [ "$output" = 'JetBrainsMono' ]
}

@test "headless machines skip GUI entries" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run manifest_list arch
  [[ "$output" == *'wl-clipboard'* ]]

  run env DOTFILES_HEADLESS=1 bash -c 'source "$1"; manifest_list arch' _ \
    "$PROJECT_ROOT/scripts/unix/lib/common.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *'wl-clipboard'* ]]
  [[ "$output" == *'neovim'* ]]
}

@test "an unknown manifest list renders nothing and a missing list name fails" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run manifest_list no-such-list
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash -c 'chezmoi --source "$1" execute-template <"$1/scripts/package-list.tmpl"' _ "$PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *'DOTFILES_PACKAGE_LIST is not set'* ]]
}

@test "package diff reports extra and missing packages without installing" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  mock_bin="$BATS_TEST_TMPDIR/diff-bin"
  marker="$BATS_TEST_TMPDIR/paru-executed"
  mkdir -p "$mock_bin"
  cat >"$mock_bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -Qqe) printf '%s\n' git neovim leftover-app ;;
  -Qq) printf '%s\n' git neovim leftover-app fzf ;;
esac
EOF
  printf '#!/usr/bin/env bash\ntouch %q\n' "$marker" >"$mock_bin/paru"
  chmod +x "$mock_bin/pacman" "$mock_bin/paru"

  run env PATH="$mock_bin:$PATH" DOTFILES_PLATFORM=arch \
    "$PROJECT_ROOT/scripts/unix/install-packages.sh" --diff

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  extra_section="$(sed -n '/Explicitly installed/,/In the manifest/p' <<<"$output")"
  missing_section="$(sed -n '/In the manifest but not installed/,$p' <<<"$output")"
  [[ "$extra_section" == *'  leftover-app'* ]]
  [[ "$extra_section" != *'  git'* ]]
  [[ "$missing_section" == *'  paru'* ]]
  [[ "$missing_section" != *'  fzf'* ]]
}

@test "font dry-run reads Nerd Fonts from the manifest" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run "$PROJECT_ROOT/scripts/unix/install-fonts.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'install Nerd Font JetBrainsMono'* ]]
}
