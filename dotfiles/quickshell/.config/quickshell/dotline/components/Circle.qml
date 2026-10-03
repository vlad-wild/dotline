import QtQuick
import "../" as Dotline

// A plain circle: the base shape for icon buttons, avatar-style widgets and
// the dot-grid glyphs' individual dots. `diameter` is the one thing callers
// set; width/height/radius follow from it.
Rectangle {
    id: root

    property real diameter: 40
    property color tint: Dotline.Theme.surface
    property bool interactive: false
    // Same background<->foreground swap the HTML mock-up uses on hover
    // (.cbtn:hover). Icon/text children inside should bind their own
    // `color` to this, not to a hardcoded Theme.ink, so they stay legible
    // when the circle inverts.
    readonly property color contentColor: _hovered ? tint : Dotline.Theme.ink
    readonly property bool _hovered: interactive && hover.hovered

    signal clicked()

    width: diameter
    height: diameter
    radius: diameter / 2
    color: _hovered ? Dotline.Theme.ink : tint

    Behavior on color { ColorAnimation { duration: 150 } }

    HoverHandler { id: hover; enabled: root.interactive; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: root.interactive; onTapped: root.clicked() }
}
