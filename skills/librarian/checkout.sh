#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: checkout.sh <repo> [options]

Ensure a cached checkout exists at:
  ~/.cache/checkouts/<host>/<org>/<repo>

Examples:
  checkout.sh mitsuhiko/minijinja
  checkout.sh github.com/mitsuhiko/minijinja
  checkout.sh https://github.com/mitsuhiko/minijinja
  checkout.sh git@github.com:mitsuhiko/minijinja.git

Options:
  --path-only                 Print only the checkout path.
  --force-update              Always fetch from origin and attempt fast-forward.
  --update-interval <secs>    Minimum seconds between updates (default: 300).

Environment:
  LIBRARIAN_CACHE_ROOT        Override cache root (default: ~/.cache/checkouts)
  LIBRARIAN_DEFAULT_HOST      Host for owner/repo shorthand (default: github.com)
  LIBRARIAN_UPDATE_INTERVAL   Default update interval in seconds
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

repo_input=""
path_only=0
force_update=0
update_interval="${LIBRARIAN_UPDATE_INTERVAL:-300}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path-only)
      path_only=1
      shift
      ;;
    --force-update)
      force_update=1
      shift
      ;;
    --update-interval)
      if [[ $# -lt 2 ]]; then
        echo "error: --update-interval expects a value" >&2
        exit 2
      fi
      update_interval="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$repo_input" ]]; then
        repo_input="$1"
      else
        echo "error: unexpected argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$repo_input" ]]; then
  echo "error: repository is required" >&2
  exit 2
fi

if ! [[ "$update_interval" =~ ^[0-9]+$ ]]; then
  echo "error: update interval must be a non-negative integer" >&2
  exit 2
fi

trim_repo_input() {
  local s="$1"
  # Trim leading/trailing whitespace.
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

parse_repo() {
  local input host path first rest
  input="$(trim_repo_input "$1")"

  # Strip query/fragment for URL-like inputs.
  input="${input%%\?*}"
  input="${input%%#*}"

  case "$input" in
    git@*:* )
      host="${input#git@}"
      host="${host%%:*}"
      path="${input#*:}"
      ;;
    ssh://* )
      rest="${input#ssh://}"
      host="${rest%%/*}"
      host="${host#*@}"
      path="${rest#*/}"
      ;;
    http://*|https://* )
      rest="${input#*://}"
      host="${rest%%/*}"
      path="${rest#*/}"
      ;;
    */* )
      first="${input%%/*}"
      if [[ "$first" == *.* || "$first" == localhost ]]; then
        host="$first"
        path="${input#*/}"
      else
        host="${LIBRARIAN_DEFAULT_HOST:-github.com}"
        path="$input"
      fi
      ;;
    * )
      echo "error: unsupported repository format: $input" >&2
      return 1
      ;;
  esac

  host="${host#*@}"
  path="${path#/}"
  path="${path%/}"

  # For GitHub-like deep links, use owner/repo only.
  IFS='/' read -r -a parts <<< "$path"
  if [[ ${#parts[@]} -ge 3 ]]; then
    case "${parts[2]}" in
      tree|blob|pull|issues|commit|actions|releases|compare|wiki)
        path="${parts[0]}/${parts[1]}"
        ;;
    esac
  fi

  # Strip optional .git suffix.
  path="${path%.git}"

  IFS='/' read -r -a parts <<< "$path"
  if [[ ${#parts[@]} -lt 2 ]]; then
    echo "error: repository path must contain at least org/repo: $path" >&2
    return 1
  fi

  local last_index=$(( ${#parts[@]} - 1 ))
  local repo="${parts[$last_index]}"
  local org_parts=("${parts[@]:0:$last_index}")
  local org
  org="$(IFS='/'; echo "${org_parts[*]}")"

  if [[ -z "$host" || -z "$org" || -z "$repo" ]]; then
    echo "error: failed to parse repository: $input" >&2
    return 1
  fi

  printf '%s\n%s\n%s\n' "$host" "$org" "$repo"
}

parsed_output=""
if ! parsed_output="$(parse_repo "$repo_input")"; then
  echo "error: failed to parse repository input" >&2
  exit 2
fi
mapfile -t parsed <<< "$parsed_output"
if [[ ${#parsed[@]} -ne 3 || -z "${parsed[0]}" || -z "${parsed[1]}" || -z "${parsed[2]}" ]]; then
  echo "error: failed to parse repository input" >&2
  exit 2
fi

host="${parsed[0]}"
org="${parsed[1]}"
repo="${parsed[2]}"

validate_repo_path_components() {
  local value component
  case "$host" in
    ""|.|..|*/*)
      return 1
      ;;
  esac

  value="$org"
  while :; do
    component="${value%%/*}"
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
    if [[ "$value" == */* ]]; then
      value="${value#*/}"
    else
      break
    fi
  done

  case "$repo" in
    ""|.|..|*/*)
      return 1
      ;;
  esac
}

if ! validate_repo_path_components; then
  echo "error: repository path contains an empty or dot component" >&2
  exit 2
fi

cache_root="${LIBRARIAN_CACHE_ROOT:-$HOME/.cache/checkouts}"
checkout_path="$cache_root/$host/$org/$repo"
origin_url="https://$host/$org/$repo.git"
pool="$cache_root/.object-pool"

is_valid_checkout() {
  local path="$1"
  [[ -e "$path/.git" ]] &&
    [[ "$(git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]]
}

initialize_pool() {
  pool_usable=0
  if [[ -e "$pool" || -L "$pool" ]]; then
    if [[ -d "$pool" ]] &&
      [[ "$(git -C "$pool" rev-parse --is-bare-repository 2>/dev/null)" == true ]]; then
      pool_usable=1
    fi
  elif git init --bare "$pool" >/dev/null 2>&1 &&
    [[ "$(git -C "$pool" rev-parse --is-bare-repository 2>/dev/null)" == true ]]; then
    pool_usable=1
  fi
}

register_checkout_objects() {
  (( pool_usable == 1 )) || return 0

  local checkout="$1" common_dir object_dir alternates_dir alternates_file alternates_base
  local lock_fd tmp entry candidate canonical
  local -A seen=()
  if ! common_dir="$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    ! object_dir="$(cd "$common_dir/objects" 2>/dev/null && pwd -P)"; then
    return 0
  fi

  alternates_dir="$pool/objects/info"
  alternates_base="$pool/objects"
  alternates_file="$alternates_dir/alternates"
  if ! exec {lock_fd}>"$alternates_dir/alternates.lock"; then
    return 0
  fi
  if ! flock -x "$lock_fd"; then
    exec {lock_fd}>&-
    return 0
  fi

  tmp=""
  if ! tmp="$(mktemp "$alternates_dir/.alternates.XXXXXX")"; then
    flock -u "$lock_fd" || true
    exec {lock_fd}>&-
    return 0
  fi

  # Normalize existing entries relative to objects, resolve symlinks and dot
  # components, and discard entries that no longer name an object dir.
  : > "$tmp"
  if [[ -f "$alternates_file" ]]; then
    while IFS= read -r entry || [[ -n "$entry" ]]; do
      [[ -n "$entry" ]] || continue
      if [[ "$entry" = /* ]]; then
        candidate="$entry"
      else
        candidate="$alternates_base/$entry"
      fi
      if canonical="$(cd -- "$candidate" 2>/dev/null && pwd -P)" &&
        [[ -z "${seen[$canonical]+x}" ]]; then
        printf '%s\n' "$canonical" >> "$tmp"
        seen["$canonical"]=1
      fi
    done < "$alternates_file"
  fi
  if [[ -z "${seen[$object_dir]+x}" ]]; then
    printf '%s\n' "$object_dir" >> "$tmp"
  fi

  if ! mv -f -- "$tmp" "$alternates_file"; then
    rm -f -- "$tmp"
  fi
  flock -u "$lock_fd" || true
  exec {lock_fd}>&-
}

clone_checkout() {
  local clone_parent clone_tmp clone_dir
  clone_parent="$(dirname "$checkout_path")"

  # Clone in an invocation-owned temporary directory.  The canonical
  # destination is installed only after the clone succeeds, and is never
  # removed if another caller creates it first.
  clone_tmp="$(mktemp -d "$clone_parent/.librarian-clone.XXXXXX")"
  clone_dir="$clone_tmp/checkout"

  if (( pool_usable == 1 )); then
    if ! git clone --no-local --filter=blob:none --reference-if-able "$pool" \
      "$origin_url" "$clone_dir" >/dev/null; then
      rm -rf -- "$clone_tmp"
      clone_tmp="$(mktemp -d "$clone_parent/.librarian-clone.XXXXXX")"
      clone_dir="$clone_tmp/checkout"
      if ! git clone --no-local --filter=blob:none "$origin_url" "$clone_dir" >/dev/null; then
        rm -rf -- "$clone_tmp"
        return 1
      fi
    fi
  elif ! git clone --no-local --filter=blob:none "$origin_url" "$clone_dir" >/dev/null; then
    rm -rf -- "$clone_tmp"
    return 1
  fi

  # -T prevents an existing directory from becoming a parent, and -n keeps
  # an unrelated destination untouched if it appeared without our lock.
  if ! mv -T -n -- "$clone_dir" "$checkout_path"; then
    rm -rf -- "$clone_tmp"
    return 1
  fi
  if [[ -e "$clone_dir" || -L "$clone_dir" ]]; then
    echo "error: checkout path appeared during clone: $checkout_path" >&2
    rm -rf -- "$clone_tmp"
    return 1
  fi
  rm -rf -- "$clone_tmp"
}

mkdir -p "$(dirname "$checkout_path")"
pool_usable=0

# Serialize callers for this destination, while also using an isolated clone
# and no-clobber install so an uncoordinated creator cannot be deleted.
checkout_lock_file="$checkout_path.lock"
if ! exec {checkout_lock_fd}>"$checkout_lock_file"; then
  echo "error: unable to lock checkout path: $checkout_path" >&2
  exit 1
fi
if ! flock -x "$checkout_lock_fd"; then
  exec {checkout_lock_fd}>&-
  echo "error: unable to lock checkout path: $checkout_path" >&2
  exit 1
fi

if [[ -e "$checkout_path" || -L "$checkout_path" ]]; then
  if ! is_valid_checkout "$checkout_path"; then
    flock -u "$checkout_lock_fd" || true
    exec {checkout_lock_fd}>&-
    echo "error: checkout path is not a git repository: $checkout_path" >&2
    exit 3
  fi
  clone_state="existing"
else
  initialize_pool
  if ! clone_checkout; then
    flock -u "$checkout_lock_fd" || true
    exec {checkout_lock_fd}>&-
    exit 1
  fi
  clone_state="cloned"
fi

flock -u "$checkout_lock_fd" || true
exec {checkout_lock_fd}>&-

if ! is_valid_checkout "$checkout_path"; then
  echo "error: checkout path is not a git repository: $checkout_path" >&2
  exit 3
fi

if (( pool_usable == 0 )); then
  initialize_pool
fi
register_checkout_objects "$checkout_path"

if ! git -C "$checkout_path" remote get-url origin >/dev/null 2>&1; then
  git -C "$checkout_path" remote add origin "$origin_url"
fi

# If remote URL changed (e.g. host shorthand), normalize to canonical HTTPS URL.
current_origin="$(git -C "$checkout_path" remote get-url origin 2>/dev/null || true)"
if [[ "$current_origin" != "$origin_url" ]]; then
  git -C "$checkout_path" remote set-url origin "$origin_url"
fi

common_dir="$(git -C "$checkout_path" rev-parse --path-format=absolute --git-common-dir)"
last_fetch_file="$common_dir/librarian-last-fetch"
now_epoch="$(date +%s)"
needs_update=1

if [[ -f "$last_fetch_file" && "$force_update" -eq 0 ]]; then
  last_epoch="$(cat "$last_fetch_file" 2>/dev/null || echo 0)"
  if [[ "$last_epoch" =~ ^[0-9]+$ ]]; then
    age=$(( now_epoch - last_epoch ))
    if (( age < update_interval )); then
      needs_update=0
    fi
  fi
fi

update_state="skipped"
ff_state="not-attempted"

if (( needs_update == 1 )); then
  if git -C "$checkout_path" fetch --prune --tags origin >/dev/null; then
    printf '%s\n' "$now_epoch" > "$last_fetch_file"
    update_state="fetched"

    branch="$(git -C "$checkout_path" symbolic-ref --short -q HEAD 2>/dev/null || true)"
    upstream="$(git -C "$checkout_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    dirty="$(git -C "$checkout_path" status --porcelain)"

    if [[ -n "$branch" && -n "$upstream" && -z "$dirty" ]]; then
      if git -C "$checkout_path" merge --ff-only "$upstream" >/dev/null 2>&1; then
        ff_state="fast-forwarded"
      else
        ff_state="skipped-non-ff"
      fi
    elif [[ -n "$dirty" ]]; then
      ff_state="skipped-dirty"
    else
      ff_state="skipped-no-upstream"
    fi
  else
    echo "warning: fetch-failed for $checkout_path; retaining checkout" >&2
    update_state="fetch-failed"
    ff_state="not-attempted"
  fi
fi

if (( path_only == 1 )); then
  printf '%s\n' "$checkout_path"
  exit 0
fi

cat <<EOF
repo: $host/$org/$repo
path: $checkout_path
state: $clone_state
update: $update_state
fast_forward: $ff_state
EOF
