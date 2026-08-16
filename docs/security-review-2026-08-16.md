# Security review: 2026-08-16

## Scope

The review covers this repository, the generated upstream patch series and the
locally built `bluetooth-usb-drivers` and `mediatek-bluetooth-firmware` OCI
images. Downloaded dependencies and build caches were treated as opaque; their
published images are checked at the OCI boundary instead.

No scanner can prove the absence of every vulnerability. The result below
states what each tool actually covered and keeps unsupported checks visible.

## Source scans

| Check | Version or immutable image | Result |
| --- | --- | --- |
| Project tests | repository `Makefile` | Pass: source contract, mutation tests, shell syntax, argument safety and compatibility checks |
| ShellCheck | 0.11.0 | Pass on `scripts/*.sh` and `tests/*.sh` |
| Gitleaks | 8.30.1 | No leaks in the filesystem scan; output redaction enabled |
| Semgrep | 1.172.0, image `sha256:65dcd4408adda7c183a6b4550cb1e9b19f7f627a6fbb7e0559bd466bedc44d7b` | 39 applicable community `security-audit` and `secrets` rules on 36 files; no findings |
| Trivy filesystem | 0.74.0, image `sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969` | No secrets; no supported dependency or IaC files, so vulnerability and misconfiguration results are not claimed |
| Grype directory | 0.117.0, image `sha256:ddf9e9f204049f3a4a0955ef70873cabab6a31432125ad4f20a490b54950a253` | No packages with known fixed vulnerabilities found |

### Publication refresh: 2026-08-17

The publication snapshot passed `gmake test`, ShellCheck 0.11.0 and Gitleaks
8.30.1. Semgrep 1.173.0 ran 85 applicable community rules across 36 tracked
files and reported no findings. Trivy 0.74.0, pinned to the digest above, was
rerun against the amd64 and arm64 driver and firmware images: secret scanning
reported no findings, while vulnerability scanning reported no supported
package targets, as expected for raw modules and firmware.

All four upstream commits include DCO sign-offs and valid SSH signatures that
GitHub reports as `Verified`. The Sidero Labs Conform `GPG Identity` check still
reports `EOF` because its identity source covers public Sidero Labs organization
members and OpenPGP keys, not external contributors using GitHub SSH signing.

## Manual attack-surface review

- All upstream source revisions are full commit SHAs. Kres is pinned by both
  source commit and OCI digest.
- The driver extension contains kernel modules and metadata only. It starts no
  service, grants no capability, mounts no host path and contains no BlueZ or
  D-Bus policy.
- Firmware is a separate package. The driver build rejects any
  `/usr/lib/firmware` output, and Realtek firmware remains owned by the existing
  official extension.
- Bluetooth is built as modules and is opt-in at the installer and machine
  configuration layers. Nodes that do not select and load the extension do not
  expose the Bluetooth protocol implementation.
- Module signature enforcement is not disabled. The package test requires at
  least one module and the appended kernel-module signature marker.
- Installer assembly resolves local mutable tags to digests before invoking the
  Talos imager. Official extensions must already be digest-pinned.
- The local imager needs a privileged container, but receives only a new output
  directory and runs on the isolated build network. This privilege is not part
  of the installed extension.
- User-controlled version names are restricted to known files; output and
  checkout destinations must be new absolute paths outside the repository,
  `/`, and the home directory.
- No downloaded script is piped into a shell, and no credentials, kubeconfig,
  signing material or registry token is stored in the project.
- Talos regenerates a combined kernel-module dependency tree across all selected
  driver extensions. The proposed truncation fix prevents stale trailing data
  when one extension overlays a shorter file.

## Built-image scans

The upstream candidate was built for `linux/amd64` and `linux/arm64` against
Linux `6.18.44-talos`. The `pkgs` base was subsequently refreshed to the commit
in `versions/upstream.env`; `kernel-olddefconfig` reports no Bluetooth config
changes on that base, while the authoritative full rebuild is delegated to
upstream CI. The locally verified immutable multi-architecture image digests
are:

| Image | Digest |
| --- | --- |
| Matching Talos kernel | `sha256:306e74997e191977c787c32c2101af30886d15e45c161a657f34a58227ee0b8b` |
| `bluetooth-usb-drivers` | `sha256:167cbff8ece4490f3b7695409b0521b15e0592a706ee31556baf22aae10432e3` |
| Pinned `linux-firmware` source image | `sha256:e85804039c6db60721ef1199399fc915226ed9493a6400925073fdfe1d3140dd` |
| `mediatek-bluetooth-firmware` | `sha256:a4d782cfcbe59c246fd9ad68f91d4ee7446e210f473df2902af0a3a256f671d5` |

Each extension platform rootfs was exported independently and scanned with the
same immutable Trivy and Grype images listed above. Trivy reported no secrets;
Grype reported no known vulnerable packages at the `low` threshold or above.
The driver image has no firmware directory. The firmware image contains only
`BT_RAM_CODE_MT7922_1_1_hdr.bin` and `LICENCE.mediatek`, with identical hashes
on both architectures.

These are deliberately narrow claims. Raw kernel modules and firmware do not
contain an OS package database, so Trivy reported no supported vulnerability
targets and Grype could not map the files to Linux kernel CVEs. Kernel risk is
instead bounded by the exact upstream commit, matching `6.18.44-talos`
`vermagic`, PKCS#7 module signatures and the minimal Kconfig/module closure.
The CVE status of that upstream kernel must still be reviewed again at
publication time.

## Remaining security gates

- Re-run CVE scans after any maintainer-requested rebase because vulnerability
  databases and upstream bases change over time.
- Runtime-test Realtek `0bda:b85b`; the current hardware evidence is MediaTek
  MT7922 only.
- Define and test the least-privilege Home Assistant to host-BlueZ D-Bus
  boundary before claiming end-to-end Home Assistant support.
- Complete a real authenticated GATT connection to a Tion device; advertisement
  discovery alone is not an application-security test.
