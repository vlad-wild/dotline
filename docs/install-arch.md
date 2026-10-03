# Установка Arch Linux рядом с Windows 11

ASUS Zenbook 14 UX3405CA, NVMe 1 ТБ, Windows с BitLocker. Результат:
- **dual boot** через systemd-boot;
- Linux на **LUKS2 + btrfs** с подтомами под snapper;
- **swapfile 32 ГБ** для гибернации;
- Secure Boot включён обратно с собственными ключами.

Перед началом выполните разделы 0–2 из [MIGRATION.md](../MIGRATION.md): резервная копия, ключ BitLocker, быстрый запуск выключен, время в UTC.

> Раздел диска с Windows мы не форматируем и не двигаем. Опасные команды помечены **⚠** — перед ними ещё раз проверьте имя раздела (`lsblk -f`).

## 1. В Windows

1. **Проверить состояние BitLocker** (из администраторской консоли):
   ```powershell
   manage-bde -status C:
   manage-bde -protectors -get C:
   ```
   На этом ноутбуке по факту (проверено) — **«Состояние защиты: Защита отключена»** и **«Предохранители ключа: не обнаружены»**: том зашифрован (100%, только занятое место), но ничем не защищён и без привязанного ключа. В этом состоянии приостанавливать нечего, `manage-bde -protectors -disable` ничего не изменит, и изменения Secure Boot/разметки диска не вызовут запрос ключа восстановления при загрузке Windows — спрашивать его попросту не у чего.
   Если у вас (или при повторной установке на другой машине) `manage-bde -status` покажет **«Защита включена»** — тогда перед шагами 2 и BIOS выполните:
   ```powershell
   manage-bde -protectors -disable C: -RebootCount 3
   ```
   иначе смена Secure Boot действительно спросит ключ восстановления при следующей загрузке Windows.
2. **Освободить место.** Через diskpart (точнее, чем GUI «Управление дисками» — сразу видно реальный потолок):
   ```powershell
   diskpart
   list disk
   select disk 0
   list partition          # сверьтесь по размеру: C: — partition с Type=Basic
   select partition <N>
   shrink querymax          # покажет реальный максимум в МБ — может быть меньше 350-400 ГБ
   shrink desired=<МБ>      # например, 277725 для ~271 ГБ
   exit
   ```
   Если потолок заметно меньше ожидаемого (отъедают `hiberfil.sys`/`pagefile.sys`/теневые копии) — можно временно `powercfg /hibernate off` и отключить файл подкачки (Параметры → Система → О системе → Дополнительные параметры системы → Быстродействие → Виртуальная память → «Без файла подкачки»), перезагрузиться и повторить `shrink querymax`; оба можно вернуть обратно уже после `shrink`. Освобождённое место остаётся **нераспределённым** — отдельный том создавать не нужно, разметка руками через `sgdisk` в разделе 4.
3. **Записать ISO Arch** на флешку: Rufus в режиме DD или Ventoy. ISO берём с https://archlinux.org/download/ и проверяем подпись.

## 2. BIOS (F2 при включении)

- **Secure Boot → Disabled**: ISO Arch не подписан. Включим обратно в разделе 7.
- Boot order: USB первым. Fast Boot в BIOS выключить.

## 3. Загрузка с флешки и сеть

```bash
iwctl station wlan0 connect "<ваша сеть>"   # Wi-Fi
ping -c2 archlinux.org
timedatectl set-ntp true
lsblk -f                                     # смотрим разметку
```

Ожидаемая разметка `nvme0n1` (проверено на реальном диске этого ноутбука через `Get-Partition` в Windows — не предположение):
- p1 — EFI Windows (1024 МБ, FAT32);
- p2 — MSR (16 МБ);
- p3 — Windows (BitLocker);
- p4 — Windows RE (776 МБ);
- дальше — свободное место (после `shrink` в разделе 1).

## 4. Разделы

Создаём отдельный **XBOOTLDR** на 1 ГБ — не потому что ESP Windows мал
(на этом ноутбуке он реально 1024 МБ, что само по себе не крохотный
размер), а для запаса: два ядра (`linux` + `linux-lts`) с Unified
Kernel Images дают по два образа каждое (`default`+`fallback`),
~100–250 МБ штука — вместе с уже занятым Windows (bootmgfw.efi, заглушка
WinRE) это вплотную подходит к 1 ГБ или превышает его. Свободное место
на диске (271 ГБ) достаточно большое, чтобы заплатить 1 ГБ за полную
независимость от раздела Windows — если он забьётся при будущем
обновлении ядра, это тихая поломка boot-entry, а не раздел Windows с
гарантированным местом. systemd-boot читает оба раздела.

```bash
# ⚠ Создаём разделы ТОЛЬКО в свободной области после p4
sgdisk -n 0:0:+1G -t 0:ea00 -c 0:XBOOTLDR /dev/nvme0n1
sgdisk -n 0:0:0   -t 0:8309 -c 0:cryptlinux /dev/nvme0n1
partprobe /dev/nvme0n1 && lsblk -f          # появились p5 и p6

mkfs.fat -F32 -n XBOOTLDR /dev/nvme0n1p5     # ⚠ p5 — новый раздел
cryptsetup luksFormat --type luks2 /dev/nvme0n1p6   # ⚠ p6 — новый раздел; пароль шифрования
cryptsetup open /dev/nvme0n1p6 cryptroot
mkfs.btrfs -L arch /dev/mapper/cryptroot
```

Подтома btrfs (раскладка под snapper, swap отдельно — его нельзя снапшотить):
```bash
mount /dev/mapper/cryptroot /mnt
for sv in @ @home @log @pkg @snapshots @swap; do btrfs subvolume create /mnt/$sv; done
umount /mnt

o=noatime,compress=zstd:1,space_cache=v2
mount -o $o,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,swap,efi,boot}
mount -o $o,subvol=@home      /dev/mapper/cryptroot /mnt/home
mount -o $o,subvol=@log       /dev/mapper/cryptroot /mnt/var/log
mount -o $o,subvol=@pkg       /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o $o,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o noatime,subvol=@swap /dev/mapper/cryptroot /mnt/swap
mount /dev/nvme0n1p1 /mnt/efi      # EFI Windows — только добавим загрузчик
mount /dev/nvme0n1p5 /mnt/boot     # XBOOTLDR — ядра

btrfs filesystem mkswapfile --size 32g --uuid clear /mnt/swap/swapfile
swapon /mnt/swap/swapfile
```

## 5. Базовая система (pacstrap)

Без `archinstall` целиком: его режим *Pre-mounted configuration*
слишком хрупко определяет корневой раздел по смонтированному `/mnt`
(версионно-зависимо, у разных сборок ISO ведёт себя по-разному) — раз
всё уже размечено и смонтировано руками в разделе 4, надёжнее сделать
и установку руками.

```bash
pacstrap -K /mnt base base-devel linux linux-lts linux-firmware \
  intel-ucode sof-firmware btrfs-progs snapper snap-pac \
  networkmanager git nano
```

```bash
genfstab -U /mnt >> /mnt/etc/fstab
echo '/swap/swapfile none swap defaults 0 0' >> /mnt/etc/fstab
cat /mnt/etc/fstab   # ⚠ проверить: у каждого подтома свой subvol=, swapfile на месте, дублей нет
```

## 6. Настройка системы (chroot)

```bash
arch-chroot /mnt
```

```bash
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

sed -i 's/^#\(en_US\.UTF-8\)/\1/; s/^#\(ru_RU\.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

echo 'dotline' > /etc/hostname   # или любое другое имя машины

passwd                                    # пароль root
useradd -m -G wheel -s /bin/bash these
passwd these
EDITOR=nano visudo                        # раскомментировать: %wheel ALL=(ALL:ALL) ALL

systemctl enable NetworkManager
```

```bash
# 6.1 Шифрование и гибернация в initramfs (systemd-хуки):
#     HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
nano /etc/mkinitcpio.conf

# 6.2 Параметры ядра: /etc/kernel/cmdline
#     rd.luks.name=<UUID p6>=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet
blkid -s UUID -o value /dev/nvme0n1p6
nano /etc/kernel/cmdline
# resume= не нужен: systemd ≥ 255 сам записывает место гибернации в EFI-переменную.
```

**6.3 Unified kernel images — вручную, в `/boot` (XBOOTLDR), не в `/efi`**
(без archinstall этот шаг никто за вас не сделает). Для **обоих** ядер
откройте пресет в nano, **стерите всё содержимое файла (`Ctrl+K` много
раз, либо выделить всё и удалить) и вставьте** вместо него — показано
на примере `linux` (`/etc/mkinitcpio.d/linux.preset`); для `linux-lts`
(`/etc/mkinitcpio.d/linux-lts.preset`) то же самое, но с `-lts` в
именах файлов (`vmlinuz-linux-lts`, `arch-linux-lts.efi`,
`arch-linux-lts-fallback.efi`):

```bash
nano /etc/mkinitcpio.d/linux.preset
```
```ini
ALL_kver="/boot/vmlinuz-linux"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=('default' 'fallback')

#default_image="/boot/initramfs-linux.img"
default_uki="/boot/EFI/Linux/arch-linux.efi"

#fallback_image="/boot/initramfs-linux-fallback.img"
fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
```
Важно: путь `/boot/EFI/Linux/…`, а не стандартный для Arch
`/efi/EFI/Linux/…` — UKI должны лежать на **XBOOTLDR**, не на ESP
Windows (раздел 4 примонтировал его именно туда; systemd-boot сам
находит образы что на ESP, что на XBOOTLDR в `EFI/Linux/`,
Boot Loader Specification это и предусматривает).

```bash
mkinitcpio -P
ls /boot/EFI/Linux/       # ⚠ должны появиться 4 файла: arch-linux(-fallback).efi, arch-linux-lts(-fallback).efi

bootctl --esp-path=/efi --boot-path=/boot install
cat > /efi/loader/loader.conf << 'EOF'
default @saved
timeout 3
console-mode max
editor no
EOF

bootctl status          # Windows Boot Manager должен быть в списке записей
```

Если после перезагрузки клавиши яркости OLED не работают, добавьте в `/etc/kernel/cmdline` `i915.enable_dpcd_backlight=1` (или `xe.enable_dpcd_backlight=1`, если используется драйвер `xe`; проверить через `lspci -k | grep -A3 VGA`), пересоберите UKI (`mkinitcpio -P`) — старый образ в `/boot/EFI/Linux/` просто перезапишется тем же именем, перезапускать `bootctl install` не нужно.

```bash
exit            # выйти из chroot
swapoff /mnt/swap/swapfile
umount -R /mnt
reboot
```

## 7. После первой загрузки

1. **Secure Boot с собственными ключами** — `sbctl`, вместе с ключами Microsoft, чтобы Windows продолжала грузиться:
   ```bash
   sudo pacman -S sbctl
   sbctl status                 # Setup Mode должен быть Enabled (в BIOS: Secure Boot → Clear keys / Setup mode)
   sudo sbctl create-keys
   sudo sbctl enroll-keys -m    # -m — оставить ключи Microsoft
   sudo sbctl sign-all -g       # systemd-boot и всё, что sbctl видит сам — но это только ESP (/efi)!
   ```
   ⚠ **Если UKI лежат на XBOOTLDR** (раздел 6.3 этой доки кладёт их в `/boot/EFI/Linux/`, а не в `/efi/EFI/Linux/`) — `sbctl sign-all`/`sbctl verify` по умолчанию видят только ESP (подтверждено по `sbctl.conf(5)`: `verify` «looks for EFI binaries … in the ESP partition») и **не найдут и не подпишут** эти файлы сами. Подпишите их явно (`-s` — подписать и запомнить путь, чтобы `sign-all` на будущих обновлениях ядра тоже их подхватывал):
   ```bash
   sudo sbctl sign -s /boot/EFI/Linux/arch-linux.efi
   sudo sbctl sign -s /boot/EFI/Linux/arch-linux-fallback.efi
   sudo sbctl sign -s /boot/EFI/Linux/arch-linux-lts.efi
   sudo sbctl sign -s /boot/EFI/Linux/arch-linux-lts-fallback.efi
   sudo sbctl verify
   ```
   Без этого шага включение Secure Boot в BIOS откажется грузить неподписанные UKI (проверено на реальной установке — ровно так и было).
   В BIOS: **Secure Boot → Enabled**. На этом ноутбуке защита и так была выключена (раздел 1, пункт 1) — включать обратно нечего. Если вы ставили систему на машине, где протекторы действительно были и вы их приостанавливали (`-disable ... -RebootCount 3`), после входа в Windows включите защиту обратно: `manage-bde -protectors -enable C:`.
2. **Разблокировка диска по TPM** (по желанию, чтобы не вводить пароль LUKS каждый раз):
   ```bash
   sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/nvme0n1p6
   ```
   С PIN: вход по лицу работает уже после разблокировки диска, а PIN защищает при краже ноутбука. Пароль LUKS остаётся запасным.

   Без PIN (полностью автоматическая разблокировка, без единого вопроса) — заменить уже сделанную запись одной командой: `systemd-cryptenroll` сам сначала добавит новую (без PIN), и только если это получилось, сотрёт старую, так что без рабочего TPM-слота в процессе вы не остаётесь:
   ```bash
   sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p6
   ```
   Попросит ввести обычный пароль LUKS один раз — для подтверждения, так добавляется любой новый слот. Проверить результат (должен остаться один слот `tpm2` без PIN и слот с паролем как запасной):
   ```bash
   sudo systemd-cryptenroll /dev/nvme0n1p6
   ```

   ⚠ `--tpm2-pcrs=7` привязывает разблокировку к состоянию Secure Boot (PCR 7). Если потом поменяете ключи Secure Boot или включите/выключите его — TPM перестанет совпадать, и система сама откатится на запрос обычного пароля (не катастрофа, просто ввести пароль руками один раз и перерегистрировать TPM той же командой).
3. **snapper:**
   ```bash
   sudo umount /.snapshots && sudo rmdir /.snapshots
   sudo snapper -c root create-config /
   sudo btrfs subvolume delete /.snapshots
   sudo mkdir /.snapshots && sudo mount -a
   ```
4. **Проверка гибернации:** `systemctl hibernate` → включить → сессия должна восстановиться.
5. **Рабочее окружение:**
   ```bash
   git clone <репозиторий linux-migrate> ~/dev/linux-migrate
   cd ~/dev/linux-migrate
   ./install.sh --dry-run      # посмотреть план
   ./install.sh
   ```
   Пара вещей, которые выглядят как зависание, но не являются им:
   - **`openvino`** собирается из исходников (пакета AUR `openvino`, не
     `-bin` — тот неактуален на момент написания) и может идти **час и
     больше** — это нормально для такого большого C++-тулкита, не
     повод прерывать установку.
   - **`paru` перед установкой AUR-пакета спрашивает `Proceed to
     review? [Y/n]`** (показать PKGBUILD на просмотр) — это намеренно
     не подавляется никакими флагами (просматривать чужой код перед
     сборкой — не лишняя формальность), так что `install.sh` в части с
     AUR не полностью безмолвный, нужно будет подтверждать по ходу.
6. Дальше — [MIGRATION.md](../MIGRATION.md), раздел 7.

## Если что-то пошло не так

- **Windows не грузится / просит ключ BitLocker** — на этом ноутбуке защита выключена и предохранителей нет (проверено `manage-bde -protectors -get C:`), так что этот сценарий в принципе не должен случиться. Если всё же случился (протектор появился откуда-то ещё, или это другая машина) — ключ восстановления (раздел 0 MIGRATION.md), в Windows: `manage-bde -protectors -enable C:`.
- **Linux не грузится после обновления** — в меню systemd-boot выбрать `linux-lts` или снапшот. Откат: `sudo snapper -c root rollback <номер>`.
- **Сломался PAM** (не пускает в систему) — на запасной консоли root (`Ctrl+Alt+F3`) вернуть файлы: `for f in /etc/pam.d/*.dotline.bak; do cp "$f" "${f%.dotline.bak}"; done`.
- **Экран входа (greetd) пустой или не показывается** — graphical-гритер (`/etc/dotline/greeter`) сломан или не запустился. На запасной консоли (`Ctrl+Alt+F3`, логин под своим пользователем): `sudo systemctl status greetd` и `journalctl -u greetd -b` покажут ошибку. Быстрый откат на простой текстовый вход: `sudo sed -i 's/^command = .*/command = "agreety --cmd niri"/' /etc/greetd/config.toml && sudo systemctl restart greetd`.
