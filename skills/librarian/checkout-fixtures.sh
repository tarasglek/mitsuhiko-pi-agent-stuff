#!/usr/bin/env bash
set -euo pipefail

checkout_script="$(cd -- "$(dirname -- "$0")" && pwd -P)/checkout.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "$fixture_root"' EXIT

assert_rejected() {
  local input="$1"
  if LIBRARIAN_CACHE_ROOT="$fixture_root/cache" "$checkout_script" --path-only "$input" \
    >"$fixture_root/stdout" 2>"$fixture_root/stderr"; then
    echo "expected rejection: $input" >&2
    exit 1
  fi
}

# Parsed path components must not escape the cache root, and malformed input
# must fail before any empty parsed fields are used.
assert_rejected 'github.com/../escape'
assert_rejected 'github.com/org/..'
assert_rejected '../org/repo'
assert_rejected 'not-a-repository-reference'
[[ ! -e "$fixture_root/cache" ]]

cache_root="$fixture_root/cache"
checkout="$cache_root/github.com/org/repo"
pool="$cache_root/.object-pool"
mkdir -p "$checkout"
git init -q "$checkout"
printf '%s\n' "$(date +%s)" > "$checkout/.git/librarian-last-fetch"
git init --bare -q "$pool"

# This valid entry is relative to pool/objects, not pool/objects/info.
mkdir -p "$pool/donor/objects"
printf '%s\n%s\n' '../donor/objects' '../missing/objects' > \
  "$pool/objects/info/alternates"

LIBRARIAN_CACHE_ROOT="$cache_root" "$checkout_script" --path-only \
  --update-interval 999999999 github.com/org/repo >"$fixture_root/path"

expected_donor="$(cd -- "$pool/donor/objects" && pwd -P)"
expected_checkout="$(cd -- "$checkout/.git/objects" && pwd -P)"
alternates="$(<"$pool/objects/info/alternates")"
[[ "$alternates" == "$expected_donor"$'\n'"$expected_checkout" ]]
[[ "$alternates" != *missing* ]]

echo 'checkout fixtures: ok'
