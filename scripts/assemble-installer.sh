#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  echo "installer assembly failed: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 <v1.13.8|v1.14.0> <prepared-root> <registry> <namespace> <build-tag> <new-output-directory>" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

(($# == 6)) || usage

version=$1
prepared_root=$2
registry=${3%/}
namespace=$4
build_tag=$5
output_dir=${6%/}
registry_client_address=${REGISTRY_CLIENT_ADDRESS:-$registry}
docker_network=${DOCKER_NETWORK:-bridge}
version_file="$project_root/versions/$version.env"
official_extensions_file="$project_root/compatibility/official-extensions-$version.txt"

[[ -f "$version_file" ]] || fail "unsupported version: $version"
[[ -d "$prepared_root/extensions/.git" ]] || fail "extensions checkout is missing"
[[ -d "$prepared_root/talos/.git" ]] || fail "talos checkout is missing"
[[ -f "$official_extensions_file" ]] || \
  fail "official extension references are missing: $official_extensions_file"
[[ -n "$registry" && -n "$namespace" && -n "$build_tag" ]] || \
  fail "registry, namespace, and build-tag must not be empty"
[[ "$output_dir" == /* ]] || fail "output directory must be an absolute path"
[[ "$output_dir" != / && "$output_dir" != "$HOME" && "$output_dir" != "$project_root" ]] || \
  fail "unsafe output directory: $output_dir"
[[ ! -e "$output_dir" ]] || fail "output directory already exists: $output_dir"
[[ -d "$(dirname "$output_dir")" ]] || fail "output parent directory is missing"

require_command crane
require_command docker

"$project_root/scripts/validate-source.sh" "$version"
"$project_root/scripts/validate-extension-compatibility.sh" \
  --extensions-root "$prepared_root/extensions"

# shellcheck disable=SC1090
source "$version_file"

local_extensions=(
  amdgpu
  bluetooth-usb-drivers
  mediatek-bluetooth-firmware
  drbd
  uhid
  uinput
  usb-audio-drivers
  v4l-uvc-drivers
)

internal_prefix="$registry/$namespace"
client_prefix="$registry_client_address/$namespace"
extension_bldr="$prepared_root/extensions/_out/bldr"
[[ -x "$extension_bldr" ]] || fail "extensions bldr is missing or not executable"

resolve_tagged_image() {
  local image=$1
  local image_tag=$2
  local digest

  digest=$(crane digest --insecure "$client_prefix/$image:$image_tag")
  printf '%s/%s@%s' "$internal_prefix" "$image" "$digest"
}

resolve_extension_image() {
  local image=$1
  local image_tag

  image_tag=$(
    cd "$prepared_root/extensions"
    "$extension_bldr" eval \
        --target "$image" \
        --build-arg "TAG=$build_tag" \
        '{{.VERSION}}'
  )
  [[ -n "$image_tag" ]] || fail "bldr returned an empty version for $image"
  resolve_tagged_image "$image" "$image_tag"
}

installer_base_ref=$(resolve_tagged_image installer-base "$build_tag")
imager_digest=$(crane digest --insecure "$client_prefix/imager:$build_tag")
imager_client_ref="$client_prefix/imager@$imager_digest"

extension_refs=()
for extension in "${local_extensions[@]}"; do
  extension_refs+=("$(resolve_extension_image "$extension")")
done

while IFS= read -r extension_ref; do
  [[ -n "$extension_ref" && "$extension_ref" != \#* ]] || continue
  [[ "$extension_ref" == *@sha256:* ]] || \
    fail "official extension is not digest-pinned: $extension_ref"
  extension_refs+=("$extension_ref")
done < "$official_extensions_file"

[[ ${#extension_refs[@]} -eq 14 ]] || \
  fail "expected 14 extensions, resolved ${#extension_refs[@]}"

mkdir "$output_dir"
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/talos-bluetooth-imager.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT
crane pull --insecure "$imager_client_ref" "$temporary_dir/imager.tar"
load_output=$(docker load --input "$temporary_dir/imager.tar")
loaded_imager=$(
  printf '%s\n' "$load_output" |
    awk '/^Loaded image( ID)?: / { sub(/^Loaded image( ID)?: /, ""); print; exit }'
)
[[ -n "$loaded_imager" ]] || fail "Docker did not report the loaded imager reference"
local_imager_ref="talos-bluetooth-local-imager:$build_tag"
docker tag "$loaded_imager" "$local_imager_ref"

imager_args=(
  installer
  --arch amd64
  --base-installer-image "$installer_base_ref"
  --insecure
)

for extension_ref in "${extension_refs[@]}"; do
  imager_args+=(--system-extension-image "$extension_ref")
done

docker run --rm --privileged \
  --network "$docker_network" \
  --volume "$output_dir:/out" \
  "$local_imager_ref" \
  "${imager_args[@]}"

installer="$output_dir/installer-amd64.tar"
[[ -s "$installer" ]] || fail "imager did not produce $installer"

if command -v sha256sum >/dev/null 2>&1; then
  installer_sha256=$(sha256sum "$installer" | awk '{print $1}')
else
  require_command shasum
  installer_sha256=$(shasum -a 256 "$installer" | awk '{print $1}')
fi

{
  printf 'version=%s\n' "$version"
  printf 'build_tag=%s\n' "$build_tag"
  printf 'talos_commit=%s\n' "$TALOS_COMMIT"
  printf 'pkgs_commit=%s\n' "$PKGS_COMMIT"
  printf 'extensions_commit=%s\n' "$EXTENSIONS_COMMIT"
  printf 'linux_version=%s\n' "$LINUX_VERSION"
  printf 'installer_base=%s\n' "$installer_base_ref"
  printf 'imager=%s\n' "$client_prefix/imager@$imager_digest"
  printf 'installer_sha256=%s\n' "$installer_sha256"
  printf 'extensions=%s\n' "${#extension_refs[@]}"
  printf '%s\n' "${extension_refs[@]}"
} > "$output_dir/provenance.txt"

printf '%s  %s\n' "$installer_sha256" "$(basename "$installer")" \
  > "$output_dir/installer-amd64.tar.sha256"

echo "installer: $installer"
echo "sha256: $installer_sha256"
echo "provenance: $output_dir/provenance.txt"
