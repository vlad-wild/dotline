import QtQuick
import "../" as Dotline

// A pill: the bar's three sections, the search box, toasts — anything
// that in the mock-up is `border-radius: <height>/2` on a Rectangle.
// Children are laid out in a Row (default property), and the pill's own
// width hugs that Row unless the caller sets an explicit width.
Rectangle {
    id: root

    default property alias content: row.data
    property color tint: Dotline.Theme.surface
    property real paddingH: 18
    property real spacing: 12

    implicitHeight: Dotline.Theme.barHeight
    implicitWidth: row.implicitWidth + paddingH * 2
    radius: height / 2
    color: tint

    Behavior on color { ColorAnimation { duration: 900; easing.type: Easing.OutCubic } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.spacing
    }
}
