pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — per-app notification rules (plan's "правила по приложениям",
// "уведомления с телефона") for the settings window's "Уведомления" page.
// Same JSON-FileView persistence shape as services/Reminders.qml
// (onLoaded/onLoadFailed/onSaveFailed + file.setText(JSON.stringify(...))
// on every write) — a proven pattern already in this codebase, not a new
// one invented here.
//
// This is a second, independent gate alongside DoNotDisturb: DND is
// global and temporary (see DoNotDisturb.qml), this is per-app and
// persists. notifications/NotificationPopup.qml checks both before
// showing a toast — neither replaces the other.
Singleton {
    id: root

    readonly property string _stateHome: {
        const v = Quickshell.env("XDG_STATE_HOME")
        return (v && v.length > 0) ? v : (Quickshell.env("HOME") + "/.local/state")
    }

    property var blockedApps: []     // [appName, ...]
    property bool hidePhoneNotifications: false
    property var knownApps: []       // every distinct appName ever seen, for the settings list

    // KDE Connect's own app name on its forwarded notifications — same
    // string already relied on in docs/phone.md's description of how
    // phone notifications reach this notification server (ordinary
    // org.freedesktop.Notifications, app_name = "KDE Connect"), not a
    // new guess made here.
    readonly property string _phoneAppName: "KDE Connect"

    FileView {
        id: file
        path: root._stateHome + "/dotline/notification-rules.json"
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.blockedApps = parsed.blockedApps ?? []
                root.hidePhoneNotifications = parsed.hidePhoneNotifications ?? false
                root.knownApps = parsed.knownApps ?? []
            } catch (e) {
                console.warn("NotificationRules: notification-rules.json is not valid JSON, starting empty:", e)
            }
        }
        onLoadFailed: (error) => {} // absent = no rules yet, the default
        onSaveFailed: (error) => console.warn("NotificationRules: could not save notification-rules.json:", error)
    }

    function _save() {
        file.setText(JSON.stringify({
            blockedApps: root.blockedApps,
            hidePhoneNotifications: root.hidePhoneNotifications,
            knownApps: root.knownApps,
        }))
    }

    // Called for every notification that arrives, blocked or not — this
    // is how the settings page gets something real to show toggles for,
    // instead of a blind free-text box.
    function noteApp(appName) {
        if (!appName || root.knownApps.includes(appName)) return
        root.knownApps = root.knownApps.concat([appName])
        root._save()
    }

    function isBlocked(appName) {
        if (root.hidePhoneNotifications && appName === root._phoneAppName) return true
        return root.blockedApps.includes(appName)
    }

    function setBlocked(appName, blocked) {
        if (blocked) {
            if (!root.blockedApps.includes(appName)) root.blockedApps = root.blockedApps.concat([appName])
        } else {
            root.blockedApps = root.blockedApps.filter(a => a !== appName)
        }
        root._save()
    }

    function setHidePhoneNotifications(hide) {
        root.hidePhoneNotifications = hide
        root._save()
    }
}
