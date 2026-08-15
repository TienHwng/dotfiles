#!/usr/bin/env bash

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_BOLD=$'\033[1m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_RESET=$'\033[0m'
else
  C_BOLD='' C_CYAN='' C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''
fi

log_step()    { printf '%s→%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
log_success() { printf '%s✔%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn()    { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error()   { printf '%s✘%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()         { log_error "$*"; exit 1; }
has()         { command -v "$1" >/dev/null 2>&1; }

repo_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." >/dev/null 2>&1 && pwd
}

confirm() {
  local prompt="${1:-Continue?}" default="${2:-no}" answer=''

  if [[ "${NON_INTERACTIVE:-0}" == '1' ]]; then
    [[ "$default" == 'yes' ]]
    return
  fi

  if [[ "$default" == 'yes' ]]; then
    read -r -p "$prompt [Y/n] " answer
    [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]
  else
    read -r -p "$prompt [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]]
  fi
}

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif has sudo; then
    sudo "$@"
  elif has doas; then
    doas "$@"
  else
    die "Root privileges are required for: $*"
  fi
}

print_command() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run_or_print() {
  if [[ "${DRY_RUN:-0}" == '1' ]]; then
    print_command "$@"
  else
    "$@"
  fi
}

run_root_or_print() {
  if [[ "${DRY_RUN:-0}" == '1' ]]; then
    if [[ "$(id -u)" -eq 0 ]]; then
      print_command "$@"
    elif has sudo; then
      print_command sudo "$@"
    elif has doas; then
      print_command doas "$@"
    else
      print_command sudo "$@"
    fi
  else
    run_root "$@"
  fi
}

detect_platform() {
  local kernel
  kernel="$(uname -s 2>/dev/null || true)"

  if [[ "$kernel" == 'Darwin' ]]; then
    printf 'brew\n'
  elif [[ -f /etc/arch-release ]] || has pacman; then
    printf 'arch\n'
  elif has apt-get; then
    printf 'apt\n'
  elif has dnf; then
    printf 'fedora\n'
  else
    printf 'unknown\n'
  fi
}

read_list_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  sed \
    -e 's/[[:space:]]*#.*$//' \
    -e '/^[[:space:]]*$/d' \
    -e 's/^[[:space:]]*//' \
    -e 's/[[:space:]]*$//' \
    "$file"
}

chezmoi_value() {
  local expression="$1" fallback="${2:-}" value=''

  if has chezmoi; then
    value="$(chezmoi execute-template "{{ $expression }}" 2>/dev/null || true)"
  fi

  if [[ -n "$value" && "$value" != '<no value>' && "$value" != '<nil>' ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}
