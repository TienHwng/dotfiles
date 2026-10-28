#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-template-test.XXXXXX")"
trap 'rm -rf -- "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/home" "$TMP_ROOT/config" "$TMP_ROOT/cache" "$TMP_ROOT/data"
export HOME="$TMP_ROOT/home"
export XDG_CONFIG_HOME="$TMP_ROOT/config"
export XDG_CACHE_HOME="$TMP_ROOT/cache"
export XDG_DATA_HOME="$TMP_ROOT/data"

command -v chezmoi >/dev/null 2>&1 || {
  printf 'chezmoi is required for template validation.\n' >&2
  exit 1
}

chezmoi execute-template --init \
  --promptString 'Git user name=Test User,Git email=test@example.test,GitHub username (optional)=tester,SSH key email=test@example.test' \
  <"$ROOT_DIR/home/.chezmoi.toml.tmpl" >"$TMP_ROOT/chezmoi.toml"

chezmoi --config "$TMP_ROOT/chezmoi.toml" cat-config >/dev/null

chezmoi \
  --source "$ROOT_DIR/home" \
  --config "$TMP_ROOT/chezmoi-defaults.toml" \
  init --promptDefaults

[[ -z "$(chezmoi --config "$TMP_ROOT/chezmoi-defaults.toml" execute-template '{{ .gitName }}')" ]]
[[ -z "$(chezmoi --config "$TMP_ROOT/chezmoi-defaults.toml" execute-template '{{ .gitEmail }}')" ]]
[[ -z "$(chezmoi --config "$TMP_ROOT/chezmoi-defaults.toml" execute-template '{{ .sshEmail }}')" ]]

data='{"gitName":"Test User","gitEmail":"test@example.test","githubUsername":"tester","sshEmail":"test@example.test","features":{"installFonts":true,"setupShell":true},"accounts":{"ssh":{"agent":"bitwarden","keyType":"ed25519","keyPathArch":"~/.ssh/id_ed25519","keyPathUnix":"~/.ssh/id_ed25519","keyPathWindows":"~/.ssh/id_ed25519"}}}'

chezmoi \
  --source "$ROOT_DIR/home" \
  --destination "$TMP_ROOT/home" \
  --config "$TMP_ROOT/chezmoi.toml" \
  --override-data "$data" \
  apply --dry-run >/dev/null

printf 'Chezmoi templates are valid.\n'
