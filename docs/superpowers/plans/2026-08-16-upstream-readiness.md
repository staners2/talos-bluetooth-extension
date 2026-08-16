# Talos Bluetooth Upstream Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` to execute this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking. Commits, pushes, issues and pull
> requests remain gated by explicit user authorization.

**Goal:** Turn the validated Bluetooth prototype into the smallest clear set of
PR-ready changes for the official Sidero Labs repositories.

**Architecture:** Keep the upstream contribution split by ownership: Talos fixes
generic extension overlay semantics, pkgs enables a minimal LE/USB kernel stack,
and extensions packages the signed module closure and separately scoped firmware.
The local repository retains only reproducibility, compatibility and evidence
automation that cannot live in the upstream patches.

**Tech Stack:** Bash, Git patches, Linux Kconfig, Kres package definitions, Talos
extension manifests, Go regression test, ShellCheck, Gitleaks, Trivy and upstream
Sidero Labs validation targets.

**Spec:** `docs/superpowers/specs/2026-08-15-talos-bluetooth-extension-design.md`

## Global Constraints

- Target upstream `main`; release backports are maintainer decisions.
- Propose the extension as `contrib` and list `staners2` as its maintainer.
- Keep Bluetooth LE-focused and opt-in; do not add BlueZ, D-Bus or firmware to
  `bluetooth-usb-drivers`.
- Keep Realtek firmware in the official `realtek-firmware` extension.
- Do not claim Realtek `0bda:b85b`, Home Assistant or Tion acceptance until each
  has been tested directly.
- Generate upstream derived files through Kres; do not edit generated Makefiles
  manually.
- Do not create commits, push branches, publish images, open issues or open PRs
  without explicit authorization.

---

### Task 1: Encode the Current Upstream Contract

**Files:**

- Modify: `tests/source-contract.sh`
- Modify: `scripts/validate-source.sh`

**Interfaces:**

- Consumes: current upstream `main` layouts and the first Talos version expected
  to contain the matching pkgs change.
- Produces: a failing source contract for stale maintainer, compatibility and
  hardware-validation claims.

- [x] Add assertions rejecting `Needs Maintainer`, a compatibility floor above
  the pinned validator's Talos contract and an unverified Realtek claim.
- [x] Run `make test` and confirm the new assertions fail for those exact reasons.
- [x] Add an upstream-main applicability check that treats generated files as
  derived artifacts.

### Task 2: Minimize and Regenerate the Upstream Patch Set

**Files:**

- Create: `versions/upstream.env`
- Create: `patches/upstream/pkgs/0001-enable-bluetooth-usb-modules.patch`
- Create: `patches/upstream/extensions/0001-add-bluetooth-usb-drivers.patch`
- Create: `patches/upstream/extensions/0002-add-mediatek-bluetooth-firmware.patch`
- Create: `patches/upstream/talos/0001-truncate-overwritten-extension-files.patch`
- Preserve: all pinned `v1.13.8` and `v1.14.0` patch sets as historical build
  inputs.

**Interfaces:**

- Consumes: clean current upstream clones and the tested module closure.
- Produces: independent PR-shaped patches that apply cleanly to upstream `main`.

- [x] Apply the source-only parts in clean upstream `main` trees and regenerate Kres
  outputs with the upstream-pinned Kres image.
- [x] Replace generic author/maintainer placeholders with `Dima Aratin` and
  `staners2`.
- [x] Keep the repository's system-extension API compatibility floor. Bind
  kernel-module availability through the versioned catalog and matching `pkgs`
  image instead of raising the manifest floor above the pinned validator.
- [x] Correct README evidence to distinguish tested MediaTek from targeted
  Realtek hardware.
- [x] Preserve the minimal five-module amd64 closure and the two arm64 crypto
  dependencies; do not add userspace or duplicate firmware.
- [x] Run `git apply --check` against clean current upstream trees.

### Task 3: Senior-Level Codebase Reduction and Documentation Alignment

**Files:**

- Modify only scripts, tests and docs that duplicate behavior or make stale
  claims.
- Create: `docs/upstream-submission.md`

**Interfaces:**

- Consumes: the regenerated patch set and existing runtime evidence.
- Produces: a concise submission rationale and reproducible local review flow.

- [x] Review every shell function and test fixture for a concrete current use;
  remove only demonstrably redundant logic.
- [x] Keep safety validation at external boundaries even where it costs lines.
- [x] Update v1.14 runtime evidence, rollback evidence and remaining Realtek /
  Home Assistant / Tion gates.
- [x] Write concise PR dependencies, rationale and reviewer notes without
  overstating support.

### Task 4: Upstream and Security Verification

**Files:**

- Modify findings from scanners only when they are in this repository's scope.
- Create: `docs/security-review-2026-08-16.md`

**Interfaces:**

- Consumes: final source tree and prepared upstream checkouts.
- Produces: fresh build, lint, secret, configuration and vulnerability evidence.

- [x] Run `make test`, Bash syntax checks, ShellCheck and whitespace checks.
- [x] Run upstream patch applicability, Kconfig normalization, extension catalog,
  validator and relevant Go regression tests where the local environment permits.
- [x] Run Gitleaks over the complete worktree and history available locally.
- [x] Run Trivy filesystem/config/secret scanning and Grype against built
  extension images when locally available.
- [x] Review shell command construction, path validation, digest pinning, module
  signatures, firmware provenance and kernel attack-surface changes manually.
- [x] Fix actionable findings and repeat every affected check.
- [x] Record tool versions, commands, results and explicit coverage limits.

### Task 5: Submission Handoff

**Files:**

- Create: `docs/upstream-pr-drafts.md`

**Interfaces:**

- Consumes: verified independent patches and evidence.
- Produces: issue and PR text ready for user-authorized publication.

- [x] Draft the initial maintainer discussion with the no-dongle smart-home use
  case, security boundary, size impact and hardware evidence.
- [x] Draft independent Talos, pkgs, driver-extension and firmware-extension PR
  bodies with dependencies and test results.
- [x] Verify DCO/GPG identity prerequisites without creating commits.
- [x] Stop before any external write and request explicit publication approval.
