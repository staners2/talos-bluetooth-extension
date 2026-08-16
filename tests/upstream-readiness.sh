#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
validator="$project_root/scripts/validate-source.sh"

"$validator" upstream

test_root=$(mktemp -d "${TMPDIR:-/tmp}/talos-bluetooth-upstream.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

cp -R "$project_root/scripts" "$project_root/versions" "$project_root/patches" "$test_root/"
test_validator="$test_root/scripts/validate-source.sh"
drivers_patch="$test_root/patches/upstream/extensions/0001-add-bluetooth-usb-drivers.patch"
firmware_patch="$test_root/patches/upstream/extensions/0002-add-mediatek-bluetooth-firmware.patch"

expect_rejected() {
  local message=$1

  if "$test_validator" upstream >/dev/null 2>&1; then
    echo "$message" >&2
    exit 1
  fi
}

sed -i.bak \
  's/| Dima Aratin        | \[staners2\](https:\/\/github.com\/staners2)/| Needs Maintainer   | NA/' \
  "$drivers_patch"
rm "$drivers_patch.bak"
expect_rejected "upstream validator accepted a driver extension without a maintainer"

cp "$project_root/patches/upstream/extensions/0001-add-bluetooth-usb-drivers.patch" "$drivers_patch"
sed -i.bak 's/>= v1.13.0-alpha.2/>= v1.15.0-alpha.0/' "$drivers_patch"
rm "$drivers_patch.bak"
expect_rejected "upstream validator accepted a manifest floor incompatible with its pinned contract"

cp "$project_root/patches/upstream/extensions/0001-add-bluetooth-usb-drivers.patch" "$drivers_patch"
sed -i.bak \
  's/+Talos Linux\./+Talos Linux. Validated hardware includes Realtek 0bda:b85b./' \
  "$drivers_patch"
rm "$drivers_patch.bak"
expect_rejected "upstream validator accepted an unexecuted Realtek validation claim"

cp "$project_root/patches/upstream/extensions/0001-add-bluetooth-usb-drivers.patch" "$drivers_patch"
sed -i.bak \
  's/| Dima Aratin        | \[staners2\](https:\/\/github.com\/staners2)/| Needs Maintainer   | NA/' \
  "$firmware_patch"
rm "$firmware_patch.bak"
expect_rejected "upstream validator accepted a firmware extension without a maintainer"

echo "upstream readiness tests passed"
