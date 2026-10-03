import QtQuick
import Quickshell
import Quickshell.Io
import "../" as Dotline
import "../components" as Components

// dotline — first-run wizard (plan's "мастер первого запуска"). Opens
// itself once, the first time `qs -c dotline` ever starts (no
// ~/.local/state/dotline/firstrun marker yet — same FileView-presence
// pattern Theme.qml already uses for its oled flag), and can be reopened
// any time from Settings → "О системе".
//
// Every step reuses an action this rice already has — opening quick
// settings for Wi-Fi, faceauth-ui for the face step, the phone menu, the
// keys cheat sheet, dotline-theme/dotline-wallpaper/dotline-battery — this
// file adds no new backend, just a guided path through what's already
// there. Any step can be skipped; skipping never blocks finishing.
//
// Deliberately simplified against the plan in two places (both noted at
// their step below): "мышь (проверка хаптики)" — haptics aren't
// Linux-controllable from any known tool yet (see docs/mouse.md), so this
// step is just a Solaar launcher, not a haptics test. "Интерактивный тур
// по клавишам" — a real per-keypress detector would need wiring into
// niri's own bind dispatch, which doesn't exist; this step is a static
// hint list + the existing cheat sheet, not live detection.
Item {
    id: root

    property bool open: false
    property int step: 0
    readonly property int stepCount: 10

    function show(): void { root.step = 0; root.open = true }
    function hide(): void { root.open = false }
    function toggle(): void { if (root.open) hide(); else show() }
    function next(): void {
        if (root.step >= root.stepCount - 1) finish()
        else root.step += 1
    }
    function back(): void {
        if (root.step > 0) root.step -= 1
    }
    function finish(): void {
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && echo done > \"$1\"",
            "dotline-firstrun", root._stateHome + "/dotline/firstrun"])
        root.hide()
    }

    readonly property string _stateHome: {
        const v = Quickshell.env("XDG_STATE_HOME")
        return (v && v.length > 0) ? v : (Quickshell.env("HOME") + "/.local/state")
    }

    FileView {
        id: _marker
        path: root._stateHome + "/dotline/firstrun"
        onLoaded: {} // marker exists — this install has already been through the wizard
        onLoadFailed: (error) => Qt.callLater(() => root.show())
    }

    visible: open
    enabled: open

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Dotline.Theme.surface.r, Dotline.Theme.surface.g, Dotline.Theme.surface.b, 0.6)
        MouseArea { anchors.fill: parent; onClicked: {} } // modal on purpose — no click-through-to-dismiss
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 560
        height: 400
        radius: Dotline.Theme.radius * 1.6
        color: Dotline.Theme.surface

        MouseArea { anchors.fill: parent; onClicked: {} }

        // ---------- progress dots ----------
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 24
            spacing: 8
            Repeater {
                model: root.stepCount
                delegate: Rectangle {
                    required property int index
                    width: 8; height: 8; radius: 4
                    color: index === root.step ? Dotline.Theme.accent : Dotline.Theme.outline
                }
            }
        }

        Item {
            id: content
            anchors.top: parent.top
            anchors.bottom: buttons.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 32
            anchors.topMargin: 56

            // ---------- 0: приветствие ----------
            Column {
                visible: root.step === 0
                anchors.centerIn: parent
                spacing: 16
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "DOTLINE"
                    color: Dotline.Theme.ink
                    font.family: Dotline.Theme.fontDot
                    font.pixelSize: 34
                    font.weight: Font.ExtraBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Несколько шагов, чтобы всё настроить. Любой можно пропустить."
                    color: Dotline.Theme.muted
                    font.family: Dotline.Theme.fontUi
                    font.pixelSize: 14
                }
            }

            // ---------- 1: Wi-Fi ----------
            Column {
                visible: root.step === 1
                anchors.fill: parent
                spacing: 16
                Text { text: "Wi-Fi"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: "Список сетей и подключение — в быстрых настройках."
                    color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 14
                }
                Components.ActionButton {
                    label: "Открыть быстрые настройки"
                    onClicked: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "quicksettings", "toggle"])
                }
            }

            // ---------- 2: обои и тема ----------
            Column {
                visible: root.step === 2
                anchors.fill: parent
                spacing: 16
                Text { text: "Обои и тема"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold }
                Row {
                    spacing: 10
                    Repeater {
                        model: [["auto", "Авто"], ["dark", "Тёмная"], ["light", "Светлая"]]
                        delegate: Components.ActionButton {
                            required property var modelData
                            label: modelData[1]
                            onClicked: Quickshell.execDetached(["dotline-theme", modelData[0]])
                        }
                    }
                }
                Components.ActionButton {
                    label: "Следующие обои"
                    onClicked: Quickshell.execDetached(["dotline-wallpaper", "next"])
                }
            }

            // ---------- 3: лицо ----------
            Column {
                visible: root.step === 3
                anchors.fill: parent
                spacing: 16
                Text { text: "Вход по лицу"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: "Запись лица и настройка — в faceauth-ui (своя модель безопасности для root-хранилища, см. докстрoку Settings.qml)."
                    color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 14
                }
                Components.ActionButton {
                    label: "Открыть faceauth-ui"
                    onClicked: Quickshell.execDetached(["faceauth-ui"])
                }
            }

            // ---------- 4: телефон ----------
            Column {
                visible: root.step === 4
                anchors.fill: parent
                spacing: 16
                Text { text: "Телефон"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: "Спаривание через KDE Connect — в меню телефона (глиф в баре или Mod+K)."
                    color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 14
                }
                Components.ActionButton {
                    label: "Открыть меню телефона"
                    onClicked: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "phone", "toggle"])
                }
            }

            // ---------- 5: мышь ----------
            Column {
                visible: root.step === 5
                anchors.fill: parent
                spacing: 16
                Text { text: "Мышь (MX Master 4)"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: "Жесты и DPI — через Solaar. Хаптика на Linux пока нигде не настраивается (см. docs/mouse.md) — это не проверка, а просто ссылка на сам Solaar."
                    color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 14
                }
                Components.ActionButton {
                    label: "Открыть Solaar"
                    onClicked: Quickshell.execDetached(["solaar", "--window=show"])
                }
            }

            // ---------- 6: лимит заряда ----------
            Column {
                visible: root.step === 6
                anchors.fill: parent
                spacing: 16
                Text { text: "Лимит зарядки"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: "Продлевает срок службы батареи. Спросит пароль в kitty."
                    color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 14
                }
                Row {
                    spacing: 10
                    Repeater {
                        model: [60, 80, 100]
                        delegate: Components.ActionButton {
                            required property int modelData
                            label: modelData + "%"
                            onClicked: Quickshell.execDetached(["kitty", "sh", "-c",
                                "dotline-battery limit \"$1\"; echo; read -p 'Нажмите Enter для выхода…'",
                                "dotline-firstrun", String(modelData)])
                        }
                    }
                }
            }

            // ---------- 7: приложения по умолчанию ----------
            Column {
                visible: root.step === 7
                anchors.fill: parent
                spacing: 16
                Text { text: "Приложения по умолчанию"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold }
                Text {
                    text: "Браузер"; color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 13
                }
                Row {
                    spacing: 10
                    Components.ActionButton {
                        label: "Firefox"
                        onClicked: Quickshell.execDetached(["xdg-settings", "set", "default-web-browser", "firefox.desktop"])
                    }
                    Components.ActionButton {
                        label: "Brave"
                        onClicked: Quickshell.execDetached(["xdg-settings", "set", "default-web-browser", "brave-browser.desktop"])
                    }
                }
                Text {
                    text: "Почта"; color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 13
                }
                Components.ActionButton {
                    label: "Thunderbird"
                    onClicked: Quickshell.execDetached(["xdg-mime", "default", "thunderbird.desktop", "x-scheme-handler/mailto"])
                }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: "Файлы/терминал/редактор не предлагаются здесь: в этом рисе это yazi/kitty/neovim — уже открываются по Mod+E/Mod+Enter напрямую, а не через xdg-mime."
                    color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 12
                }
            }

            // ---------- 8: тур по клавишам ----------
            Column {
                visible: root.step === 8
                anchors.fill: parent
                spacing: 12
                Text { text: "Главные клавиши"; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontUi; font.pixelSize: 20; font.weight: Font.DemiBold }
                Repeater {
                    model: [
                        ["Mod+Enter", "Терминал"],
                        ["Mod+Space", "Поиск и запуск"],
                        ["Mod+A", "Быстрые настройки"],
                        ["Mod+L", "Блокировка"],
                        ["Mod+Comma", "Настройки"],
                        ["Mod+Shift+/", "Полная шпаргалка"],
                    ]
                    delegate: Row {
                        required property var modelData
                        spacing: 12
                        Text { width: 140; text: modelData[0]; color: Dotline.Theme.ink; font.family: Dotline.Theme.fontMono; font.pixelSize: 14 }
                        Text { text: modelData[1]; color: Dotline.Theme.muted; font.family: Dotline.Theme.fontUi; font.pixelSize: 14 }
                    }
                }
                Components.ActionButton {
                    label: "Открыть полную шпаргалку"
                    onClicked: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "keys", "toggle"])
                }
            }

            // ---------- 9: готово ----------
            Column {
                visible: root.step === 9
                anchors.centerIn: parent
                spacing: 12
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "ГОТОВО"
                    color: Dotline.Theme.accent
                    font.family: Dotline.Theme.fontDot
                    font.pixelSize: 28
                    font.weight: Font.ExtraBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Этот мастер снова доступен в Настройки → О системе."
                    color: Dotline.Theme.muted
                    font.family: Dotline.Theme.fontUi
                    font.pixelSize: 14
                }
            }
        }

        // ---------- nav ----------
        Row {
            id: buttons
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 24
            spacing: 10

            Components.ActionButton {
                label: "Назад"
                enabled: root.step > 0
                onClicked: root.back()
            }
            Components.ActionButton {
                label: "Пропустить"
                visible: root.step < root.stepCount - 1
                onClicked: root.next()
            }
            Components.ActionButton {
                label: root.step === root.stepCount - 1 ? "Готово" : "Далее"
                onClicked: root.step === root.stepCount - 1 ? root.finish() : root.next()
            }
        }
    }
}
