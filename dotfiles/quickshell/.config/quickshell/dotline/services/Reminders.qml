pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// dotline — `/remind <срок> <текст>` and `/timer <срок>` (launcher/
// Launcher.qml). Persisted to a plain JSON file so a due reminder still
// fires after a reboot (checked immediately on load, same reasoning
// as Theme.qml/PhoneLock.qml's own state files) instead of living only
// in a per-process timer that a restart would silently drop.
Singleton {
    id: root

    readonly property string _stateHome: {
        const v = Quickshell.env("XDG_STATE_HOME")
        return (v && v.length > 0) ? v : (Quickshell.env("HOME") + "/.local/state")
    }

    property var items: []   // [{due: epoch_ms, text: string}]

    FileView {
        id: file
        path: root._stateHome + "/dotline/reminders.json"
        onLoaded: {
            try {
                root.items = JSON.parse(text())
            } catch (e) {
                console.warn("Reminders: reminders.json is not valid JSON, starting empty:", e)
                root.items = []
            }
            root._checkDue()
        }
        onLoadFailed: (error) => { root.items = [] }
        onSaveFailed: (error) => { console.warn("Reminders: could not save reminders.json:", error) }
    }

    // seconds: how far from now; label: what to remind about.
    function add(seconds, label) {
        root.items = root.items.concat([{ due: Date.now() + seconds * 1000, text: label }])
        file.setText(JSON.stringify(root.items))
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root._checkDue()
    }

    function _checkDue() {
        const now = Date.now()
        const due = root.items.filter(i => i.due <= now)
        if (due.length === 0) return
        for (const i of due) {
            Quickshell.execDetached(["notify-send", "-a", "dotline", "Напоминание", i.text])
        }
        root.items = root.items.filter(i => i.due > now)
        file.setText(JSON.stringify(root.items))
    }
}
