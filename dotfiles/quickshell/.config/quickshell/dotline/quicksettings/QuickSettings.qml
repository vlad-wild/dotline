import QtQuick
import Quickshell
import Quickshell.Networking
import "../" as Dotline
import "../components" as Components
import "../services" as Services

// dotline — Wi-Fi and Bluetooth, toggled via `qs -c dotline ipc call
// quicksettings toggle` (see shell.qml and the bar's wifi dot). Built on
// NetworkService.qml/BtService.qml, which wrap the real
// Quickshell.Networking/Quickshell.Bluetooth modules.
Item {
    id: root

    property bool open: false
    function show(): void { open = true }
    function hide(): void { open = false }
    function toggle(): void { open = !open }

    // Password prompt state for a network that needs one.
    property var pendingNetwork: null

    visible: open
    enabled: open

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Dotline.Theme.surface.r, Dotline.Theme.surface.g, Dotline.Theme.surface.b, 0.45)
        MouseArea { anchors.fill: parent; onClicked: root.hide() }
    }

    Rectangle {
        id: card
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        anchors.topMargin: 72
        width: 380
        radius: Dotline.Theme.radius * 1.4
        color: Dotline.Theme.surface
        implicitHeight: col.implicitHeight + 40

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            spacing: 22

            // ---------- Wi-Fi ----------
            Column {
                width: parent.width
                spacing: 12

                Row {
                    width: parent.width
                    Text {
                        text: "Wi-Fi"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        width: parent.width - 60
                    }
                    Rectangle {
                        width: 46; height: 26; radius: 13
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

                Column {
                    width: parent.width
                    spacing: 6
                    visible: Services.NetworkService.wifiEnabled

                    Repeater {
                        model: Services.NetworkService.networks
                        delegate: Column {
                            id: netRow
                            required property var modelData
                            width: col.width
                            spacing: 6

                            Rectangle {
                                width: parent.width
                                height: 44
                                radius: 14
                                color: netRow.modelData.connected ? Dotline.Theme.surfaceHigh : "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Components.DotLevel {
                                        anchors.verticalCenter: parent.verticalCenter
                                        count: 4
                                        filled: Math.max(1, Math.round(netRow.modelData.signalStrength * 4))
                                        dotSize: 5
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 4 * 5 - 10 - 20
                                        elide: Text.ElideRight
                                        text: netRow.modelData.name
                                        color: Dotline.Theme.ink
                                        font.family: Dotline.Theme.fontUi
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: netRow.modelData.connected
                                        text: "✓"
                                        color: Dotline.Theme.accent
                                        font.pixelSize: 14
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (netRow.modelData.connected) return
                                        if (netRow.modelData.known || netRow.modelData.security === WifiSecurityType.Open) {
                                            Services.NetworkService.connectTo(netRow.modelData, "")
                                        } else {
                                            root.pendingNetwork = netRow.modelData
                                        }
                                    }
                                }
                            }

                            // Password entry, shown inline under the row that needs one.
                            Rectangle {
                                width: parent.width
                                height: 44
                                radius: 14
                                color: Dotline.Theme.surfaceHigh
                                visible: root.pendingNetwork === netRow.modelData

                                TextInput {
                                    id: pw
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    color: Dotline.Theme.ink
                                    font.pixelSize: 14
                                    onAccepted: {
                                        Services.NetworkService.connectTo(netRow.modelData, text)
                                        root.pendingNetwork = null
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: Services.NetworkService.networks.length === 0
                        text: "Поиск сетей…"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Dotline.Theme.outline }

            // ---------- Bluetooth ----------
            Column {
                width: parent.width
                spacing: 12

                Row {
                    width: parent.width
                    Text {
                        text: "Bluetooth"
                        color: Dotline.Theme.ink
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        width: parent.width - 60
                    }
                    Rectangle {
                        width: 46; height: 26; radius: 13
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

                Column {
                    width: parent.width
                    spacing: 6
                    visible: Services.BtService.powered

                    Repeater {
                        model: Services.BtService.devices
                        delegate: Rectangle {
                            id: btRow
                            required property var modelData
                            width: col.width
                            height: 44
                            radius: 14
                            color: modelData.connected ? Dotline.Theme.surfaceHigh : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - (btRow.modelData.batteryAvailable ? 50 : 0) - 20
                                    elide: Text.ElideRight
                                    text: btRow.modelData.name
                                    color: Dotline.Theme.ink
                                    font.family: Dotline.Theme.fontUi
                                    font.pixelSize: 14
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: btRow.modelData.batteryAvailable
                                    text: Math.round(btRow.modelData.battery * 100) + "%"
                                    color: Dotline.Theme.muted
                                    font.family: Dotline.Theme.fontDot
                                    font.pixelSize: 13
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (btRow.modelData.connected) Services.BtService.disconnectDevice(btRow.modelData)
                                    else if (btRow.modelData.paired) Services.BtService.connectDevice(btRow.modelData)
                                    else Services.BtService.pair(btRow.modelData)
                                }
                            }
                        }
                    }

                    Text {
                        visible: Services.BtService.devices.length === 0
                        text: "Нет устройств поблизости"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Dotline.Theme.outline }

            // ---------- Sound: devices + per-app mixer ----------
            Column {
                width: parent.width
                spacing: 12

                Text {
                    text: "Звук"
                    color: Dotline.Theme.ink
                    font.family: Dotline.Theme.fontUi
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                // Output device picker.
                Repeater {
                    model: Services.Audio.sinks
                    delegate: Rectangle {
                        id: sinkRow
                        required property var modelData
                        width: col.width
                        height: 40
                        radius: 14
                        color: sinkRow.modelData === Services.Audio.sink ? Dotline.Theme.surfaceHigh : "transparent"
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24
                                elide: Text.ElideRight
                                text: sinkRow.modelData.description || sinkRow.modelData.name
                                color: Dotline.Theme.ink
                                font.family: Dotline.Theme.fontUi
                                font.pixelSize: 14
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: sinkRow.modelData === Services.Audio.sink
                                text: "✓"
                                color: Dotline.Theme.accent
                                font.pixelSize: 14
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: Services.Audio.selectSink(sinkRow.modelData) }
                    }
                }

                // Input device picker, with a live level meter next to
                // whichever one is the current default.
                Repeater {
                    model: Services.Audio.sources
                    delegate: Rectangle {
                        id: sourceRow
                        required property var modelData
                        width: col.width
                        height: 40
                        radius: 14
                        color: sourceRow.modelData === Services.Audio.source ? Dotline.Theme.surfaceHigh : "transparent"
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24 - (sourceRow.modelData === Services.Audio.source ? 44 : 0)
                                elide: Text.ElideRight
                                text: sourceRow.modelData.description || sourceRow.modelData.name
                                color: Dotline.Theme.ink
                                font.family: Dotline.Theme.fontUi
                                font.pixelSize: 14
                            }
                            Components.DotLevel {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: sourceRow.modelData === Services.Audio.source
                                count: 5
                                filled: Math.round(Services.Audio.micLevel * 5)
                                dotSize: 5
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: sourceRow.modelData === Services.Audio.source
                                text: "✓"
                                color: Dotline.Theme.accent
                                font.pixelSize: 14
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: Services.Audio.selectSource(sourceRow.modelData) }
                    }
                }

                // Per-app mixer: one volume slider + mute dot per playback
                // stream (PwNodeType.AudioOutStream — apps, not devices).
                Column {
                    width: parent.width
                    spacing: 10
                    visible: Services.Audio.appStreams.length > 0

                    Repeater {
                        model: Services.Audio.appStreams
                        delegate: Column {
                            id: appRow
                            required property var modelData
                            width: col.width
                            spacing: 4

                            Row {
                                width: parent.width
                                Text {
                                    width: parent.width - 20
                                    elide: Text.ElideRight
                                    text: Services.Audio.appLabel(appRow.modelData)
                                    color: Dotline.Theme.ink
                                    font.family: Dotline.Theme.fontUi
                                    font.pixelSize: 13
                                }
                                Rectangle {
                                    width: 9; height: 9; radius: 4.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: appRow.modelData.audio.muted ? Dotline.Theme.accent : Dotline.Theme.muted
                                    TapHandler { onTapped: Services.Audio.toggleAppMute(appRow.modelData) }
                                }
                            }
                            Rectangle {
                                id: track
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Dotline.Theme.surfaceHigh
                                Rectangle {
                                    width: track.width * Math.max(0, Math.min(1, appRow.modelData.audio.volume))
                                    height: parent.height
                                    radius: parent.radius
                                    color: Dotline.Theme.ink
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: (m) => Services.Audio.setAppVolume(appRow.modelData, m.x / track.width)
                                    onPositionChanged: (m) => {
                                        if (pressed) Services.Audio.setAppVolume(appRow.modelData, m.x / track.width)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Dotline.Theme.outline }

            // Off by default — see services/PhoneLock.qml for why this
            // only ever locks, never auto-unlocks on the phone's return.
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

            // Чисто чёрный surface в тёмном режиме (plan's "OLED"), сразу
            // переприменяется к тому, что сейчас активно — обои или
            // готовая палитра (см. lib/palette.sh's palette_set_oled).
            Row {
                width: parent.width
                Text {
                    text: "ЧИСТО ЧЁРНЫЙ (OLED)"
                    color: Dotline.Theme.ink
                    font.family: Dotline.Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    width: parent.width - 60
                }
                Rectangle {
                    width: 46; height: 26; radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: Dotline.Theme.oledEnabled ? Dotline.Theme.accent : Dotline.Theme.surfaceHigh
                    Rectangle {
                        width: 20; height: 20; radius: 10
                        color: Dotline.Theme.ink
                        y: 3
                        x: Dotline.Theme.oledEnabled ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(["dotline-theme", "oled", Dotline.Theme.oledEnabled ? "off" : "on"])
                    }
                }
            }

            // Transmission to a TV: Miracast + Chromecast both go through
            // gnome-network-displays (its own GTK4 window picks the target
            // display) — see docs/screencast.md for why this needs
            // dotfiles/xdg-desktop-portal's portals.conf to actually work
            // under niri.
            Components.ActionButton {
                label: "ТРАНСЛЯЦИЯ НА ТВ"
                onClicked: {
                    Quickshell.execDetached(["gnome-network-displays"])
                    root.hide()
                }
            }
        }
    }
}
