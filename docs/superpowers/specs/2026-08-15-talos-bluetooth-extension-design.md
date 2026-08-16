# Talos Bluetooth USB extension: архитектурная спецификация

Статус: **Approved** пользователем 2026-08-15. Локальная сборка и проверка в
изолированных Talos-контейнерах разрешены последующими указаниями пользователя.
Публикация, deployment, commits, upstream PR и любые изменения физических
узлов или живого кластера требуют отдельного разрешения.

Дата: 2026-08-15.

Первый hardware target: интегрированный USB Realtek `0bda:b85b`.

Первый функциональный target: активное BLE-соединение Home Assistant с Tion.

## 1. Цель

Создать минимальную, безопасную и сопровождаемую поддержку USB Bluetooth для
Talos Linux, которую можно сначала проверить на одном домашнем узле, а затем
предложить в официальные репозитории Sidero Labs.

Результат должен быть generic: extension не должен зависеть от имени узла,
Home Assistant, Tion или одного USB ID. Реальный Realtek-адаптер нужен как
приёмочный стенд, а не как архитектурная граница.

## 2. Подтверждённая исходная ситуация

- В кластере сейчас наблюдался Talos `v1.13.3`.
- Целевой узел видит USB-устройство Realtek `0bda:b85b`.
- Официальный `realtek-firmware` уже установлен.
- `/sys/class/bluetooth` и `hci0` отсутствуют.
- В исходном kernel config Talos `v1.13.8` и `v1.14.0-rc.1` выключены
  `CONFIG_BT` и `CONFIG_RFKILL`.
- В официальном `siderolabs/extensions` нет готового Bluetooth/BlueZ extension.
- Privileged pod, Device Plugin или один BlueZ-контейнер не могут создать
  отсутствующий kernel Bluetooth stack.

Следовательно, блокер находится ниже Kubernetes: сначала нужны собранные и
подписанные Bluetooth-модули для точно соответствующего Talos kernel.

## 3. Решение

Предлагаются два независимых upstream-изменения и один локальный build pipeline:

```text
siderolabs/pkgs
  минимальный kernel config для Bluetooth USB как modules
            │
            ▼
siderolabs/extensions
  bluetooth-usb-drivers: выбранные signed .ko + depmod metadata
            │
            ▼
custom Talos installer для целевого узла
  kernel и modules из одной pkgs build
  + bluetooth-usb-drivers
  + официальный realtek-firmware
            │
            ▼
Talos kernel: hci0
            │
            ▼
отдельный Kubernetes workload: BlueZ + D-Bus
            │
            ▼
Home Assistant: BLE scan, GATT и управление Tion
```

Современный system extension позволяет поставить kernel modules отдельно от
base initramfs. Практическая сборка выявила общий дефект Talos overlay: при
замене более длинного файла более коротким destination открывался без
`O_TRUNC`, и в `modules.softdep` оставался хвост старого содержимого. Поэтому
build pipeline применяет отдельный минимальный Talos patch с regression test;
он не переносит Bluetooth-модули в base initramfs и не зависит от этого
extension.

## 4. Почему выбран этот вариант

### Вариант A: `pkgs` modules + system extension — выбран

Преимущества:

- Bluetooth не встраивается в каждый Talos image;
- модули доступны только на выбранных узлах;
- сохраняется обязательная kernel-module signature verification;
- extension следует текущим patterns `uinput` и `usb-audio-drivers`;
- kernel config и каталог extension можно рассматривать раздельными PR;
- firmware остаётся в существующем официальном extension.

### Вариант B: модули в Talos initramfs — отклонён

Так работал старый community proof-of-concept. В актуальной архитектуре это
расширяет base image и поверхность атаки на всех узлах, требует изменения Talos и
смешивает generic kernel capability с политикой установки.

### Вариант C: BlueZ pod или Device Plugin без kernel changes — отклонён

Userspace не заменяет `CONFIG_BT`, HCI core и `btusb`. Device Plugin полезен для
обычных `/dev/*` устройств, но Home Assistant работает с Bluetooth через BlueZ
D-Bus API, а не через проброс `/dev/hci0`.

## 5. Граница компонентов

### `siderolabs/pkgs`

Включает минимальные in-tree kernel capabilities для `amd64` и `arm64`:

- `CONFIG_BT=m`;
- `CONFIG_BT_LE=y`;
- `CONFIG_BT_HCIBTUSB=m`;
- `CONFIG_BT_HCIBTUSB_RTL=y`;
- `CONFIG_RFKILL=y`.

`CONFIG_BT_HCIBTUSB` в Linux 6.18 выбирает `BT_INTEL`, а Realtek option выбирает
`BT_RTL`. Поэтому полный набор символов и модулей определяет результат
`olddefconfig` и фактическая dependency graph сборки, а не вручную составленный
список.

В начальном scope отключены Classic Bluetooth и неиспользуемые protocols,
transports и vendors: RFCOMM, BNEP, CMTP, HIDP, 6LoWPAN, UART, SDIO, virtual HCI,
Broadcom USB, MediaTek USB, debugfs и testing facilities. `BT_LE_L2CAP_ECRED`
предлагается оставить включённым ради generic BLE compatibility: это часть BLE
core и не добавляет отдельного transport module.

### Implementation note 2026-08-15: generic MediaTek USB support

Hardware inventory разрешённого тестового узла обнаружил MediaTek
MT7922. Поэтому реализованный generic USB scope расширен символами
`CONFIG_BT_MTK=m` и `CONFIG_BT_HCIBTUSB_MTK=y`; module closure дополнен
`btmtk.ko`. Это не node-specific workaround: используется штатный upstream
Linux driver без USB-ID override. Минимальная firmware MT7922 и её license
упакованы в отдельную `mediatek-bluetooth-firmware` extension, а module-extension
по-прежнему не содержит firmware.

### `siderolabs/extensions`

Новый пакет с предлагаемым именем `bluetooth-usb-drivers`:

```text
drivers/bluetooth-usb-drivers/
├── README.md
├── files/
│   ├── modules-x86_64.txt
│   └── modules-aarch64.txt
├── manifest.yaml.tmpl
├── pkg.yaml
└── vars.yaml
```

Он копирует только необходимые `.ko` из matching kernel package в
`/usr/lib/modules/<kernelrelease>`, запускает `depmod` и проходит официальный
`extensions-validator`. Точный module list формируется после сборки через
`modinfo -F depends`, `modules.dep` и `modprobe --show-depends`.

Проверенный amd64 dependency closure включает `bluetooth.ko`, `btusb.ko`,
`btrtl.ko`, `btintel.ko` и `btmtk.ko`; rfkill встроен в kernel. На arm64
дополнительно требуются `ecc.ko` и `ecdh_generic.ko`.

Extension не содержит:

- Realtek firmware;
- BlueZ или D-Bus;
- USB-ID overrides и node-specific scripts;
- приватные signing keys;
- диагностические binaries;
- файлы вне разрешённого extension rootfs.

### Custom installer

Локальный pipeline строит kernel и modules из одной pinned `pkgs` revision,
собирает extension и передаёт тот же kernel в Talos `installer-base`/imager.
Installer включает `bluetooth-usb-drivers`, существующий официальный
`realtek-firmware` и минимальную MediaTek firmware extension. Конкретный image
назначается только явно выбранному тестовому узлу.

Другие узлы продолжают использовать официальный Talos installer. Установка
extension сама по себе не должна автоматически загружать Bluetooth: модуль
`btusb` включается явно в machine configuration только целевого узла.

### BlueZ, D-Bus и Home Assistant

Это следующий, отдельный этап. Kernel extension считается работоспособным после
появления стабильного `hci0`, но поддержка Home Assistant подтверждается только
после запуска BlueZ/D-Bus и реального GATT-сеанса с Tion.

Kubernetes workload должен предоставлять Home Assistant D-Bus socket и только
необходимые capabilities (`NET_ADMIN`, `NET_RAW`, если runtime testing не покажет
более узкую границу). BlueZ не включается в kernel-driver PR.

## 6. Версионная стратегия и точные источники

Проверенные на 2026-08-15 references:

| Source | Reference | Commit |
| --- | --- | --- |
| Talos stable | `v1.13.8` | `3de4932272a820af6de3852691a35645565c33b3` |
| `pkgs` для Talos `v1.13.8` | `v1.13.0-55-gf677246` | `f677246a73ed1353a1e0ec9e92f0027b2f759978` |
| Talos prerelease | `v1.14.0-rc.1` | `7a84d742b3d53451cbaa1eb91d9b12403e80161c` |
| `pkgs` для `v1.14.0-rc.1` | `v1.14.0-1-geffed43` | `effed4398f9bda2126d37b1547c519bb121c82e6` |
| Extensions для `v1.13.8` | pinned commit | `a0a1c3996c1ba8648ce1269c004dacde89ad4838` |
| Extensions для `v1.14.0-rc.1` | pinned commit | `076693f8a560d71a4100a81adbd52c077f94af6f` |
| Community `pkgs` proof | — | `c8d738929f88f18149ac5da7c0e1dd591ec14e0b` |
| Community Talos proof | — | `ad53f78b677f3a180dbf873ebd726d5e1fbe34e3` |

Для первой production-проверки принято сначала независимо обновить кластер
с `v1.13.3` на официальный `v1.13.8`, а затем собирать custom `v1.13.8` для
целевого узла. Upstream-разработка должна следовать актуальным `main`/`v1.14`, но
prerelease installer не используется в production.

Перед каждой сборкой pipeline повторно сверяет Talos tag/commit, его `pkgs` pin,
`extensions` `PKGS`/`TOOLS`, Linux version, bldr, validator и imager. Тег без
зафиксированного commit/digest не является воспроизводимым входом.

Основные upstream sources:

- [Talos system extensions](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/system-extensions)
- [Talos custom kernel](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/customizing-the-kernel)
- [Talos kernel module guide](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/kernel-module)
- [`siderolabs/pkgs`](https://github.com/siderolabs/pkgs)
- [`siderolabs/extensions`](https://github.com/siderolabs/extensions)
- [Linux 6.18 Bluetooth core Kconfig](https://github.com/torvalds/linux/blob/v6.18/net/bluetooth/Kconfig)
- [Linux 6.18 Bluetooth drivers Kconfig](https://github.com/torvalds/linux/blob/v6.18/drivers/bluetooth/Kconfig)
- [Home Assistant Bluetooth](https://www.home-assistant.io/integrations/bluetooth/)
- [`siderolabs/pkgs#486`](https://github.com/siderolabs/pkgs/issues/486)
- [`siderolabs/extensions#247`](https://github.com/siderolabs/extensions/issues/247)

## 7. Provenance и лицензии

`siderolabs/talos`, `siderolabs/pkgs` и `siderolabs/extensions` используют
MPL-2.0. In-tree Linux modules сохраняют upstream GPL-2.0-only licensing.
Realtek firmware остаётся в официальном `realtek-firmware` и не копируется.

Community commits dancavallaro используются как подтверждение feasibility:

- `talos-pkgs@c8d7389` включал широкий набор Bluetooth Kconfig, перенесённый из
  Ubuntu 22.04;
- `talos@ad53f78` добавлял семь модулей в старый Talos initramfs.

Код и 60-symbol config из этих commits не переносятся. Минимальный config
выводится независимо из актуального Linux Kconfig, а module list — из artifacts
собственной сборки. Если при реализации всё же потребуется дословный fragment,
его source commit, license и преобразование фиксируются в документации и commit
message.

Никакие community images не используются: они не опубликованы как релизы, не
имеют текущей CI/provenance цепочки и не соответствуют актуальной версии Talos.

## 8. Security model

Bluetooth исторически расширяет kernel attack surface, поэтому:

- функциональность собирается как modules, а не built-in;
- extension устанавливается и модуль загружается только на целевом узле;
- Classic Bluetooth и неиспользуемые transports/protocols выключены;
- `module.sig_enforce` не отключается;
- signing private key создаётся внутри kernel build и не публикуется;
- kernel и modules всегда происходят из одной build;
- OCI images публикуются immutable digest и отдельно подписываются Cosign;
- registry credentials, signing identity и kubeconfig не хранятся в репозитории;
- BlueZ workload не получает unrestricted privileged mode без доказанной
  необходимости;
- firmware не дублируется и не подменяется.

Kernel module signature и OCI signature независимы: первая проверяется ядром и
доказывает совместимость с конкретной kernel build, вторая доказывает provenance
поставляемого image.

`btusb` autosuspend оставляется generic upstream default. Для первого стенда
предлагается явно задать `btusb.enable_autosuspend=0`, если это
поддерживает выбранная kernel version: надёжность долгих BLE-соединений важнее
экономии энергии, а node-specific policy не должна становиться глобальным default
extension.

## 9. CI/CD design

Pipeline состоит из следующих gates.

### Source and config gate

1. Проверить exact upstream refs и OCI digests.
2. Применить минимальный `pkgs` config change к pinned source.
3. Выполнить `kernel-olddefconfig` для `linux/amd64` и `linux/arm64`.
4. Автоматически проверить обязательные и запрещённые symbols.
5. Отклонить неожиданный config scope growth.

### Kernel gate

1. Собрать kernel для обеих architectures официальным `pkgs`/bldr workflow.
2. Получить module dependency closure из собранных artifacts.
3. Проверить `vermagic`, `signer`, `sig_id`, PKCS#7 trailer и dependency closure.
4. Выполнить `depmod -e` с соответствующим `System.map`.
5. Отклонить unsigned, чужие или отсутствующие modules.

### Extension gate

1. Собрать target по актуальному `drivers/*` pattern.
2. Выполнить package tests и `extensions-validator`.
3. Проверить разрешённые paths и permissions.
4. Проверить отсутствие `/usr/lib/firmware` в новом extension.
5. Выполнить duplicate finder для обоих architectures.
6. Выполнить `make`, `extensions-catalog`, `check-dirty`,
   `extensions-validate` и `conformance` в upstream-shaped checkout.
7. Выполнить reproducibility test и vulnerability scan там, где они применимы.

Generated Makefile, Pkgfile, CI и catalog не редактируются вручную. Source of
truth меняется в `.kres.yaml`/package sources, затем запускаются официальные
генераторы.

### Installer and provenance gate

1. Собрать installer с тем же custom kernel package.
2. Включить Bluetooth extension и официальный Realtek firmware.
3. Зафиксировать SBOM/provenance, source SHAs, tool versions и artifact digests.
4. Подписать публикуемые OCI artifacts средствами CI.
5. Публиковать только immutable digest после manual approval.

Локальные build и изолированные container tests разрешены. Registry остаётся
приватным и недоступным извне; publish, upstream PR и live deployment требуют
отдельного разрешения.

## 10. Acceptance tests

### Статические проверки

- required/forbidden kernel symbols соответствуют утверждённому scope;
- обе architectures проходят `olddefconfig` и build;
- module closure полон и одинаково формируется из artifacts;
- каждый `.ko` подписан, имеет ожидаемый `vermagic` и signer;
- validator принимает manifest/rootfs;
- extension не содержит firmware, userspace services или лишних файлов;
- build воспроизводим из pinned inputs;
- digests, provenance и license inventory сохранены.

### Bare-metal preflight

- сохранён текущий официальный installer digest выбранного тестового узла;
- сохранена применённая machine configuration;
- подтверждены health etcd и двух остальных control-plane nodes;
- сделан и проверен etcd snapshot;
- доступны локальная консоль и recovery media;
- drain узла не нарушает доступность критичных workloads.

### Runtime kernel acceptance

- custom image назначен только выбранному тестовому узлу;
- после upgrade узел возвращается в `Ready`;
- Kubernetes, Cilium, CSI и workloads остаются здоровыми;
- Talos показывает Bluetooth extension и `realtek-firmware`;
- загружены `rfkill`, Bluetooth core, `btusb`, `btrtl` и фактические dependencies;
- `/sys/class/bluetooth/hci0` существует;
- dmesg подтверждает загрузку firmware и не содержит module signature,
  symbol/version или USB reset errors;
- адаптер стабилен после warm reboot и cold boot.

### Userspace and product acceptance

- BlueZ и D-Bus запускаются с зафиксированными versions;
- adapter виден через BlueZ API;
- passive и active scan находят BLE devices;
- Home Assistant использует правильный D-Bus socket;
- выполнено реальное GATT connection/control с Tion;
- 24-часовой soak не показывает исчезновения адаптера, recovery loops или
  деградации cluster services.

Готовность к upstream review наступает после статических gates и сборки extension.
Поддержка Home Assistant заявляется только после bare-metal и product acceptance.

## 11. Rollout и rollback

Rollout выполняется только после отдельного согласования:

1. Обновить весь кластер до официального `v1.13.8` отдельным изменением и
   подтвердить стабильность.
2. Собрать и проверить custom artifacts на той же версии.
3. Drain только выбранного тестового узла.
4. Выполнить upgrade узла на custom installer по digest.
5. Проверить kernel acceptance до установки BlueZ workload.
6. Затем отдельно развернуть и проверить userspace.

Rollback не зависит от работоспособности Kubernetes API:

1. До изменения сохранить официальный installer digest и recovery media.
2. При kernel/boot/cluster failure загрузить captured official image через
   `talosctl upgrade` с сохранением данных либо через локальную консоль.
3. Вернуть machine configuration без custom module load после загрузки
   официального kernel.
4. Проверить etcd membership, node Ready, Cilium, CSI и workloads.
5. Не продолжать rollout, пока причина failure не воспроизведена в build/test
   environment.

Без физического recovery access rollout запрещён: ошибка kernel может возникнуть
до появления Talos API.

## 12. Upstreaming strategy

1. Открыть RFC/issue со ссылками на закрытые `pkgs#486` и `extensions#247`.
2. Прямо признать прежнее security objection и предложить modules-only,
   non-autoloaded, LE-focused scope.
3. Согласовать с maintainers имя, tier, architectures и protocol scope.
4. Подать отдельный `pkgs` PR для kernel config обеих architectures.
5. После появления соответствующего `pkgs` artifact подать отдельный
   `extensions` PR.
6. Включить package, documentation, `.kres.yaml`, generated artifacts и запись
   maintainer по текущим repository conventions.
7. Приложить build matrix, signature/vermagic evidence и результаты Realtek
   hardware validation.
8. Начать с tier `contrib`; переход в `extra`/`core` остаётся решением Sidero Labs.

Talos PR не смешивается с Bluetooth PR: общий `O_TRUNC` fix при необходимости
предлагается отдельно и не добавляет модули в base initramfs.
BlueZ/D-Bus userspace обсуждается отдельным proposal, чтобы не смешивать kernel
security review и container service lifecycle.

## 13. Решения, требующие согласования

Для реализации утверждены следующие значения:

1. **Имя:** `bluetooth-usb-drivers` — показывает, что это kernel drivers, а не
   BlueZ. Альтернатива `bluetooth` слишком широкая.
2. **Protocol scope:** LE-only — минимальная поверхность для Tion. Classic можно
   добавить отдельным обоснованным изменением.
3. **Architectures:** локальный prototype `amd64`, upstream implementation и CI
   сразу `amd64` + `arm64`.
4. **Production baseline:** сначала официальный `v1.13.8`, затем custom
   `v1.13.8` только на явно выбранном тестовом узле; upstream work отслеживает
   `v1.14`/`main`. Первый тест выполнен на выделенном узле, после чего он возвращён
   на официальный image.
5. **BLE L2CAP ECRED:** включить для generic modern BLE compatibility.
6. **Autosuspend:** сохранить generic upstream default, а на целевом узле при
   подтверждении module parameter задать `btusb.enable_autosuspend=0`.
7. **Tier:** предлагать `contrib`, не заявляя поддержку от имени Sidero Labs.

Текущий scope разрешает подготовить patch sets, локально собрать их и проверить
в изолированных контейнерах для `v1.13.8` и линии `v1.14.0`. Он не разрешает
автоматически публиковать, деплоить, коммитить, менять физические узлы или создавать
upstream issues/PR.
