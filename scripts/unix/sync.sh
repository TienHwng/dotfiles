#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

NOTIFY=0
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dots"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/sync.sh --check [--notify]

Fetches the repository and prints how many commits this machine is behind its upstream.
Never pulls or applies anything.

--notify   Also show a desktop notification with a "Sync now" button when there are new
           commits (once per upstream commit). The button opens a terminal running dots sync.
           Used by the systemd user timer dots-sync.timer.
EOF
}

while (($#)); do
  case "$1" in
    --check) shift ;;
    --notify)
      NOTIFY=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

ROOT_DIR="$(repo_root)"

# Never prompt: the timer runs without a terminal
fetch_upstream() {
  GIT_TERMINAL_PROMPT=0 timeout 60 git -C "$ROOT_DIR" fetch --quiet
}

# A terminal for the "Sync now" button: $TERMINAL, then kitty, then konsole
open_sync_terminal() {
  local dots="$SCRIPT_DIR/dots"
  if [[ -n "${TERMINAL:-}" ]] && has "$TERMINAL"; then
    "$TERMINAL" -e "$dots" sync &
  elif has kitty; then
    kitty --hold "$dots" sync &
  elif has konsole; then
    konsole --hold -e "$dots" sync &
  else
    log_warn 'No terminal found (set TERMINAL); run dots sync yourself.'
    return 0
  fi
  disown
}

notify_behind() {
  local behind="$1" upstream_sha="$2" stamp="$STATE_DIR/notified" choice

  if [[ -f "$stamp" && "$(<"$stamp")" == "$upstream_sha" ]]; then
    return 0
  fi
  if ! has notify-send; then
    log_warn 'notify-send is missing (libnotify); no notification shown.'
    return 0
  fi
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$upstream_sha" >"$stamp"

  # --action waits until the notification is clicked or closed and prints the chosen action
  choice="$(notify-send --app-name=dots --icon=emblem-synchronizing \
    --action=sync='Sync now' \
    'Dotfiles repository changed' \
    "$behind new commit(s) on $(git -C "$ROOT_DIR" rev-parse --abbrev-ref '@{upstream}'). Review and apply them with dots sync." \
    || true)"
  if [[ "$choice" == 'sync' ]]; then
    open_sync_terminal
  fi
}

if ! git -C "$ROOT_DIR" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  die "The current branch of $ROOT_DIR has no upstream; nothing to check."
fi
if ! fetch_upstream; then
  log_warn 'git fetch failed (offline?); the count below uses the last fetch.'
fi

behind="$(git -C "$ROOT_DIR" rev-list --count 'HEAD..@{upstream}')"
ahead="$(git -C "$ROOT_DIR" rev-list --count '@{upstream}..HEAD')"
printf 'behind %s, ahead %s\n' "$behind" "$ahead"

if [[ "$NOTIFY" == '1' && "$behind" -gt 0 ]]; then
  notify_behind "$behind" "$(git -C "$ROOT_DIR" rev-parse '@{upstream}')"
fi
