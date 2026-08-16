# Требования к upstream-ready Talos Bluetooth extension

Статус исследования: 2026-08-17.

Этот документ фиксирует проверенные правила разработки Talos system extension и
критерии, по которым Bluetooth-реализацию можно готовить к включению в официальный
репозиторий `siderolabs/extensions`. Здесь слово «официальный» не означает
автоматически «полностью поддерживаемый Sidero Labs»: официальный каталог содержит
три разных уровня поддержки.

## Проверенная upstream-база

На дату исследования:

- последний стабильный релиз Talos — `v1.13.8`;
- последний выбранный pre-release snapshot — `v1.14.0-rc.1`;
- `siderolabs/talos@v1.13.8` указывает на
  `siderolabs/pkgs@f677246a73ed1353a1e0ec9e92f0027b2f759978` через значение
  `v1.13.0-55-gf677246`;
- `siderolabs/extensions@v1.13.8` указывает на тот же `PKGS` tag;
- текущие `main`-ветки на момент проверки:
  - `siderolabs/talos@be6b96386a99f2c90ac7337db570540644feb625`;
  - `siderolabs/pkgs@c9173bb3fa60ae23ad8f2c6e8cee0499a8c45077`;
  - `siderolabs/extensions@f2c879a7c5ab806063b6a48d347ae0d78df91b28`.

Версионные факты нужно перепроверять перед каждой сборкой и перед открытием PR.
Нельзя смешивать kernel image, extension и installer от разных Talos/`pkgs`
ревизий: внешне совпадающего номера Linux недостаточно для гарантии совместимости
модулей.

Основные источники:

- [Talos v1.13: System Extensions](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/system-extensions)
- [Talos v1.13: Adding a Kernel Module](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/kernel-module)
- [Talos v1.13: Developing Talos](https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/custom-images-and-development/developing-talos)
- [`siderolabs/extensions`](https://github.com/siderolabs/extensions)
- [`siderolabs/extensions` maintainers](https://github.com/siderolabs/extensions/blob/main/MAINTAINERS.md)
- [`siderolabs/pkgs`](https://github.com/siderolabs/pkgs)
- [`siderolabs/pkgs` kernel configuration guide](https://github.com/siderolabs/pkgs/blob/main/kernel/README.md)
- [`siderolabs/talos`](https://github.com/siderolabs/talos)
- [Home Assistant Bluetooth requirements](https://www.home-assistant.io/integrations/bluetooth/)

## Что считается официальным extension

Официальный каталог `siderolabs/extensions` делится на три tier:

| Tier | Поддержка | Обновления | Тесты и SBOM | Сбой совместимости |
| --- | --- | --- | --- | --- |
| `core` | полностью Sidero Labs | Sidero Labs | обязательны либо явно неприменимы | исправляется как поддерживаемый компонент |
| `extra` | best effort Sidero Labs | Sidero Labs | best effort | поддержка и сроки могут различаться |
| `contrib` | сообщество | best effort сообщества | не гарантируются | extension может быть отключён, если перестал собираться |

Следствия:

1. Попадание в репозиторий `siderolabs/extensions` и публикация в
   `ghcr.io/siderolabs/*` уже делают extension частью официального каталога.
2. Для внешнего нового драйвера реалистичная начальная цель — `contrib`. Tier нельзя
   объявить самостоятельно как обещание поддержки Sidero Labs.
3. Переход в `extra` или `core` — решение maintainers. Публичной формальной шкалы
   автоматического повышения tier нет; таблица описывает уровень обязательств, а не
   гарантированный promotion workflow.
4. У extension должен быть реальный maintainer. Официальный репозиторий ведёт
   отдельный `MAINTAINERS.md`; запись `Needs Maintainer` означает неподдерживаемый
   пакет.

Для Bluetooth разумная upstream-цель первой итерации — generic kernel-driver
extension уровня `contrib`, с качеством сборки и тестов не ниже существующих
`extra` driver extensions. Это не связывает реализацию с конкретным узлом или USB ID
`0bda:b85b`.

## Граница между `pkgs`, `extensions` и `talos`

### `siderolabs/pkgs`

`pkgs` собирает официальный Talos kernel image и все in-tree модули. Если символы
ядра выключены, system extension не может создать отсутствующие модули постфактум.

Для in-tree USB Realtek Bluetooth здесь требуется минимальное изменение обеих
архитектурных kernel config:

- `kernel/build/config-amd64`;
- `kernel/build/config-arm64` — официальный extensions CI по умолчанию собирает
  `linux/amd64,linux/arm64`, поэтому amd64-only патч не является полноценным
  upstream-вариантом.

Конфигурацию нужно менять через штатный kernel workflow и затем нормализовать:

```bash
make kernel-olddefconfig PLATFORM=linux/amd64
make kernel-olddefconfig PLATFORM=linux/arm64
```

Ручной патч должен содержать только необходимые символы и изменения, которые
добавил `olddefconfig`. В upstream `main` на момент исследования используются Linux
`6.18.44` и `bldr v0.6.2`; в Talos `v1.13.8` — Linux `6.18.42` и связанный `pkgs`
commit, указанный выше.

### `siderolabs/extensions`

Extension не пересобирает in-tree Bluetooth driver из независимого исходника. Он:

1. использует точно соответствующий `ghcr.io/siderolabs/kernel:<PKGS>`;
2. выбирает только нужные подписанные `.ko`;
3. формирует `/rootfs/usr/lib/modules/<kernelrelease>/...`;
4. запускает `depmod` для extension rootfs;
5. добавляет `manifest.yaml` в корень OCI image;
6. проходит официальный `extensions-validator`.

Realtek firmware не входит в Bluetooth extension. Оно уже поставляется отдельным
официальным `realtek-firmware`, который копирует каталог `rtl_bt` из
`linux-firmware`. Повторное включение этих файлов создаст дубликаты и нарушит
границу ответственности.

### `siderolabs/talos`

Для основного kernel-extension интерфейса Talos уже:

- разрешает `/usr/lib/modules` в extension rootfs;
- проверяет manifest и содержимое extension;
- строит dependency metadata для модулей;
- загружает модули из `machine.kernel.modules`.

Практическая сборка обеих линий выявила отдельный дефект overlay-копирования:
destination открывался без `O_TRUNC`, поэтому более короткий файл следующего
extension сохранял хвост предыдущего. Минимальный Talos patch добавляет
`os.O_TRUNC` и regression test. Это общий fix сборщика extensions, а не
Bluetooth-специфичная упаковка.

Старый community-подход с ручным добавлением Bluetooth-модулей в
`hack/modules-amd64.txt` изменял сам initramfs. Современная upstream-архитектура
предпочитает отдельный system extension и custom boot asset/installer, поэтому тот
патч является только доказательством работоспособности, а не шаблоном для копирования.

### BlueZ и D-Bus

BlueZ и D-Bus — отдельный userspace-слой. Kernel extension не должен объявлять
поддержку Home Assistant только по факту появления `hci0`.

Home Assistant на Linux требует:

- доступный D-Bus socket;
- BlueZ не ниже `5.43`, рекомендован `>= 5.63`;
- предпочтительно `dbus-broker`;
- для container deployment — `NET_ADMIN`, `NET_RAW` и read-only mount
  `/run/dbus`;
- для passive scanning — BlueZ `>= 5.63` с experimental features.

Talos умеет запускать extension services из
`/usr/local/etc/containers/<service>.yaml`, а rootfs сервиса располагается в
`/usr/local/lib/containers/<service>`. Это позволяет спроектировать BlueZ/D-Bus
extension отдельно, но его socket lifecycle, D-Bus policies, service dependencies,
capabilities и Kubernetes mount boundary должны быть доказаны тестами. Эти вопросы
не входят в kernel-only PR.

## Формат extension image

Распакованный image обязан иметь ровно два объекта верхнего уровня:

```text
manifest.yaml
rootfs/
```

Talos отклоняет неожиданные файлы в корне, отсутствие manifest или rootfs, а также
неподдерживаемую версию manifest.

Минимальный manifest:

```yaml
version: v1alpha1
metadata:
  name: bluetooth-usb-drivers
  version: "<extension version>"
  author: "<maintainer>"
  description: |
    [contrib] Generic Bluetooth kernel modules built for the matching Talos kernel.
  compatibility:
    talos:
      version: ">= v<verified minimum>"
```

В самом upstream-репозитории manifest обычно хранится как
`manifest.yaml.tmpl`, а `vars.yaml` задаёт `VERSION` и `TIER`. Сгенерированный
`manifest.yaml` попадает в final image.

Compatibility constraint должен отражать реально проверенный Talos API/формат, а
не желаемый широкий диапазон. Он не заменяет точное совпадение kernel build для
`.ko`. Для kernel extensions доставка модулей привязана к версионному каталогу и
matching `pkgs` image. Поэтому manifest сохраняет штатный contract floor
`>= v1.13.0-alpha.2`, а не будущий release floor, который pinned validator ещё не может
проверить.

## Ограничения содержимого

Текущий Talos validator:

- допускает только обычные файлы, каталоги и symlink;
- запрещает world-writable файлы;
- разрешает только утверждённые префиксы, включая `/usr/lib/modules`,
  `/usr/lib/firmware`, `/usr/lib/udev/rules.d` и `/usr/local`;
- проверяет Talos semver constraint;
- отклоняет неверную структуру верхнего уровня.

Для Bluetooth kernel extension разрешён только `/usr/lib/modules`. Он не должен
содержать:

- firmware из `realtek-firmware`;
- BlueZ, D-Bus или диагностические binaries;
- node-specific scripts или USB-ID overrides;
- ключи подписи;
- произвольные файлы в `/etc`, `/boot`, `/lib` или `/var`.

## Upstream-совместимая структура исходников

Ожидаемая форма изменения в `siderolabs/extensions`:

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

Дополнительно меняются source-of-truth файлы репозитория:

- `.kres.yaml` — добавить target в алфавитном порядке;
- `MAINTAINERS.md` — добавить ответственного maintainer;
- сгенерированные файлы обновить только штатной командой `make rekres`;
- generated catalog в `README.md` обновить через `make extensions-catalog`, если
  этого требует PR workflow.

README старой формулировкой предлагает добавить target непосредственно в
`Makefile`, но текущий `Makefile` помечен как generated. Актуальный kernel-module
guide и `.kres.yaml` показывают правильный путь: менять `.kres.yaml`, затем запускать
`make rekres`; вручную редактировать Makefile нельзя.

## Правила `pkg.yaml`

Для in-tree kernel modules следует повторять актуальный паттерн существующих driver
extensions:

- `variant: scratch`;
- dependency на `base` stage;
- dependency на matching `kernel` image через `BUILD_ARG_PKGS`;
- определение `KERNELRELEASE` из `/usr/lib/modules/*-talos`;
- явный список копируемых модулей, а не весь kernel module tree;
- `install -D` с сохранением upstream path;
- `depmod -b /rootfs/usr <kernelrelease>`;
- запуск `extensions-validator` в test stage;
- finalize только `/rootfs` и `/pkg/manifest.yaml`.

Список модулей должен быть получен из фактического результата сборки и проверен
через `modinfo`/`modprobe --show-depends`, а не угадан. Для USB Realtek ожидаются как
минимум Bluetooth core, `btusb`, `btrtl` и зависимости, выбранные Kconfig; итоговый
набор фиксируется только после `olddefconfig` и сборки обеих архитектур.

## Минимальная kernel configuration для USB BLE Realtek

Kconfig Linux 6.18 показывает следующий функциональный минимум:

- `CONFIG_BT=m` — Bluetooth core;
- `CONFIG_BT_LE=y` — BLE;
- `CONFIG_BT_HCIBTUSB=m` — USB HCI transport (`btusb`);
- `CONFIG_BT_HCIBTUSB_RTL=y` — Realtek firmware/config download path;
- `CONFIG_RFKILL=y` — rfkill subsystem встроен в kernel.

Встроенный rfkill необходим не только Bluetooth. В Talos v1.14 base module
`eeepc-laptop.ko` начинает ссылаться на rfkill symbols сразу после включения
subsystem; если оставить `RFKILL=m` исключительно в позднем extension layer,
строгий base `depmod --errsyms` завершает сборку до наложения extension.

`CONFIG_BT_HCIBTUSB` автоматически выбирает `BT_INTEL`, а Realtek option выбирает
`BT_RTL`; поэтому итоговые `.config` и module dependencies должны приниматься как
источник истины. Не нужно переносить 60-symbol community-конфигурацию, скопированную
из Ubuntu 22.04: RFCOMM, BNEP, CMTP, HIDP, UART, SDIO, MediaTek, Broadcom, Atheros,
debugfs и virtual HCI не требуются для локального BLE через Realtek USB.

Нужно явно проверить, не включил ли `olddefconfig` default options, которые расширяют
scope, например Broadcom USB support или Bluetooth debugfs. Ненужные значения
фиксируются как `# CONFIG_... is not set` только если это необходимо для стабильного
минимального результата.

Kconfig sources:

- [Linux 6.18 Bluetooth core](https://github.com/torvalds/linux/blob/v6.18/net/bluetooth/Kconfig)
- [Linux 6.18 Bluetooth device drivers](https://github.com/torvalds/linux/blob/v6.18/drivers/bluetooth/Kconfig)
- [Linux 6.18 rfkill](https://github.com/torvalds/linux/blob/v6.18/net/rfkill/Kconfig)

## Подпись и точное совпадение модулей

Talos требует загружаемые модули, подписанные ключом, которому доверяет конкретное
ядро. Поэтому:

1. kernel и модули собираются в одном `pkgs` build;
2. extension использует kernel image именно этого build;
3. custom Talos installer-base использует тот же kernel image;
4. module signature enforcement остаётся включённым;
5. `module.sig_enforce=0` не используется как способ «починить» сборку.

Минимальные artifact checks:

```bash
modinfo -F vermagic <module.ko>
modinfo -F signer <module.ko>
modinfo -F sig_id <module.ko>
modinfo -F depends <module.ko>
depmod -e -F <System.map> -b <root> <kernelrelease>
```

Проверка должна утверждать, что:

- `vermagic` соответствует загружаемому Talos kernel release;
- `signer` и `sig_id` не пусты;
- в каждом `.ko` присутствует signature trailer;
- все hard dependencies присутствуют в extension либо уже находятся в base Talos;
- `modules.dep`, `modules.alias` и прочие depmod metadata согласованы.

## Воспроизводимость и supply chain

Для каждой сборки фиксируются:

- Talos tag и commit SHA;
- `pkgs` tag/commit SHA;
- `extensions` tag/commit SHA;
- Linux version и source checksums из `Pkgfile`;
- `bldr`, toolchain, validator и imager versions/images;
- digest каждого использованного OCI image;
- build platform;
- digest результирующего extension и installer;
- результат signature verification.

Upstream `extensions`:

- строит все targets для amd64 и arm64;
- запускает `extensions-validator`;
- генерирует каталог и требует чистый tree после генерации;
- проверяет дубликаты файлов между extensions;
- по PR label может запускать Grype и reproducibility test;
- публикует подписанные images, которые потребителям следует указывать по digest.

Наличие SBOM зависит от типа и tier. Для userspace BlueZ/D-Bus extension нужно
планировать SBOM с версиями, CPE и лицензиями. Для копии in-tree модулей отдельный
SBOM не должен ложно дублировать provenance самого kernel package; решение нужно
сверить с maintainer pattern на момент PR.

## Contribution hygiene

Перед upstream PR:

1. открыть issue/discussion и подтвердить, что maintainers готовы принять kernel
   config footprint и новый catalog entry;
2. предложить kernel config change в `siderolabs/pkgs` отдельно от extension PR;
3. после доступности соответствующего `pkgs` image предложить
   `siderolabs/extensions` PR;
4. не объединять kernel drivers и BlueZ/D-Bus userspace в один review;
5. приложить hardware evidence минимум для одного Realtek USB controller и
   generic dependency evidence для обеих архитектур;
6. указать maintainer и поддержку tier без требования повысить tier;
7. приложить exact build/test commands и digests;
8. обновить документацию и generated artifacts штатными генераторами.

Текущая `.conform.yaml` декларирует DCO, signed commits, US English spellcheck,
imperative lowercase commit header до 89 символов и обязательное тело commit. Перед
реальной отправкой нужно перепроверить, как эти правила применяются к external
contributors. Этот проект не создаёт commits или PR без отдельного разрешения.

Репозитории `pkgs`, `extensions` и `talos` лицензированы под MPL-2.0; Linux kernel
modules сохраняют upstream GPL-2.0 licensing. Любой заимствованный source fragment
должен иметь записанный commit, лицензию и понятное преобразование. Generated
artifacts и чужие unsigned images не заимствуются.

## Community references и допустимое использование

Проверены два исторических proof-of-concept:

- [`dancavallaro/talos-pkgs@c8d7389`](https://github.com/dancavallaro/talos-pkgs/commit/c8d738929f88f18149ac5da7c0e1dd591ec14e0b)
  включал широкий Ubuntu-derived набор из 60 Bluetooth Kconfig lines;
- [`dancavallaro/talos@ad53f78`](https://github.com/dancavallaro/talos/commit/ad53f78b677f3a180dbf873ebd726d5e1fbe34e3)
  вручную добавлял семь Bluetooth modules в Talos initramfs.

Из них допустимо использовать только подтверждение общей жизнеспособности подхода и
названия возможных модулей. Нельзя копировать их архитектуру буквально, потому что:

- она относится к старой структуре Talos;
- Kconfig существенно шире текущего BLE use case;
- она не создаёт отдельный catalog extension;
- она не доказывает совместимость с текущим validator, signature enforcement,
  dual-architecture CI или Home Assistant D-Bus boundary.

## Acceptance gates проекта

### Gate A: source и config

- exact upstream revisions pinned;
- обе config проходят `olddefconfig` без неожиданного scope growth;
- обязательные `CONFIG_BT*` и `CONFIG_RFKILL` проверяются автоматически;
- не включены ненужные protocols/transports/vendors;
- diff соответствует upstream conventions.

### Gate B: kernel artifacts

- kernel и modules успешно собраны для amd64 и arm64;
- список модулей выведен из build artifacts;
- dependency tree полон;
- signature и `vermagic` проверены;
- enforcement не отключён.

### Gate C: extension artifacts

- manifest и rootfs проходят official validator;
- catalog target собирается;
- duplicate finder не обнаруживает bundled Realtek firmware или другие конфликты;
- local output содержит только заявленные модули и metadata;
- build воспроизводим из pinned sources.

### Gate D: безопасный bare-metal тест

- есть rollback installer и проверенный recovery path;
- custom image назначается только явно выбранному тестовому узлу;
- после загрузки доступны `bluetooth`, `btusb`, нужный vendor helper и `rfkill`;
- появился `hci0`, firmware загрузилось без kernel errors;
- Kubernetes, Cilium, CSI и workloads здоровы после возврата node.

### Gate E: userspace и Home Assistant

- активны dbus-broker и BlueZ с подтверждённой версией;
- `bluetoothctl list/show/scan` или эквивалент доказывает работу адаптера;
- D-Bus socket доступен Home Assistant read-only;
- capabilities ограничены `NET_ADMIN` и `NET_RAW`, если runtime evidence не требует
  иного;
- Home Assistant выполняет active/passive BLE scan;
- выполнено реальное GATT-соединение с Tion, а не только discovery.

Проект можно называть «готовым к upstream review» после Gates A-C. Полную поддержку
Home Assistant можно заявлять только после Gates D-E.

## Перед каждой новой сессией или сборкой

1. Проверить latest stable/pre-release и heads `main`/release branch.
2. Проверить pin `talos/pkg/machinery/gendata/data/pkgs`.
3. Проверить `PKGS`, `TOOLS`, `BLDR_RELEASE` и validator image в `extensions`.
4. Сравнить актуальные driver-extension patterns и `.kres.yaml`.
5. Проверить текущий Linux Kconfig для выбранной версии.
6. Зафиксировать, работает ли сессия только с source artifacts или имеет отдельное
   разрешение на image publication/live mutation.
