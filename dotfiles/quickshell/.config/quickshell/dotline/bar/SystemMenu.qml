import QtQuick
import Quickshell
import "../" as Dotline
import "../components" as Components

// dotline — the bar's leftmost glyph (Mac's  menu, in spirit). A
// real per-app File/Edit/View menu isn't attempted here: that's the
// dbusmenu/appmenu-gtk-module mechanism from Unity-era X11, GTK dropped
// most of it years ago, and there's no native-Wayland equivalent most
// apps export — building it would mean a D-Bus menu client for a protocol
// that would silently fail to show anything for the great majority of
// real apps. This is the honest, achievable version: system actions, the
// same place a Mac keeps them.
Item {
    id: root

    // Inline components declared first (not sure whether QML requires
    // them before first use within a file — costs nothing to be safe).
    component MenuItem: Rectangle {
        id: item
        property string text: ""
        property string subtitle: ""
        property bool itemEnabled: true
        property bool danger: false
        signal activate()

        width: parent ? parent.width : 220
        height: 40
        color: ma.containsMouse && item.itemEnabled ? Dotline.Theme.surfaceHigh : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 16
            spacing: 8
            Text {
                text: item.text
                color: !item.itemEnabled ? Dotline.Theme.muted : (item.danger ? Dotline.Theme.accent : Dotline.Theme.ink)
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 14
            }
            Text {
                visible: item.subtitle.length > 0
                text: item.subtitle
                color: Dotline.Theme.muted
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 12
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            enabled: item.itemEnabled
            onClicked: item.activate()
        }
    }

    component MenuSep: Rectangle {
        width: parent ? parent.width - 32 : 0
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        height: 1
        color: Dotline.Theme.outline
    }

    implicitWidth: dot.diameter
    implicitHeight: Dotline.Theme.barHeight

    property bool open: false
    // Destructive actions arm on first click and fire on a second one
    // within this window, instead of popping a whole separate confirm
    // dialog for two lines of menu.
    property string armed: ""
    Timer { id: disarmTimer; interval: 2500; onTriggered: root.armed = "" }

    Components.Circle {
        id: dot
        diameter: Dotline.Theme.barHeight
        interactive: true
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.open = !root.open

        Components.DotMatrix {
            anchors.centerIn: parent
            pattern: ["#.#", ".#.", "#.#"]
            cell: 6
            color: dot.contentColor
        }
    }

    Rectangle {
        id: menu
        visible: root.open
        anchors.top: parent.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        width: 220
        radius: Dotline.Theme.radius
        color: Dotline.Theme.surface
        implicitHeight: col.implicitHeight + 16

        Behavior on color { ColorAnimation { duration: 900 } }

        MouseArea {
            // swallow clicks so they don't fall through to the desktop
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            id: col
            y: 8
            width: parent.width
            MenuItem { text: "О системе"; onActivate: { root.open = false } }
            MenuSep {}
            MenuItem {
                text: "Настройки"
                onActivate: {
                    root.open = false
                    Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "settings", "toggle"])
                }
            }
            MenuSep {}
            MenuItem {
                text: root.armed === "lock" ? "Точно?" : "Заблокировать"
                onActivate: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "lock", "lock"])
            }
            MenuItem {
                text: root.armed === "reboot" ? "Точно? Перезапустить" : "Перезапустить"
                danger: root.armed === "reboot"
                onActivate: root._confirmThen("reboot", () => Quickshell.execDetached(["systemctl", "reboot"]))
            }
            MenuItem {
                text: root.armed === "poweroff" ? "Точно? Выключить" : "Выключить"
                danger: root.armed === "poweroff"
                onActivate: root._confirmThen("poweroff", () => Quickshell.execDetached(["systemctl", "poweroff"]))
            }
        }
    }

    function _confirmThen(key, action) {
        if (armed === key) {
            disarmTimer.stop()
            armed = ""
            open = false
            action()
        } else {
            armed = key
            disarmTimer.restart()
        }
    }

    // No outside-click-to-close: the bar's own PanelWindow is only
    // Theme.barHeight tall (anchored top/left/right, no bottom), so a
    // MouseArea here can't catch clicks on the desktop below it anyway —
    // same structural reason the notification/OSD windows stay
    // click-through-shaped rather than click-to-dismiss (see their TODOs
    // in shell.qml). Picking a menu item, or clicking the glyph again,
    // closes it instead.
}
