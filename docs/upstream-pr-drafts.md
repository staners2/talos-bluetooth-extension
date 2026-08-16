# Upstream discussion and pull request reference

These texts describe the repository state pinned in `versions/upstream.env`.
The implementations are published as the ready-for-review PR series linked in
`docs/upstream-submission.md`. Do not combine the changes across repositories.

## Maintainer discussion

**Title:** Opt-in USB Bluetooth kernel support as a contrib system extension

Talos currently builds the Bluetooth and rfkill kernel subsystems out. A
privileged workload can see an integrated USB Bluetooth controller, but it
cannot create an HCI device because the host has no Bluetooth core or `btusb`
driver. This prevents BlueZ-based workloads such as Home Assistant from using
hardware already present in a node and forces users to add a USB dongle or an
external BLE proxy.

I would like to propose an opt-in `bluetooth-usb-drivers` contrib extension.
The implementation keeps the ownership boundaries explicit:

- `pkgs` enables the Bluetooth LE/rfkill/USB HCI kernel configuration for
  amd64 and arm64;
- `extensions` packages the signed module closure for the matching Talos
  kernel, without firmware or userspace;
- existing official vendor firmware extensions remain authoritative;
- a small, independently useful Talos fix truncates a destination when a later
  extension replaces an existing initramfs file.

The extension does not autoload modules, start BlueZ, expose D-Bus or change the
default installer. A node administrator must select the extension, load
`btusb`, and explicitly configure the userspace access boundary.

The current prototype has been built for amd64 and arm64. Runtime validation on
an integrated MediaTek MT7922 controller produced `hci0`, exposed
`org.bluez.Adapter1`, and completed an active BLE scan on Talos v1.13.8 and
v1.14.0-rc.1. The node was then returned to the official installer and its
Kubernetes, etcd, Cilium, CSI and workload health was checked. Realtek
`0bda:b85b`, Home Assistant host-D-Bus access, and a real Tion GATT connection
remain explicit follow-up gates.

The compressed driver layer is approximately 697 KiB on amd64 and 759 KiB on
arm64. The separate MediaTek firmware layer is approximately 507 KiB on either
architecture and is selected only by nodes that need it.

Before opening the dependent PRs, I would appreciate maintainer guidance on:

1. whether the kernel footprint is acceptable for an opt-in contrib extension;
2. whether Bluetooth autosuspend should retain the upstream kernel default;
3. whether the MediaTek firmware addition should be independent from the
   driver extension;
4. which Talos release should first carry the required kernel configuration.

## `siderolabs/talos` pull request

**Title:** fix: truncate files replaced by system extensions

### What

Open an existing initramfs destination with `O_TRUNC` when copying extension
content, and add a regression test in `internal/pkg/extensions`.

### Why

Multiple extensions can intentionally overlay the same path. Reopening a
longer existing file without truncation leaves stale trailing bytes when the
replacement is shorter. This is generic extension-layer behavior and does not
depend on Bluetooth support.

### Validation

- `go test ./internal/pkg/extensions -run '^TestCopyFilesTruncatesExistingDestination$'`
- `git diff --check`

## `siderolabs/pkgs` pull request

**Title:** feat: enable USB Bluetooth kernel modules

### What

Enable the minimal Bluetooth core, LE, rfkill and USB HCI module set needed by
an opt-in system extension on amd64 and arm64. Include the Intel, Realtek and
MediaTek USB helper modules selected by current commodity controllers. Keep the
kernel's normal USB Bluetooth autosuspend behavior.

### Why

Talos cannot load Bluetooth support from a system extension while the kernel
subsystem is disabled at build time. USB device visibility inside a privileged
pod alone cannot create the host HCI device required by BlueZ.

### Validation

- `make kernel-olddefconfig PLATFORM=linux/amd64,linux/arm64`
- complete multi-arch `kernel` build using the standard bldr workflow
- module signature and `vermagic` checks in the dependent extension build

## `siderolabs/extensions` driver pull request

**Title:** feat: add Bluetooth USB drivers extension

### What

Add a maintained contrib extension containing the signed module dependency
closure for `btusb`: `bluetooth`, `btusb`, `btintel`, `btrtl`, and `btmtk`, plus
architecture-selected crypto dependencies. The package contains no firmware,
BlueZ, D-Bus configuration, device overrides or module autoload policy.

### Why

This lets nodes with supported integrated controllers opt into the host kernel
HCI path used by BlueZ workloads without replacing the controller or adding an
external BLE proxy. Realtek users continue to select the existing official
`realtek-firmware` extension.

### Validation

- standard extension package tests and metadata validation;
- amd64 and arm64 images built against the exact proposed kernel; candidate
  index digest
  `sha256:167cbff8ece4490f3b7695409b0521b15e0592a706ee31556baf22aae10432e3`;
- signed module and `vermagic` validation;
- no firmware paths in the resulting image;
- runtime evidence currently covers MediaTek MT7922; Realtek runtime coverage
  is not claimed.

## `siderolabs/extensions` MediaTek firmware pull request

**Title:** feat: add MediaTek Bluetooth firmware extension

### What

Add a separately maintained firmware extension containing only the MediaTek
Bluetooth firmware selected from the existing pinned `linux-firmware` source.

### Why

Firmware has a different update and licensing lifecycle from kernel modules.
Keeping it separate avoids duplicating vendor blobs in the driver extension and
matches the existing vendor-firmware model in the catalog.

### Validation

- standard firmware package and metadata checks;
- image contains only the declared MediaTek Bluetooth firmware paths;
- amd64/arm64 candidate index digest
  `sha256:a4d782cfcbe59c246fd9ad68f91d4ee7446e210f473df2902af0a3a256f671d5`;
- runtime validation on an MT7922 controller;
- license and source remain inherited from the pinned upstream
  `linux-firmware` package.

## Publication checklist

- Rebase every patch on current upstream `main` and refresh all immutable pins.
- Confirm the Git author matches the GitHub account and all commits satisfy the
  repository DCO/signature policy.
- Explain that the manifest API floor remains `>= v1.13.0-alpha.2`; matching
  kernel availability is enforced by the versioned catalog and `pkgs` image.
- Replace local build statements with reproducible CI jobs or attached logs.
- Record multi-arch image digests and compressed sizes.
- Link the maintainer discussion and dependent PRs in both directions.
- Request backports only if maintainers approve them; do not include release
  branches in the initial proposal.
