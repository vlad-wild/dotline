import QtQuick
import Quickshell
import "../" as Dotline
import "../components" as Components
import "../services" as Services

// dotline — the phone popup: click the bar glyph (see Bar.qml) or
// `Win+K` (config.kdl) → `qs -c dotline ipc call phone toggle`. Same
// click-catching-backdrop shape as QuickSettings.qml/KeysCheatSheet.qml.
Item {
    id: root

    property bool open: false
    function show(): void { open = true }
    function hide(): void { open = false }
    function toggle(): void { open = !open }

    visible: open
    enabled: open

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Dotline.Theme.surface.r, Dotline.Theme.surface.g, Dotline.Theme.surface.b, 0.45)
        MouseArea { anchors.fill: parent; onClicked: root.hide() }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        anchors.topMargin: 72
        width: 340
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
            spacing: 18

            // ---------- no device known at all ----------
            Text {
                visible: Services.Phone.deviceList.length === 0
                width: parent.width
                text: "ТЕЛЕФОН НЕ НАЙДЕН"
                color: Dotline.Theme.muted
                font.family: Dotline.Theme.fontDot
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            // ---------- one block per known device ----------
            Repeater {
                model: Services.Phone.deviceList
                delegate: Column {
                    id: devRow
                    required property var modelData
                    width: col.width
                    spacing: 12

                    Row {
                        width: parent.width
                        spacing: 10
                        Rectangle {
                            width: 9; height: 9; radius: 4.5
                            anchors.verticalCenter: parent.verticalCenter
                            color: devRow.modelData.reachable ? Dotline.Theme.accent : Dotline.Theme.muted
                        }
                        Text {
                            width: parent.width - 9 - 10 - 50
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: devRow.modelData.name
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            visible: devRow.modelData.battery !== null
                            Text {
                                text: devRow.modelData.battery ? devRow.modelData.battery.charge + "%" : ""
                                color: Dotline.Theme.muted
                                font.family: Dotline.Theme.fontDot
                                font.pixelSize: 13
                            }
                            Components.DotLevel {
                                anchors.verticalCenter: parent.verticalCenter
                                filled: devRow.modelData.battery ? Math.round(devRow.modelData.battery.charge / 20) : 0
                                color: devRow.modelData.battery && devRow.modelData.battery.charging ? Dotline.Theme.accent : Dotline.Theme.ink
                            }
                        }
                    }

                    // Peer wants to pair with us.
                    Row {
                        width: parent.width
                        spacing: 10
                        visible: devRow.modelData.pairRequestedByPeer
                        Components.ActionButton {
                            label: "ПРИНЯТЬ"
                            onClicked: Services.Phone.acceptPair(devRow.modelData.id)
                        }
                        Components.ActionButton {
                            label: "ОТКЛОНИТЬ"
                            onClicked: Services.Phone.rejectPair(devRow.modelData.id)
                        }
                    }

                    // We're not paired at all yet — only a request button.
                    Components.ActionButton {
                        visible: !devRow.modelData.paired && !devRow.modelData.pairRequestedByPeer
                        label: devRow.modelData.pairRequested ? "ЖДЁМ ПОДТВЕРЖДЕНИЯ…" : "СПАРИТЬ"
                        enabled: !devRow.modelData.pairRequested
                        onClicked: Services.Phone.requestPair(devRow.modelData.id)
                    }

                    // Paired and reachable — the actual actions.
                    Row {
                        width: parent.width
                        spacing: 10
                        visible: devRow.modelData.paired && devRow.modelData.reachable
                        Components.ActionButton {
                            label: "НАЙТИ"
                            onClicked: Services.Phone.ring(devRow.modelData.id)
                        }
                        Components.ActionButton {
                            label: "ПИНГ"
                            onClicked: Services.Phone.ping(devRow.modelData.id)
                        }
                        Components.ActionButton {
                            label: "ФАЙЛЫ"
                            onClicked: Services.Phone.browse(devRow.modelData.id)
                        }
                    }

                    Text {
                        width: parent.width
                        visible: devRow.modelData.paired && !devRow.modelData.reachable
                        text: "Недоступен"
                        color: Dotline.Theme.muted
                        font.family: Dotline.Theme.fontUi
                        font.pixelSize: 13
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Dotline.Theme.outline }

            Components.ActionButton {
                label: "ПРИЛОЖЕНИЕ KDE CONNECT"
                onClicked: Quickshell.execDetached(["kdeconnect-app"])
            }
        }
    }
}
