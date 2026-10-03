import QtQuick
import Quickshell
import Quickshell.Io
import "../" as Dotline
import "../components" as Components
import "../services" as Services

// dotline — the settings window (Mod+Comma). First, deliberately
// modest version: a few sections that are genuinely wired up, not a
// placeholder shell for pages that don't exist yet. "Лицо" launches
// faceauth-ui rather than reimplementing face capture here — that project
// already has its own root-store security model (pkexec-mediated writes,
// see faceauth's own README); duplicating it in Quickshell would just be
// a second, less-reviewed path to the same root-only model store.
Item {
    id: root

    property bool open: false
    function show(): void { open = true }
    function hide(): void { open = false }
    function toggle(): void { open = !open }

    property int section: 0
    readonly property var sections: ["Оформление", "Лицо", "Приложения", "Телефон", "Ноутбук", "Экраны", "Уведомления", "Режимы", "Сеть и Bluetooth", "Система", "О системе"]

    // ---------- Приложения: search (pacman+AUR+Flathub) + curated sets ----------
    // Same scripts/app backend as the launcher's /app mode (see
    // launcher/Launcher.qml) — one search/install implementation, two
    // front ends.
    property string appQuery: ""
    property var appResults: []
    onAppQueryChanged: {
        if (!appQuery) { appResults = []; return }
        appDebounce.restart()
    }
    Timer {
        id: appDebounce
        interval: 250
        onTriggered: {
            if (appSearchProc.running) appSearchProc.running = false
            appSearchProc.command = [Quickshell.env("DOTLINE_ROOT") + "/scripts/app", "search", root.appQuery]
            appSearchProc.running = true
        }
    }
    Process {
        id: appSearchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.appResults = JSON.parse(text) } catch (e) { root.appResults = [] }
            }
        }
    }
    function appInstall(source, id) {
        // Same positional-parameter trick as the launcher: source/id can
        // come from an AUR search result (attacker-influenced package
        // names), so they're never interpolated into the shell string.
        Quickshell.execDetached(["kitty", "sh", "-c",
            Quickshell.env("DOTLINE_ROOT") + "/scripts/app install \"$1\" \"$2\"; echo; read -p 'Нажмите Enter для выхода…'",
            "dotline-app", source, id])
    }
    // Curated sets (plan's "Наборы"): fixed package lists I wrote myself,
    // not user input, so a plain joined string for `paru -S` is safe here
    // — unlike appInstall() above. Steam/MangoHud aren't repeated here:
    // packages/gaming.txt already installs them by default for every
    // install (see install.sh — gaming stopped being eGPU-gated earlier
    // in this project), so "Игры" only adds what isn't already on by
    // default. onlyoffice-bin/telegram-desktop/vlc are already in
    // packages/apps.txt, installed by default unless `--skip-apps` —
    // repeated here anyway since `paru -S --needed` is a no-op for
    // anything already installed, and someone who did pass `--skip-apps`
    // may still want just this one set.
    readonly property var appBundles: [
        { label: "Разработка", pkgs: ["git", "github-cli", "visual-studio-code-bin"] },
        { label: "Игры", pkgs: ["heroic-games-launcher-bin", "lutris"] },
        { label: "Офис", pkgs: ["onlyoffice-bin", "libreoffice-fresh"] },
        { label: "Мессенджеры", pkgs: ["telegram-desktop", "vesktop-bin"] },
        { label: "Медиа", pkgs: ["vlc", "obs-studio", "gimp"] },
    ]
    function installBundle(pkgs) {
        Quickshell.execDetached(["kitty", "sh", "-c",
            "paru -S --needed " + pkgs.join(" ") + "; echo; read -p 'Нажмите Enter для выхода…'"])
    }

    // ---------- Веб-приложения (scripts/webapp) ----------
    property string webappName: ""
    property string webappUrl: ""
    property var webappList: []
    function refreshWebapps() {
        webappListProc.running = true
    }
    Process {
        id: webappListProc
        command: [Quickshell.env("DOTLINE_ROOT") + "/scripts/webapp", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.webappList = JSON.parse(text) } catch (e) { root.webappList = [] }
            }
        }
    }
    function addWebapp() {
        if (!root.webappName || !root.webappUrl) return
        // Plain argv array (Quickshell.execDetached), not a shell string —
        // no injection surface here regardless of what's typed, same
        // reasoning as every other execDetached call in this file.
        Quickshell.execDetached([Quickshell.env("DOTLINE_ROOT") + "/scripts/webapp", "add", root.webappName, root.webappUrl])
        root.webappName = ""
        root.webappUrl = ""
        webappRefreshDelay.restart()
    }
    function removeWebapp(slug) {
        Quickshell.execDetached([Quickshell.env("DOTLINE_ROOT") + "/scripts/webapp", "remove", slug])
        webappRefreshDelay.restart()
    }
    // scripts/webapp writes the .desktop file synchronously but
    // execDetached doesn't wait for it — a short delay before re-reading
    // the list is simpler than wiring up a completion signal for what's
    // a rarely-used, non-urgent refresh.
    Timer { id: webappRefreshDelay; interval: 400; onTriggered: root.refreshWebapps() }

    visible: open
    enabled: open

    // ---------- "about" data: one-shot queries, not polled ----------
    property string osInfo: ""
    property string kernelInfo: ""
    property string niriInfo: ""
    function refreshAbout() {
        osProc.running = true
        kernelProc.running = true
        niriProc.running = true
    }
    Process {
        id: osProc
        command: ["sh", "-c", ". /etc/os-release 2>/dev/null; echo \"$PRETTY_NAME\""]
        stdout: StdioCollector { onStreamFinished: root.osInfo = text.trim() }
    }
    Process {
        id: kernelProc
        command: ["uname", "-r"]
        stdout: StdioCollector { onStreamFinished: root.kernelInfo = text.trim() }
    }
    Process {
        id: niriProc
        command: ["niri", "--version"]
        stdout: StdioCollector { onStreamFinished: root.niriInfo = text.trim() }
    }
    onOpenChanged: if (open) { refreshAbout(); refreshWebapps(); refreshBattery(); Services.Displays.refresh() }

    // ---------- Ноутбук: профиль питания + батарея ----------
    // Profile cycling/reading already exists (services/PowerProfile.qml,
    // used by the bar glyph) — this page just adds direct set() buttons
    // instead of only cycle(). Battery status reuses scripts/battery
    // status verbatim (plain text, same as a terminal would show) rather
    // than re-parsing sysfs a second time in QML.
    property string batteryStatusText: ""
    function refreshBattery() { batteryProc.running = true }
    Process {
        id: batteryProc
        command: ["dotline-battery", "status"]
        stdout: StdioCollector { onStreamFinished: root.batteryStatusText = text.trim() }
    }
    function setChargeLimit(value) {
        Quickshell.execDetached(["kitty", "sh", "-c",
            "dotline-battery limit \"$1\"; echo; read -p 'Нажмите Enter для выхода…'",
            "dotline-settings", String(value)])
    }
    function chargeFullOnce() {
        Quickshell.execDetached(["kitty", "sh", "-c",
            "dotline-battery full-once; echo; read -p 'Нажмите Enter для выхода…'"])
    }

    // ---------- Система: обновления, предпросмотр, диагностика ----------
    // ANSI colour codes from dotline-doctor's own ✔/⚠/✘ output (meant for
    // a real terminal) would show as literal escape garbage in a plain
    // QML Text — stripped here, the symbols and text themselves still
    // carry the meaning without colour.
    readonly property var ansiRe: /\x1b\[[0-9;]*m/g
    property string doctorOutput: ""
    function runDoctor() {
        doctorProc.running = true
    }
    Process {
        id: doctorProc
        command: ["dotline-doctor"]
        stdout: StdioCollector { onStreamFinished: root.doctorOutput = text.replace(root.ansiRe, "") }
    }
    function collectDebug() {
        Quickshell.execDetached(["kitty", "sh", "-c", "dotline-debug; echo; read -p 'Нажмите Enter для выхода…'"])
    }
    function previewUpdate() {
        Quickshell.execDetached(["kitty", "sh", "-c",
            Quickshell.env("DOTLINE_ROOT") + "/update.sh --dry-run; echo; read -p 'Нажмите Enter для выхода…'"])
    }
    function previewUninstall() {
        Quickshell.execDetached(["kitty", "sh", "-c",
            Quickshell.env("DOTLINE_ROOT") + "/uninstall.sh --dry-run; echo; read -p 'Нажмите Enter для выхода…'"])
    }
    function showSnapshots() {
        // Same `snapper -c root list` already used by lib/common.sh's own
        // snapshot() — rollback itself stays a manual terminal step (the
        // plan's own wording: "откат через инструкцию"), restoring a
        // snapshot is destructive and not something a settings button
        // should do silently.
        Quickshell.execDetached(["kitty", "sh", "-c", "sudo snapper -c root list; echo; read -p 'Нажмите Enter для выхода…'"])
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Dotline.Theme.surface.r, Dotline.Theme.surface.g, Dotline.Theme.surface.b, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.hide() }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        // Grown a few times as pages were added — some (Система,
        // Уведомления) need noticeably more room than Оформление/Лицо
        // ever did. "Уведомления"'s per-app list isn't scrollable (no
        // Flickable anywhere in this file yet) — fine for a handful of
        // apps, would clip past the card's edge with many; a real fix
        // needs a proper scroll view, not just a taller fixed number.
        width: 760
        height: 740
        radius: Dotline.Theme.radius * 1.6
        color: Dotline.Theme.surface

        MouseArea { anchors.fill: parent; onClicked: {} }

        Row {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 24

            // ---------- nav ----------
            Column {
                width: 180
                spacing: 6
                Repeater {
                    model: root.sections
                    delegate: Rectangle {
                        id: navItem
                        required property string modelData
                        required property int index
                        width: 180
                        height: 40
                        radius: 14
                        color: root.section === index ? Dotline.Theme.surfaceHigh : "transparent"
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: navItem.modelData
                            color: root.section === index ? Dotline.Theme.ink : Dotline.Theme.muted
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 14
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.section = navItem.index }
                    }
                }
            }

            Rectangle { width: 1; height: parent.height; color: Dotline.Theme.outline }

            // ---------- page ----------
            Item {
                width: parent.width - 180 - 24 - 1
                height: parent.height

                // Оформление
                Column {
                    visible: root.section === 0
                    anchors.fill: parent
                    spacing: 18

                    Text {
                        text: "Оформление"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "Тема"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: [["auto", "Авто"], ["dark", "Тёмная"], ["light", "Светлая"]]
                            delegate: Rectangle {
                                required property var modelData
                                width: 100; height: 40; radius: 20
                                // Not highlighting the active mode: that
                                // choice (auto/dark/light) lives in
                                // ~/.local/state/dotline/theme, which
                                // nothing here reads yet — showing a
                                // highlight that's sometimes just wrong
                                // would be worse than showing none.
                                color: Dotline.Theme.surfaceHigh
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData[1]
                                    color: Dotline.Theme.ink
                                    font.family: Dotline.Theme.fontUi
                                    font.pixelSize: 14
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Quickshell.execDetached(["dotline-theme", parent.modelData[0]])
                                }
                            }
                        }
                    }
                    Text {
                        text: "Обои"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Rectangle {
                        width: 160; height: 40; radius: 20
                        color: Dotline.Theme.surfaceHigh
                        Text { anchors.centerIn: parent; text: "Следующие"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["dotline-wallpaper", "next"]) }
                    }
                }

                // Лицо
                Column {
                    visible: root.section === 1
                    anchors.fill: parent
                    spacing: 16

                    Text {
                        text: "Лицо"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Запись лица, включение/отключение и история попыток — в отдельном "
                            + "приложении faceauth-ui (у него своя модель безопасности для "
                            + "root-хранилища моделей — pkexec, не повторяем её здесь)."
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 14
                    }
                    Rectangle {
                        width: 200; height: 44; radius: 22
                        color: Dotline.Theme.ink
                        Text { anchors.centerIn: parent; text: "Открыть faceauth-ui"; color: Dotline.Theme.surface; font.family: Dotline.Theme.fontUi; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["faceauth-ui"]) }
                    }
                }

                // Приложения
                Column {
                    visible: root.section === 2
                    anchors.fill: parent
                    spacing: 14

                    Text {
                        text: "Приложения"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Наборы"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: root.appBundles
                            delegate: Components.ActionButton {
                                required property var modelData
                                label: modelData.label
                                onClicked: root.installBundle(modelData.pkgs)
                            }
                        }
                    }

                    Text {
                        text: "Поиск (pacman, AUR, Flathub)"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 20
                        color: Dotline.Theme.surfaceHigh
                        TextInput {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            verticalAlignment: TextInput.AlignVCenter
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 14
                            clip: true
                            onTextChanged: root.appQuery = text
                        }
                    }

                    Column {
                        width: parent.width
                        height: 160
                        spacing: 4
                        clip: true

                        Repeater {
                            model: root.appResults
                            delegate: Row {
                                required property var modelData
                                width: parent.width
                                height: 32
                                spacing: 10
                                Text {
                                    width: parent.width - 96
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: "[" + modelData.source.charAt(0).toUpperCase() + "] " + modelData.name
                                        + (modelData.description ? " — " + modelData.description : "")
                                    color: Dotline.Theme.ink
                                    font.family: Dotline.Theme.fontUi
                                    font.pixelSize: 13
                                }
                                Components.ActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "Установить"
                                    onClicked: root.appInstall(modelData.source, modelData.id)
                                }
                            }
                        }
                        Text {
                            visible: root.appQuery.length > 0 && root.appResults.length === 0
                            text: "Ничего не нашлось"
                            color: Dotline.Theme.muted
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                        }
                    }

                    Text {
                        text: "Веб-приложения"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Row {
                        width: parent.width
                        spacing: 8
                        Rectangle {
                            width: 160; height: 36; radius: 18
                            color: Dotline.Theme.surfaceHigh
                            TextInput {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                color: Dotline.Theme.ink
                                font.family: Dotline.Theme.fontUi
                                font.pixelSize: 13
                                clip: true
                                text: root.webappName
                                onTextChanged: root.webappName = text
                                Text { visible: parent.text.length === 0; text: "Имя"; color: Dotline.Theme.muted; font: parent.font }
                            }
                        }
                        Rectangle {
                            width: 260; height: 36; radius: 18
                            color: Dotline.Theme.surfaceHigh
                            TextInput {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                color: Dotline.Theme.ink
                                font.family: Dotline.Theme.fontUi
                                font.pixelSize: 13
                                clip: true
                                text: root.webappUrl
                                onTextChanged: root.webappUrl = text
                                Text { visible: parent.text.length === 0; text: "https://…"; color: Dotline.Theme.muted; font: parent.font }
                            }
                        }
                        Components.ActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Добавить"
                            enabled: root.webappName.length > 0 && root.webappUrl.length > 0
                            onClicked: root.addWebapp()
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: root.webappList
                            delegate: Row {
                                required property var modelData
                                width: parent.width
                                height: 32
                                spacing: 10
                                Text {
                                    width: parent.width - 96
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: modelData.name
                                    color: Dotline.Theme.ink
                                    font.family: Dotline.Theme.fontUi
                                    font.pixelSize: 13
                                }
                                Components.ActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "Удалить"
                                    onClicked: root.removeWebapp(modelData.slug)
                                }
                            }
                        }
                        Text {
                            visible: root.webappList.length === 0
                            text: "Веб-приложений нет"
                            color: Dotline.Theme.muted
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                        }
                    }
                }

                // Телефон — status summary + phone_away_lock + link to the
                // full device menu (pairing/ring/ping/files already live
                // there, phone/PhoneMenu.qml — not duplicated here).
                Column {
                    visible: root.section === 3
                    anchors.fill: parent
                    spacing: 16

                    Text {
                        text: "Телефон"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: Services.Phone.connected
                            ? (Services.Phone.primaryDevice.name + (Services.Phone.primaryDevice.battery ? ("  ·  " + Services.Phone.primaryDevice.battery.charge + "%") : ""))
                            : (Services.Phone.deviceList.length > 0 ? "Спарен, но недоступен" : "Телефон не найден")
                        color: Services.Phone.connected ? Dotline.Theme.ink : Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 15
                    }
                    Components.ActionButton {
                        label: "Открыть меню телефона"
                        onClicked: {
                            root.hide()
                            Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "phone", "toggle"])
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: Dotline.Theme.outline }
                    Row {
                        width: parent.width
                        Text {
                            text: "БЛОКИРОВКА ПРИ УХОДЕ ТЕЛЕФОНА"
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            width: parent.width - 60
                            wrapMode: Text.WordWrap
                        }
                        Rectangle {
                            width: 46; height: 26; radius: 13
                            anchors.verticalCenter: parent.verticalCenter
                            color: Services.PhoneLock.enabled ? Dotline.Theme.accent : Dotline.Theme.surfaceHigh
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: Dotline.Theme.ink
                                y: 3
                                x: Services.PhoneLock.enabled ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: Services.PhoneLock.enabled = !Services.PhoneLock.enabled }
                        }
                    }
                }

                // Ноутбук — профиль питания + лимит зарядки + статус
                // батареи. Датчики/кривая вентилятора/подсветка
                // клавиатуры/Fn-lock/автоматические правила по событию
                // зарядки — не делал, см. docs/laptop-settings.md: ни у
                // одного из них ещё нет бэкенда (scripts/power не отдаёт
                // sensors, подсветка и Fn-lock нигде в рисе не читаются).
                Column {
                    visible: root.section === 4
                    anchors.fill: parent
                    spacing: 16

                    Text {
                        text: "Ноутбук"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "Профиль питания"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: [["power-saver", "Тихий"], ["balanced", "Баланс"], ["performance", "Производительность"]]
                            delegate: Components.ActionButton {
                                required property var modelData
                                label: modelData[1]
                                enabled: Services.PowerProfile.profile !== modelData[0]
                                onClicked: Services.PowerProfile.set(modelData[0])
                            }
                        }
                    }
                    Text {
                        text: "Лимит зарядки (спросит пароль в kitty)"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: [60, 80, 100]
                            delegate: Components.ActionButton {
                                required property int modelData
                                label: modelData + "%"
                                onClicked: root.setChargeLimit(modelData)
                            }
                        }
                        Components.ActionButton {
                            label: "Зарядить один раз до 100%"
                            onClicked: root.chargeFullOnce()
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: 10
                        Text {
                            width: parent.width - 100
                            text: root.batteryStatusText || "…"
                            wrapMode: Text.Wrap
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontMono
                            font.pixelSize: 12
                        }
                        Components.ActionButton { label: "Обновить"; onClicked: root.refreshBattery() }
                    }
                }

                // Экраны — список мониторов из `niri msg --json outputs`
                // (services/Displays.qml), только то, что подтверждено по
                // документации niri_ipc: имя/модель/разрешение/частоту/
                // масштаб и вкл/выкл (OutputAction::On/Off). Никакой схемы
                // с перетаскиванием и никакой смены разрешения/масштаба из
                // UI — синтаксис этих действий (Mode/Scale/Transform) не
                // подтверждён с той же уверенностью, а менять сигнал
                // монитора по неподтверждённой команде не стоит риска.
                Column {
                    visible: root.section === 5
                    anchors.fill: parent
                    spacing: 14

                    Row {
                        width: parent.width
                        Text {
                            text: "Экраны"
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: Services.Displays.outputs
                            delegate: Row {
                                required property var modelData
                                width: parent.width
                                height: 40
                                spacing: 10
                                Rectangle {
                                    width: 9; height: 9; radius: 4.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: modelData.enabled ? Dotline.Theme.accent : Dotline.Theme.muted
                                }
                                Text {
                                    width: parent.width - 9 - 90 - 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: modelData.label + (modelData.resolution ? ("  ·  " + modelData.resolution + (modelData.refresh ? (" @ " + modelData.refresh) : "") + (modelData.scale ? ("  ·  ×" + modelData.scale) : "")) : "  ·  выключен")
                                    color: Dotline.Theme.ink
                                    font.family: Dotline.Theme.fontUi
                                    font.pixelSize: 14
                                }
                                Components.ActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: modelData.enabled ? "Выключить" : "Включить"
                                    onClicked: Services.Displays.setEnabled(modelData.name, !modelData.enabled)
                                }
                            }
                        }
                        Text {
                            visible: Services.Displays.outputs.length === 0
                            text: "Мониторы не найдены (ещё не прочитаны или niri недоступен)"
                            color: Dotline.Theme.muted
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                        }
                    }
                    Components.ActionButton {
                        label: "Обновить"
                        onClicked: Services.Displays.refresh()
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Масштаб, поворот и позиция мониторов пока меняются только через сам niri (config.kdl) — точный синтаксис CLI-команд для этого не подтверждён настолько же надёжно, чтобы предлагать кнопку."
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 12
                    }
                }

                // Уведомления — DND (временный, глобальный, уже есть
                // глиф в баре/тумблер в быстрых настройках — дублируем
                // здесь, тот же паттерн, что у «Блокировки при уходе
                // телефона» на странице «Телефон») + правила по
                // приложениям (постоянные, per-app — services/
                // NotificationRules.qml, новый сервис) + отдельный
                // тумблер для уведомлений с телефона (частный случай
                // правила по appName == "KDE Connect").
                Column {
                    visible: root.section === 6
                    anchors.fill: parent
                    spacing: 16

                    Text {
                        text: "Уведомления"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Row {
                        width: parent.width
                        Text {
                            text: "НЕ БЕСПОКОИТЬ"
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            width: parent.width - 60
                        }
                        Rectangle {
                            width: 46; height: 26; radius: 13
                            anchors.verticalCenter: parent.verticalCenter
                            color: Services.DoNotDisturb.enabled ? Dotline.Theme.accent : Dotline.Theme.surfaceHigh
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: Dotline.Theme.ink
                                y: 3
                                x: Services.DoNotDisturb.enabled ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: Services.DoNotDisturb.toggle() }
                        }
                    }
                    Row {
                        width: parent.width
                        Text {
                            text: "УВЕДОМЛЕНИЯ С ТЕЛЕФОНА"
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            width: parent.width - 60
                        }
                        Rectangle {
                            width: 46; height: 26; radius: 13
                            anchors.verticalCenter: parent.verticalCenter
                            color: !Services.NotificationRules.hidePhoneNotifications ? Dotline.Theme.accent : Dotline.Theme.surfaceHigh
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: Dotline.Theme.ink
                                y: 3
                                x: !Services.NotificationRules.hidePhoneNotifications ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                            // Switch shows "on" = notifications shown, so
                            // the toggle reads naturally even though the
                            // backing flag is named the opposite way.
                            MouseArea {
                                anchors.fill: parent
                                onClicked: Services.NotificationRules.setHidePhoneNotifications(!Services.NotificationRules.hidePhoneNotifications)
                            }
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: Dotline.Theme.outline }
                    Text {
                        text: "Правила по приложениям"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Column {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: Services.NotificationRules.knownApps
                            delegate: Row {
                                required property string modelData
                                width: parent.width
                                height: 32
                                Text {
                                    width: parent.width - 60
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData
                                    color: Dotline.Theme.ink
                                    font.family: Dotline.Theme.fontUi
                                    font.pixelSize: 13
                                }
                                Rectangle {
                                    width: 46; height: 26; radius: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    readonly property bool shown: !Services.NotificationRules.blockedApps.includes(modelData)
                                    color: shown ? Dotline.Theme.accent : Dotline.Theme.surfaceHigh
                                    Rectangle {
                                        width: 20; height: 20; radius: 10
                                        color: Dotline.Theme.ink
                                        y: 3
                                        x: parent.shown ? parent.width - width - 3 : 3
                                        Behavior on x { NumberAnimation { duration: 150 } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: Services.NotificationRules.setBlocked(modelData, parent.shown)
                                    }
                                }
                            }
                        }
                        Text {
                            visible: Services.NotificationRules.knownApps.length === 0
                            text: "Пока ни одно приложение не присылало уведомлений"
                            color: Dotline.Theme.muted
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                        }
                    }
                }

                // Режимы — прямые кнопки поверх уже полностью готового
                // services/Modes.qml (снимок-и-применение DND/Caffeine/
                // PowerProfile; план хотел больше рычагов — скрытие
                // бара, выключение анимаций niri и т.д. — но ни у одного
                // из них нет своей базовой реализации в рисе, см. сам
                // Modes.qml и docs/modes.md). Никакого нового кода
                // здесь — чистое UI поверх того, что уже умеет сервис.
                Column {
                    visible: root.section === 7
                    anchors.fill: parent
                    spacing: 16

                    Text {
                        text: "Режимы"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Column {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: [
                                ["normal", "Обычный"],
                                ["game", "Игра"],
                                ["focus", "Фокус"],
                                ["presentation", "Презентация"],
                            ]
                            delegate: Row {
                                required property var modelData
                                width: parent.width
                                height: 40
                                spacing: 10
                                Rectangle {
                                    width: 9; height: 9; radius: 4.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Services.Modes.current === modelData[0] ? Dotline.Theme.accent : Dotline.Theme.muted
                                }
                                Text {
                                    width: parent.width - 9 - 140 - 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData[1]
                                    color: Dotline.Theme.ink
                                    font.family: Dotline.Theme.fontUi
                                    font.pixelSize: 15
                                }
                                Components.ActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: Services.Modes.current === modelData[0] ? "Активен" : "Включить"
                                    enabled: Services.Modes.current !== modelData[0]
                                    onClicked: Services.Modes.set(modelData[0])
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Каждый режим — это снимок и применение DND/кофеина/профиля питания; выход возвращает то, что было перед включением, не фиксированные значения по умолчанию. Остальные рычаги из плана (скрытие бара, анимации niri, авто-detect gamemode) честно ждут своих подсистем — см. docs/modes.md."
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 12
                    }
                }

                // Сеть и Bluetooth — только то, confirmed safe to expose:
                // Wi-Fi radio toggle + known-network count (already-used
                // Quickshell.Networking properties, services/
                // NetworkService.qml), Bluetooth adapter name (read-only
                // on BluetoothAdapter — can't rename from this API) +
                // discoverable toggle (confirmed read-write property) +
                // power toggle (already existed). Saved-network
                // priorities/MAC-рандомизация/AmneziaWG — not here, see
                // the note at the bottom of this page for why.
                Column {
                    visible: root.section === 8
                    anchors.fill: parent
                    spacing: 16

                    Text {
                        text: "Сеть и Bluetooth"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "Wi-Fi"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Row {
                        width: parent.width
                        Text {
                            width: parent.width - 60
                            text: Services.NetworkService.wifiEnabled
                                ? ("Включён" + (Services.NetworkService.activeName ? ("  ·  " + Services.NetworkService.activeName) : "")
                                    + "  ·  известных сетей: " + Services.NetworkService.networks.filter(n => n.known).length)
                                : "Выключен"
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 14
                        }
                        Rectangle {
                            width: 46; height: 26; radius: 13
                            anchors.verticalCenter: parent.verticalCenter
                            color: Services.NetworkService.wifiEnabled ? Dotline.Theme.accent : Dotline.Theme.surfaceHigh
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: Dotline.Theme.ink
                                y: 3
                                x: Services.NetworkService.wifiEnabled ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: Services.NetworkService.toggleWifi() }
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: Dotline.Theme.outline }
                    Text {
                        text: "Bluetooth"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                    Row {
                        width: parent.width
                        Text {
                            width: parent.width - 60
                            text: Services.BtService.available
                                ? (Services.BtService.adapterName + "  ·  " + (Services.BtService.powered ? "включён" : "выключен"))
                                : "Адаптер не найден"
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 14
                        }
                        Rectangle {
                            width: 46; height: 26; radius: 13
                            anchors.verticalCenter: parent.verticalCenter
                            color: Services.BtService.powered ? Dotline.Theme.accent : Dotline.Theme.surfaceHigh
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: Dotline.Theme.ink
                                y: 3
                                x: Services.BtService.powered ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: Services.BtService.togglePower() }
                        }
                    }
                    Row {
                        width: parent.width
                        Text {
                            text: "ВИДИМОСТЬ (DISCOVERABLE)"
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            width: parent.width - 60
                        }
                        Rectangle {
                            width: 46; height: 26; radius: 13
                            anchors.verticalCenter: parent.verticalCenter
                            color: Services.BtService.discoverable ? Dotline.Theme.accent : Dotline.Theme.surfaceHigh
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: Dotline.Theme.ink
                                y: 3
                                x: Services.BtService.discoverable ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: Services.BtService.toggleDiscoverable() }
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Сохранённые сети по приоритету, MAC-рандомизация и импорт AmneziaWG не делал: первые два потребовали бы читать и писать сырую карту настроек NetworkManager (NMSettings.read()/write() в Quickshell.Networking) без подтверждённого формата её ключей — трогать настоящий сетевой профиль по неподтверждённой команде не тот риск, который стоит того. AmneziaWG — отдельный helper со своей polkit-политикой, не начат."
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 12
                    }
                }

                // Система — обновления (переиспользует уже опрашиваемый
                // services/Updates.qml, второй процесс не нужен),
                // предпросмотр update.sh/uninstall.sh --dry-run, снапшоты
                // snapper (только список — откат, как и просил план,
                // остаётся ручным шагом в терминале, не кнопкой), doctor,
                // debug.
                Column {
                    visible: root.section === 9
                    anchors.fill: parent
                    spacing: 14

                    Text {
                        text: "Система"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Row {
                        width: parent.width
                        spacing: 10
                        Text {
                            text: Services.Updates.total > 0
                                ? ("Обновлений: " + Services.Updates.total + " (pacman " + Services.Updates.pacman
                                    + ", AUR " + Services.Updates.aur + ", flatpak " + Services.Updates.flatpak
                                    + ", прошивки " + Services.Updates.firmware + ")")
                                : "Обновлений нет"
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                        }
                        Components.ActionButton {
                            label: "Обновить всё"
                            enabled: Services.Updates.total > 0
                            onClicked: Services.Updates.updateAll()
                        }
                    }
                    Row {
                        spacing: 10
                        Components.ActionButton { label: "Предпросмотр update.sh"; onClicked: root.previewUpdate() }
                        Components.ActionButton { label: "Предпросмотр uninstall.sh"; onClicked: root.previewUninstall() }
                        Components.ActionButton { label: "Снапшоты (snapper)"; onClicked: root.showSnapshots() }
                    }
                    Row {
                        spacing: 10
                        Components.ActionButton { label: "Проверить (doctor)"; onClicked: root.runDoctor() }
                        Components.ActionButton { label: "Собрать debug-архив"; onClicked: root.collectDebug() }
                    }
                    Text {
                        width: parent.width
                        height: 140
                        clip: true
                        text: root.doctorOutput
                        wrapMode: Text.Wrap
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontMono
                        font.pixelSize: 11
                    }
                }

                // О системе
                Column {
                    visible: root.section === 10
                    anchors.fill: parent
                    spacing: 12

                    Text {
                        text: "О системе"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: [
                            ["ОС", root.osInfo],
                            ["Ядро", root.kernelInfo],
                            ["niri", root.niriInfo],
                        ]
                        delegate: Row {
                            required property var modelData
                            spacing: 10
                            Text { width: 70; text: parent.modelData[0]; color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 14 }
                            Text { text: parent.modelData[1] || "…"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontMono; font.pixelSize: 14 }
                        }
                    }
                    Components.ActionButton {
                        label: "Мастер первого запуска"
                        onClicked: {
                            root.hide()
                            Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "firstrun", "open"])
                        }
                    }
                }
            }
        }
    }
}
