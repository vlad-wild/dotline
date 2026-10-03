pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

// dotline — "lock when the phone's Bluetooth connection drops"
// (toggle in QuickSettings.qml, off by default). Deliberately one-way:
// this only ever locks, never unlocks/wakes on return. Bluetooth
// proximity confirms the phone is somewhere in radio range, not that its
// owner is sitting in front of the screen — auto-unlock on that signal
// would be a real authentication hole, which is why Windows' own Dynamic
// Lock (the feature this mirrors) doesn't do it either. See docs/phone.md.
//
// "The phone" is identified among BtService's paired Bluetooth devices by
// name match against the first paired KDE Connect device — there's no
// shared identifier between a KDE Connect device id and a Bluetooth MAC
// address, so this is the simplest thing that works for one phone. Fragile
// if the phone's Bluetooth name differs from its KDE Connect name.
//
// A disconnect doesn't lock immediately: a `graceSeconds`-long timer must
// elapse first, so a transient BT-stack hiccup or a few seconds out of
// range doesn't lock the session every time.
Singleton {
    id: root

    property bool enabled: false
    readonly property int graceSeconds: 25

    readonly property var pairedPhoneName: {
        const d = Services.Phone.deviceList.find(p => p.paired)
        return d ? d.name : null
    }
    readonly property bool phoneBtConnected:
        pairedPhoneName !== null &&
        Services.BtService.connectedDevices.some(d => d.name === pairedPhoneName)

    // Only arms the "disconnected" branch after we've actually seen the
    // phone connected at least once — otherwise a fresh login before the
    // phone ever reconnects would immediately queue up a lock.
    property bool sawConnected: false

    onPhoneBtConnectedChanged: {
        if (phoneBtConnected) {
            sawConnected = true
            graceTimer.stop()
        } else if (root.enabled && sawConnected) {
            graceTimer.restart()
        }
    }

    onEnabledChanged: {
        stateFile.setText(enabled ? "on" : "off")
        if (!enabled) graceTimer.stop()
    }

    Timer {
        id: graceTimer
        interval: root.graceSeconds * 1000
        onTriggered: Quickshell.execDetached(["qs", "-c", "dotline", "ipc", "call", "lock", "lock"])
    }

    readonly property string _stateHome: {
        const v = Quickshell.env("XDG_STATE_HOME")
        return (v && v.length > 0) ? v : (Quickshell.env("HOME") + "/.local/state")
    }

    FileView {
        id: stateFile
        path: root._stateHome + "/dotline/phone-away-lock"
        onLoaded: root.enabled = (text().trim() === "on")
        onLoadFailed: (error) => {
            console.warn("PhoneLock: no saved state yet (" + error + ") — staying off until toggled.")
        }
        onSaveFailed: (error) => {
            console.warn("PhoneLock: could not save toggle state:", error)
        }
    }
}
