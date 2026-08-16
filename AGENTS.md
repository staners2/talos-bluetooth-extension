# Talos Bluetooth Extension Working Context

## Objective

Develop upstream-quality Bluetooth support for Talos Linux so the built-in
Bluetooth controller in a Talos node can be used by Home Assistant without an
external ESP32 or USB replacement adapter.

The intended first use case is local BLE communication with Tion devices. The
implementation must remain generic enough to be proposed upstream to Sidero
Labs and must not become a node-specific binary hack.

## Verified baseline

- The homelab runs Talos Linux. The observed cluster version was `v1.13.3`.
  Recheck the current cluster and latest upstream release before choosing a
  build target.
- The target hardware exposes USB device `0bda:b85b`, reported as a Realtek Bluetooth
  Radio.
- The current Talos image already contains the official `realtek-firmware`
  system extension.
- The current node has no `/sys/class/bluetooth`, and the Bluetooth kernel
  modules are not loaded.
- The examined Talos kernel configuration had `CONFIG_BT` and
  `CONFIG_RFKILL` disabled. Confirm this against the exact upstream tag used by
  every build.
- Home Assistant can see the USB controller from its privileged pod, but USB
  visibility alone is insufficient. Home Assistant ultimately needs a working
  kernel HCI device, BlueZ and system D-Bus access.
- Treat the deployment repository as read-only unless the user explicitly asks
  to integrate or deploy the resulting image.

## Required architecture

Treat Bluetooth enablement as separate, testable layers:

1. The Talos kernel configuration enables the smallest usable Bluetooth core,
   LE, rfkill and USB Realtek driver set.
2. Kernel modules are built, signed and version-matched with the exact Talos
   kernel that will load them.
3. A Talos system extension packages only the required modules and metadata in
   the structure expected by the current `siderolabs/extensions` repository.
4. Realtek firmware remains a dependency on the official
   `realtek-firmware` extension; do not duplicate firmware blobs.
5. BlueZ and D-Bus userspace integration is designed separately from kernel
   enablement. Do not claim Home Assistant support until an `hci` device and an
   active BlueZ D-Bus API have both been verified.
6. A custom Talos installer is selected only for the approved test node; other cluster
   nodes remain on official images unless broader testing is explicitly
   approved.

Validate this architecture against current upstream build definitions. If the
current Talos extension mechanism requires a different boundary between
`pkgs`, `extensions` and `talos`, document the evidence and update the design
before implementation.

## Upstream sources and provenance

Use primary sources as authoritative:

- <https://github.com/siderolabs/extensions>
- <https://github.com/siderolabs/pkgs>
- <https://github.com/siderolabs/talos>
- <https://docs.siderolabs.com/talos/latest/build-and-extend-talos/>
- <https://www.home-assistant.io/integrations/bluetooth/>

Known community references:

- Kernel configuration example:
  `dancavallaro/talos-pkgs@c8d738929f88f18149ac5da7c0e1dd591ec14e0b`.
- Talos module/initramfs example:
  `dancavallaro/talos@ad53f78b677f3a180dbf873ebd726d5e1fbe34e3`.

Community changes are evidence that the approach can work, not a dependency to
copy blindly. Record the source commit for every borrowed fragment, review its
license, and adapt it to the current upstream APIs and kernel configuration.
Never import generated artifacts or unsigned third-party installer images.

## Development rules

- Read `README.md`, the approved design under `docs/superpowers/specs/`, and
  `git status` before changing files.
- Follow the current contribution, formatting, lint and build conventions in
  the upstream repositories. Do not invent parallel packaging formats.
- Keep patches minimal. Enable only the Bluetooth protocols and drivers needed
  for USB BLE with the Realtek controller, plus dependencies selected by the
  kernel configuration system.
- Do not disable kernel module signature enforcement in a production image.
- Pin upstream tags, container images and tool versions. Record source commit
  SHAs and image digests in build provenance.
- Do not vendor full upstream repositories into this project. Use documented
  patches, build definitions and shallow temporary checkouts.
- Do not read or edit generated dependency directories or caches.
- Never store tokens, signing keys, kubeconfig contents or other credentials in
  Git. Use the existing secret-management workflow when CI signing is added.
- Do not create commits, publish images, open upstream pull requests, install a
  Talos image or modify the live cluster without explicit user authorization.
- Installation on a physical node requires a documented rollback image and a
  verified recovery path before rebooting the node.

## Quality and acceptance gates

The project is not complete when an image merely builds. Evidence must cover:

- kernel config checks for the required `CONFIG_BT*` and `CONFIG_RFKILL`
  values;
- module dependency, signature and `vermagic` validation;
- upstream-compatible extension metadata and lint checks;
- reproducible amd64 build from pinned sources;
- absence of bundled duplicate Realtek firmware;
- boot of the custom installer on the approved test node with rollback available;
- detection of `hci0` and successful loading of `bluetooth`, `btusb` and
  `btrtl` without kernel errors;
- BlueZ enumeration and an active BLE scan;
- Home Assistant access through D-Bus with only the capabilities and mounts it
  actually requires;
- a real BLE connection to a Tion device, not only advertisement discovery;
- unchanged health of Kubernetes, Cilium, CSI and workloads after the node
  rejoins the cluster.

## Session workflow

At the start of each Codex session:

1. Confirm the working directory is this repository.
2. Read this file, `README.md`, the approved design and the active plan.
3. Inspect the working tree and preserve unfinished user or agent changes.
4. Verify current upstream Talos tags and contribution rules before relying on
   version-sensitive facts.
5. State whether the work affects only source artifacts or also proposes a
   live image/cluster mutation.

Lead status reports with the current outcome, exact validation performed and
remaining safety gates.
