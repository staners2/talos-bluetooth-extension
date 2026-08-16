#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$project_root/compatibility/target-node.yaml"
extensions_root=

fail() {
  echo "extension compatibility validation failed: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 [--manifest <path>] --extensions-root <path>" >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --manifest)
      (($# >= 2)) || usage
      manifest=$2
      shift 2
      ;;
    --extensions-root)
      (($# >= 2)) || usage
      extensions_root=$2
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

command -v yq >/dev/null 2>&1 || fail "yq v4 is required"
command -v rg >/dev/null 2>&1 || fail "rg is required"
[[ -s "$manifest" ]] || fail "manifest is missing or empty: $manifest"
[[ -d "$extensions_root" ]] || fail "extensions root does not exist: $extensions_root"

schema_version=$(yq -r '.schemaVersion' "$manifest")
[[ "$schema_version" == 1 ]] || fail "unsupported schemaVersion: $schema_version"

node=$(yq -r '.node' "$manifest")
architecture=$(yq -r '.architecture' "$manifest")
schematic_id=$(yq -r '.factorySchematicID' "$manifest")
[[ "$node" == target-node ]] || fail "unexpected node: $node"
[[ "$architecture" == amd64 ]] || fail "unexpected architecture: $architecture"
[[ "$schematic_id" =~ ^[0-9a-f]{64}$ ]] || \
  fail "factorySchematicID must be a lowercase SHA-256 value"

duplicate_names=$(yq -r '.extensions[].name' "$manifest" | sort | uniq -d)
[[ -z "$duplicate_names" ]] || fail "duplicate extension names: $duplicate_names"

current_count=0
final_count=0
custom_count=0
firmware_count=0
official_count=0

while IFS=$'\t' read -r name present source; do
  [[ -n "$name" ]] || fail "extension name cannot be empty"

  final_count=$((final_count + 1))
  [[ "$present" == true || "$present" == false ]] || \
    fail "$name has invalid presentInCurrentImage value: $present"

  if [[ "$present" == true ]]; then
    current_count=$((current_count + 1))
  fi

  case "$source" in
    custom-kernel) custom_count=$((custom_count + 1)) ;;
    custom-firmware) firmware_count=$((firmware_count + 1)) ;;
    official) official_count=$((official_count + 1)) ;;
    *) fail "$name has unsupported source: $source" ;;
  esac

  matches=$(rg -l -F "name: $name" "$extensions_root" -g 'manifest.yaml.tmpl' || true)
  match_count=$(printf '%s\n' "$matches" | awk 'NF { count++ } END { print count + 0 }')
  [[ "$match_count" == 1 ]] || \
    fail "$name resolved to $match_count package directories instead of 1"

  package_file="$(dirname "$matches")/pkg.yaml"
  [[ -s "$package_file" ]] || fail "$name package definition is missing: $package_file"

  case "$source" in
    custom-kernel)
      rg -q '/usr/lib/modules|/kernel:' "$package_file" || \
        fail "$name is custom-kernel but does not use kernel modules"
      ;;
    custom-firmware)
      rg -q '/linux-firmware:' "$package_file" || \
        fail "$name is custom-firmware but does not use the pinned linux-firmware image"
      rg -q 'BT_RAM_CODE_MT7922_1_1_hdr\.bin' "$package_file" || \
        fail "$name is custom-firmware but does not select the MT7922 firmware"
      ;;
    official)
      if rg -q '/usr/lib/modules|/kernel:' "$package_file"; then
        fail "$name is official-reusable but requires a custom kernel build"
      fi
      ;;
  esac
done < <(yq -r '.extensions[] | [.name, .presentInCurrentImage, .source] | @tsv' "$manifest")

[[ "$current_count" == 12 ]] || fail "expected 12 current extensions, found $current_count"
[[ "$final_count" == 14 ]] || fail "expected 14 final extensions, found $final_count"
[[ "$custom_count" == 7 ]] || fail "expected 7 custom-kernel rebuilds, found $custom_count"
[[ "$firmware_count" == 1 ]] || fail "expected 1 custom firmware extension, found $firmware_count"
[[ "$official_count" == 6 ]] || fail "expected 6 reusable official extensions, found $official_count"

bluetooth_state=$(
  yq -r '.extensions[] | select(.name == "bluetooth-usb-drivers") | [.presentInCurrentImage, .source] | @tsv' "$manifest"
)
[[ "$bluetooth_state" == $'false\tcustom-kernel' ]] || \
  fail "bluetooth-usb-drivers must be the new custom-kernel extension"

realtek_source=$(
  yq -r '.extensions[] | select(.name == "realtek-firmware") | .source' "$manifest"
)
[[ "$realtek_source" == official ]] || \
  fail "realtek-firmware must remain the official firmware source"

mediatek_source=$(
  yq -r '.extensions[] | select(.name == "mediatek-bluetooth-firmware") | .source' "$manifest"
)
[[ "$mediatek_source" == custom-firmware ]] || \
  fail "mediatek-bluetooth-firmware must remain a separately auditable custom firmware source"

echo "current extensions: $current_count"
echo "final extensions: $final_count"
echo "custom-kernel rebuilds: $custom_count"
echo "custom firmware extensions: $firmware_count"
echo "official reusable extensions: $official_count"
