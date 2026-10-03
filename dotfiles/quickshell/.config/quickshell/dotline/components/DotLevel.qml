import QtQuick
import "../" as Dotline

// A row of small dots showing a level out of a count — volume, battery,
// signal strength. Same idea as the mock-up's `.lvl` (lvl() JS helper),
// just as a real component instead of inline SVG.
Row {
    id: root

    property int count: 5
    property int filled: 3
    property real dotSize: 4
    property real spacing_: 3
    property color color: Dotline.Theme.ink
    // Qt.alpha() doesn't exist in QML; a color's .r/.g/.b/.a components do.
    property color dimColor: Qt.rgba(Dotline.Theme.ink.r, Dotline.Theme.ink.g, Dotline.Theme.ink.b, 0.28)

    spacing: spacing_

    Repeater {
        model: root.count
        delegate: Rectangle {
            required property int index
            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            color: index < root.filled ? root.color : root.dimColor
            Behavior on color { ColorAnimation { duration: 250 } }
        }
    }
}
