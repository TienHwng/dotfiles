PROJECT_ROOT="$(cd -- "$BATS_TEST_DIRNAME/.." && pwd)"
export PROJECT_ROOT

setup_isolated_home() {
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME"
  export HOME="$TEST_HOME"
  export XDG_CONFIG_HOME="$TEST_HOME/.config"
  export XDG_CACHE_HOME="$TEST_HOME/.cache"
  export XDG_DATA_HOME="$TEST_HOME/.local/share"
}
