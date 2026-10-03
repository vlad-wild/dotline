pragma Singleton
import QtQuick

// dotline — "Не беспокоить" (Mod+Shift+N, quicksettings, and a lever used
// by services/Modes.qml). In-memory only, like Caffeine.qml — resets on
// restart, no state file needed for something meant to be toggled during
// a session, not carried across reboots.
//
// This only sets the flag; notifications/NotificationPopup.qml is the one
// that actually checks it before showing a toast (received notifications
// aren't dropped — the server still tracks them, see that file — only the
// popup is suppressed, same as how most DND implementations work: nothing
// is lost, it's just not interrupting you right now).
Singleton {
    id: root

    property bool enabled: false
    function toggle() { enabled = !enabled }
}
