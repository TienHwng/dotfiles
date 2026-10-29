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
  ./scripts/unix/capture.sh kde --discover

Lists what changed on this machine but not in the repository, lets you pick items, writes
them back into the repository, then shows the diff, asks for a message, commits to main
and pushes:
  file      a file changed in the repository (on Linux dotfiles are symlinks into it)
  re-add    a dotfile chezmoi wrote as a copy (templates are listed for a manual edit)
  kde       a KDE key whose value differs from home/.chezmoidata/kde.yaml
  kde-pkg   a Plasma package from kde.packages whose installed copy changed (Get New, an
            update); the installed copy replaces kde/<path>/<id>
  packages  installed packages that are not in the manifest (a second picker)

--dry-run lists the items and changes nothing.

kde --discover snapshots the KDE config files, waits while you change settings in System
Settings, then offers the keys that changed; the chosen ones are added to kde.yaml for every
machine or only this one (files in kde.discover.ignore are skipped).
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

# Plasma packages (kde.packages) whose installed copy differs from kde/, e.g. after Get New
collect_kde_packages() {
  local type path id source_dir target_dir
  has chezmoi || return 0
  while IFS=$'\t' read -r type path id; do
    [[ -n "$type" ]] || continue
    source_dir="$ROOT_DIR/kde/$path/$id"
    target_dir="${XDG_DATA_HOME:-$HOME/.local/share}/$path/$id"
    # Only a real installed copy can be kept: missing or dangling means the desktop step installs it
    [[ -d "$target_dir" ]] || continue
    [[ -z "$(find "$target_dir" -xtype l -print -quit)" ]] || continue
    diff -rq "$source_dir" "$target_dir" >/dev/null 2>&1 && continue
    items+=("kde-pkg"$'\t'"$path/$id"$'\t'"kde-pkg   $path/$id: keep the installed copy in kde/$path/$id")
  done < <(chezmoi --source "$ROOT_DIR/home" execute-template \
    '{{ range .kde.packages }}{{ .type }}{{ "\t" }}{{ .path }}{{ "\t" }}{{ .id }}{{ "\n" }}{{ end }}' 2>/dev/null || true)
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

# Prints add, uninstall, or skip for the $1 chosen packages
choose_package_action() {
  local answer
  if use_gum; then
    answer="$(gum choose --header "$1 package(s)" 'Add to the manifest' 'Uninstall' 'Skip')" || answer='Skip'
  else
    read -r -p "$1 package(s): [a]dd to the manifest / [u]ninstall / [s]kip: " answer <&3 || answer=''
  fi
  case "${answer,,}" in
    a | add*) printf 'add\n' ;;
    u | uninstall) printf 'uninstall\n' ;;
    *) printf 'skip\n' ;;
  esac
}

# Removes the packages (on Arch with the dependencies nothing else needs); the package
# manager asks before removing anything
uninstall_packages() {
  case "$(detect_platform)" in
    apt) run_root apt-get remove "$@" ;;
    *)
      if has paru; then
        paru -Rns "$@"
      else
        run_root pacman -Rns "$@"
      fi
      ;;
  esac
}

# A YAML flow scalar: plain when safe, else double-quoted
yaml_scalar() {
  local text="$1"
  if [[ "$text" =~ ^[A-Za-z_][A-Za-z0-9_.+\ -]*$ && "$text" != *' ' ]]; then
    printf '%s' "$text"
  else
    text="${text//\\/\\\\}"
    printf '"%s"' "${text//\"/\\\"}"
  fi
}

# One kde.yaml entry line (without indentation) for file, groups (SEP-joined), key, value
kde_entry() {
  local file="$1" groups="$2" key="$3" value="$4" group joined=''
  local -a list
  IFS="$SEP" read -r -a list <<<"$groups"
  for group in "${list[@]}"; do
    joined+="${joined:+, }$(yaml_scalar "$group")"
  done
  value="${value//\\/\\\\}"
  printf -- '- { file: %s, group: [%s], key: %s, value: "%s" }' \
    "$file" "$joined" "$(yaml_scalar "$key")" "${value//\"/\\\"}"
}

# Appends an entry line to kde.settings (HOST empty) or to kde.machines.HOST.settings,
# creating the machine section when it is missing
append_kde_entry() {
  local host="$1" entry="$2"
  HOST="$host" ENTRY="$entry" awk '
    BEGIN { host = ENVIRON["HOST"]; entry = ENVIRON["ENTRY"] }
    { lines[NR] = $0 }
    /^  settings:/ { shared = 1; next }
    /^  machines:/ { shared = 0; machines = NR; mine = 0; next }
    /^  [A-Za-z]/ { shared = 0 }
    shared && /^    - / { last_shared = NR }
    machines && /^    [A-Za-z0-9_.-]+:[ \t]*$/ { mine = ($0 ~ "^    " host ":") }
    machines && mine && /^        - / { last_mine = NR }
    END {
      if (host == "") at = last_shared
      else at = last_mine
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (i == at) print (host == "" ? "    " : "        ") entry
      }
      if (host != "" && !at) {
        if (!machines) print "  machines:"
        print "    " host ":"
        print "      settings:"
        print "        " entry
      }
    }
  ' "$KDE_YAML" >"$KDE_YAML.new"
  mv "$KDE_YAML.new" "$KDE_YAML"
}

# Flat file<TAB>groups<TAB>key<TAB>raw value lines of the KDE config files, minus the files
# kde.discover.ignore names; keys outside a group and localized keys (Name[vi]) are left out
kde_snapshot() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}" file name pattern skip
  local -a ignore
  mapfile -t ignore < <(chezmoi --source "$ROOT_DIR/home" execute-template \
    '{{ range .kde.discover.ignore }}{{ . }}{{ "\n" }}{{ end }}')
  for file in "$dir"/*rc "$dir"/kdeglobals "$dir"/mimeapps.list; do
    [[ -f "$file" ]] || continue
    name="${file##*/}"
    skip=0
    for pattern in "${ignore[@]}"; do
      # shellcheck disable=SC2053 # the ignore entries are globs
      [[ -n "$pattern" && "$name" == $pattern ]] && skip=1
    done
    ((skip)) && continue
    SEP="$SEP" awk -v F="$name" '
      BEGIN { sep = ENVIRON["SEP"] }
      /^[ \t]*(#|$)/ { next }
      /^\[/ { group = $0; sub(/^\[/, "", group); sub(/\][ \t]*$/, "", group); gsub(/\]\[/, sep, group); next }
      {
        i = index($0, "=")
        if (!i || group == "") next
        key = substr($0, 1, i - 1)
        if (key ~ /\[/) next
        print F "\t" group "\t" key "\t" substr($0, i + 1)
      }
    ' "$file"
  done | LC_ALL=C sort
}

# Snapshot, let the person change settings, snapshot again; offer the new or changed keys
discover_kde() {
  local before after host scope line file groups key value old label
  local -a changed labels chosen entries=()
  local -a group_args list

  if ! has kreadconfig6 || ! has chezmoi; then
    die 'Discovering KDE keys needs KDE Plasma 6 (kreadconfig6) and chezmoi.'
  fi
  before="$(mktemp)"
  after="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$before' '$after'" RETURN

  kde_snapshot >"$before"
  log_step 'Change the settings you want to keep in System Settings now, then press Enter here.'
  read -r _ <&3 || true
  kde_snapshot >"$after"

  mapfile -t changed < <(LC_ALL=C comm -13 "$before" "$after")
  for line in "${changed[@]}"; do
    IFS=$'\t' read -r file groups key _ <<<"$line"
    group_args=()
    IFS="$SEP" read -r -a list <<<"$groups"
    for group in "${list[@]}"; do
      group_args+=(--group "$group")
    done
    # kreadconfig6 decodes KConfig escapes that the raw file keeps
    value="$(kreadconfig6 --file "$file" "${group_args[@]}" --key "$key")"
    old="$(awk -F'\t' -v f="$file" -v g="$groups" -v k="$key" '$1 == f && $2 == g && $3 == k { print $4; exit }' "$before")"
    label="$file [${groups//$SEP/][}] $key: ${old:-<unset>} -> $value"
    labels+=("$label")
    entries+=("$label"$'\t'"$(kde_entry "$file" "$groups" "$key" "$value")")
  done

  if ((${#labels[@]} == 0)); then
    log_success 'No KDE key changed'
    return 0
  fi
  mapfile -t chosen < <(printf '%s\n' "${labels[@]}" | pick_lines 'KDE keys to keep in kde.yaml')
  ((${#chosen[@]})) || return 0

  host="$(chezmoi --source "$ROOT_DIR/home" execute-template '{{ .chezmoi.hostname }}')"
  if use_gum; then
    scope="$(gum choose --header 'Keep these keys for' 'Every machine' "Only $host")" || scope=''
  else
    read -r -p "Keep these keys for [e]very machine or [o]nly $host? " scope <&3 || scope=''
  fi
  case "${scope,,}" in
    e | every*) host='' ;;
    o | only*) ;;
    *)
      log_warn 'Nothing written'
      return 0
      ;;
  esac

  for label in "${chosen[@]}"; do
    for line in "${entries[@]}"; do
      [[ "${line%%$'\t'*}" == "$label" ]] && append_kde_entry "$host" "${line#*$'\t'}"
    done
  done
  repo_git add -- "$KDE_YAML"
}

capture_item() {
  local kind="$1" payload="$2" source
  local -a parts

  case "$kind" in
    file) repo_git add -A -- "$payload" ;;
    kde-pkg)
      # Copy the installed package (following links) over the repository copy
      rm -rf -- "${ROOT_DIR:?}/kde/$payload"
      mkdir -p -- "$(dirname -- "$ROOT_DIR/kde/$payload")"
      cp -rL -- "${XDG_DATA_HOME:-$HOME/.local/share}/$payload" "$ROOT_DIR/kde/$payload"
      repo_git add -A -- "kde/$payload"
      ;;
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
      mapfile -t chosen < <("$SCRIPT_DIR/install-packages.sh" --extra | pick_lines 'Packages outside the manifest')
      ((${#chosen[@]})) || return 0
      case "$(choose_package_action "${#chosen[@]}")" in
        add)
          add_packages "${chosen[@]}"
          repo_git add -- "$PACKAGES_YAML"
          ;;
        uninstall) uninstall_packages "${chosen[@]}" ;;
        *) log_warn 'Packages left alone' ;;
      esac
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

check_repo_ready() {
  [[ "$(repo_git branch --show-current)" == "$BRANCH" ]] \
    || die "Captures commit to $BRANCH; switch the repository to it first (git -C $ROOT_DIR switch $BRANCH)."
  repo_git diff --cached --quiet || die 'The repository already has staged changes; commit or unstage them first.'
}

main() {
  local label item kind payload
  local -a chosen

  local discover=0
  while (($#)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      kde)
        [[ "${2:-}" == '--discover' ]] || die 'Usage: dots capture kde --discover'
        discover=1
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  if ((discover)); then
    [[ "$NON_INTERACTIVE" == '1' ]] && die 'dots capture asks what to keep; it never runs non-interactively.'
    check_repo_ready
    exec 3<"${DOTS_TTY:-/dev/tty}"
    discover_kde
    commit_and_push
    return 0
  fi

  collect_repo_files
  collect_chezmoi_drift
  collect_kde_keys
  collect_kde_packages
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
  check_repo_ready
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
