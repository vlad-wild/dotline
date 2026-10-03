import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../" as Dotline
import "../components" as Components
import "../services" as Services

// dotline — the stack of toast pills in the top-right corner (see the
// mock-up's .toasts/.toast). One NotificationServer for the whole shell;
// this file is the popup UI, meant to be placed inside its own small
// PanelWindow from shell.qml (anchored top-right, no input-exclusive zone
// except over the toasts themselves).
//
// Verified against the real Quickshell.Services.Notifications docs
// (quickshell.org): appName/summary/body/dismiss() are exactly as used
// below. First check on the laptop anyway: `notify-send "Test" "Hello"`
// and watch a toast appear correctly shaped.
Item {
    id: root

    readonly property int autoCloseMs: 6000

    // Plain JS array, not a ListModel: a Notification is a live object with
    // methods (dismiss()), and ListModel only reliably stores serialisable
    // values, not object references with behaviour. Reassigning the whole
    // array (never push()/splice() in place) is what makes Repeater notice.
    property var popups: []

    NotificationServer {
        id: server
        onNotification: (notification) => {
            // Confirmed necessary, not just belt-and-suspenders: per the
            // docs, a Notification isn't retained by the server unless
            // this is set — without it the object could be gone before
            // the toast below ever reads it.
            notification.tracked = true
            Services.NotificationRules.noteApp(notification.appName)
            // DND suppresses every toast, temporarily and globally.
            // NotificationRules gates by app instead, persists across
            // restarts (see services/NotificationRules.qml) — either one
            // can suppress the popup; the notification itself is still
            // tracked/received above, nothing is lost, it just doesn't
            // interrupt.
            if (!Services.DoNotDisturb.enabled && !Services.NotificationRules.isBlocked(notification.appName)) {
                root.popups = root.popups.concat([notification])
            }
        }
    }

    function dismiss(notification) {
        root.popups = root.popups.filter(n => n !== notification)
        notification?.dismiss?.()
    }

    // Exposed so shell.qml can size this item's own PanelWindow to just
    // the toasts actually showing, instead of a fixed height that leaves
    // empty space blocking clicks underneath (see shell.qml for why this
    // matters: no input-mask/click-through property is documented on
    // PanelWindow, so keeping the window small is the fix, not a flag).
    implicitWidth: col.width + 32
    implicitHeight: col.height + 16

    Column {
        id: col
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        spacing: 10
        width: 410

        Repeater {
            model: root.popups
            delegate: Rectangle {
                id: toast
                required property var modelData
                readonly property var n: modelData

                width: 410
                implicitHeight: 78
                radius: 30
                color: Dotline.Theme.surface

                Behavior on color { ColorAnimation { duration: 900 } }

                Timer {
                    interval: root.autoCloseMs
                    running: true
                    onTriggered: root.dismiss(toast.n)
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    Components.Circle {
                        diameter: 46
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: (toast.n?.appName ?? "?").charAt(0).toUpperCase()
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 18
                        }
                    }

                    Column {
                        width: parent.width - 46 - 14 - 32
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            text: toast.n?.appName ?? ""
                            color: Dotline.Theme.muted
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: toast.n?.summary ?? ""
                            color: Dotline.Theme.ink
                            font.family: Dotline.Theme.fontUi
                            font.pixelSize: 15
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }

                TapHandler {
                    onTapped: root.dismiss(toast.n)
                }
            }
        }
    }
}
