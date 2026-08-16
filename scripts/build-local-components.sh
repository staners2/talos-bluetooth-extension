#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  echo "local component build failed: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 <v1.13.8|v1.14.0> <prepared-root> <registry> <namespace> <build-tag>" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

(($# == 5)) || usage

version=$1
prepared_root=$2
registry=${3%/}
namespace=$4
build_tag=$5
registry_client_address=${REGISTRY_CLIENT_ADDRESS:-$registry}
version_file="$project_root/versions/$version.env"
make_command=${MAKE_COMMAND:-gmake}
platform=linux/amd64

[[ -f "$version_file" ]] || fail "unsupported version: $version"
[[ -d "$prepared_root/pkgs/.git" ]] || fail "pkgs checkout is missing"
[[ -d "$prepared_root/extensions/.git" ]] || fail "extensions checkout is missing"
[[ -d "$prepared_root/talos/.git" ]] || fail "talos checkout is missing"
[[ -n "$registry" && -n "$namespace" && -n "$build_tag" ]] || \
  fail "registry, namespace, and build-tag must not be empty"

require_command docker
require_command "$make_command"
require_command crane

"$project_root/scripts/validate-source.sh" "$version"
"$project_root/scripts/validate-extension-compatibility.sh" \
  --extensions-root "$prepared_root/extensions"

# shellcheck disable=SC1090
source "$version_file"

image_prefix="$registry/$namespace"
common_args=(
  "TAG=$build_tag"
  "PLATFORM=$platform"
  "REGISTRY=$registry"
  "USERNAME=$namespace"
  "PUSH=true"
  "PROGRESS=plain"
)

"$make_command" -C "$prepared_root/pkgs" kernel "${common_args[@]}"
kernel_ref="$image_prefix/kernel:$build_tag"
kernel_client_ref="$registry_client_address/$namespace/kernel:$build_tag"
kernel_digest=$(crane digest --insecure "$kernel_client_ref")
kernel_ref="$image_prefix/kernel@$kernel_digest"

"$make_command" -C "$prepared_root/pkgs" linux-firmware "${common_args[@]}"
"$make_command" -C "$prepared_root/pkgs" drbd-pkg \
  "${common_args[@]}" \
  "PKG_KERNEL=$kernel_ref"

module_extensions=(
  amdgpu
  bluetooth-usb-drivers
  drbd
  uhid
  uinput
  usb-audio-drivers
  v4l-uvc-drivers
)

custom_extensions=(
  "${module_extensions[@]}"
  mediatek-bluetooth-firmware
)

"$make_command" -C "$prepared_root/extensions" \
  "${custom_extensions[@]}" \
  "${common_args[@]}" \
  "PKGS=$build_tag" \
  "PKGS_PREFIX=$image_prefix"

"$make_command" -C "$prepared_root/talos" installer-base imager talos \
  "TAG=$build_tag" \
  "PLATFORM=$platform" \
  "INSTALLER_ARCH=amd64" \
  "IMAGE_REGISTRY=$registry" \
  "USERNAME=$namespace" \
  "PKG_KERNEL=$kernel_ref" \
  "PUSH=true" \
  "PROGRESS=plain"

echo "kernel: $kernel_ref"
echo "installer-base: $image_prefix/installer-base:$build_tag"
echo "imager: $image_prefix/imager:$build_tag"
echo "talos-container: $image_prefix/talos:$build_tag"
echo "extension metadata: $prepared_root/extensions/_out/*.metadata.json"
