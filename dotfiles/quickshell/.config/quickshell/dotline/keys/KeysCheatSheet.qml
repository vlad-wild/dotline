import QtQuick
import "../" as Dotline
import "../components" as Components

// dotline — the keybindings cheat sheet (Mod+Slash). Hardcoded from
// what's actually bound in dotfiles/niri/config.kdl at the time this was
// written, grouped by category — not generated from a shared source of
// truth yet (that's the plan's "gen-binds from binds.toml" idea, a later,
// separate piece of work). Keeping this and config.kdl in sync by hand is
// the accepted cost of shipping the cheat sheet now rather than waiting
// for that generator.
Item {
    id: root

    property bool open: false
    function show(): void { open = true }
    function hide(): void { open = false }
    function toggle(): void { open = !open }

    visible: open
    enabled: open

    readonly property var groups: [
        {
            title: "Окна и столы",
            items: [
                ["Mod+Return", "Терминал"],
                ["Mod+D", "Лаунчер"],
                ["Mod+V", "История буфера обмена"],
                ["Mod+Q", "Закрыть окно"],
                ["Mod+←/→ или H/L", "Фокус на колонку"],
                ["Mod+Shift+←/→", "Передвинуть колонку"],
                ["Mod+↑/↓", "Рабочий стол вверх/вниз"],
                ["Mod+Shift+↑/↓", "Передвинуть на стол"],
                ["Mod+1…5", "На стол 1…5"],
                ["Mod+Shift+1…5", "Передвинуть на стол 1…5"],
                ["Mod+R", "Другая ширина колонки"],
                ["Mod+Shift+R", "Другая высота окна"],
                ["Mod+F", "На весь стол"],
                ["Mod+Shift+F", "Полный экран"],
                ["Mod+C", "Отцентрировать колонку"],
                ["Mod+O", "Обзор"],
                ["Mod+Tab", "Предыдущее окно"],
            ]
        },
        {
            title: "Система",
            items: [
                ["Mod+N", "Быстрые настройки"],
                ["Mod+K", "Телефон (KDE Connect)"],
                ["Mod+Ctrl+C", "Не засыпать (кофеин)"],
                ["Mod+Shift+M", "Заглушить приложение активного окна"],
                ["Mod+Shift+N", "Не беспокоить вкл/выкл"],
                ["Mod+Ctrl+M", "Следующий режим работы"],
                ["Mod+Shift+L", "Заблокировать"],
                ["Mod+Ctrl+P", "Профиль питания"],
                ["Mod+Shift+W", "Следующие обои"],
                ["Mod+Ctrl+Shift+T", "Тема: авто"],
                ["Mod+Slash", "Эта шпаргалка"],
                ["Mod+Comma", "Настройки"],
                ["Mod+Shift+E", "Выйти из niri"],
            ]
        },
        {
            title: "Снимки экрана и громкость",
            items: [
                ["Print", "Выделить область → буфер"],
                ["Mod+Print", "Весь экран"],
                ["Mod+Shift+T", "Распознать текст в области (OCR) → буфер"],
                ["Mod+Shift+Q", "Сканировать QR в области"],
                ["Mod+`", "Выпадающий терминал"],
                ["Mod+Shift+`", "Выпадающие заметки (scratch.md)"],
                ["Mod+Shift+P", "Закрепить плавающее окно"],
                ["XF86AudioRaise/LowerVolume", "Громкость"],
                ["XF86AudioMute", "Без звука"],
                ["XF86MonBrightness Up/Down", "Яркость"],
            ]
        }
    ]

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Dotline.Theme.surface.r, Dotline.Theme.surface.g, Dotline.Theme.surface.b, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.hide() }
    }

    Row {
        anchors.centerIn: parent
        spacing: 20

        Repeater {
            model: root.groups
            delegate: Rectangle {
                id: card
                required property var modelData
                width: 300
                radius: Dotline.Theme.radius * 1.2
                color: Dotline.Theme.surface
                implicitHeight: colLayout.implicitHeight + 36

                Column {
                    id: colLayout
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 18
                    spacing: 12

                    Text {
                        text: card.modelData.title
                        color: Dotline.Theme.accent
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: card.modelData.items
                        delegate: Column {
                            required property var modelData
                            width: colLayout.width
                            spacing: 2
                            Text {
                                text: modelData[0]
                                color: Dotline.Theme.ink
                                font.family: Dotline.Theme.fontMono
                                font.pixelSize: 13
                            }
                            Text {
                                text: modelData[1]
                                color: Dotline.Theme.muted
                                font.family: Dotline.Theme.fontUi
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }
        }
    }
}
