import QtQuick
import "../" as Dotline

// A small pill-shaped button: label + click. components/Pill.qml is a bare
// container (its default property is just a Row of whatever content you
// give it, no label/onClicked of its own) — this is the thing you reach
// for once you actually need something pressable, instead of inventing
// properties Pill doesn't have.
//
// Deliberately not named/shaped `enabled: bool` as a fresh property: Item
// already has a real `enabled`, and redeclaring it was a real bug caught
// elsewhere in this repo (SystemMenu.qml). Setting the inherited `enabled`
// to false already disables the MouseArea below for free (QML propagates
// it to children) — this file only adds the dimming on top.
Rectangle {
    id: root

    signal clicked()
    property string label: ""

    implicitHeight: 36
    implicitWidth: labelText.implicitWidth + 28
    radius: height / 2
    opacity: enabled ? 1.0 : 0.5
    color: Dotline.Theme.surfaceHigh

    Behavior on opacity { NumberAnimation { duration: 150 } }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        color: Dotline.Theme.ink
        font.family: Dotline.Theme.fontUi
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
