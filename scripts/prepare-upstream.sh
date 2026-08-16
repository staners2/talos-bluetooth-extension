#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  echo "upstream preparation failed: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 <v1.13.8|v1.14.0|upstream> <absolute-new-destination>" >&2
  exit 2
}

clone_at_commit() {
  local name=$1
  local url=$2
  local commit=$3
  local checkout="$destination/$name"
  local actual_commit

  git init --quiet "$checkout"
  git -C "$checkout" remote add origin "$url"
  git -C "$checkout" fetch --quiet --depth=1 origin "$commit"
  git -C "$checkout" checkout --quiet --detach FETCH_HEAD

  actual_commit=$(git -C "$checkout" rev-parse HEAD)
  [[ "$actual_commit" == "$commit" ]] || \
    fail "$name resolved to $actual_commit instead of $commit"
}

apply_patch_series() {
  local name=$1
  local patch_directory="$project_root/patches/$version/$name"
  local patches=()

  shopt -s nullglob
  patches=("$patch_directory"/*.patch)
  shopt -u nullglob

  ((${#patches[@]} > 0)) || fail "no $name patches found for $version"

  local patch
  for patch in "${patches[@]}"; do
    git -C "$destination/$name" apply --check "$patch"
    git -C "$destination/$name" apply "$patch"
  done
}

(($# == 2)) || usage

version=$1
requested_destination=$2
version_file="$project_root/versions/$version.env"

[[ "$requested_destination" == /* ]] || \
  fail "destination must be an absolute path"
[[ "$requested_destination" != "/" ]] || fail "destination cannot be /"
[[ -f "$version_file" ]] || fail "unsupported version: $version"
[[ ! -e "$requested_destination" ]] || fail "destination already exists"

destination_parent=$(dirname "$requested_destination")
destination_name=$(basename "$requested_destination")
[[ -d "$destination_parent" ]] || fail "destination parent does not exist"
[[ "$destination_name" != "." && "$destination_name" != ".." ]] || \
  fail "destination name is unsafe"

destination_parent=$(cd "$destination_parent" && pwd -P)
destination="$destination_parent/$destination_name"

case "$destination/" in
  "$project_root/"*) fail "destination cannot be inside the project repository" ;;
esac

if [[ -n "${HOME:-}" && "$destination" == "$HOME" ]]; then
  fail "destination cannot be the home directory"
fi

"$project_root/scripts/validate-source.sh" "$version"

# shellcheck disable=SC1090
source "$version_file"

mkdir "$destination"

clone_at_commit pkgs https://github.com/siderolabs/pkgs.git "$PKGS_COMMIT"
clone_at_commit extensions https://github.com/siderolabs/extensions.git "$EXTENSIONS_COMMIT"
clone_at_commit talos https://github.com/siderolabs/talos.git "$TALOS_COMMIT"

apply_patch_series pkgs
apply_patch_series extensions
apply_patch_series talos

echo "prepared $version source checkouts at $destination"
echo "pkgs:       $(git -C "$destination/pkgs" rev-parse HEAD) (patched, detached)"
echo "extensions: $(git -C "$destination/extensions" rev-parse HEAD) (patched, detached)"
echo "talos:      $(git -C "$destination/talos" rev-parse HEAD) (patched, detached)"
