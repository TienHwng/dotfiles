#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=0
TIMER=dots-sync.timer

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/setup-sync.sh [--dry-run]

Enables the systemd user timer dots-sync.timer (rendered by the apply step into
~/.config/systemd/user): at login and every 6 hours it runs `dots sync --check --notify`,
which only notifies about new commits.
EOF
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --non-interactive) shift ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

export DRY_RUN

if ! has systemctl || ! systemctl --user show-environment >/dev/null 2>&1; then
  log_warn 'No systemd user manager here; the repository check timer is not enabled.'
  exit 0
fi

unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$TIMER"
if [[ ! -e "$unit" && "$DRY_RUN" == '0' ]]; then
  die "$unit is missing; run the apply step first."
fi

if [[ "$(systemctl --user is-enabled "$TIMER" 2>/dev/null || true)" == 'enabled' ]]; then
  log_success "$TIMER is already enabled"
  exit 0
fi

run_or_print systemctl --user daemon-reload
run_or_print systemctl --user enable --now "$TIMER"
[[ "$DRY_RUN" == '1' ]] && exit 0
log_success "$TIMER enabled: checks the repository at login and every 6 hours"
