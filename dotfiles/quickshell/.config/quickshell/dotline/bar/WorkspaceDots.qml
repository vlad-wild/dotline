import QtQuick
import "../" as Dotline
import "../services" as Services

// The bar's ● ○ ○ row: one dot per workspace on this output, the focused
// one stretched into a small pill (same shape language as the mock-up's
// .wsdots). Click a dot to switch to that workspace.
Row {
    id: root

    required property string output
    spacing: 7

    readonly property var _forOutput: Services.Niri.workspaces
        .filter(w => w.output === root.output)
        .sort((a, b) => a.idx - b.idx)

    Repeater {
        model: root._forOutput
        delegate: Rectangle {
            id: dot
            required property var modelData

            readonly property bool active: modelData.active_window_id !== null && modelData.active_window_id !== undefined
            readonly property bool focused: modelData.is_focused === true

            width: focused ? 20 : 9
            height: 9
            radius: height / 2
            color: focused ? Dotline.Theme.ink
                 : active  ? "transparent"
                 : "transparent"
            border.width: focused ? 0 : 1.5
            border.color: active ? Dotline.Theme.ink : Dotline.Theme.muted

            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 200 } }

            TapHandler {
                onTapped: Services.Niri.focusWorkspace(modelData.idx)
            }
        }
    }
}
