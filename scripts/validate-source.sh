#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
supported_versions=(v1.13.8 v1.14.0 upstream)

fail() {
  echo "source validation failed: $*" >&2
  exit 1
}

is_supported_version() {
  local requested=$1
  local supported

  for supported in "${supported_versions[@]}"; do
    [[ "$requested" == "$supported" ]] && return 0
  done

  return 1
}

require_file() {
  local path=$1
  [[ -s "$path" ]] || fail "required file is missing or empty: ${path#"$project_root/"}"
}

require_patch_text() {
  local patch=$1
  local expected=$2
  grep -Fq -- "$expected" "$patch" || \
    fail "${patch#"$project_root/"} does not contain required text: $expected"
}

validate_version() {
  local version=$1
  local version_file="$project_root/versions/$version.env"
  local pkgs_patch="$project_root/patches/$version/pkgs/0001-enable-bluetooth-usb-modules.patch"
  local extensions_patch="$project_root/patches/$version/extensions/0001-add-bluetooth-usb-drivers.patch"
  local firmware_patch="$project_root/patches/$version/extensions/0002-add-mediatek-bluetooth-firmware.patch"
  local talos_patch="$project_root/patches/$version/talos/0001-truncate-overwritten-extension-files.patch"
  local compatibility_floor='version: ">= v1.13.0-alpha.2"'
  local variable

  is_supported_version "$version" || fail "unsupported version: $version"
  require_file "$version_file"

  # shellcheck disable=SC1090
  source "$version_file"

  [[ "$VERSION_ID" == "$version" ]] || fail "$version_file has VERSION_ID=$VERSION_ID"

  for variable in TALOS_COMMIT PKGS_COMMIT EXTENSIONS_COMMIT; do
    [[ "${!variable}" =~ ^[0-9a-f]{40}$ ]] || \
      fail "$version_file has an invalid $variable"
  done

  [[ "$KRES_COMMIT" =~ ^[0-9a-f]{7,40}$ ]] || \
    fail "$version_file has an invalid KRES_COMMIT"
  [[ "$KRES_IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || \
    fail "$version_file has an invalid KRES_IMAGE_DIGEST"

  require_file "$pkgs_patch"
  require_file "$extensions_patch"
  require_file "$firmware_patch"
  require_file "$talos_patch"

  require_patch_text "$pkgs_patch" "diff --git a/kernel/build/config-amd64 b/kernel/build/config-amd64"
  require_patch_text "$pkgs_patch" "diff --git a/kernel/build/config-arm64 b/kernel/build/config-arm64"

  local required_symbol
  for required_symbol in \
    "CONFIG_BT=m" \
    "# CONFIG_BT_BREDR is not set" \
    "CONFIG_BT_LE=y" \
    "CONFIG_BT_LE_L2CAP_ECRED=y" \
    "CONFIG_BT_INTEL=m" \
    "CONFIG_BT_RTL=m" \
    "CONFIG_BT_MTK=m" \
    "CONFIG_BT_HCIBTUSB=m" \
    "CONFIG_BT_HCIBTUSB_POLL_SYNC=y" \
    "CONFIG_BT_HCIBTUSB_MTK=y" \
    "CONFIG_BT_HCIBTUSB_RTL=y" \
    "CONFIG_RFKILL=y"; do
    require_patch_text "$pkgs_patch" "$required_symbol"
  done

  if [[ "$version" == upstream ]]; then
    require_patch_text "$pkgs_patch" "CONFIG_BT_HCIBTUSB_AUTOSUSPEND=y"
  else
    require_patch_text "$pkgs_patch" "# CONFIG_BT_HCIBTUSB_AUTOSUSPEND is not set"
  fi

  local forbidden_enabled
  for forbidden_enabled in \
    "CONFIG_BT_RFCOMM=m" \
    "CONFIG_BT_BNEP=m" \
    "CONFIG_BT_CMTP=m" \
    "CONFIG_BT_HIDP=m" \
    "CONFIG_BT_6LOWPAN=m" \
    "CONFIG_BT_HCIUART=m" \
    "CONFIG_BT_HCIBTSDIO=m" \
    "CONFIG_BT_HCIVHCI=m" \
    "CONFIG_BT_HCIBTUSB_BCM=y" \
    "CONFIG_BT_DEBUGFS=y" \
    "CONFIG_BT_SELFTEST=y"; do
    if grep -Fq -- "+$forbidden_enabled" "$pkgs_patch"; then
      fail "$pkgs_patch enables out-of-scope symbol: $forbidden_enabled"
    fi
  done

  local extension_path
  for extension_path in \
    ".kres.yaml" \
    "MAINTAINERS.md" \
    "Makefile" \
    "drivers/bluetooth-usb-drivers/README.md" \
    "drivers/bluetooth-usb-drivers/files/modules-x86_64.txt" \
    "drivers/bluetooth-usb-drivers/files/modules-aarch64.txt" \
    "drivers/bluetooth-usb-drivers/manifest.yaml.tmpl" \
    "drivers/bluetooth-usb-drivers/pkg.yaml" \
    "drivers/bluetooth-usb-drivers/vars.yaml"; do
    require_patch_text "$extensions_patch" "$extension_path"
  done

  local module_path
  for module_path in \
    "kernel/crypto/ecc.ko" \
    "kernel/crypto/ecdh_generic.ko" \
    "kernel/net/bluetooth/bluetooth.ko" \
    "kernel/drivers/bluetooth/btusb.ko" \
    "kernel/drivers/bluetooth/btintel.ko" \
    "kernel/drivers/bluetooth/btrtl.ko"; do
    require_patch_text "$extensions_patch" "$module_path"
  done
  require_patch_text "$extensions_patch" "kernel/drivers/bluetooth/btmtk.ko"

  require_patch_text "$extensions_patch" "/extensions-validator validate"
  require_patch_text "$extensions_patch" "~Module signature appended~"
  require_patch_text "$extensions_patch" "test ! -e /rootfs/usr/lib/firmware"
  if [[ "$version" == upstream ]]; then
    require_patch_text "$extensions_patch" "$compatibility_floor"
    require_patch_text "$extensions_patch" "[staners2](https://github.com/staners2)"
    require_patch_text "$extensions_patch" "author: Dima Aratin"
    if grep -Fq -- "Validated hardware includes Realtek" "$extensions_patch"; then
      fail "$extensions_patch claims unexecuted Realtek validation"
    fi
    if grep -Eq '^\+\| bluetooth-usb-drivers[[:space:]]+\| Needs Maintainer' "$extensions_patch"; then
      fail "$extensions_patch has no accountable maintainer"
    fi
  else
    require_patch_text "$extensions_patch" "Needs Maintainer"
    require_patch_text "$extensions_patch" "$compatibility_floor"
  fi
  for firmware_path in \
    ".kres.yaml" \
    "MAINTAINERS.md" \
    "Makefile" \
    "firmware/mediatek-bluetooth-firmware/README.md" \
    "firmware/mediatek-bluetooth-firmware/manifest.yaml.tmpl" \
    "firmware/mediatek-bluetooth-firmware/pkg.yaml" \
    "firmware/mediatek-bluetooth-firmware/vars.yaml"; do
    require_patch_text "$firmware_patch" "$firmware_path"
  done
  require_patch_text "$firmware_patch" "/linux-firmware:{{ .BUILD_ARG_PKGS }}"
  require_patch_text "$firmware_patch" "BT_RAM_CODE_MT7922_1_1_hdr.bin"
  require_patch_text "$firmware_patch" "/usr/lib/firmware/LICENSES/LICENCE.mediatek"
  require_patch_text "$firmware_patch" "/extensions-validator validate"
  if [[ "$version" == upstream ]]; then
    require_patch_text "$firmware_patch" "$compatibility_floor"
    require_patch_text "$firmware_patch" "[staners2](https://github.com/staners2)"
    require_patch_text "$firmware_patch" "author: Dima Aratin"
    if grep -Eq '^\+\| mediatek-bluetooth-firmware[[:space:]]+\| Needs Maintainer' "$firmware_patch"; then
      fail "$firmware_patch has no accountable maintainer"
    fi
  else
    require_patch_text "$firmware_patch" "Needs Maintainer"
    require_patch_text "$firmware_patch" "$compatibility_floor"
  fi
  require_patch_text "$talos_patch" "os.O_CREATE|os.O_WRONLY|os.O_TRUNC"
  require_patch_text "$talos_patch" "TestCopyFilesTruncatesExistingDestination"

  if grep -E '^\+.*usr/lib/firmware' "$extensions_patch" | \
    grep -Fvq -- "test ! -e /rootfs/usr/lib/firmware"; then
    fail "$extensions_patch bundles or references firmware"
  fi

  if grep -Fq -- "+kernel/net/rfkill/rfkill.ko" "$extensions_patch"; then
    fail "$extensions_patch packages rfkill even though it is built into the kernel"
  fi

  if grep -E '^\+.*(/mediatek/|/firmware/)' "$firmware_patch" | \
    grep -Ev 'BT_RAM_CODE_MT7922_1_1_hdr\.bin|LICENCE\.mediatek|test|mkdir|manifest|README|description|firmware/mediatek-bluetooth-firmware' >/dev/null; then
    fail "$firmware_patch packages firmware outside the MT7922 scope"
  fi

  echo "$version source contract is valid"
}

if (($# == 0)); then
  requested_versions=("${supported_versions[@]}")
else
  requested_versions=("$@")
fi

for version in "${requested_versions[@]}"; do
  validate_version "$version"
done
