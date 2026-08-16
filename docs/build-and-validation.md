# Сборка и проверка Talos Bluetooth extension

Этот документ разделяет source-, build-, container-runtime- и hardware-gates.
Локальные сборки выполняются в изолированной Docker-сети. Разрешённый
hardware-test `v1.13.8` и `v1.14.0-rc.1` выполнен только на выделенном тестовом
узле с последующим возвратом на официальный installer `v1.13.8`; целевой
Realtek-узел не изменялся.

## 1. Зафиксированные исходники

| Линия | Talos | pkgs | extensions | Linux |
| --- | --- | --- | --- | --- |
| `v1.13.8` | `3de4932272a820af6de3852691a35645565c33b3` | `f677246a73ed1353a1e0ec9e92f0027b2f759978` | `a0a1c3996c1ba8648ce1269c004dacde89ad4838` | `6.18.42` |
| `v1.14.0-rc.1` | `7a84d742b3d53451cbaa1eb91d9b12403e80161c` | `effed4398f9bda2126d37b1547c519bb121c82e6` | `076693f8a560d71a4100a81adbd52c077f94af6f` | `6.18.44` |
| published upstream PR base | `be6b96386a99f2c90ac7337db570540644feb625` | `c9173bb3fa60ae23ad8f2c6e8cee0499a8c45077` | `f2c879a7c5ab806063b6a48d347ae0d78df91b28` | `6.18.44` |

Полная версия инструментов и Kres digests хранится в `versions/*.env`.

## 2. Уже выполненные проверки

На релизных линиях выполнены:

- проверка SHA-256 архивов Linux по значениям из upstream `Pkgfile`;
- `kernel-olddefconfig` через официальный LLVM/toolchain `siderolabs/pkgs` для
  `linux/amd64` и `linux/arm64`;
- генерация `Makefile` extension соответствующей каждой ветке версией Kres;
- `git apply --check` для pkgs patch sets и reverse-check для сформированных
  extension patch sets;
- source contract, shell syntax и whitespace checks.

`olddefconfig` подтвердил архитектурное различие: на amd64 ECC/ECDH уже встроены,
а arm64 требует `kernel/crypto/ecc.ko` и `kernel/crypto/ecdh_generic.ko` в
extension.

На опубликованной upstream-базе patch preparation и `kernel-olddefconfig`
повторены для обеих архитектур без дополнительных изменений. Полная сборка
соседнего upstream snapshot зафиксирована отдельно в build evidence; сборка
точного опубликованного base SHA остаётся задачей upstream CI.

## 3. Повторная source-проверка

```console
make test
make prepare VERSION=v1.13.8 DESTINATION=/tmp/talos-bluetooth-v1.13.8
```

В подготовленном `pkgs` повторить нормализацию:

```console
cd /tmp/talos-bluetooth-v1.13.8/pkgs
make kernel-olddefconfig
git diff --check
```

После `olddefconfig` не должно появиться изменений сверх применённого patch set.

В `extensions` Kres следует запускать только по digest из version manifest:

```console
cd /tmp/talos-bluetooth-v1.13.8/extensions
source /path/to/talos-bluetooth-extension/versions/v1.13.8.env
make rekres KRES_IMAGE="ghcr.io/siderolabs/kres@${KRES_IMAGE_DIGEST}"
```

## 4. Kernel build gate

Полная сборка должна использовать patched `pkgs` и обе архитектуры. Обычный
upstream target:

```console
make kernel PLATFORM=linux/amd64,linux/arm64 PUSH=false
```

Для передачи изменённого kernel image в сборку extension понадобится отдельно
разрешённый registry с TLS. Затем kernel публикуется с точным `PKGS_IMAGE_TAG`, а
`extensions` собирается с теми же `PKGS_PREFIX` и `PKGS`:

```console
make kernel \
  PLATFORM=linux/amd64,linux/arm64 \
  REGISTRY=<registry> USERNAME=<namespace> PUSH=true

make bluetooth-usb-drivers \
  PLATFORM=linux/amd64,linux/arm64 \
  PKGS_PREFIX=<registry>/<namespace> \
  PKGS=<exact-pkgs-tag> \
  PUSH=false
```

Не использовать официальный kernel image без pkgs patch: нужных модулей в нём
нет.

На локальном upstream-main build BTF generation превысила доступные 8 GiB
Docker VM. Воспроизводимый режим для этой машины: 12 GiB, архитектуры
последовательно, arm64 с обычным параллелизмом и amd64 с шестью CPU. После
сборки отдельные manifests объединяются в multi-arch index; снижение
параллелизма не меняет содержимое артефакта.

Для локального build-registry, доступного сборщику по внутреннему DNS-имени, а
macOS — по отдельному адресу, весь совместимый набор собирается wrapper-скриптом:

```console
REGISTRY_CLIENT_ADDRESS=<registry-address> \
  MAKE_COMMAND=gmake \
  ./scripts/build-local-components.sh \
    v1.14.0 \
    /tmp/talos-bluetooth-v1.14.0 \
    talos-bt-registry:5000 \
    talos-bluetooth \
    v1.14.0-bluetooth.3
```

После успешной сборки новый installer создаётся отдельно:

```console
REGISTRY_CLIENT_ADDRESS=<registry-address> \
  DOCKER_NETWORK=talos-bt-build \
  ./scripts/assemble-installer.sh \
    v1.14.0 \
    /tmp/talos-bluetooth-v1.14.0 \
    talos-bt-registry:5000 \
    talos-bluetooth \
    v1.14.0-bluetooth.3 \
    /tmp/talos-bluetooth-artifacts/v1.14.0
```

Assembler требует новый абсолютный output-каталог, проверяет семь локально
пересобранных module extensions, локальную минимальную MediaTek firmware
extension и шесть официальных digest-pinned extensions, затем сохраняет
`installer-amd64.tar`, checksum и `provenance.txt`.

## 5. Проверка kernel artifacts

Для обеих архитектур проверить фактический `modules.dep` и замкнутость списка:

```console
modinfo -F depends btusb.ko
modinfo -F depends bluetooth.ko
modinfo -F vermagic btusb.ko
modinfo -F signer btusb.ko
grep -F '~Module signature appended~' btusb.ko
```

Требования:

- `vermagic` совпадает с точным `KERNELRELEASE` Talos;
- каждый `.ko` имеет Talos signature marker и непустого signer;
- все зависимости из `modules.dep` либо находятся в extension, либо встроены в
  ядро согласно `modules.builtin`;
- amd64 содержит пять Bluetooth-модулей (`bluetooth`, `btusb`, `btintel`,
  `btrtl`, `btmtk`), arm64 дополнительно содержит `ecc.ko` и
  `ecdh_generic.ko`;
- rfkill встроен в kernel (`CONFIG_RFKILL=y`), поэтому extension не содержит
  `rfkill.ko` и base Talos modules не зависят от порядка наложения extensions;
- в rootfs module-extension отсутствует `/usr/lib/firmware`; отдельная
  MediaTek extension содержит только firmware MT7922 и файл её лицензии.

Package test самого extension уже проверяет signature marker, непустой набор
модулей, отсутствие firmware и запускает `extensions-validator`.

## 6. Upstream CI gates

После сборки matching kernel image выполнить применимые upstream targets:

```console
make bluetooth-usb-drivers
make extensions-catalog
make extensions-validate
make reproducibility-test
```

`extensions-validate` строит каталог и запускает duplicate finder для amd64 и
arm64. `check-dirty` запускается только на чистом commit, поэтому в локальном
source-only checkout с применёнными незакоммиченными patches он ожидаемо не
подходит.

## 7. Изолированный container-runtime gate

Перед hardware-тестом custom Talos container должен запуститься в отдельной
Docker-сети и подтвердить:

1. точную custom-версию Talos через API;
2. состояния `Running/OK` у `apid`, `containerd`, `machined`, `etcd`, `cri` и
   `kubelet`;
3. `Ready` у тестового Kubernetes node и `Running` у control-plane/CNI pods;
4. отсутствие записи в пользовательский kubeconfig — для команды обязательно
   задаётся отдельный `KUBECONFIG` внутри временного каталога;
5. уничтожение тестового cluster после сохранения логов.

На Apple Silicon amd64 container проверяет собранный userspace и API, но запуск
полного Kubernetes под трансляцией может быть ограничен отсутствием
`mount_setattr`. Поэтому cluster smoke-test дополнительно выполняется нативным
arm64 container из того же patched Talos source. Он не заменяет проверку amd64
installer и его модулей.

Container gate не может доказать наличие физического `hci0`, загрузку Realtek
firmware или BLE-связь: эти свойства требуют реального USB controller.

Фактические digests, checksum двух installer и результаты выполненных
container-smoke зафиксированы в
[build-evidence-2026-08-15.md](build-evidence-2026-08-15.md).

### Локальный USB gate на macOS

OrbStack умеет dedicated USB passthrough, но Talos Docker container продолжает
использовать kernel OrbStack. Поэтому локальная проверка собранных Talos modules
должна выполняться в полной VM:

1. Подключить внешний USB Bluetooth dongle и убедиться, что он появился в
   `orb usb list` с ожидаемыми vendor/product ID.
2. Передать устройство в Linux через `orb usb attach <id>` и проверить появление
   raw USB device. Встроенный PCIe Bluetooth Mac для этого не подходит.
3. Загрузить full Talos VM из custom kernel/initramfs соответствующей версии и
   передать raw USB именно этой VM. Docker-only provisioner для проверки modules
   не использовать.
4. Через Talos API проверить kernel logs, `/sys/class/bluetooth/hci0` и состояние
   загруженных modules.
5. Запустить временный privileged diagnostic pod с BlueZ `btmgmt` и выполнить LE
   scan. Не сохранять увиденные адреса и имена соседних устройств в Git.
6. Сохранить обезличенные логи, удалить VM и выполнить `orb usb detach <id>`,
   возвращая устройство macOS.

Проверка произвольным USB dongle подтверждает generic Bluetooth USB path. Для
приёмки `btrtl` и Realtek firmware нужен Realtek adapter, желательно с целевым
USB ID `0bda:b85b`.

## 8. Runtime acceptance на физическом узле

Перед установкой нужны rollback installer и проверенный recovery path. Custom
installer применяется только к явно выбранному тестовому узлу; остальные узлы
остаются на официальных образах.

На тестовом узле для `v1.13.8` и `v1.14.0-rc.1` уже подтверждены:

- matching kernels `6.18.42-talos` и `6.18.44-talos`;
- загрузка `bluetooth`, `btusb`, `btintel`, `btrtl`, `btmtk`;
- появление `hci0`, загрузка firmware MT7922 и отсутствие fatal kernel errors;
- BlueZ system D-Bus, powered controller и активный BLE scan;
- возврат на официальный Talos `v1.13.8`, `Ready` node и восстановление
  Kubernetes, etcd, Cilium, CSI и workloads.

После загрузки проверить:

1. Встроенный rfkill и необходимые модули `bluetooth`, `btusb` и chipset driver
   работают без kernel errors.
2. `/sys/class/bluetooth/hci0` существует, firmware загружена из соответствующей
   extension.
3. BlueZ предоставляет активный system D-Bus API и выполняет BLE scan.
4. Home Assistant получает D-Bus socket и только необходимые capabilities/mounts.
5. Выполнено реальное BLE-подключение к Tion, а не только обнаружение advertisement.
6. Kubernetes, Cilium, CSI и workloads здоровы после возврата узла в cluster.

Для тестового узла пункты 1–3 пройдены. До проверки пунктов 4–5 нельзя заявлять
полную поддержку Home Assistant/Tion, даже при успешном BLE discovery.
