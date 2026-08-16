#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
validator="$project_root/scripts/validate-source.sh"

if [[ ! -x "$validator" ]]; then
  echo "source validator is missing or not executable: $validator" >&2
  exit 1
fi

"$validator"

for version in v1.13.8 v1.14.0; do
  pkgs_patch="$project_root/patches/$version/pkgs/0001-enable-bluetooth-usb-modules.patch"
  drivers_patch="$project_root/patches/$version/extensions/0001-add-bluetooth-usb-drivers.patch"
  firmware_patch="$project_root/patches/$version/extensions/0002-add-mediatek-bluetooth-firmware.patch"

  grep -Fq '+CONFIG_BT_MTK=m' "$pkgs_patch" || {
    echo "$version does not build the MediaTek Bluetooth helper" >&2
    exit 1
  }
  grep -Fq '+CONFIG_BT_HCIBTUSB_MTK=y' "$pkgs_patch" || {
    echo "$version does not enable MediaTek USB Bluetooth support" >&2
    exit 1
  }
  grep -Fq '+kernel/drivers/bluetooth/btmtk.ko' "$drivers_patch" || {
    echo "$version driver extension does not package btmtk" >&2
    exit 1
  }
  [[ -s "$firmware_patch" ]] || {
    echo "$version MediaTek Bluetooth firmware patch is missing" >&2
    exit 1
  }
  grep -Fq '/usr/lib/firmware/LICENSES/LICENCE.mediatek' "$firmware_patch" || {
    echo "$version MediaTek firmware license path does not match the Sidero package" >&2
    exit 1
  }
done

if "$validator" unsupported >/dev/null 2>&1; then
  echo "source validator accepted an unsupported version" >&2
  exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/talos-bluetooth-contract.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

cp -R "$project_root/scripts" "$project_root/versions" "$project_root/patches" "$test_root/"

sed -i.bak \
  's/^PKGS_COMMIT=.*/PKGS_COMMIT=invalid/' \
  "$test_root/versions/v1.13.8.env"
rm "$test_root/versions/v1.13.8.env.bak"

if "$test_root/scripts/validate-source.sh" v1.13.8 >/dev/null 2>&1; then
  echo "source validator accepted an invalid commit SHA" >&2
  exit 1
fi

cp "$project_root/versions/v1.13.8.env" "$test_root/versions/v1.13.8.env"
printf '\n+rootfs/usr/lib/firmware/rtl_bt/forbidden.bin\n' >> \
  "$test_root/patches/v1.13.8/extensions/0001-add-bluetooth-usb-drivers.patch"

if "$test_root/scripts/validate-source.sh" v1.13.8 >/dev/null 2>&1; then
  echo "source validator accepted bundled firmware" >&2
  exit 1
fi

cp "$project_root/patches/v1.13.8/extensions/0001-add-bluetooth-usb-drivers.patch" \
  "$test_root/patches/v1.13.8/extensions/0001-add-bluetooth-usb-drivers.patch"
sed -i.bak \
  's/version: ">= v1.13.0-alpha.2"/version: ">= v1.13.8"/' \
  "$test_root/patches/v1.13.8/extensions/0001-add-bluetooth-usb-drivers.patch"
rm "$test_root/patches/v1.13.8/extensions/0001-add-bluetooth-usb-drivers.patch.bak"

if "$test_root/scripts/validate-source.sh" v1.13.8 >/dev/null 2>&1; then
  echo "source validator accepted a release-specific manifest compatibility floor" >&2
  exit 1
fi

cp "$project_root/patches/v1.13.8/pkgs/0001-enable-bluetooth-usb-modules.patch" \
  "$test_root/patches/v1.13.8/pkgs/0001-enable-bluetooth-usb-modules.patch"
cp "$project_root/patches/v1.13.8/extensions/0001-add-bluetooth-usb-drivers.patch" \
  "$test_root/patches/v1.13.8/extensions/0001-add-bluetooth-usb-drivers.patch"
sed -i.bak 's/CONFIG_RFKILL=y/CONFIG_RFKILL=m/g' \
  "$test_root/patches/v1.13.8/pkgs/0001-enable-bluetooth-usb-modules.patch"
rm "$test_root/patches/v1.13.8/pkgs/0001-enable-bluetooth-usb-modules.patch.bak"

if "$test_root/scripts/validate-source.sh" v1.13.8 >/dev/null 2>&1; then
  echo "source validator accepted modular rfkill" >&2
  exit 1
fi

cp "$project_root/patches/v1.13.8/pkgs/0001-enable-bluetooth-usb-modules.patch" \
  "$test_root/patches/v1.13.8/pkgs/0001-enable-bluetooth-usb-modules.patch"
printf '\n+kernel/net/rfkill/rfkill.ko\n' >> \
  "$test_root/patches/v1.13.8/extensions/0001-add-bluetooth-usb-drivers.patch"

if "$test_root/scripts/validate-source.sh" v1.13.8 >/dev/null 2>&1; then
  echo "source validator accepted extension-owned rfkill" >&2
  exit 1
fi

echo "source contract tests passed"
