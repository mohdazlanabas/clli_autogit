#!/usr/bin/env zsh
# check-project-git.zsh
# Scan each immediate subfolder of a main directory and report Git status hygiene.
# Optional --fix mode will:
#   - add 'origin' using --remote-template when missing
#   - set upstream for current branch
#   - push current branch if ahead or not yet on remote
#
# It will NOT:
#   - auto-commit dirty changes
#   - pull/merge/rebase for you
#   - guess remotes without an explicit --remote-template

set -o errexit
set -o nounset
set -o pipefail

autoload -Uz colors && colors

# ---------- Defaults ----------
BASE_DIR="."
DO_FIX=false
REMOTE_TEMPLATE=""     # e.g. git@github.com:youruser/{name}.git
DEFAULT_BRANCH=""      # optional hint, otherwise detect per repo
QUIET=false

# ---------- Arg parsing ----------
usage() {
  cat <<'USAGE'
Usage:
  check-project-git.zsh [OPTIONS] [BASE_DIR]

Options:
  --fix                       Perform safe fixes: add origin (via template), set upstream, push if ahead.
  --remote-template=TPL       Template for origin when missing. Use {name} for project folder name.
                              Examples:
                                --remote-template=git@github.com:roger/{name}.git
                                --remote-template=https://github.com/roger/{name}.git
  --default-branch=NAME       Optional branch hint for new repos missing HEAD. Otherwise auto-detected.
  --quiet                     Less chatty.
  -h, --help                  Show help.

Columns:
  Project | Status | Branch | Ahead | Behind | Dirty

Status tags:
  UNINITIALIZED       Not a git repo
  NO_REMOTE           Repo exists but no 'origin'
  NO_UPSTREAM         Current branch not tracking a remote branch
  NOT_PUSHED_OR_AHEAD Has local commits not on remote, or never pushed
  BEHIND_REMOTE       Local behind upstream
  DIRTY               Uncommitted changes
  UNTRACKED_BRANCHES  Local branches without upstreams
  OK                  Everything is fine, unnervingly so

Safety rules in --fix:
  - Skips DIRTY repos
  - Won't pull or rebase
  - Requires --remote-template to add origin
  - Sets upstream by pushing with -u when remote exists
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --fix) DO_FIX=true ;;
    --remote-template=*) REMOTE_TEMPLATE="${arg#*=}" ;;
    --default-branch=*)  DEFAULT_BRANCH="${arg#*=}" ;;
    --quiet) QUIET=true ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      # First non-flag is BASE_DIR
      if [[ "$arg" = /* || "$arg" = ./* || "$arg" = ../* || -d "$arg" ]]; then
        BASE_DIR="$arg"
      else
        print -u2 -- "%F{red}Unknown argument:%f $arg"
        usage; exit 2
      fi
      ;;
  esac
done

# ---------- Helpers ----------
print_header() {
  $QUIET && return 0
  printf "%s\n" "%F{cyan}%BProject%f%b | %F{cyan}%BStatus%f%b | %F{cyan}%BBranch%f%b | %F{cyan}%BAhead%f%b | %F{cyan}%BBehind%f%b | %F{cyan}%BDirty%f%b"
  print -r -- "------------------------------------------------------------------------------------------"
}

enter_dir() { builtin cd "$1" || return 1; }

is_git_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

has_remote_origin() { git remote get-url origin >/dev/null 2>&1; }

current_branch() { git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(detached)"; }

ensure_head_branch() {
  # If HEAD is unborn (no commits), try to set an initial branch name
  if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    local b="${DEFAULT_BRANCH:-main}"
    # git default branch may already be set; just return it
    echo "$b"
    return 0
  fi
  current_branch
}

has_upstream_for_head() { git rev-parse --abbrev-ref --symbolic-full-name @{upstream} >/dev/null 2>&1; }

ahead_behind_counts() {
  if has_upstream_for_head; then
    local counts
    counts=$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null | awk '{print $1" "$2}')
    [[ -n "$counts" ]] && print -r -- "$counts" || print -r -- "0 0"
  else
    print -r -- "0 0"
  fi
}

dirty_worktree() { [[ -n "$(git status --porcelain 2>/dev/null)" ]]; }

untracked_local_branches() {
  git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads \
    | awk '$2=="" {print $1}' | xargs
}

# ---------- Fix routines ----------
template_origin_url() {
  # Build origin URL from template and project name
  local proj_name="$1"
  if [[ -z "$REMOTE_TEMPLATE" ]]; then
    return 1
  fi
  print -r -- "${REMOTE_TEMPLATE//\{name\}/$proj_name}"
}

add_origin_if_missing() {
  local proj_name="$1"
  if has_remote_origin; then return 0; fi
  local url
  url="$(template_origin_url "$proj_name")" || {
    print -u2 -- "%F{yellow}[SKIP]%f $proj_name: no --remote-template for origin"; return 1; }
  git remote add origin "$url"
  $QUIET || print -- "%F{green}[FIX]%f $proj_name: added origin -> $url"
  return 0
}

set_upstream_and_push() {
  local proj_name="$1"
  local br
  br="$(current_branch)"
  # Detached heads are not pushable in this safe mode
  if [[ "$br" == "(detached)" ]]; then
    $QUIET || print -- "%F{yellow}[SKIP]%f $proj_name: detached HEAD"
    return 1
  fi

  if dirty_worktree; then
    $QUIET || print -- "%F{yellow}[SKIP]%f $proj_name: dirty worktree"
    return 1
  fi

  if ! has_remote_origin; then
    $QUIET || print -- "%F{yellow}[SKIP]%f $proj_name: no origin remote"
    return 1
  fi

  # If no upstream, push -u
  if ! has_upstream_for_head; then
    # If remote branch missing, this will create it; if it exists, sets tracking
    if git push -u origin "$br" >/dev/null 2>&1; then
      $QUIET || print -- "%F{green}[FIX]%f $proj_name: set upstream and pushed '$br'"
      return 0
    else
      $QUIET || print -- "%F{red}[FAIL]%f $proj_name: push -u origin $br"
      return 1
    fi
  fi

  # If upstream exists, check ahead/behind
  local ahead behind
  read -r ahead behind <<<"$(ahead_behind_counts)"
  if (( behind > 0 )); then
    $QUIET || print -- "%F{yellow}[SKIP]%f $proj_name: behind remote; not pulling in --fix"
    return 1
  fi

  if (( ahead > 0 )); then
    if git push >/dev/null 2>&1; then
      $QUIET || print -- "%F{green}[FIX]%f $proj_name: pushed '$br' (ahead by $ahead)"
      return 0
    else
      $QUIET || print -- "%F{red}[FAIL]%f $proj_name: push '$br'"
      return 1
    fi
  fi

  $QUIET || print -- "%F{blue}[OK]%f $proj_name: up to date"
  return 0
}

# ---------- Reporting ----------
report_repo() {
  local proj="$1"
  local status_parts=()
  local br="—"
  local ahead="0" behind="0" dirty="no"

  if ! is_git_repo; then
    status_parts+=("%F{yellow}UNINITIALIZED%f")
    printf "%s | %s | %s | %s | %s | %s\n" "$proj" "${(j:, :)status_parts}" "$br" "$ahead" "$behind" "$dirty"
    return
  fi

  br="$(current_branch)"

  if ! has_remote_origin; then
    status_parts+=("%F{yellow}NO_REMOTE%f")
  fi

  if has_upstream_for_head; then
    read -r ahead behind <<<"$(ahead_behind_counts)"
    if (( behind > 0 )); then
      status_parts+=("%F{red}BEHIND_REMOTE%f")
    fi
  else
    status_parts+=("%F{yellow}NO_UPSTREAM%f")
  fi

  # Unpushed/ahead detection
  if [[ "$br" != "(detached)" ]]; then
    if ! has_remote_origin || ! has_upstream_for_head; then
      status_parts+=("%F{magenta}NOT_PUSHED_OR_AHEAD%f")
    else
      local a b
      read -r a b <<<"$(ahead_behind_counts)"
      (( a > 0 )) && status_parts+=("%F{magenta}NOT_PUSHED_OR_AHEAD%f")
    fi
  fi

  if dirty_worktree; then
    dirty="yes"
    status_parts+=("%F{red}DIRTY%f")
  fi

  local orphan_branches
  orphan_branches="$(untracked_local_branches)"
  if [[ -n "$orphan_branches" ]]; then
    status_parts+=("%F{yellow}UNTRACKED_BRANCHES(${orphan_branches})%f")
  fi

  (( ${#status_parts} == 0 )) && status_parts+=("%F{green}OK%f")

  printf "%s | %s | %s | %s | %s | %s\n" "$proj" "${(j:, :)status_parts}" "$br" "$ahead" "$behind" "$dirty"
}

process_repo() {
  local proj="$1"
  # Report first
  report_repo "$proj"

  # Optional fix actions
  $DO_FIX || return 0

  if ! is_git_repo; then
    # Being conservative: do not auto-init in --fix. You can init manually if desired.
    $QUIET || print -- "%F{yellow}[SKIP]%f $proj: not a git repo (no auto-init in --fix)"
    return 0
  fi

  # Ensure we know a branch name even on unborn HEAD (no commits yet)
  local br
  br="$(ensure_head_branch)"

  # Try adding origin if missing
  add_origin_if_missing "$proj" || true

  # Set upstream and push if appropriate
  set_upstream_and_push "$proj" || true
}

# ---------- Main ----------
main() {
  if [[ ! -d "$BASE_DIR" ]]; then
    print -u2 -- "%F{red}Error:%f '$BASE_DIR' is not a directory."
    exit 1
  fi

  print_header

  for d in "$BASE_DIR"/*(/N); do
    [[ "${d:t}" == .* ]] && continue
    (
      enter_dir "$d" || exit 0
      process_repo "${d:t}"
    )
  done
}

main
