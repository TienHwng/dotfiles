#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/unix/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=0
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
BRANCH=main

usage() {
  cat <<'EOF'
Usage:
  ./scripts/unix/capture.sh [--dry-run]

Lists what changed on this machine but not in the repository, lets you pick items, writes
them back into the repository, then shows the diff, asks for a message, commits to main
and pushes:
  file      a file changed in the repository (on Linux dotfiles are symlinks into it)
  re-add    a dotfile chezmoi wrote as a copy (templates are listed for a manual edit)
  kde       a KDE key whose value differs from home/.chezmoidata/kde.yaml
  packages  installed packages that are not in the manifest (a second picker)

--dry-run lists the items and changes nothing.
EOF
}

ROOT_DIR="$(repo_root)"
KDE_YAML="$ROOT_DIR/home/.chezmoidata/kde.yaml"
PACKAGES_YAML="$ROOT_DIR/home/.chezmoidata/packages.yaml"
SEP=$'\x1f'

# One item per line: kind<TAB>payload<TAB>label
items=()
templates=()

use_gum() {
  [[ -z "${DOTS_NO_GUM:-}" && -t 0 && -t 1 ]] && has gum
}

repo_git() {
  git -C "$ROOT_DIR" "$@"
}

collect_repo_files() {
  local line path
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line:3}"
    path="${path##* -> }"
    items+=("file"$'\t'"$path"$'\t'"file      ${line:0:2} $path")
  done < <(repo_git status --porcelain=v1 --untracked-files=all)
}

# Targets edited by hand since chezmoi wrote them (first status column)
collect_chezmoi_drift() {
  local line target source
  has chezmoi || return 0
  while IFS= read -r line; do
    [[ "${line:0:1}" == 'M' ]] || continue
    target="$HOME/${line:3}"
    source="$(chezmoi --source "$ROOT_DIR/home" source-path "$target" 2>/dev/null || true)"
    [[ -n "$source" ]] || continue
    if [[ "$source" == *.tmpl ]]; then
      templates+=("$target (${source#"$ROOT_DIR/"})")
    else
      items+=("re-add"$'\t'"$target"$'\t'"re-add    ~/${line:3}")
    fi
  done < <(chezmoi --source "$ROOT_DIR/home" status --exclude externals,scripts 2>/dev/null || true)
}

collect_kde_keys() {
  local file groups key value current
  local -a group_args group_list
  has kreadconfig6 && has chezmoi || return 0
  while IFS=$'\t' read -r file groups key value; do
    [[ -n "$file" ]] || continue
    group_args=()
    IFS="$SEP" read -r -a group_list <<<"$groups"
    for group in "${group_list[@]}"; do
      group_args+=(--group "$group")
    done
    current="$(kreadconfig6 --file "$file" "${group_args[@]}" --key "$key")"
    [[ -n "$current" && "$current" != "$value" ]] || continue
    items+=("kde"$'\t'"$file$SEP$groups$SEP$key$SEP$current"$'\t'"kde       $file [${groups//$SEP/][}] $key: $value -> $current")
  done < <(chezmoi --source "$ROOT_DIR" execute-template <"$ROOT_DIR/scripts/kde-settings.tmpl")
}

collect_packages() {
  local count
  [[ "$(detect_platform)" =~ ^(arch|apt)$ ]] && has chezmoi || return 0
  count="$("$SCRIPT_DIR/install-packages.sh" --extra | grep -c . || true)"
  ((count > 0)) || return 0
  items+=("packages"$'\t'"-"$'\t'"packages  pick from $count installed package(s) not in the manifest")
}

# Prints the chosen lines of stdin; $1 is the header
pick_lines() {
  local header="$1" answer index
  local -a lines

  mapfile -t lines
  ((${#lines[@]})) || return 0
  if use_gum; then
    printf '%s\n' "${lines[@]}" | gum filter --no-limit --header "$header" || true
    return 0
  fi

  printf '%s\n' "$header" >&2
  for index in "${!lines[@]}"; do
    printf '  %3d  %s\n' "$((index + 1))" "${lines[$index]}" >&2
  done
  read -r -p 'Numbers to capture (e.g. 1 3, "all"; empty for none): ' answer <&3 || answer=''
  if [[ "$answer" == 'all' ]]; then
    printf '%s\n' "${lines[@]}"
    return 0
  fi
  for index in $answer; do
    if [[ "$index" =~ ^[0-9]+$ ]] && ((index >= 1 && index <= ${#lines[@]})); then
      printf '%s\n' "${lines[$((index - 1))]}"
    fi
  done
}

# Sets a KDE key's value in kde.yaml: the entry under kde.machines.<this host> when there is
# one (it replaces the shared entry there), else the shared entry. Entries are one-line flow
# mappings: { file: F, group: [G, ...], key: K, value: V }.
set_kde_value() {
  local file="$1" groups="$2" key="$3" value="$4" host
  host="$(chezmoi --source "$ROOT_DIR/home" execute-template '{{ .chezmoi.hostname }}')"
  value="${value//\\/\\\\}"
  value="\"${value//\"/\\\"}\""

  # ENVIRON, not -v: awk would turn the backslashes of the quoted value into escapes
  F="$file" G="$groups" K="$key" V="$value" HOST="$host" SEP="$SEP" awk '
    BEGIN { F = ENVIRON["F"]; G = ENVIRON["G"]; K = ENVIRON["K"]; V = ENVIRON["V"]; HOST = ENVIRON["HOST"]; SEP = ENVIRON["SEP"] }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function unquote(s) {
      s = trim(s)
      if (s ~ /^".*"$/ || s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
      return s
    }
    # Line number of the matching entry, or 0
    function entry(line,   p1, p2, p3, p4, n, i, parts, joined) {
      p1 = index(line, "file:"); p2 = index(line, ", group: ["); p3 = index(line, "], key:"); p4 = index(line, ", value:")
      if (!(p1 && p2 && p3 && p4)) return 0
      if (trim(substr(line, p1 + 5, p2 - p1 - 5)) != F) return 0
      if (trim(substr(line, p3 + 7, p4 - p3 - 7)) != K) return 0
      n = split(substr(line, p2 + 10, p3 - p2 - 10), parts, ",")
      joined = ""
      for (i = 1; i <= n; i++) joined = joined (i > 1 ? SEP : "") unquote(parts[i])
      return joined == G
    }
    NR == FNR {
      if ($0 ~ /^  machines:/) machines = 1
      else if ($0 ~ /^  [A-Za-z]/) machines = 0
      if (machines && $0 ~ /^    [A-Za-z0-9_.-]+:[ \t]*$/) { host = trim($0); sub(/:.*/, "", host) }
      if (entry($0)) {
        if (machines && host == HOST) mine = FNR
        else if (!machines) shared = FNR
      }
      next
    }
    FNR == 1 { target = mine ? mine : shared; if (!target) exit 1 }
    FNR == target { print substr($0, 1, index($0, ", value:") - 1) ", value: " V " }"; next }
    { print }
  ' "$KDE_YAML" "$KDE_YAML" >"$KDE_YAML.new" || {
    rm -f "$KDE_YAML.new"
    die "No kde.yaml entry for $file $key"
  }
  mv "$KDE_YAML.new" "$KDE_YAML"
}

# Appends packages to the platform's list in packages.yaml, after its last item
add_packages() {
  local list
  list="$(detect_platform)"
  awk -v LIST="$list" -v NAMES="$(printf '%s\n' "$@")" '
    { lines[NR] = $0 }
    $0 ~ "^  " LIST ":" { inside = 1; next }
    inside && /^  [A-Za-z]/ { inside = 0 }
    inside && /^    - / { last = NR }
    END {
      if (!last) exit 1
      n = split(NAMES, names, "\n")
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (i == last) for (j = 1; j <= n; j++) if (names[j] != "") print "    - " names[j]
      }
    }
  ' "$PACKAGES_YAML" >"$PACKAGES_YAML.new" || {
    rm -f "$PACKAGES_YAML.new"
    die "No '$list:' list with items in packages.yaml"
  }
  mv "$PACKAGES_YAML.new" "$PACKAGES_YAML"
}

capture_item() {
  local kind="$1" payload="$2" source
  local -a parts

  case "$kind" in
    file) repo_git add -A -- "$payload" ;;
    re-add)
      chezmoi --source "$ROOT_DIR/home" re-add "$payload"
      source="$(chezmoi --source "$ROOT_DIR/home" source-path "$payload")"
      repo_git add -A -- "$source"
      ;;
    kde)
      IFS="$SEP" read -r -a parts <<<"$payload"
      # file, groups..., key, value: the groups sit between the first and the last two
      set_kde_value "${parts[0]}" "$(
        IFS="$SEP"
        printf '%s' "${parts[*]:1:${#parts[@]}-3}"
      )" "${parts[-2]}" "${parts[-1]}"
      repo_git add -- "$KDE_YAML"
      ;;
    packages)
      local -a chosen
      mapfile -t chosen < <("$SCRIPT_DIR/install-packages.sh" --extra | pick_lines 'Packages to add to the manifest')
      ((${#chosen[@]})) || return 0
      add_packages "${chosen[@]}"
      repo_git add -- "$PACKAGES_YAML"
      ;;
  esac
}

commit_and_push() {
  local message default answer
  if repo_git diff --cached --quiet; then
    log_warn 'Nothing selected; nothing committed.'
    return 0
  fi

  repo_git --no-pager diff --cached --stat
  repo_git --no-pager diff --cached
  default="Capture local changes from $(uname -n)"
  if use_gum; then
    message="$(gum input --header 'Commit message' --value "$default")" || message=''
  else
    read -r -p "Commit message [$default]: " answer <&3 || answer=''
    message="${answer:-$default}"
  fi
  if [[ -z "$message" ]] || ! confirm "Commit and push to origin/$BRANCH?" yes <&3; then
    repo_git reset --quiet
    log_warn 'Unstaged everything; your edits stay in the working tree.'
    return 0
  fi
  repo_git commit --quiet -m "$message"
  repo_git push --quiet origin "$BRANCH"
  log_success "Committed and pushed to origin/$BRANCH: $message"
}

main() {
  local label item kind payload
  local -a chosen

  while (($#)); do
    case "$1" in
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

  collect_repo_files
  collect_chezmoi_drift
  collect_kde_keys
  collect_packages

  if ((${#templates[@]})); then
    log_warn 'Templates changed by hand; edit their source and run dots capture again:'
    printf '  %s\n' "${templates[@]}" >&2
  fi
  if ((${#items[@]} == 0)); then
    log_success 'Nothing to capture: this machine matches the repository'
    exit 0
  fi

  if [[ "$DRY_RUN" == '1' ]]; then
    log_step "${#items[@]} item(s) to capture:"
    printf '%s\n' "${items[@]}" | cut -f3 | sed 's/^/  /'
    exit 0
  fi
  [[ "$NON_INTERACTIVE" == '1' ]] && die 'dots capture asks what to keep; it never runs non-interactively.'
  [[ "$(repo_git branch --show-current)" == "$BRANCH" ]] \
    || die "Captures commit to $BRANCH; switch the repository to it first (git -C $ROOT_DIR switch $BRANCH)."
  repo_git diff --cached --quiet || die 'The repository already has staged changes; commit or unstage them first.'
  # Answers come from the terminal: stdin carries the lists to the pickers (DOTS_TTY for tests)
  exec 3<"${DOTS_TTY:-/dev/tty}"

  mapfile -t chosen < <(printf '%s\n' "${items[@]}" | cut -f3 | pick_lines 'Changes to keep in the repository')
  for label in "${chosen[@]}"; do
    for item in "${items[@]}"; do
      [[ "${item##*$'\t'}" == "$label" ]] || continue
      IFS=$'\t' read -r kind payload _ <<<"$item"
      capture_item "$kind" "$payload"
    done
  done

  commit_and_push
}

# Sourcing (Bats) loads the functions without running a capture
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
