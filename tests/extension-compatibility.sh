#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
validator="$project_root/scripts/validate-extension-compatibility.sh"
manifest="$project_root/compatibility/target-node.yaml"
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/talos-bluetooth-extensions.XXXXXX")
trap 'rm -rf "$fixture_root"' EXIT

module_extensions=(
  amdgpu
  bluetooth-usb-drivers
  drbd
  uhid
  uinput
  usb-audio-drivers
  v4l-uvc-drivers
)

userspace_extensions=(
  amd-ucode
  fuse3
  iscsi-tools
  nfs-utils
  nvme-cli
  realtek-firmware
)

firmware_extensions=(
  mediatek-bluetooth-firmware
)

create_extension() {
  local name=$1
  local kind=$2
  local extension_dir="$fixture_root/$name"

  mkdir -p "$extension_dir"
  printf 'metadata:\n  name: %s\n' "$name" > "$extension_dir/manifest.yaml.tmpl"

  case "$kind" in
    module)
      printf 'steps:\n  - install:\n      - mkdir -p /rootfs/usr/lib/modules\n' > "$extension_dir/pkg.yaml"
      ;;
    firmware)
      printf 'dependencies:\n  - image: example/linux-firmware:test\nsteps:\n  - install:\n      - install BT_RAM_CODE_MT7922_1_1_hdr.bin\n' > "$extension_dir/pkg.yaml"
      ;;
    userspace)
      printf 'steps:\n  - install:\n      - mkdir -p /rootfs/usr/bin\n' > "$extension_dir/pkg.yaml"
      ;;
  esac
}

for extension in "${module_extensions[@]}"; do
  create_extension "$extension" module
done

for extension in "${userspace_extensions[@]}"; do
  create_extension "$extension" userspace
done

for extension in "${firmware_extensions[@]}"; do
  create_extension "$extension" firmware
done

output=$(
  "$validator" \
    --manifest "$manifest" \
    --extensions-root "$fixture_root"
)

grep -Fq 'current extensions: 12' <<< "$output"
grep -Fq 'final extensions: 14' <<< "$output"
grep -Fq 'custom-kernel rebuilds: 7' <<< "$output"
grep -Fq 'custom firmware extensions: 1' <<< "$output"
grep -Fq 'official reusable extensions: 6' <<< "$output"

printf 'steps:\n  - install:\n      - mkdir -p /rootfs/usr/bin\n' > "$fixture_root/drbd/pkg.yaml"

if "$validator" --manifest "$manifest" --extensions-root "$fixture_root" >/dev/null 2>&1; then
  echo 'compatibility validator accepted drbd without kernel modules' >&2
  exit 1
fi

create_extension drbd module
printf 'steps:\n  - install:\n      - mkdir -p /rootfs/usr/lib/modules\n' > "$fixture_root/iscsi-tools/pkg.yaml"

if "$validator" --manifest "$manifest" --extensions-root "$fixture_root" >/dev/null 2>&1; then
  echo 'compatibility validator accepted an official reusable extension with kernel modules' >&2
  exit 1
fi

create_extension iscsi-tools userspace
invalid_manifest="$fixture_root/invalid-manifest.yaml"
sed 's/^factorySchematicID:.*/factorySchematicID: invalid/' "$manifest" > "$invalid_manifest"

if "$validator" --manifest "$invalid_manifest" --extensions-root "$fixture_root" >/dev/null 2>&1; then
  echo 'compatibility validator accepted an invalid schematic ID' >&2
  exit 1
fi

echo 'extension compatibility tests passed'
