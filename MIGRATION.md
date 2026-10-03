# Перенос с Windows 11 на Arch Linux

План переноса данных, настроек и приложений с ASUS Zenbook 14 (UX3405CA). Составлен по инвентаризации Windows от 30.09.2026: установленные программы, размеры папок, профили приложений, WSL. Установка самой системы описана в [docs/install-arch.md](docs/install-arch.md), рабочее окружение ставится через [install.sh](install.sh).

**Стратегия.** Первое время живём в **dual boot**: Windows остаётся на диске, пока в Linux не заработает всё нужное. Данные копируем прямо с раздела Windows. Linux читает NTFS, а зашифрованный BitLocker-раздел открывается через `cryptsetup --type bitlk` ключом восстановления. То, что в Linux не работает (ЭЦП, Office с Visio и Project, Photoshop, Hikvision), уходит в **виртуальную машину Windows**, окна которой выглядят как обычные окна Linux (WinApps). Windows с диска удаляем только после чек-листа в конце.

---

## 0. Главные риски — проверить до переезда

| Что | Почему важно | Что делаем |
|---|---|---|
| **КриптоПро CSP, ЭЦП Browser plug-in, Госплагин, Контур.Плагин, Рутокен (rtCOMLite)** | Подпись документов, Госуслуги, Контур. Под Linux есть версии КриптоПро, Рутокена и плагина Госуслуг, но на Arch это неофициальная сборка, а Контур официально поддерживает Linux ограниченно | Основной путь — **ВМ Windows** с пробросом токена по USB. Параллельно пробуем нативно: КриптоПро CSP для Linux + `librtpkcs11ecp` + плагин Госуслуг в Chromium-браузере. Проверяем подписью тестового документа **до** удаления Windows |
| **Ключ восстановления BitLocker** | Без него не открыть диск C: из Linux, а смена настроек Secure Boot может потребовать ключ при загрузке Windows — **но на этом ноутбуке проверено (`manage-bde -status C:`/`-protectors -get C:`): защита выключена, предохранителей нет вообще** — сохранять нечего, а `scripts/migrate` это уже учитывает (при отсутствии BitLocker-протектора сам находит и монтирует NTFS-раздел напрямую, без `cryptsetup`) | Если команда ниже всё же найдёт предохранители (например, после обновления Windows или на другой машине) — `manage-bde -protectors -get C:` (консоль администратора) или https://account.microsoft.com/devices/recoverykey → сохранить в двух местах вне ноутбука |
| **WSL Ubuntu: 34 ГБ в `/home/vlad`** | Там часть проектов (`adb`, `b24-process-lab`, `netbox`, `speech-analytics`) и, возможно, незакоммиченные изменения | Сначала `git status` и `git push` во всех репозиториях, потом `wsl --export Ubuntu D:\ubuntu.tar` на внешний диск (или копирование `/home/vlad` через `\\wsl.localhost`) |
| **Downloads: 93 ГБ** | Половина занятого пользователем места; тормозит копирование | Разобрать до переезда: удалить установщики `.exe` и `.msi`, ISO-образы, дубликаты. Нужное — в `Documents` / на внешний диск |
| **SSH-ключи** (`id_ed25519`, `config`, `known_hosts`) | Доступ к серверам и GitHub | Копируем с правами `700` / `600`, проверяем `ssh -T git@github.com` |

## 1. Резервная копия (до любых действий с диском)

1. Внешний диск ≥ 256 ГБ. Копируем:
   - `Desktop` (8,5 ГБ), `Documents` (0,5 ГБ), `Pictures`, `Videos` (1,3 ГБ);
   - разобранную `Downloads`;
   - `C:\Users\these\dev` (2,5 ГБ);
   - экспорт WSL (см. п. 0).
2. Отдельно — всё, что трудно восстановить:
   - `.ssh`;
   - сохранения игр (п. 4);
   - профиль Thunderbird (1,3 ГБ);
   - заметки Joplin;
   - конфиги VPN (AmneziaVPN, WireGuard, OpenVPN, Happ);
   - экспорт профилей Wi-Fi (п. 5).
3. **Синхронизация в облако** — включить и дождаться завершения:
   - Brave Sync (цепочка синхронизации), Firefox Sync;
   - Settings Sync в VS Code и Cursor, JetBrains Settings Sync (IntelliJ, Android Studio);
   - синхронизация Joplin.
4. Проверяем, что копия открывается на другом компьютере или хотя бы с внешнего диска.

## 2. Подготовка Windows

- Отключить **быстрый запуск**: Панель управления → Электропитание → «Действия кнопок питания». Иначе раздел NTFS остаётся в полу-гибернации, и Linux не сможет безопасно на него писать.
- **Время в UTC** для dual boot: в реестре `HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation` создать `RealTimeIsUniversal` (DWORD) = `1`. Иначе часы будут сдвигаться на 3 часа при каждой смене системы.
- Сжать раздел C: в «Управлении дисками». Сейчас занято 544 ГБ из 954. После чистки Downloads под Linux можно отдать **350–400 ГБ** (раскладка разделов — в `docs/install-arch.md`).
- Обновить прошивку BIOS и Thunderbolt, пока доступен MyASUS; в Linux дальше обновляемся через `fwupd`.
- Выписать то, что настраивалось вручную: раскладки, горячие клавиши в Logi Options+, плагины Windhawk. Их аналоги уже есть в плане рис.

## 3. Данные: откуда → куда

| Windows | Linux | Как |
|---|---|---|
| `Desktop`, `Documents`, `Pictures`, `Videos`, `Music` | `~/Desktop`, `~/Documents`, `~/Pictures`, `~/Videos`, `~/Music` (`xdg-user-dirs`) | `rsync -aHAX --info=progress2` с раздела Windows |
| `Downloads` (после разбора) | `~/Downloads` | то же |
| `C:\Users\these\dev` | `~/dev` | `rsync`, затем в каждом репозитории: `git config core.autocrlf input`, `git status` (CRLF после Windows), пересобрать `target/` и `node_modules/` на месте |
| WSL `/home/vlad` (34 ГБ) | `~/dev` + `~/wsl-home` для остального | распаковать `ubuntu.tar` или скопировать `/home/vlad` |
| `.ssh` | `~/.ssh` | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_* ~/.ssh/config` |
| `.gitconfig` (`Vlad Wild`, `ya.vlash1@yandex.ru`) | `~/.gitconfig` | переносим, `safe.directory` на пути `wsl.localhost` удаляем |
| Обои из `Pictures` (7 шт.) и облака | `linux-migrate/wallpapers/` | уже в плане рис |
| `.lmstudio` (16 ГБ моделей) | `~/.lmstudio` или `~/models` | копировать, только если модели нужны; на RX 7900 GRE (16 ГБ) они пойдут через ROCm или Vulkan |

Скрипт-помощник **`scripts/migrate`**:
```
dotline-migrate mount [/dev/sdXN]        BitLocker (спросит ключ) или обычный NTFS, смотря что найдёт — см. ниже; только для чтения в /mnt/windows
dotline-migrate status                   размеры папок, что сейчас примонтировано
dotline-migrate data [--only=Desktop,…]  rsync по таблице выше (можно повторять, докопирует новое)
dotline-migrate games                    сохранения нативных игр (таблица в разделе 4)
dotline-migrate wifi <папка> [--apply]   импорт экспорта netsh wlan в NetworkManager
dotline-migrate unmount                  закрыть раздел обратно
```
Раздел Windows **никогда не монтируется на запись**. Wi-Fi (`--apply`) без флага только показывает, что будет сделано.

## 4. Игры и сохранения

Steam ставим нативно (multilib), остальное — через Proton. Облачные сохранения Steam подтянутся сами, но **копию локальных сохранений делаем всё равно**:

| Игра | В Linux | Сохранения в Windows → куда |
|---|---|---|
| Factorio | нативная | `%APPDATA%\Factorio` (107 МБ) → `~/.factorio` |
| RimWorld | нативная | `AppData\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios` (278 МБ) → `~/.config/unity3d/Ludeon Studios/RimWorld by Ludeon Studios` |
| Oxygen Not Included | нативная | `Documents\Klei\OxygenNotIncluded` (360 МБ) → `~/.config/unity3d/Klei/Oxygen Not Included` |
| Stellaris | нативная | `Documents\Paradox Interactive\Stellaris` (167 МБ) → `~/.local/share/Paradox Interactive/Stellaris` |
| Dwarf Fortress | нативная | папка `save` в каталоге игры |
| Kenshi, Turbo Overkill, SEX, SIN & ROCK'N'ROLL, Strata | Proton | сохранения внутри префикса Proton (`steamapps/compatdata/<appid>`); Kenshi — папка `save` в игре (сейчас пустая) |
| Minecraft (Modrinth App, 1,2 ГБ; Prism Launcher) | нативные | `%APPDATA%\ModrinthApp` → `~/.local/share/ModrinthApp`; Prism — экспорт инстансов |
| Paradox Launcher | нативный | вход в аккаунт |

После первого запуска каждой игры в Linux проверяем, что сохранения видны. Только потом удаляем их копию в Windows.

## 5. Настройки

| Что | Как переносим |
|---|---|
| **Wi-Fi** (7 профилей) | В Windows: `netsh wlan export profile key=clear folder=D:\wifi` (XML с паролями — хранить аккуратно и удалить после импорта); `dotline-migrate` импортирует их в NetworkManager |
| **Bluetooth** (MX Master 4, Galaxy Buds) | При dual boot ключи спаривания в двух системах расходятся, и после каждой смены ОС устройства пришлось бы спаривать заново. Синхронизируем ключи утилитой `bt-dualboot` (AUR) или ставим мышь на приёмник Bolt |
| **VPN** | AmneziaVPN — экспорт конфигов из клиента → импорт в клиент AmneziaVPN под Linux или `.conf` в `/etc/amnezia/amneziawg/`. WireGuard и OpenVPN — конфиги в NetworkManager. Happ — перенос подписки в Linux-клиент (Happ / Hiddify / Throne) |
| **Раскладки и горячие клавиши** | Уже в плане рис: EN/RU на Copilot, клавиши в стиле Windows |
| **Мышь (Logi Options+)** | Solaar: жесты, кнопки, хаптика — в плане рис |
| **Принтеры** (Kyocera, HP) | CUPS: `hplip` для HP, `kyocera-cups` (AUR) для Kyocera; добавление через `system-config-printer` |
| **Звук (Dolby, Realtek)** | EasyEffects-пресет для динамиков Zenbook (в плане рис) |
| **Шрифты для документов Office** | `ttf-ms-win11-auto` (AUR) копирует шрифты с раздела Windows — нужны, чтобы `.docx` не «поехали» в LibreOffice или OnlyOffice |
| **Браузеры** | Brave и Firefox — через их синхронизацию (п. 1). Профиль Firefox можно перенести и папкой, но синхронизация надёжнее |
| **Терминал** | Nushell, Carapace и starship есть под Linux — переносим конфиги из `.config`; Tabby — экспорт настроек (или переходим на kitty из рис) |

## 6. Приложения: что ставить в Linux

**Нативно, просто ставим и входим:**
Brave, Firefox, Thunderbird (перенос профиля), Telegram, Zoom, Bitrix24 (клиент для Linux), VS Code, Cursor, IntelliJ IDEA, Android Studio, Postman, DbGate, SQLiteStudio, Git, Node.js, Python, Rust (`rustup`), JDK 21, Docker (нативный `docker`, без Docker Desktop), PowerShell 7 (`pwsh`), Nushell, starship, Carapace, OBS Studio, Kdenlive, VLC, qBittorrent, LocalSend, Joplin, LM Studio (AppImage), Steam, Modrinth App, Prism Launcher, Paradox Launcher, AmneziaVPN, WireGuard, 7-Zip (`7zip`).

**Замена на Linux-аналог:**

| Windows | Linux |
|---|---|
| Everything | поиск файлов `/f` в лаунчере рис (`fd` + `plocate`), FSearch |
| Lightshot | скриншоты рис (`Win+Shift+S`) |
| ImageGlass, Paint | Loupe / qimgv; Pinta или Krita |
| CPU-Z, CrystalDiskInfo | CPU-X, GSmartControl (`smartctl`) |
| Phone Link | KDE Connect (в плане рис) |
| Logi Options+ | Solaar (в плане рис) |
| MyASUS, Intel Arc Control, Thunderbolt Control Center | окно настроек рис: «Ноутбук», «Видеокарты», устройства Thunderbolt |
| Galaxy Buds | GalaxyBudsClient (открытый, есть под Linux) |
| Windhawk, Winaero Tweaker, Revision Tool | не нужны: всё это настраивается в рис |
| VirtualBox | virt-manager (QEMU/KVM); VirtualBox тоже есть под Linux |
| Yandex Музыка | веб-версия или неофициальный клиент (AUR) |
| Figma | веб-версия (или `figma-linux`, AUR) |
| Visual Studio 2022 | JetBrains Rider / VS Code; для проектов, которым нужен именно Windows и MSVC, — ВМ |
| Мессенджер Exolve | веб-версия; если её нет — ВМ |
| Microsoft Office 2019 (Word, Excel, PowerPoint) | OnlyOffice или LibreOffice для повседневного + шрифты Windows; сложные документы — Office в ВМ |

**Только в Windows — уходят в ВМ Windows (WinApps):**
- Microsoft **Visio** и **Project** 2019; альтернативы — draw.io и ProjectLibre;
- Adobe **Photoshop** CC 2019; альтернативы — Photopea (веб), Krita, GIMP;
- **КриптоПро / ЭЦП / Контур / Госплагин**, если нативно не заработают (п. 0);
- **iVMS-4200, SADP** (Hikvision): доступ к камерам через веб-интерфейс регистратора или из ВМ;
- Office целиком — как запасной вариант.

Как устроена ВМ:
- Windows 11 в `virt-manager`, лицензия переносится с текущей установки (привязка к оборудованию) или ставится отдельная;
- **WinApps** через RDP показывает окна Office и Visio как обычные окна niri, и они запускаются из лаунчера;
- в ВМ пробрасываются USB-токены (Рутокен), папка `~/Documents` и принтеры;
- ВМ — это 60–80 ГБ диска и примерно 8 ГБ оперативной памяти, пока она запущена.

## 7. Порядок действий по дням

1. **День 0 (Windows).** Чек-лист п. 0 → резервная копия (п. 1) → подготовка (п. 2) → экспорт Wi-Fi и VPN-конфигов.
2. **День 1.** Установка Arch рядом с Windows (`docs/install-arch.md`) → `install.sh` → запись лица, спаривание телефона и мыши (мастер первого запуска).
3. **День 1–2.** `dotline-migrate`: данные (п. 3), сохранения (п. 4), Wi-Fi. Ставим приложения (п. 6), входим в аккаунты, ждём синхронизации.
4. **День 2–3.** ВМ Windows + WinApps. Проверка ЭЦП на тестовом документе. Принтеры.
5. **Неделя–месяц.** Живём в Linux; всё, чего не хватило, записываем в раздел «Недостаёт» внизу этого файла.
6. **Решение о Windows** — только когда чек-лист п. 8 весь отмечен. Тогда раздел Windows удаляется, место отходит Linux (btrfs расширяется на лету), ВМ остаётся для Visio, Project и ЭЦП.

## 8. Чек-лист «можно удалять Windows»

- [ ] Все репозитории из `dev` и WSL запушены и собираются в Linux
- [ ] SSH к серверам и GitHub работает
- [ ] Документы, фото, видео на месте, резервная копия на внешнем диске проверена
- [ ] Подпись ЭЦП (Госуслуги, Контур) работает — нативно или в ВМ
- [ ] Visio, Project, Photoshop, Office открываются в ВМ и сохраняют файлы в `~/Documents`
- [ ] Почта Thunderbird, заметки Joplin, пароли в браузерах на месте
- [ ] VPN (AmneziaWG, WireGuard, OpenVPN) подключаются
- [ ] Игры запускаются, сохранения видны
- [ ] Принтеры печатают
- [ ] Камеры Hikvision доступны (веб или ВМ)
- [ ] BitLocker-ключ больше не нужен (или сохранён на случай восстановления с внешней копии)

## Недостаёт

_Сюда записываем то, чего не хватило в Linux после переезда._
