# Build evidence: Talos Bluetooth extension

Дата проверки: 2026-08-15–16.

## Итог

- Обе поддерживаемые линии воспроизводимо собраны из pinned upstream source.
- Talos `v1.13.8-bluetooth.3` и `v1.14.0-rc.1` временно загружались на
  выделенный тестовый узел: kernel HCI, MediaTek MT7922 firmware, BlueZ system D-Bus и active
  BLE scan работали на обеих линиях.
- После теста узел возвращён на официальный Talos `v1.13.8`; node `Ready`,
  Kubernetes API, etcd, Cilium, CSI и workloads восстановились.
- Целевой Realtek-узел не изменялся.
- На дату проверки GA tag `v1.14.0` ещё отсутствует, поэтому manifest фиксирует
  проверенный `v1.14.0-rc.1` и Linux `6.18.44`.

## Матрица воспроизводимости

| Поле | `v1.13.8` | `v1.14.0` line |
| --- | --- | --- |
| Talos ref | `v1.13.8` | `v1.14.0-rc.1` |
| Talos commit | `3de4932272a820af6de3852691a35645565c33b3` | `7a84d742b3d53451cbaa1eb91d9b12403e80161c` |
| pkgs commit | `f677246a73ed1353a1e0ec9e92f0027b2f759978` | `effed4398f9bda2126d37b1547c519bb121c82e6` |
| extensions commit | `a0a1c3996c1ba8648ce1269c004dacde89ad4838` | `076693f8a560d71a4100a81adbd52c077f94af6f` |
| Linux | `6.18.42` | `6.18.44` |
| build tag | `v1.13.8-bluetooth.3` | `v1.14.0-bluetooth.3` |
| custom kernel digest | `sha256:a3f1b60f6021c04d1869be77bb053529c04d5a5bb9f1e5e34cc38e0ff20687bd` | `sha256:aa03ba498015326c50340061145fcac0241932dc491ec56b610b272b062dd579` |
| Talos container digest | `sha256:8e6a629173e43c2f49c437e579796a4cb2b88930217c4474604e9ed9ae1a1b35` | `sha256:8ed9c380ee4fbda972022035ce35d267a04c7bd9aa4a9c3311d3a447bbdc4e32` |
| Bluetooth extension digest | `sha256:24aa52002842008146835cc90bea639134e7636c5b420f01cf008e3200dba21e` | `sha256:d34f3f4aeb37a0c41bfae4942fd15b52c6d6c9a436d9197f6ec82e14a103b82a` |
| MediaTek firmware digest | `sha256:c89c494442578434b187ab3dfee80dbf07e126cfab66e153c42e084963f9b7e7` | `sha256:bd3928f797726bb989baff2288a4042853e121d97ef22bacb8a9bcfe67435afa` |
| installer SHA-256 | `7a3f945379f480a4bfbb68bdba2afcb2258f7bae9807fd9017d00f1e360dbf4b` | `991a4276815aa73af3957209147344752ef0b5d68f4e276a64bd3ec28faf4ca2` |

Полный список 14 extension references и immutable digests находится в
`provenance.txt`. Семь kernel-dependent extensions собраны локально против одного
custom kernel: `amdgpu`, `bluetooth-usb-drivers`, `drbd`, `uhid`, `uinput`,
`usb-audio-drivers`, `v4l-uvc-drivers`. Отдельно собрана минимальная
`mediatek-bluetooth-firmware`. Шесть уже используемых extensions взяты из
официального каталога по digest: `amd-ucode`, `fuse3`, `iscsi-tools`,
`nfs-utils`, `nvme-cli`, `realtek-firmware`.

Текущие артефакты:

- `artifacts/v1.13.8-bluetooth.3-mt7922/installer-amd64.tar`;
- `artifacts/v1.13.8-bluetooth.3-mt7922/installer-amd64.tar.sha256`;
- `artifacts/v1.13.8-bluetooth.3-mt7922/provenance.txt`;
- `artifacts/v1.14.0-rc.1-bluetooth.3-mt7922/installer-amd64.tar`;
- `artifacts/v1.14.0-rc.1-bluetooth.3-mt7922/installer-amd64.tar.sha256`;
- `artifacts/v1.14.0-rc.1-bluetooth.3-mt7922/provenance.txt`.

Артефакты `.2` сохранены как предыдущая Realtek-only итерация и не являются
текущим кандидатом для hardware-test.

## Проверка installer и extensions

Для обеих линий assembler подтвердил ровно 14 extensions и
`module.sig_enforce=1`. Для текущего Bluetooth layer проверено:

- ровно пять модулей: `bluetooth.ko`, `btusb.ko`, `btintel.ko`, `btrtl.ko`,
  `btmtk.ko`;
- `vermagic` равен `6.18.42-talos SMP preempt mod_unload modversions` для
  `v1.13.8` и `6.18.44-talos SMP preempt mod_unload modversions` для
  `v1.14.0-rc.1`;
- у каждого модуля есть `sig_id: PKCS#7` и signer
  `Build time throw-away kernel key`;
- `btusb` зависит от `bluetooth`, `btmtk`, `btrtl`, `btintel`;
- rfkill встроен в kernel, а `rfkill.ko` отсутствует в extension;
- module-extension не содержит `/usr/lib/firmware`;
- MediaTek firmware extension содержит только
  `mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin` и
  `LICENSES/LICENCE.mediatek`;
- Realtek firmware не дублируется и остаётся официальной extension;
- extension validator, `depmod`, UKI assembly, checksum и `crane validate`
  завершились успешно.

Для `v1.14.0-rc.1` отдельно перепроверено: firmware размером 517398 bytes имеет
SHA-256 `299942dbec7d34af030670ea59f9f7b4fd5c64e738b9e0157d76f4dd3beb190f`.

## Upstream-main candidate

PR-shaped patch series дополнительно собрана против зафиксированного снимка
upstream `main`:

- Talos `32f7fc0dfde48e606c359b10224329e226cc74f4`;
- pkgs `d418aa74ca7237ea573f4580f469d9ece839c7fb`;
- extensions `f2c879a7c5ab806063b6a48d347ae0d78df91b28`;
- Linux `6.18.44`, Kres image
  `sha256:b8b917e508fa3c1b3a93e9eab01f0ee3ede9f6cd131a38a4f9ac268dece6fb82`.

Полная multi-architecture сборка завершилась следующими immutable index
digests:

| Артефакт | Digest |
| --- | --- |
| matching kernel | `sha256:306e74997e191977c787c32c2101af30886d15e45c161a657f34a58227ee0b8b` |
| `bluetooth-usb-drivers` | `sha256:eaea5e7b8bf598feaa2c2f569728add2c83e386d01833b76da456194d241a4f0` |
| `linux-firmware` build input | `sha256:e85804039c6db60721ef1199399fc915226ed9493a6400925073fdfe1d3140dd` |
| `mediatek-bluetooth-firmware` | `sha256:a4d782cfcbe59c246fd9ad68f91d4ee7446e210f473df2902af0a3a256f671d5` |

Оба extension index содержат `linux/amd64` и `linux/arm64`. Экспортированные
driver rootfs подтвердили пять ожидаемых модулей на amd64 и те же модули плюс
`ecc.ko`/`ecdh_generic.ko` на arm64. Для `btusb.ko` проверены
`6.18.44-talos` vermagic, `PKCS#7`, SHA-512 и signer
`Build time throw-away kernel key`. Package tests и pinned validator прошли на
обеих архитектурах; firmware в driver image отсутствует. Суммарный compressed
layer size составляет 713541 bytes для driver amd64, 777190 bytes для driver
arm64 и 518625 bytes для MediaTek firmware на каждой архитектуре.

Сборка BTF требует больше обычных 8 GiB памяти локальной Docker VM. Временные
12 GiB позволили последовательно собрать arm64, затем amd64; для amd64
параллелизм был ограничен шестью CPU. Это требование только локального
build-host и не увеличивает runtime footprint extension.

## Hardware acceptance на тестовом узле, Talos `v1.13.8`

Перед upgrade был сохранён официальный rollback image:

`factory.talos.dev/metal-installer/c5e585882ded5c117077df8abfbaee4ea3045da3647ae5b21ed5067df148c20c:v1.13.8@sha256:a0747ada3eb69a23289295a9d51d93a9b90fd1aa9ff18b0ae7143ee8b5fe063f`.

Custom installer
`<private-registry>/talos-bluetooth-installer:v1.13.8-bluetooth.3`
с digest
`sha256:d29abb37fb236037ded78021c5a9e438ac06e2c0a0ea31b331ff67514807ac2c`
временно применён только к выделенному тестовому узлу.

После загрузки подтверждены:

- Talos `v1.13.8-bluetooth.3`, kernel `6.18.42-talos`;
- загруженные `bluetooth`, `btusb`, `btintel`, `btrtl`, `btmtk`;
- `/sys/class/bluetooth/hci0`;
- успешная инициализация MediaTek MT7922 и загрузка firmware;
- BlueZ controller в powered state с ролями central/peripheral;
- system D-Bus и 20-секундный active BLE scan, обнаруживший 10 устройств.

Идентификаторы соседних BLE-устройств намеренно не сохранены в Git.
Предупреждение MediaTek о неподдерживаемом firmware coredump не мешало HCI и
сканированию и не являлось fatal kernel error.

BlueZ должен работать в host network namespace: диагностический pod без
`hostNetwork` видел sysfs, но не мог открыть Bluetooth management socket.
Privileged pod с `hostNetwork`, D-Bus и `bluetoothd` выполнил scan; временные
pod’ы после теста удалены.

## Hardware acceptance на тестовом узле, Talos `v1.14.0-rc.1`

На том же разрешённом тестовом узле подтверждены kernel `6.18.44-talos`, модули
`bluetooth`, `btusb`, `btintel`, `btrtl` и `btmtk`, устройство `hci0` и
инициализация MediaTek MT7922. Временный privileged `hostNetwork` pod запустил
BlueZ `5.82`, получил `org.bluez.Adapter1`, включил контроллер и активным scan
обнаружил девять BLE-устройств. Диагностический pod после проверки удалён.

Этот тест подтверждает kernel/BlueZ boundary, но не доступ постоянного Home
Assistant pod и не GATT-сеанс с Tion.

## Rollback и здоровье кластера

Тестовый узел возвращён на официальный image по digest. После rollback подтверждены:

- Talos `v1.13.8`, kernel `6.18.42-talos`, node `Ready`;
- Kubernetes `/readyz`: `ok`;
- все три etcd member присутствуют;
- Cilium, CSI и KubeVirt node components восстановились;
- отсутствуют pods в неожиданных фазах;
- `/sys/class/bluetooth/hci0` отсутствует, то есть custom layer не остался
  активным.

Полный `talosctl health` с клиентской машины был недоступен из-за маршрутизации
discovery. Kubernetes API, etcd, Talos services и workloads проверены напрямую
из доступной сети.

Во время первой попытки upgrade стандартный Talos drain удалил unmanaged
ephemeral pod `money-test/postgres-test-2`. У pod не было owner reference и PVC,
а исходный manifest не найден в read-only GitOps repository, поэтому точное
состояние невозможно безопасно восстановить и pod не создавался по догадке.

## Оставшиеся acceptance-gates

1. Realtek hardware-test `0bda:b85b` для `btrtl` и официальной
   `realtek-firmware`.
2. Доступ постоянного Home Assistant workload к host BlueZ D-Bus с минимальными
   privileges.
3. Реальное GATT connection/control с Tion, а не только discovery.
4. Warm/cold reboot и 24-часовой soak.

До gates 2–3 нельзя заявлять полную поддержку Home Assistant/Tion. Kernel BLE и
BlueZ discovery на MediaTek MT7922 уже подтверждены.
