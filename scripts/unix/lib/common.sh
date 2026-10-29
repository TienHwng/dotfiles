#!/usr/bin/env bash

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_RESET=$'\033[0m'
else
  C_CYAN='' C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''
fi

log_step() { printf '%s→%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
log_success() { printf '%s✔%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s✘%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die() {
  log_error "$*"
  exit 1
}
has() { command -v "$1" >/dev/null 2>&1; }

require_command() {
  local command_name="$1" message="${2:-$1 is required.}"

  has "$command_name" || die "$message"
}

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
    if [[ "${NON_INTERACTIVE:-0}" == '1' ]]; then
      sudo -n "$@"
    else
      sudo "$@"
    fi
  elif has doas; then
    if [[ "${NON_INTERACTIVE:-0}" == '1' ]]; then
      doas -n "$@"
    else
      doas "$@"
    fi
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
      if [[ "${NON_INTERACTIVE:-0}" == '1' ]]; then
        print_command sudo -n "$@"
      else
        print_command sudo "$@"
      fi
    elif has doas; then
      if [[ "${NON_INTERACTIVE:-0}" == '1' ]]; then
        print_command doas -n "$@"
      else
        print_command doas "$@"
      fi
    else
      print_command sudo "$@"
    fi
  else
    run_root "$@"
  fi
}

detect_platform() {
  local kernel

  if [[ -n "${DOTFILES_PLATFORM:-}" ]]; then
    case "$DOTFILES_PLATFORM" in
      arch | apt | brew | unknown)
        printf '%s\n' "$DOTFILES_PLATFORM"
        return
        ;;
      *) die "Invalid DOTFILES_PLATFORM override: $DOTFILES_PLATFORM" ;;
    esac
  fi

  kernel="$(uname -s 2>/dev/null || true)"

  if [[ "$kernel" == 'Darwin' ]]; then
    printf 'brew\n'
  elif [[ -f /etc/arch-release ]] || has pacman; then
    printf 'arch\n'
  elif has apt-get; then
    printf 'apt\n'
  else
    printf 'unknown\n'
  fi
}

# Print one package per line from a manifest list (arch, apt, brew, brewCask,
# winget, scoop, nerdFonts) in home/.chezmoidata/packages.yaml.
# The firmware's manufacturer ("ASUSTeK COMPUTER INC."); empty when unknown
machine_vendor() {
  cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true
}

manifest_list() {
  local list="$1" root output vendor

  root="$(repo_root)"
  # A set DOTFILES_VENDOR, even empty, overrides detection (tests)
  vendor="${DOTFILES_VENDOR-$(machine_vendor)}"
  output="$(DOTFILES_PACKAGE_LIST="$list" DOTFILES_VENDOR="$vendor" chezmoi --source "$root" \
    execute-template <"$root/scripts/package-list.tmpl")" || return
  [[ -n "$output" ]] || return 0
  awk 'NF && !seen[$0]++' <<<"$output"
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
