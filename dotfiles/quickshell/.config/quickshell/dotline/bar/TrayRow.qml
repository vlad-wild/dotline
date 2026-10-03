import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Services.SystemTray
import "../" as Dotline

// dotline — third-party tray icons (apps that still only offer a
// legacy status-notifier icon, no native Quickshell service of their own).
// Verified against the real Quickshell.Services.SystemTray docs:
// SystemTray.items is an ObjectModel (read via .values, the same lesson
// NetworkService.qml/BtService.qml already learned the hard way), and
// each item's `icon` is directly usable as an Image source — no icon
// theme lookup needed, unlike the launcher's best-effort app icons.
//
// Named TrayRow, not SystemTray: that's the exact name of the imported
// singleton type, and shadowing it the way an earlier draft of
// NetworkService.qml/BtService.qml did (before they got renamed) is
// exactly the mistake this file avoids by construction.
Row {
    id: root
    spacing: 10

    Repeater {
        model: [...SystemTray.items.values]
        delegate: Item {
            id: trayItem
            required property var modelData
            width: 18; height: 18

            Image {
                anchors.fill: parent
                source: trayItem.modelData.icon
                smooth: true
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: trayItem.modelData.activate()
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (eventPoint) => {
                    if (trayItem.modelData.hasMenu) {
                        trayItem.modelData.display(trayItem.Window.window, eventPoint.position.x, eventPoint.position.y)
                    }
                }
            }
            TapHandler {
                acceptedButtons: Qt.MiddleButton
                onTapped: trayItem.modelData.secondaryActivate()
            }
        }
    }
}
