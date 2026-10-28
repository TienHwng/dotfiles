#!/usr/bin/env bats

load test_helper

setup() {
  setup_isolated_home
  WALLPAPER="$PROJECT_ROOT/scripts/unix/setup-wallpaper.sh"
  mock_bin="$BATS_TEST_TMPDIR/bin"
  plasma_marker="$BATS_TEST_TMPDIR/plasma-executed"
  mkdir -p "$mock_bin"
  printf '#!/usr/bin/env bash\ntouch %q\n' "$plasma_marker" >"$mock_bin/plasma-apply-wallpaperimage"
  chmod +x "$mock_bin/plasma-apply-wallpaperimage"
}

@test "wallpaper dry-run prints the clone and the KDE command without running them" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run env PATH="$mock_bin:$PATH" "$WALLPAPER" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'Cloning wallpapers from https://github.com/TienHwng/wallpapers.git'* ]]
  [[ "$output" == *"apply --verbose $HOME/Pictures/wallpaper"* ]]
  [[ "$output" == *"plasma-apply-wallpaperimage $HOME/Pictures/wallpaper/space2.jpg"* ]]
  [ ! -e "$HOME/Pictures" ]
  [ ! -e "$plasma_marker" ]
}

@test "wallpaper step refuses a directory that is a clone of another repository" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  git init -q "$HOME/Pictures/wallpaper"
  git -C "$HOME/Pictures/wallpaper" remote add origin https://github.com/someone/wallpaper.git

  run env PATH="$mock_bin:$PATH" "$WALLPAPER" --dry-run

  [ "$status" -ne 0 ]
  [[ "$output" == *'is not a clone of https://github.com/TienHwng/wallpapers.git'* ]]
  [[ "$output" == *'someone/wallpaper.git'* ]]
}

@test "wallpaper step updates its own clone" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'
  git init -q "$HOME/Pictures/wallpaper"
  git -C "$HOME/Pictures/wallpaper" remote add origin https://github.com/TienHwng/wallpapers

  run env PATH="$mock_bin:$PATH" "$WALLPAPER" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updating wallpapers in $HOME/Pictures/wallpaper"* ]]
}

@test "the wallpaper external renders only when the feature is on" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run chezmoi --source "$PROJECT_ROOT/home" execute-template <"$PROJECT_ROOT/home/.chezmoiexternal.toml.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'["Pictures/wallpaper"]'* ]]
  [[ "$output" == *'type = "git-repo"'* ]]

  run chezmoi --source "$PROJECT_ROOT/home" --override-data '{"features":{"wallpapers":false}}' \
    execute-template <"$PROJECT_ROOT/home/.chezmoiexternal.toml.tmpl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the git template owns the Git LFS filter" {
  command -v chezmoi >/dev/null || skip 'chezmoi is not installed'

  run chezmoi --source "$PROJECT_ROOT/home" execute-template <"$PROJECT_ROOT/home/dot_gitconfig.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[filter "lfs"]'* ]]
  [[ "$output" == *'process = git-lfs filter-process'* ]]
}
