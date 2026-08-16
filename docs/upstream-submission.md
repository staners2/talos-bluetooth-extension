# Upstream submission scope

## Submission state

The complete upstream series is published and ready for maintainer review:

- [siderolabs/pkgs#1651](https://github.com/siderolabs/pkgs/pull/1651) enables
  the kernel modules from signed commit
  `310618841c077775aa832b691f720ca6d230e2f9`;
- [siderolabs/extensions#1203](https://github.com/siderolabs/extensions/pull/1203)
  adds the generic driver extension from signed commit
  `acc438a8ed5e2f7afa54bfc4709525b6d08d1169`;
- [siderolabs/extensions#1204](https://github.com/siderolabs/extensions/pull/1204)
  adds the separate MT7922 firmware extension from signed commit
  `ce43ee86f8c44bd4e3002b9762aa542ba15b6688`;
- [siderolabs/talos#14056](https://github.com/siderolabs/talos/pull/14056)
  fixes extension-file truncation from signed commit
  `5bebe5f984147ef180a9dea076c93ed22b8c5d45`.

All four commits are reported as `Verified` by GitHub and include DCO
sign-offs. Merge and backport decisions now belong to the Sidero Labs
maintainers.

## Problem

Talos currently builds its kernel with `CONFIG_BT` and `CONFIG_RFKILL` disabled.
Passing an integrated Bluetooth controller into a privileged Kubernetes pod is
therefore insufficient: the host has no Bluetooth HCI stack, `btusb` driver or
`hci0` device for BlueZ to use.

This affects smart-home installations that already have supported Bluetooth
hardware integrated into their node. An opt-in driver extension would allow
Home Assistant and similar workloads to use that controller without requiring
an additional USB dongle or an external BLE proxy.

## Proposed boundary

The contribution is split by upstream ownership:

1. `siderolabs/talos`: generic `O_TRUNC` fix when a later extension replaces a
   longer file, with a Go regression test.
2. `siderolabs/pkgs`: LE-focused Bluetooth core, rfkill and USB HCI support for
   `amd64` and `arm64`.
3. `siderolabs/extensions`: `contrib` package `bluetooth-usb-drivers` containing
   only the signed module closure built for the matching Talos kernel.
4. `siderolabs/extensions`: separate `mediatek-bluetooth-firmware` package for
   the tested MT7922 controller. Realtek continues to use the existing official
   `realtek-firmware` extension.

The driver extension does not contain BlueZ, D-Bus, firmware, device-specific
USB ID overrides or automatic module loading. Nodes opt in by selecting the
extension and loading `btusb` in machine configuration.

The extension manifest retains the repository's
`>= v1.13.0-alpha.2` system-extension API floor. This value describes manifest
and filesystem compatibility, not the first kernel that contains Bluetooth
modules. Module availability is bound by the versioned extensions catalog and
the matching `pkgs` kernel image; raising the manifest floor to the development
kernel version would make the repository's pinned validator reject the package
without improving runtime safety.

## Current upstream pins

The PR candidate in `patches/upstream/` is generated against:

- `siderolabs/talos@be6b96386a99f2c90ac7337db570540644feb625`;
- `siderolabs/pkgs@c9173bb3fa60ae23ad8f2c6e8cee0499a8c45077`;
- `siderolabs/extensions@f2c879a7c5ab806063b6a48d347ae0d78df91b28`;
- Kres `76f6e99`, image digest
  `sha256:1944aac3fe9df24c3da89fec78d64811dea3a07bbd073645985738788056bfd6`.

These values are the published review snapshot, not a promise that the PRs can
remain unrebased. Refresh them whenever upstream requests a rebase.

## Evidence

- Matching signed modules and exact `vermagic` were built for Linux `6.18.42`
  and `6.18.44`.
- The current upstream-main amd64/arm64 candidate completed a full kernel and
  extension build; immutable image digests are recorded in the build evidence.
- The amd64 extension contains only `bluetooth`, `btusb`, `btintel`, `btrtl` and
  `btmtk`; arm64 additionally contains the Kconfig-selected ECC/ECDH modules.
- Module signature enforcement remains enabled.
- The driver extension contains no firmware and does not duplicate the official
  Realtek firmware package.
- On MediaTek MT7922 hardware, both Talos `v1.13.8` and `v1.14.0-rc.1` created
  `hci0`; BlueZ exposed `org.bluez.Adapter1` and active BLE scans found nearby
  devices.
- The test node was returned to official Talos `v1.13.8`, and Kubernetes, etcd,
  Cilium, CSI and workloads were checked after rollback.

## Claims intentionally not made

- Realtek `0bda:b85b` has not yet been runtime-tested with this extension.
- The permanent Home Assistant pod has not yet been connected to host BlueZ.
- A real GATT connection to a Tion device has not yet been completed.
- Inclusion in `contrib` would make the package part of the official catalog,
  but support would remain with maintainer `staners2`, not Sidero Labs.

## Review and merge order

The Talos truncation fix and MediaTek firmware package are independently
reviewable. The driver extension requires the `pkgs` kernel change and should
not be released for a Talos version until its matching kernel publishes those
modules. Backports remain a Sidero Labs maintainer decision.
