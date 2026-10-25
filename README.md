# Bluetooth USB Drivers

> [!WARNING]
> **Out-of-tree only — do not expect this extension to ever be included in
> mainstream Talos Linux.** Upstream maintainers oppose Bluetooth support because
> of its kernel attack surface, history of CVEs and long-term maintenance burden.
> This is an unofficial project, not a Sidero Labs-supported extension.
>
> See the author's [kernel PR, siderolabs/pkgs#1651](https://github.com/siderolabs/pkgs/pull/1651),
> the maintainer's [security objection](https://github.com/siderolabs/pkgs/pull/1651#issuecomment-5328377153)
> and [maintenance concerns](https://github.com/siderolabs/pkgs/pull/1651#issuecomment-5359336126).
> The PR remains open as of 2026-10-25; this warning reflects upstream's stated
> position, not a formal closure or a guarantee about future upstream decisions.

This system extension provides the Bluetooth core and USB HCI kernel modules
required to use supported USB and integrated USB Bluetooth controllers on
Talos Linux.

The proposed driver extension is published in the author's
[siderolabs/extensions#1203](https://github.com/siderolabs/extensions/pull/1203).
See [upstream submission status](docs/upstream-submission.md) for the related PRs.

## Installation

This extension requires a custom Talos kernel with matching, signed Bluetooth
modules and a custom installer. Adding it to a stock Talos image is not enough:
the matching kernel must have Bluetooth enabled at build time. It is not
available from the official extension catalog or Image Factory.

Follow this repository's [build and validation guide](docs/build-and-validation.md).
The upstream [Installing Extensions](https://github.com/siderolabs/extensions#installing-extensions)
guide describes the general mechanism, not availability of this custom package.

Install the firmware extension required by the controller alongside this
extension. Realtek controllers use `realtek-firmware`; MediaTek controllers use
`mediatek-bluetooth-firmware`.

## Usage

Enable `btusb` in the Talos machine configuration. Kernel dependencies and the
matching chipset helper module load automatically.

```yaml
machine:
  kernel:
    modules:
      - name: btusb
```

## Verifying

Check that the Bluetooth modules are loaded:

```console
talosctl -n <IP> read /proc/modules | grep -E "bluetooth|btusb|btintel|btrtl|btmtk"
```

Check that the kernel created an HCI device:

```console
talosctl -n <IP> ls /sys/class/bluetooth
```

Kernel initialization and firmware errors are available in the node log:

```console
talosctl -n <IP> dmesg | grep -i bluetooth
```

## Notes

- The extension contains kernel modules only. BlueZ, D-Bus policy and
  application configuration belong in the workload.
- Firmware is provided by separate vendor extensions and is not duplicated in
  this package.
- The workload running BlueZ must use the host network namespace to access the
  host Bluetooth management interface.
