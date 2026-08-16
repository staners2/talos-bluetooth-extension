# Talos Bluetooth USB Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or `superpowers:executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. This repository currently forbids commits, pushes, image publication
> and live-cluster changes without separate authorization.

**Goal:** Produce and locally validate upstream-shaped, reproducible patch sets
that enable the generic Linux Bluetooth USB stack and package its signed modules
as a Talos system extension for Talos `v1.13.8` and the `release-1.14` line.

**Architecture:** Keep the change split across the same boundaries used upstream:
`siderolabs/pkgs` owns kernel configuration, while `siderolabs/extensions` copies
a minimal module closure from the matching kernel package. A separate generic
`siderolabs/talos` patch fixes truncation when extensions overwrite metadata.
This repository stores only pins, patch series, verification scripts and evidence;
it does not vendor upstream repositories.

**Tech Stack:** Bash, Git patches, Linux Kconfig, Sidero Labs bldr/Kres package
definitions, Talos extension manifest v1alpha1.

**Spec:** `docs/superpowers/specs/2026-08-15-talos-bluetooth-extension-design.md`

## Global Constraints

- Production baseline is Talos `v1.13.8`.
- The parallel upstream line is `release-1.14`, pinned to exact commits until
  `v1.14.0` GA exists.
- Configure both `amd64` and `arm64` for official upstream CI compatibility.
- Enable only Bluetooth core, LE, rfkill, USB HCI and Realtek USB support plus
  Kconfig-selected dependencies.
- Do not bundle Realtek firmware; depend on the official `realtek-firmware` extension.
- Keep kernel module signature enforcement enabled.
- Keep the Talos `O_TRUNC` fix independent from Bluetooth packaging and cover it
  with its regression test.
- Do not commit, push, publish images, open PRs or modify the live cluster.

---

### Task 1: Version Matrix and Source Validation Contract

**Files:**

- Create: `versions/v1.13.8.env`
- Create: `versions/v1.14.0.env`
- Create: `tests/source-contract.sh`
- Create: `scripts/validate-source.sh`

**Interfaces:**

- Consumes: exact upstream commits verified from Git refs and Talos `pkgs` pins.
- Produces: `scripts/validate-source.sh [version]`, which validates either one
  version or both supported versions without mutating upstream repositories.

- [x] Write `tests/source-contract.sh` first so it fails while version manifests,
  patch paths and validator are missing.
- [x] Run `bash tests/source-contract.sh` and confirm the failure names the first
  missing contract artifact.
- [x] Add exact Talos, pkgs and extensions refs plus their human-readable tags to
  the two environment manifests.
- [x] Implement `scripts/validate-source.sh` to validate allowed version names,
  required files, 40-character lowercase SHAs, patch headers, required/forbidden
  Kconfig entries and firmware absence.
- [x] Run the source contract and validator for both versions.

### Task 2: Minimal Bluetooth Kernel Configuration Patches

**Files:**

- Create: `patches/v1.13.8/pkgs/0001-enable-bluetooth-usb-modules.patch`
- Create: `patches/v1.14.0/pkgs/0001-enable-bluetooth-usb-modules.patch`
- Modify: `tests/source-contract.sh`

**Interfaces:**

- Consumes: upstream `kernel/build/config-amd64` and `config-arm64` at the exact
  `PKGS_COMMIT` for each version.
- Produces: patches enabling the same reviewed Kconfig contract on both architectures.

- [x] Add failing tests for required symbols and explicitly forbidden protocols,
  transports, vendors and debug facilities.
- [x] Confirm the tests fail because the pkgs patches do not yet exist.
- [x] Build the `v1.13.8` patch against `f677246a73ed1353a1e0ec9e92f0027b2f759978`.
- [x] Build the `v1.14.0` patch against `effed4398f9bda2126d37b1547c519bb121c82e6`.
- [x] Verify both patches apply with `git apply --check` to clean pinned checkouts.
- [x] Run static source tests and official dual-architecture `kernel-olddefconfig`.
  Full kernel compilation remains a separate build gate.

### Task 3: Upstream-Shaped Bluetooth Driver Extension Patches

**Files:**

- Create: `patches/v1.13.8/extensions/0001-add-bluetooth-usb-drivers.patch`
- Create: `patches/v1.14.0/extensions/0001-add-bluetooth-usb-drivers.patch`
- Modify: `tests/source-contract.sh`

**Interfaces:**

- Consumes: matching Sidero kernel image selected by upstream `BUILD_ARG_PKGS`.
- Produces: `bluetooth-usb-drivers` target with manifest, variables, README,
  architecture-specific module lists, validator test and maintainer entry.

- [x] Add failing tests for extension metadata, package validation, explicit module
  lists, `.kres.yaml` registration, maintainer registration and firmware exclusion.
- [x] Confirm the tests fail because the extension patches do not yet exist.
- [x] Create the extension source in temporary exact upstream checkouts, following
  current `joydev` and `usb-audio-drivers` patterns.
- [x] Include `bluetooth.ko`, `btusb.ko`, `btintel.ko` and `btrtl.ko`; keep rfkill
  built into the matching kernel
  for both architectures, plus the Kconfig-selected arm64 ECC/ECDH modules.
- [x] Make the package test fail on any unsigned module, validate the rootfs with
  `extensions-validator`, and assert that no firmware path is created.
- [x] Register the target in `.kres.yaml` and the maintainer in `MAINTAINERS.md`.
- [x] Generate clean unified patches and verify them with `git apply --check`.
- [x] Mark the module list as requiring confirmation from built `modules.dep` and
  `modinfo`; do not claim artifact acceptance before that gate runs.

### Task 4: Reproducible Patch Preparation Workflow

**Files:**

- Create: `scripts/prepare-upstream.sh`
- Create: `Makefile`
- Modify: `README.md`

**Interfaces:**

- Consumes: supported version name and a new explicit destination directory.
- Produces: exact shallow checkouts of `pkgs`, `extensions` and `talos`, with the
  version-specific patch series applied to all affected repositories.

- [x] Add failing tests for version rejection, existing-destination rejection and
  exact pin validation.
- [x] Implement safe argument validation; never accept an empty, root, home or
  existing destination.
- [x] Clone/fetch exact commits, verify `HEAD`, apply every available patch series
  and print the resulting prepared-source status.
- [x] Add `make validate` and documented preparation commands.
- [x] Run shell syntax checks and offline static tests.

### Task 5: Source Verification and Build Handoff

**Files:**

- Modify: `README.md`
- Create: `docs/build-and-validation.md`

**Interfaces:**

- Consumes: completed source patches and validation scripts.
- Produces: exact commands and expected evidence for the authorized local build gate.

- [x] Apply every patch to a clean checkout at its exact commit.
- [x] Run `bash -n` on all scripts and the complete source contract.
- [x] Run whitespace checks on repository artifacts and patched upstream checkouts.
- [x] Document commands for `kernel-olddefconfig`, dual-architecture kernel build,
  module closure/signature/vermagic checks, extension validator and duplicate finder.
- [x] Review the final diff for generated/vendor files, duplicate firmware,
  placeholders, unrelated edits and claims unsupported by executed evidence.
- [x] Report source implementation separately from build, container-runtime and
  hardware/live-runtime acceptance gates.

### Task 6: Local Reproducible Build and Isolated Runtime Validation

**Files:**

- Create: `scripts/build-local-components.sh`
- Create: `tests/build-local-components.sh`
- Modify: `docs/build-and-validation.md`

**Interfaces:**

- Consumes: prepared pinned upstream trees and a private local registry.
- Produces: custom kernel, matching module extensions and Talos installer without
  publishing externally or modifying a physical Talos node.

- [x] Build all module-owning extensions against one exact custom kernel and
  retain official digest-pinned userspace/firmware extensions.
- [x] Reproduce and fix the extension metadata truncation defect in Talos.
- [x] Complete corrected installer builds for both supported versions.
- [x] Verify signatures, vermagic, dependency metadata and firmware separation.
- [x] Boot the resulting Talos source/image boundary in an isolated native-arch
  container and verify Talos plus Kubernetes health where the host supports it.
- [x] Record exact artifact digests and clearly separate container evidence from
  the still-unexecuted USB HCI, BlueZ, Tion and live-cluster gates.
