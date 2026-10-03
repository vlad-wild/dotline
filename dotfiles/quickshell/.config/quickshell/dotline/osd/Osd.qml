import QtQuick
import "../" as Dotline
import "../components" as Components

// dotline — the brief volume/brightness/power-profile popup, shown
// via scripts/osd and scripts/power's IPC calls (see shell.qml's
// `IpcHandler { target: "osd" }`). A pill with a dot-level row for
// volume/brightness, same shape language as the bar's own indicators —
// auto-hides after a beat. Sized to exactly fill its own small
// PanelWindow (see shell.qml: anchored to the bottom edge only, not the
// whole screen), not positioned within a fullscreen one.
Item {
    id: root

    property string kind: "volume"     // "volume" | "brightness" | "power"
    property int percent: 0
    property bool muted: false
    property string label: ""          // "power" kind: the profile name

    readonly property var _powerNames: ({
        "power-saver": "Энергосбережение",
        "balanced": "Баланс",
        "performance": "Производительность"
    })

    opacity: 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    // For "volume"/"brightness", `value` is a 0-100 percent; for "power"
    // it's the profile name (scripts/power reuses the same 3-string IPC
    // call rather than needing its own IpcHandler target).
    function flash(newKind, value, newMuted) {
        kind = newKind
        if (kind === "power") {
            label = _powerNames[value] ?? value
        } else {
            percent = Math.max(0, Math.min(100, Math.round(Number(value) || 0)))
            muted = newMuted === "1" || newMuted === true
        }
        opacity = 1
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: 1100
        onTriggered: root.opacity = 0
    }

    Components.Pill {
        anchors.centerIn: parent
        paddingH: 22
        spacing: 14

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.kind === "power" ? "Питание"
                : root.kind === "brightness" ? "Яркость"
                : (root.muted ? "Выкл" : "Звук")
            color: Dotline.Theme.muted
            font.family: Dotline.Theme.fontUi
            font.pixelSize: 14
        }
        Components.DotLevel {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.kind !== "power"
            count: 10
            filled: root.muted ? 0 : Math.round(root.percent / 10)
            dotSize: 6
            spacing_: 5
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.kind !== "power"
            text: root.percent + "%"
            color: Dotline.Theme.ink
            font.family: Dotline.Theme.fontDot
            font.pixelSize: 16
            font.weight: Font.ExtraBold
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.kind === "power"
            text: root.label
            color: Dotline.Theme.ink
            font.family: Dotline.Theme.fontUi
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
    }
}
