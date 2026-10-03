import QtQuick
import Quickshell
import "../" as Dotline
import "../components" as Components
import "../services" as Services

// dotline — the updates popup: click the bar's update counter (Bar.qml) →
// `qs -c dotline ipc call updates toggle`. Same click-catching-backdrop
// shape as quicksettings/QuickSettings.qml and media/MediaCard.qml.
Item {
    id: root

    property bool open: false
    function show(): void { open = true; Services.Updates.refresh() }
    function hide(): void { open = false }
    function toggle(): void { if (open) hide(); else show() }

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
        width: 320
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
            spacing: 16

            Text {
                width: parent.width
                text: Services.Updates.total === 0 ? "ВСЁ АКТУАЛЬНО" : "ОБНОВЛЕНИЯ"
                color: Dotline.Theme.ink
                font.family: Dotline.Theme.fontDot
                font.pixelSize: 15
                font.weight: Font.ExtraBold
            }

            Column {
                width: parent.width
                spacing: 10

                Repeater {
                    model: [
                        { label: "Pacman", n: Services.Updates.pacman },
                        { label: "AUR", n: Services.Updates.aur },
                        { label: "Flatpak", n: Services.Updates.flatpak },
                        { label: "Прошивки", n: Services.Updates.firmware },
                    ]
                    delegate: Row {
                        required property var modelData
                        width: col.width
                        Text {
                            width: parent.width - 30
                            text: modelData.label
                            color: Dotline.Theme.muted
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 14
                        }
                        Text {
                            width: 30
                            horizontalAlignment: Text.AlignRight
                            text: modelData.n
                            color: modelData.n > 0 ? Dotline.Theme.accent : Dotline.Theme.muted
                            font.family: Dotline.Theme.fontDot
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Dotline.Theme.outline }

            Components.ActionButton {
                label: "ОБНОВИТЬ ВСЁ"
                enabled: Services.Updates.total > 0
                onClicked: { Services.Updates.updateAll(); root.hide() }
            }

            Text {
                width: parent.width
                visible: Services.Updates.firmware > 0
                text: "Прошивки обновляются отдельно: update.sh --firmware (только от сети)."
                wrapMode: Text.WordWrap
                color: Dotline.Theme.muted
                font.family: Dotline.Theme.fontUi
                font.pixelSize: 12
            }
        }
    }
}
