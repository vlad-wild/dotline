import QtQuick
import "../" as Dotline
import "../components" as Components
import "../services" as Services

// dotline — the media popup: click the bar's equalizer glyph (Bar.qml) →
// `qs -c dotline ipc call media toggle`. Same click-catching-backdrop shape
// as quicksettings/QuickSettings.qml and phone/PhoneMenu.qml.
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
            spacing: 16

            Text {
                visible: !Services.Media.hasPlayer
                width: parent.width
                text: "НИЧЕГО НЕ ИГРАЕТ"
                color: Dotline.Theme.muted
                font.family: Dotline.Theme.fontDot
                font.pixelSize: 13
            }

            Column {
                width: parent.width
                visible: Services.Media.hasPlayer
                spacing: 14

                Row {
                    width: parent.width
                    spacing: 14

                    Rectangle {
                        id: art
                        width: 64; height: 64
                        radius: 16
                        color: Dotline.Theme.surfaceHigh
                        clip: true
                        Image {
                            id: artImage
                            anchors.fill: parent
                            source: Services.Media.artUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: artImage.status !== Image.Ready
                            text: "♪"
                            color: Dotline.Theme.muted
                            font.pixelSize: 24
                        }
                    }

                    Column {
                        width: parent.width - art.width - 14
                        anchors.verticalCenter: art.verticalCenter
                        spacing: 4
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: Services.Media.title || Services.Media.identity
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            visible: Services.Media.artist.length > 0
                            elide: Text.ElideRight
                            text: Services.Media.artist
                            color: Dotline.Theme.muted
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                        }
                    }
                }

                // Progress: drag to seek, same track+fill+MouseArea shape
                // as the per-app volume sliders in quicksettings/QuickSettings.qml.
                Rectangle {
                    id: track
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Dotline.Theme.surfaceHigh
                    visible: Services.Media.length > 0
                    Rectangle {
                        width: track.width * Services.Media.progress
                        height: parent.height
                        radius: parent.radius
                        color: Dotline.Theme.accent
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: (m) => Services.Media.seekTo(m.x / track.width)
                        onPositionChanged: (m) => { if (pressed) Services.Media.seekTo(m.x / track.width) }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Components.ActionButton { label: "⏮"; onClicked: Services.Media.previous() }
                    Components.ActionButton { label: Services.Media.playing ? "⏸" : "▶"; onClicked: Services.Media.toggle() }
                    Components.ActionButton { label: "⏭"; onClicked: Services.Media.next() }
                }

                // Player switcher — only shown with more than one, see
                // Media.qml's selectPlayer()/manualPlayer for why picking
                // one here doesn't stick once something else starts playing.
                Column {
                    width: parent.width
                    spacing: 4
                    visible: Services.Media.players.length > 1

                    Repeater {
                        model: Services.Media.players
                        delegate: Rectangle {
                            id: playerRow
                            required property var modelData
                            width: col.width
                            height: 36
                            radius: 12
                            color: playerRow.modelData === Services.Media.activePlayer ? Dotline.Theme.surfaceHigh : "transparent"
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                text: playerRow.modelData.identity
                                color: Dotline.Theme.ink
                                font.family: Dotline.Theme.fontUi
                                font.pixelSize: 13
                            }
                            MouseArea { anchors.fill: parent; onClicked: Services.Media.selectPlayer(playerRow.modelData) }
                        }
                    }
                }
            }
        }
    }
}
