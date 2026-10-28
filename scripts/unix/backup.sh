#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DESTINATION="${DOTFILES_BACKUP_DIR:-$HOME/dotfiles-backups}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/backup.sh [--destination DIR] [--dry-run]

Saves a tarball of the repository working tree (including uncommitted work)
plus the untracked local chezmoi configs (user and system instance). Choose a
destination that survives an OS reinstall: an external drive or a cloud folder.
EOF
}

# A backup on the disk that holds the running OS does not survive a reinstall
warn_if_same_disk() {
  local probe="$1"

  while [[ ! -e "$probe" ]]; do
    probe="$(dirname "$probe")"
  done
  if [[ "$(df -P "$probe" | awk 'NR == 2 { print $1 }')" == "$(df -P / | awk 'NR == 2 { print $1 }')" ]]; then
    log_warn "$1 is on the same disk as the running OS; copy the backup to an external drive or cloud folder before reinstalling."
  fi
}

while (($#)); do
  case "$1" in
    --destination)
      [[ $# -ge 2 ]] || die '--destination requires a value'
      DESTINATION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

has chezmoi || die 'chezmoi is required.'
source_dir="$(chezmoi source-path)"
config_file="$(chezmoi execute-template '{{ .chezmoi.configFile }}')"
repo_dir="$source_dir"

while [[ "$repo_dir" != '/' && ! -d "$repo_dir/.git" ]]; do
  repo_dir="$(dirname "$repo_dir")"
done
[[ -d "$repo_dir/.git" ]] || repo_dir="$source_dir"

system_config_file="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi-root/chezmoi.toml"
timestamp="$(date '+%Y%m%d-%H%M%S')"
backup_dir="$DESTINATION/dotfiles-$timestamp"
warn_if_same_disk "$DESTINATION"

if [[ "$DRY_RUN" == '1' ]]; then
  printf '+ mkdir -p %q\n' "$backup_dir"
  printf '+ tar -czf %q -C %q %q\n' "$backup_dir/repository.tar.gz" "$(dirname "$repo_dir")" "$(basename "$repo_dir")"
  [[ -f "$config_file" ]] && printf '+ cp -p %q %q\n' "$config_file" "$backup_dir/"
  [[ -f "$system_config_file" ]] && printf '+ cp -p %q %q\n' "$system_config_file" "$backup_dir/chezmoi-system.toml"
  exit 0
fi

mkdir -p "$backup_dir"
log_step 'Backing up the dotfiles repository...'
tar -czf "$backup_dir/repository.tar.gz" -C "$(dirname "$repo_dir")" "$(basename "$repo_dir")"

if [[ -f "$config_file" ]]; then
  log_step 'Backing up machine-specific chezmoi configuration...'
  cp -p "$config_file" "$backup_dir/"
fi

if [[ -f "$system_config_file" ]]; then
  log_step 'Backing up the system instance chezmoi configuration...'
  cp -p "$system_config_file" "$backup_dir/chezmoi-system.toml"
fi

if has git && [[ -d "$repo_dir/.git" ]]; then
  git -C "$repo_dir" status --short >"$backup_dir/git-status.txt"
  git -C "$repo_dir" log -1 --oneline >"$backup_dir/git-head.txt"
fi

cat >"$backup_dir/RESTORE.txt" <<EOF
Created: $(date -Iseconds)
Source state: $source_dir
Repository: $repo_dir
Chezmoi config: $config_file
System chezmoi config: $system_config_file (saved as chezmoi-system.toml)

Extract repository.tar.gz into a temporary directory first. Review its
contents and copy only the files you need; do not overwrite an active source
state blindly.
EOF

log_success "Backup created at $backup_dir"
